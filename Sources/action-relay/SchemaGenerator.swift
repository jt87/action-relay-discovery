import Foundation
import MCP

enum SchemaGenerator {

    static func generateTools(from metadata: AppIntentMetadata) -> [Tool] {
        metadata.actions.values
            .filter { $0.isDiscoverable }
            .sorted(by: { $0.identifier < $1.identifier })
            .map { action in
                generateTool(action: action, enums: metadata.enums)
            }
    }

    static func generateTool(action: ActionMetadata, enums: [String: EnumMetadata]) -> Tool {
        var properties: [String: Value] = [:]
        var required: [Value] = []

        for param in action.parameters {
            properties[param.name] = schemaForValueType(param.valueType, enums: enums, param: param)
            if !param.isOptional && param.defaultValue == nil {
                required.append(.string(param.name))
            }
        }

        var schemaDict: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schemaDict["required"] = .array(required)
        }
        let inputSchema: Value = .object(schemaDict)

        var description = action.title
        if let desc = action.descriptionText {
            description += " — \(desc)"
        }

        return Tool(
            name: action.identifier,
            description: description,
            inputSchema: inputSchema
        )
    }

    private static func schemaForValueType(
        _ valueType: ValueType,
        enums: [String: EnumMetadata],
        param: ParameterMetadata
    ) -> Value {
        var schema: [String: Value] = [:]

        switch valueType {
        case .primitive(.string):
            schema["type"] = "string"
        case .primitive(.bool):
            schema["type"] = "boolean"
        case .primitive(.integer):
            schema["type"] = "integer"
        case .primitive(.double):
            schema["type"] = "number"
        case .primitive(.date):
            schema["type"] = "string"
            schema["format"] = "date-time"
        case .primitive(.location):
            schema["type"] = "object"
            schema["properties"] = .object([
                "latitude": .object(["type": "number"]),
                "longitude": .object(["type": "number"]),
            ])
            schema["required"] = .array(["latitude", "longitude"])
        case .primitive(.url):
            schema["type"] = "string"
            schema["format"] = "uri"
        case .intentFile:
            schema["type"] = "string"
            schema["description"] = .string("File path")
        case .linkEnumeration(let identifier):
            schema["type"] = "string"
            if let enumMeta = enums[identifier] {
                schema["enum"] = .array(enumMeta.cases.map { .string($0.identifier) })
            }
        case .entity(let typeName):
            schema["type"] = "string"
            schema["description"] = .string("Entity ID for \(typeName)")
        case .array(let memberType):
            schema["type"] = "array"
            let dummyParam = ParameterMetadata(
                name: "item", title: "Item", descriptionText: nil,
                valueType: memberType, isOptional: false, defaultValue: nil
            )
            schema["items"] = schemaForValueType(memberType, enums: enums, param: dummyParam)
        case .measurement(let unitType):
            schema["type"] = "number"
            schema["description"] = .string("Measurement (unit type \(unitType))")
        case .unknown(let typeID):
            schema["type"] = "string"
            schema["description"] = .string("Unknown type (typeIdentifier \(typeID))")
        }

        // Add description from parameter metadata
        if let desc = param.descriptionText, schema["description"] == nil {
            schema["description"] = .string(desc)
        }

        // Add default value
        if let defaultVal = param.defaultValue {
            switch defaultVal {
            case .string(let s): schema["default"] = .string(s)
            case .bool(let b): schema["default"] = .bool(b)
            case .integer(let i): schema["default"] = .int(i)
            case .double(let d): schema["default"] = .double(d)
            }
        }

        return .object(schema)
    }

    /// Serialize tools to JSON for --list output.
    static func toolsToJSON(_ tools: [Tool]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tools)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
