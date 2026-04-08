import Foundation
import MCP

enum SchemaGenerator {

    static func generateTools(from metadata: AppIntentMetadata) -> [Tool] {
        // Build a lookup: entity typeName → find_ tool name
        let entityQueryNames = buildEntityQueryNameMap(metadata: metadata)
        // Build a lookup: entity typeName → display name (for friendly descriptions)
        let entityDisplayNames = buildEntityDisplayNameMap(metadata: metadata)

        var tools: [Tool] = metadata.actions.values
            .filter { $0.isDiscoverable }
            .sorted(by: { $0.identifier < $1.identifier })
            .map { action in
                generateTool(action: action, enums: metadata.enums, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames)
            }

        // Add find_* tools for entity queries
        tools.append(contentsOf: generateQueryTools(from: metadata, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames))

        return tools.sorted(by: { $0.name < $1.name })
    }

    /// Build map from entity typeName to display name.
    private static func buildEntityDisplayNameMap(metadata: AppIntentMetadata) -> [String: String] {
        var map: [String: String] = [:]
        for (_, entity) in metadata.entities {
            map[entity.typeName] = entity.displayTypeName
        }
        return map
    }

    /// Build map from entity typeName to the find_ tool name.
    private static func buildEntityQueryNameMap(metadata: AppIntentMetadata) -> [String: String] {
        var map: [String: String] = [:]
        for (_, entity) in metadata.entities {
            guard entity.defaultQueryIdentifier != nil else { continue }
            // Find the default query for this entity
            let hasQuery = metadata.queries.values.contains { q in
                q.entityType == entity.typeName && q.isDefaultQuery
            }
            if hasQuery {
                map[entity.typeName] = "find_\(entity.typeName)"
            }
        }
        return map
    }

    static func generateTool(
        action: ActionMetadata,
        enums: [String: EnumMetadata],
        entityQueryNames: [String: String] = [:],
        entityDisplayNames: [String: String] = [:]
    ) -> Tool {
        var properties: [String: Value] = [:]
        var required: [Value] = []

        for param in action.parameters {
            properties[param.name] = schemaForValueType(
                param.valueType, enums: enums, param: param, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames
            )
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

    // MARK: - Query Tool Generation

    static func generateQueryTools(from metadata: AppIntentMetadata, entityQueryNames: [String: String] = [:], entityDisplayNames: [String: String] = [:]) -> [Tool] {
        var tools: [Tool] = []

        for (_, entity) in metadata.entities.sorted(by: { $0.key < $1.key }) {
            guard let defaultQueryID = entity.defaultQueryIdentifier else { continue }

            // Find the matching query
            let query = metadata.queries.values.first { q in
                q.fullyQualifiedIdentifier == defaultQueryID
                    || "\(metadata.bundleIdentifier.split(separator: ".").last ?? "").\(q.identifier)" == defaultQueryID.replacingOccurrences(of: metadata.bundleIdentifier + ".", with: "\(metadata.bundleIdentifier.split(separator: ".").last ?? "").")
                    || q.entityType == entity.typeName && q.isDefaultQuery
            }

            guard let query = query else { continue }

            let tool = generateQueryTool(
                entity: entity,
                query: query,
                enums: metadata.enums,
                entityQueryNames: entityQueryNames,
                entityDisplayNames: entityDisplayNames
            )
            tools.append(tool)
        }

        return tools
    }

    private static func generateQueryTool(
        entity: EntityMetadata,
        query: QueryMetadata,
        enums: [String: EnumMetadata],
        entityQueryNames: [String: String] = [:],
        entityDisplayNames: [String: String] = [:]
    ) -> Tool {
        var properties: [String: Value] = [:]

        // Add search param if capabilities include search
        if query.capabilities.contains(.search) {
            properties["search"] = .object([
                "type": "string",
                "description": .string("Search string to find \(entity.displayTypeName.lowercased())s"),
            ])
        }

        // Add filter parameters from query comparators
        if query.capabilities.contains(.filter) {
            for filterParam in query.parameters {
                if filterParam.comparators.count == 1 {
                    // Single comparator → use property name directly
                    let comp = filterParam.comparators[0]
                    let paramName = filterParam.propertyIdentifier
                    properties[paramName] = schemaForComparatorValue(
                        comp, title: filterParam.localizedTitle, enums: enums, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames
                    )
                } else {
                    // Multiple comparators → property_comparator
                    for comp in filterParam.comparators {
                        let paramName = "\(filterParam.propertyIdentifier)_\(comp.comparatorType)"
                        properties[paramName] = schemaForComparatorValue(
                            comp, title: filterParam.localizedTitle, enums: enums, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames
                        )
                    }
                }
            }
        }

        // Add sort parameters if capabilities include sort
        if query.capabilities.contains(.sort) && !query.sortingOptions.isEmpty {
            let sortValues = query.sortingOptions.map { Value.string($0.propertyIdentifier) }
            properties["sort_by"] = .object([
                "type": "string",
                "enum": .array(sortValues),
                "description": .string("Property to sort results by"),
            ])
            properties["sort_order"] = .object([
                "type": "string",
                "enum": .array(["ascending", "descending"]),
                "description": .string("Sort order"),
                "default": .string("ascending"),
            ])
        }

        // Always add optional limit
        properties["limit"] = .object([
            "type": "integer",
            "description": .string("Maximum number of results to return"),
        ])

        let schemaDict: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
        ]
        let inputSchema: Value = .object(schemaDict)

        let toolName = "find_\(entity.typeName)"
        var description = "Find \(entity.displayTypeName)"
        if let desc = query.descriptionText {
            description += " — \(desc)"
        }

        return Tool(
            name: toolName,
            description: description,
            inputSchema: inputSchema
        )
    }

    private static func schemaForComparatorValue(
        _ comparator: QueryComparator,
        title: String,
        enums: [String: EnumMetadata],
        entityQueryNames: [String: String] = [:],
        entityDisplayNames: [String: String] = [:]
    ) -> Value {
        let dummyParam = ParameterMetadata(
            name: "value", title: title, descriptionText: nil,
            valueType: comparator.valueType, isOptional: true, defaultValue: nil
        )
        var schema = schemaForValueType(comparator.valueType, enums: enums, param: dummyParam, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames)

        // Add comparator type to description
        if var obj = schema.objectValue {
            let existingDesc = obj["description"]?.stringValue ?? title
            obj["description"] = .string("\(existingDesc) (\(comparator.comparatorType))")
            schema = .object(obj)
        }

        return schema
    }

    private static func schemaForValueType(
        _ valueType: ValueType,
        enums: [String: EnumMetadata],
        param: ParameterMetadata,
        entityQueryNames: [String: String] = [:],
        entityDisplayNames: [String: String] = [:]
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
            let displayName = entityDisplayNames[typeName] ?? typeName
            if entityQueryNames[typeName] != nil {
                // Entity has a default query — will be auto-resolved by name
                schema["description"] = .string("Name of the \(displayName.lowercased()) to use")
            } else {
                schema["description"] = .string("Identifier for \(displayName)")
            }
        case .array(let memberType):
            schema["type"] = "array"
            let dummyParam = ParameterMetadata(
                name: "item", title: "Item", descriptionText: nil,
                valueType: memberType, isOptional: false, defaultValue: nil
            )
            schema["items"] = schemaForValueType(memberType, enums: enums, param: dummyParam, entityQueryNames: entityQueryNames, entityDisplayNames: entityDisplayNames)
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
