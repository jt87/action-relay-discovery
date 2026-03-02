import Foundation
import MCP

enum OutputExtractor {

    /// Extract string values from a WFWorkflowRunResult object.
    static func extractFromResult(_ resultObj: NSObject) -> [String] {
        var values: [String] = []

        // Path 1: WFWorkflowOutputRunResult — single output
        if resultObj.responds(to: NSSelectorFromString("archivedOutput")),
           let archived = resultObj.value(forKey: "archivedOutput") as? Data {
            if let extracted = extractValuesFromArchive(archived) {
                values.append(contentsOf: extracted.map { stringify($0) })
            }
        }

        // Path 2: WFAllActionOutputsRunResult — per-action outputs
        if resultObj.responds(to: NSSelectorFromString("archivedOutputs")),
           let archived = resultObj.value(forKey: "archivedOutputs") as? Data {
            if let extracted = extractValuesFromArchive(archived) {
                values.append(contentsOf: extracted.map { stringify($0) })
            }
        }

        return values
    }

    /// Convert an ExecutionResult to MCP tool content.
    static func toMCPContent(_ result: ExecutionResult) -> [Tool.Content] {
        if let error = result.error {
            return [.text("Error: \(error)")]
        }
        if result.values.isEmpty {
            return [.text("(no output)")]
        }
        return result.values.map { .text($0) }
    }

    /// Check if the result represents an error.
    static func isError(_ result: ExecutionResult) -> Bool {
        result.error != nil
    }

    // MARK: - NSKeyedArchiver Extraction

    /// Parse an NSKeyedArchiver plist and extract the actual values.
    private static func extractValuesFromArchive(_ data: Data) -> [Any]? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else {
            return nil
        }

        var values: [Any] = []

        for obj in objects {
            guard let dict = obj as? [String: Any] else { continue }

            if let repRef = dict["internalRepresentation"] {
                let repIdx = resolveUID(repRef)
                if repIdx > 0, repIdx < objects.count,
                   let repDict = objects[repIdx] as? [String: Any],
                   let valRef = repDict["object"] {
                    let valIdx = resolveUID(valRef)
                    if valIdx > 0, valIdx < objects.count {
                        values.append(objects[valIdx])
                    }
                }
            }
        }

        return values.isEmpty ? nil : values
    }

    /// Resolve a CFKeyedArchiverUID to its integer index.
    private static func resolveUID(_ ref: Any) -> Int {
        let desc = "\(ref)"
        if let range = desc.range(of: "value = "),
           let end = desc.range(of: "}", range: range.upperBound..<desc.endIndex) {
            let numStr = desc[range.upperBound..<end.lowerBound]
            return Int(numStr) ?? -1
        }
        if let num = ref as? Int { return num }
        return -1
    }

    /// Convert any value to a string representation.
    private static func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let d = value as? Data {
            if let s = String(data: d, encoding: .utf8) { return s }
            return "<\(d.count) bytes>"
        }
        if let dict = value as? [String: Any] {
            if let json = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let s = String(data: json, encoding: .utf8) {
                return s
            }
        }
        if let arr = value as? [Any] {
            if let json = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted),
               let s = String(data: json, encoding: .utf8) {
                return s
            }
        }
        return "\(value)"
    }
}
