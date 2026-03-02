import Foundation

enum WorkflowBuilder {

    /// Build a binary plist representing a single-action workflow.
    static func build(
        bundleID: String,
        appName: String,
        intentIdentifier: String,
        parameters: [String: Any]
    ) -> Data {
        let actionUUID = UUID().uuidString

        var actionParams: [String: Any] = [
            "AppIntentDescriptor": [
                "BundleIdentifier": bundleID,
                "Name": appName,
                "AppIntentIdentifier": intentIdentifier,
            ] as [String: Any],
            "UUID": actionUUID,
        ]

        // Merge in user-supplied parameters
        for (key, value) in parameters {
            actionParams[key] = value
        }

        let workflow: [String: Any] = [
            "WFWorkflowActions": [
                [
                    "WFWorkflowActionIdentifier": "\(bundleID).\(intentIdentifier)",
                    "WFWorkflowActionParameters": actionParams,
                ] as [String: Any],
            ],
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowClientVersion": "4046.0.2.2",
            "WFWorkflowHasOutputFallback": false,
            "WFWorkflowHasShortcutInputVariables": false,
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": -314_141_441,
                "WFWorkflowIconGlyphNumber": 61440,
            ] as [String: Any],
            "WFWorkflowImportQuestions": [] as [Any],
            "WFWorkflowInputContentItemClasses": [
                "WFAppContentItem",
                "WFAppStoreAppContentItem",
                "WFStringContentItem",
            ],
            "WFWorkflowOutputContentItemClasses": [] as [Any],
            "WFQuickActionSurfaces": [] as [Any],
            "WFWorkflowTypes": ["WFWorkflowTypeShowInSearch"],
        ]

        do {
            return try PropertyListSerialization.data(
                fromPropertyList: workflow, format: .binary, options: 0)
        } catch {
            fatalError("Failed to serialize workflow plist: \(error)")
        }
    }

    /// Convert MCP tool arguments to plist-compatible parameter values.
    static func convertArguments(
        _ arguments: [String: Any],
        action: ActionMetadata,
        metadata: AppIntentMetadata
    ) -> [String: Any] {
        var result: [String: Any] = [:]

        for param in action.parameters {
            guard let value = arguments[param.name] else { continue }

            switch param.valueType {
            case .primitive(.string):
                result[param.name] = value as? String ?? "\(value)"
            case .primitive(.bool):
                if let b = value as? Bool {
                    result[param.name] = b
                } else if let s = value as? String {
                    result[param.name] = s.lowercased() == "true"
                }
            case .primitive(.integer):
                if let i = value as? Int {
                    result[param.name] = i
                } else if let s = value as? String, let i = Int(s) {
                    result[param.name] = i
                }
            case .primitive(.double):
                if let d = value as? Double {
                    result[param.name] = d
                } else if let s = value as? String, let d = Double(s) {
                    result[param.name] = d
                }
            case .primitive(.url):
                result[param.name] = value as? String ?? "\(value)"
            case .primitive(.date):
                result[param.name] = value as? String ?? "\(value)"
            case .linkEnumeration:
                result[param.name] = value as? String ?? "\(value)"
            case .entity:
                result[param.name] = value as? String ?? "\(value)"
            case .intentFile:
                result[param.name] = value as? String ?? "\(value)"
            default:
                // For complex types, pass through as-is
                result[param.name] = value
            }
        }

        return result
    }
}
