import Foundation

enum MarkdownExporter {

    static func export(_ metadata: AppIntentMetadata) -> String {
        var out = ""

        let discoverable = metadata.actions.values
            .filter { $0.isDiscoverable }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        // Header
        out += "# App Intents — \(metadata.appName)\n\n"
        out += "| | |\n|---|---|\n"
        out += "| **Bundle ID** | `\(metadata.bundleIdentifier)` |\n"
        out += "| **Actions** | \(discoverable.count) |\n"
        if !metadata.entities.isEmpty {
            out += "| **Entities** | \(metadata.entities.count) |\n"
        }
        if !metadata.enums.isEmpty {
            out += "| **Enums** | \(metadata.enums.count) |\n"
        }
        out += "\n"

        // Actions
        if !discoverable.isEmpty {
            out += "---\n\n## Actions\n\n"
            for action in discoverable {
                out += actionSection(action, enums: metadata.enums)
            }
        }

        // Entities
        if !metadata.entities.isEmpty {
            out += "---\n\n## Entities\n\n"
            for (_, entity) in metadata.entities.sorted(by: { $0.key < $1.key }) {
                out += entitySection(entity, queries: metadata.queries, enums: metadata.enums)
            }
        }

        // Enums
        if !metadata.enums.isEmpty {
            out += "---\n\n## Enums\n\n"
            for (_, enumMeta) in metadata.enums.sorted(by: { $0.key < $1.key }) {
                out += enumSection(enumMeta)
            }
        }

        return out
    }

    // MARK: - Sections

    private static func actionSection(_ action: ActionMetadata, enums: [String: EnumMetadata]) -> String {
        var out = ""
        out += "### \(action.title)\n\n"
        out += "`\(action.identifier)`"
        if let desc = action.descriptionText {
            out += " — \(cell(desc))"
        }
        out += "\n\n"

        if !action.parameters.isEmpty {
            out += "| Parameter | Type | Required | Default |\n"
            out += "|-----------|------|:--------:|---------|\n"
            for p in action.parameters {
                let req = (!p.isOptional && p.defaultValue == nil) ? "✓" : ""
                let def = p.defaultValue.map { defaultStr($0) } ?? "—"
                let typeStr = typeName(p.valueType, enums: enums)
                let label = p.title == p.name ? "`\(p.name)`" : "`\(p.name)` (\(cell(p.title)))"
                out += "| \(label) | \(typeStr) | \(req) | \(def) |\n"
            }
            out += "\n"
        }

        if let output = action.outputType {
            out += "**Returns:** \(typeName(output, enums: enums))\n\n"
        }

        out += "\n"
        return out
    }

    private static func entitySection(
        _ entity: EntityMetadata,
        queries: [String: QueryMetadata],
        enums: [String: EnumMetadata]
    ) -> String {
        var out = ""
        out += "### \(entity.displayTypeName)\n\n"
        if entity.typeName != entity.displayTypeName {
            out += "`\(entity.typeName)`\n\n"
        }

        if !entity.properties.isEmpty {
            out += "| Property | Type | Optional |\n"
            out += "|----------|------|:--------:|\n"
            for prop in entity.properties {
                let opt = prop.isOptional ? "✓" : ""
                out += "| `\(prop.identifier)` | \(typeName(prop.valueType, enums: enums)) | \(opt) |\n"
            }
            out += "\n"
        }

        // Inline the query for this entity if one exists
        if let query = queries.values.first(where: { $0.entityType == entity.typeName && $0.isDefaultQuery }) {
            var caps: [String] = []
            if query.capabilities.contains(.search) { caps.append("search") }
            if query.capabilities.contains(.filter) { caps.append("filter") }
            if query.capabilities.contains(.sort)   { caps.append("sort") }
            if !caps.isEmpty {
                out += "**Query capabilities:** \(caps.joined(separator: ", "))\n\n"
            }
            if !query.parameters.isEmpty {
                out += "| Filter property | Comparators |\n"
                out += "|-----------------|-------------|\n"
                for p in query.parameters {
                    let comps = p.comparators.map { $0.comparatorType.description }.joined(separator: ", ")
                    out += "| `\(p.propertyIdentifier)` | \(comps) |\n"
                }
                out += "\n"
            }
            if !query.sortingOptions.isEmpty {
                let opts = query.sortingOptions.map { "`\($0.propertyIdentifier)`" }.joined(separator: ", ")
                out += "**Sort by:** \(opts)\n\n"
            }
        }

        out += "\n"
        return out
    }

    private static func enumSection(_ enumMeta: EnumMetadata) -> String {
        var out = ""
        out += "### \(enumMeta.identifier)\n\n"
        out += "| Value | Display title |\n"
        out += "|-------|---------------|\n"
        for c in enumMeta.cases {
            out += "| `\(c.identifier)` | \(cell(c.displayTitle)) |\n"
        }
        out += "\n\n"
        return out
    }

    // MARK: - Helpers

    private static func typeName(_ valueType: ValueType, enums: [String: EnumMetadata]) -> String {
        switch valueType {
        case .primitive(.string):   return "string"
        case .primitive(.bool):     return "boolean"
        case .primitive(.integer):  return "integer"
        case .primitive(.double):   return "number"
        case .primitive(.date):     return "date"
        case .primitive(.location): return "location"
        case .primitive(.url):      return "URL"
        case .intentFile:           return "file"
        case .linkEnumeration(let id): return "enum `\(id)`"
        case .entity(let name):     return name
        case .array(let member):    return "[\(typeName(member, enums: enums))]"
        case .measurement:          return "measurement"
        case .unknown(let id):      return "unknown (\(id))"
        }
    }

    private static func defaultStr(_ value: DefaultValue) -> String {
        switch value {
        case .string(let s):  return "`\"\(s)\"`"
        case .bool(let b):    return b ? "`true`" : "`false`"
        case .integer(let i): return "`\(i)`"
        case .double(let d):  return "`\(d)`"
        }
    }

    /// Escape characters that would break a Markdown table cell.
    private static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
         .replacingOccurrences(of: "\n", with: " ")
    }
}
