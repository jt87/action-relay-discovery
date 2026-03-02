import Foundation

// MARK: - Public Types

struct AppIntentMetadata: Sendable {
    let bundleIdentifier: String
    let appName: String
    let actions: [String: ActionMetadata]
    let enums: [String: EnumMetadata]
}

struct ActionMetadata: Sendable {
    let identifier: String
    let title: String
    let descriptionText: String?
    let parameters: [ParameterMetadata]
    let outputType: ValueType?
    let isDiscoverable: Bool
    let openAppWhenRun: Bool
    let mangledTypeName: String
}

struct ParameterMetadata: Sendable {
    let name: String
    let title: String
    let descriptionText: String?
    let valueType: ValueType
    let isOptional: Bool
    let defaultValue: DefaultValue?
}

indirect enum ValueType: Sendable {
    case primitive(PrimitiveType)
    case linkEnumeration(identifier: String)
    case entity(typeName: String)
    case intentFile
    case array(memberType: ValueType)
    case measurement(unitType: Int)
    case unknown(typeIdentifier: Int)
}

enum PrimitiveType: Int, Sendable {
    case string = 0
    case bool = 1
    case integer = 2
    case double = 7
    case date = 8
    case location = 10
    case url = 11
}

enum DefaultValue: Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case double(Double)
}

struct EnumMetadata: Sendable {
    let identifier: String
    let cases: [EnumCase]
}

struct EnumCase: Sendable {
    let identifier: String
    let displayTitle: String
}

// MARK: - Discovery

enum Discovery {

    /// Resolve an app specifier (name, bundle ID, or path) to the .app bundle path.
    static func resolveAppPath(_ specifier: String) throws -> String {
        // Direct .app path
        if specifier.hasSuffix(".app") {
            let path = (specifier as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
            throw DiscoveryError.appNotFound(specifier)
        }

        // Try as app name in common locations
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        for dir in searchDirs {
            let directPath = "\(dir)/\(specifier).app"
            if FileManager.default.fileExists(atPath: directPath) {
                return directPath
            }
        }

        // Try bundle ID via mdfind
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == \"\(specifier)\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let paths = output.split(separator: "\n").map(String.init)
        if let appPath = paths.first(where: { $0.hasSuffix(".app") }) {
            return appPath
        }

        // Try case-insensitive search
        let fm = FileManager.default
        for dir in searchDirs {
            if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                let match = contents.first { item in
                    let name = (item as NSString).deletingPathExtension
                    return name.lowercased() == specifier.lowercased() && item.hasSuffix(".app")
                }
                if let match = match {
                    return "\(dir)/\(match)"
                }
            }
        }

        throw DiscoveryError.appNotFound(specifier)
    }

    /// Find the extract.actionsdata file inside an app bundle.
    static func findActionsData(appPath: String) throws -> String {
        let resourcesPath = "\(appPath)/Contents/Resources/Metadata.appintents/extract.actionsdata"
        if FileManager.default.fileExists(atPath: resourcesPath) {
            return resourcesPath
        }

        // Also check directly inside bundle (some apps)
        let directPath = "\(appPath)/Contents/Metadata.appintents/extract.actionsdata"
        if FileManager.default.fileExists(atPath: directPath) {
            return directPath
        }

        throw DiscoveryError.noIntentsMetadata(appPath)
    }

    /// Read bundle identifier and app name from Info.plist.
    static func readBundleInfo(appPath: String) throws -> (bundleID: String, appName: String) {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            throw DiscoveryError.cannotReadInfoPlist(appPath)
        }
        let bundleID = plist["CFBundleIdentifier"] as? String ?? "unknown"
        let appName = plist["CFBundleName"] as? String
            ?? plist["CFBundleDisplayName"] as? String
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return (bundleID, appName)
    }

    /// Parse an app into full metadata.
    static func parse(appPath: String) throws -> AppIntentMetadata {
        let actionsDataPath = try findActionsData(appPath: appPath)
        let (bundleID, appName) = try readBundleInfo(appPath: appPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: actionsDataPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiscoveryError.invalidJSON(actionsDataPath)
        }

        let enums = parseEnums(json["enums"])
        let actions = parseActions(json["actions"] as? [String: Any] ?? [:])

        return AppIntentMetadata(
            bundleIdentifier: bundleID,
            appName: appName,
            actions: actions,
            enums: enums
        )
    }

    // MARK: - Private Parsing

    private static func parseActions(_ dict: [String: Any]) -> [String: ActionMetadata] {
        var result: [String: ActionMetadata] = [:]
        for (identifier, value) in dict {
            guard let actionDict = value as? [String: Any] else { continue }
            result[identifier] = parseAction(identifier: identifier, dict: actionDict)
        }
        return result
    }

    private static func parseAction(identifier: String, dict: [String: Any]) -> ActionMetadata {
        let titleDict = dict["title"] as? [String: Any]
        let title = titleDict?["key"] as? String ?? identifier

        let descDict = dict["descriptionMetadata"] as? [String: Any]
        let descTextDict = descDict?["descriptionText"] as? [String: Any]
        let descriptionText = descTextDict?["key"] as? String

        let params = (dict["parameters"] as? [[String: Any]] ?? []).map { parseParameter($0) }

        let outputType = parseValueType(dict["outputType"] as? [String: Any])

        let visibility = dict["visibilityMetadata"] as? [String: Any]
        let isDiscoverable = visibility?["isDiscoverable"] as? Bool
            ?? dict["isDiscoverable"] as? Bool
            ?? true
        let openAppWhenRun = dict["openAppWhenRun"] as? Bool ?? false
        let mangledTypeName = dict["mangledTypeName"] as? String ?? ""

        return ActionMetadata(
            identifier: identifier,
            title: title,
            descriptionText: descriptionText,
            parameters: params,
            outputType: outputType,
            isDiscoverable: isDiscoverable,
            openAppWhenRun: openAppWhenRun,
            mangledTypeName: mangledTypeName
        )
    }

    private static func parseParameter(_ dict: [String: Any]) -> ParameterMetadata {
        let name = dict["name"] as? String ?? "unknown"
        let titleDict = dict["title"] as? [String: Any]
        let title = titleDict?["key"] as? String ?? name

        // Description can be in parameterDescription.key or descriptionMetadata.descriptionText.key
        let paramDescDict = dict["parameterDescription"] as? [String: Any]
        let descDict = dict["descriptionMetadata"] as? [String: Any]
        let descTextDict = descDict?["descriptionText"] as? [String: Any]
        let descriptionText = paramDescDict?["key"] as? String
            ?? descTextDict?["key"] as? String

        let valueType = parseValueType(dict["valueType"] as? [String: Any]) ?? .primitive(.string)
        let isOptional = dict["isOptional"] as? Bool ?? false

        // Default values may be in typeSpecificMetadata array:
        // ["LNValueTypeSpecificMetadataKeyDefaultValue", {"int": {"wrapper": N}}]
        let defaultValue = parseDefaultValue(dict["defaultValue"])
            ?? parseDefaultFromTypeSpecificMetadata(dict["typeSpecificMetadata"], valueType: valueType)

        return ParameterMetadata(
            name: name,
            title: title,
            descriptionText: descriptionText,
            valueType: valueType,
            isOptional: isOptional,
            defaultValue: defaultValue
        )
    }

    private static func parseValueType(_ dict: [String: Any]?) -> ValueType? {
        guard let dict = dict else { return nil }

        // Check for primitive wrapper: {"primitive": {"wrapper": {"typeIdentifier": N}}}
        if let primitive = dict["primitive"] as? [String: Any],
           let wrapper = primitive["wrapper"] as? [String: Any],
           let typeID = wrapper["typeIdentifier"] as? Int {
            if let pt = PrimitiveType(rawValue: typeID) {
                return .primitive(pt)
            }
            if typeID == 12 {
                return .intentFile
            }
            return .unknown(typeIdentifier: typeID)
        }

        // Check for link enumeration: {"linkEnumeration": {"identifier": "..."}}
        if let linkEnum = dict["linkEnumeration"] as? [String: Any],
           let id = linkEnum["identifier"] as? String {
            return .linkEnumeration(identifier: id)
        }

        // Check for entity: {"entity": {"typeName": "..."}}
        if let entity = dict["entity"] as? [String: Any],
           let typeName = entity["typeName"] as? String {
            return .entity(typeName: typeName)
        }

        // Check for array: {"array": {"memberValueType": {...}}}
        if let array = dict["array"] as? [String: Any],
           let memberType = parseValueType(array["memberValueType"] as? [String: Any]) {
            return .array(memberType: memberType)
        }

        // Check for measurement: {"measurement": {"unitType": N}}
        if let measurement = dict["measurement"] as? [String: Any],
           let unitType = measurement["unitType"] as? Int {
            return .measurement(unitType: unitType)
        }

        return nil
    }

    private static func parseDefaultValue(_ value: Any?) -> DefaultValue? {
        guard let value = value else { return nil }
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .integer(i) }
        if let d = value as? Double { return .double(d) }
        return nil
    }

    /// Parse default value from typeSpecificMetadata array.
    /// Format: ["LNValueTypeSpecificMetadataKeyDefaultValue", {"int": {"wrapper": N}}]
    private static func parseDefaultFromTypeSpecificMetadata(_ value: Any?, valueType: ValueType) -> DefaultValue? {
        guard let arr = value as? [Any], arr.count >= 2,
              let key = arr[0] as? String,
              key == "LNValueTypeSpecificMetadataKeyDefaultValue",
              let valDict = arr[1] as? [String: Any] else {
            return nil
        }

        // Bool encoded as {"int": {"wrapper": 0}} or {"int": {"wrapper": 1}}
        if case .primitive(.bool) = valueType,
           let intDict = valDict["int"] as? [String: Any],
           let wrapper = intDict["wrapper"] as? Int {
            return .bool(wrapper != 0)
        }

        if let intDict = valDict["int"] as? [String: Any],
           let wrapper = intDict["wrapper"] as? Int {
            return .integer(wrapper)
        }

        if let doubleDict = valDict["double"] as? [String: Any],
           let wrapper = doubleDict["wrapper"] as? Double {
            return .double(wrapper)
        }

        if let strDict = valDict["string"] as? [String: Any],
           let wrapper = strDict["wrapper"] as? String {
            return .string(wrapper)
        }

        return nil
    }

    private static func parseEnums(_ value: Any?) -> [String: EnumMetadata] {
        // enums can be an array of enum definitions or a dict
        var result: [String: EnumMetadata] = [:]

        if let arr = value as? [[String: Any]] {
            for enumDict in arr {
                guard let identifier = enumDict["identifier"] as? String else { continue }
                let cases = (enumDict["cases"] as? [[String: Any]] ?? []).compactMap { caseDict -> EnumCase? in
                    guard let caseID = caseDict["identifier"] as? String else { return nil }
                    let titleDict = caseDict["title"] as? [String: Any]
                    let displayTitle = titleDict?["key"] as? String ?? caseID
                    return EnumCase(identifier: caseID, displayTitle: displayTitle)
                }
                result[identifier] = EnumMetadata(identifier: identifier, cases: cases)
            }
        } else if let dict = value as? [String: Any] {
            for (identifier, enumValue) in dict {
                guard let enumDict = enumValue as? [String: Any] else { continue }
                let cases = (enumDict["cases"] as? [[String: Any]] ?? []).compactMap { caseDict -> EnumCase? in
                    guard let caseID = caseDict["identifier"] as? String else { return nil }
                    let titleDict = caseDict["title"] as? [String: Any]
                    let displayTitle = titleDict?["key"] as? String ?? caseID
                    return EnumCase(identifier: caseID, displayTitle: displayTitle)
                }
                result[identifier] = EnumMetadata(identifier: identifier, cases: cases)
            }
        }

        return result
    }
}

// MARK: - Errors

enum DiscoveryError: Error, CustomStringConvertible {
    case appNotFound(String)
    case noIntentsMetadata(String)
    case cannotReadInfoPlist(String)
    case invalidJSON(String)

    var description: String {
        switch self {
        case .appNotFound(let s): return "App not found: \(s)"
        case .noIntentsMetadata(let s): return "No App Intents metadata found in: \(s)"
        case .cannotReadInfoPlist(let s): return "Cannot read Info.plist from: \(s)"
        case .invalidJSON(let s): return "Invalid JSON in: \(s)"
        }
    }
}
