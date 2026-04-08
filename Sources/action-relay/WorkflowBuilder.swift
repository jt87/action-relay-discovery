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

    // MARK: - Multi-Action Workflow with Entity Resolution

    /// Information about an entity parameter that needs resolution via a find action.
    struct EntityResolution {
        let paramName: String
        let queryIdentifier: String
        let searchString: String
        let queryUUID: String
        let outputName: String
    }

    /// Build a multi-action workflow that resolves entity parameters by name.
    ///
    /// For each entity parameter with a string value, a "find" action is prepended
    /// that queries the entity by name. The intent action then references the find
    /// action's output via WFTextTokenAttachment.
    static func buildWithEntityResolution(
        bundleID: String,
        appName: String,
        intentIdentifier: String,
        parameters: [String: Any],
        entityResolutions: [EntityResolution]
    ) -> Data {
        var actions: [[String: Any]] = []

        // Build find actions for each entity parameter
        for resolution in entityResolutions {
            let findParams: [String: Any] = [
                "AppIntentDescriptor": [
                    "BundleIdentifier": bundleID,
                    "Name": appName,
                    "AppIntentIdentifier": resolution.queryIdentifier,
                ] as [String: Any],
                "UUID": resolution.queryUUID,
                "CustomOutputName": resolution.outputName,
                "searchString": resolution.searchString,
                "limit": 1,
            ]

            actions.append([
                "WFWorkflowActionIdentifier": "\(bundleID).\(resolution.queryIdentifier)",
                "WFWorkflowActionParameters": findParams,
            ] as [String: Any])
        }

        // Build the intent action with entity refs as WFTextTokenAttachment
        let actionUUID = UUID().uuidString
        var actionParams: [String: Any] = [
            "AppIntentDescriptor": [
                "BundleIdentifier": bundleID,
                "Name": appName,
                "AppIntentIdentifier": intentIdentifier,
            ] as [String: Any],
            "UUID": actionUUID,
        ]

        // Build a lookup from param name → resolution
        let resolutionMap = Dictionary(uniqueKeysWithValues: entityResolutions.map { ($0.paramName, $0) })

        for (key, value) in parameters {
            if let resolution = resolutionMap[key] {
                // Replace with variable reference to the find action's output
                actionParams[key] = [
                    "Value": [
                        "OutputUUID": resolution.queryUUID,
                        "OutputName": resolution.outputName,
                        "Type": "ActionOutput",
                    ] as [String: Any],
                    "WFSerializationType": "WFTextTokenAttachment",
                ] as [String: Any]
            } else {
                actionParams[key] = value
            }
        }

        actions.append([
            "WFWorkflowActionIdentifier": "\(bundleID).\(intentIdentifier)",
            "WFWorkflowActionParameters": actionParams,
        ] as [String: Any])

        let workflow: [String: Any] = [
            "WFWorkflowActions": actions,
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

    // MARK: - Entity Query Workflows

    /// Build a workflow plist for an entity query (find_* tool).
    static func buildEntityQuery(
        bundleID: String,
        appName: String,
        query: QueryMetadata,
        entity: EntityMetadata,
        arguments: QueryFilterArguments
    ) -> Data {
        let actionUUID = UUID().uuidString

        var actionParams: [String: Any] = [
            "AppIntentDescriptor": [
                "BundleIdentifier": bundleID,
                "Name": appName,
                "AppIntentIdentifier": query.identifier,
            ] as [String: Any],
            "UUID": actionUUID,
        ]

        // Add search string if provided
        if let searchText = arguments.searchText {
            actionParams["searchString"] = searchText
        }

        // Add filter predicates
        if !arguments.filters.isEmpty {
            var predicates: [[String: Any]] = []
            for filter in arguments.filters {
                predicates.append([
                    "property": filter.propertyIdentifier,
                    "comparator": filter.comparatorType.rawValue,
                    "value": filter.value,
                ])
            }
            actionParams["filterPredicates"] = predicates
        }

        // Add sort
        if let sortBy = arguments.sortBy {
            actionParams["sortBy"] = sortBy
            actionParams["sortOrder"] = arguments.sortOrder == "descending" ? 1 : 0
        }

        // Add limit
        if let limit = arguments.limit {
            actionParams["limit"] = limit
        }

        let workflow: [String: Any] = [
            "WFWorkflowActions": [
                [
                    "WFWorkflowActionIdentifier": "\(bundleID).\(query.identifier)",
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
            fatalError("Failed to serialize entity query workflow plist: \(error)")
        }
    }

    /// Parse flattened MCP tool arguments back into structured query filter arguments.
    static func convertQueryArguments(
        _ arguments: [String: Any],
        query: QueryMetadata
    ) -> QueryFilterArguments {
        var searchText: String? = nil
        var filters: [QueryFilter] = []
        var sortBy: String? = nil
        var sortOrder: String? = nil
        var limit: Int? = nil

        // Extract search
        if let search = arguments["search"] as? String {
            searchText = search
        }

        // Extract limit
        if let l = arguments["limit"] as? Int {
            limit = l
        } else if let l = arguments["limit"] as? String, let li = Int(l) {
            limit = li
        }

        // Extract sort
        if let sb = arguments["sort_by"] as? String {
            sortBy = sb
        }
        if let so = arguments["sort_order"] as? String {
            sortOrder = so
        }

        // Extract filter parameters
        for filterParam in query.parameters {
            if filterParam.comparators.count == 1 {
                // Single comparator → property name directly
                if let value = arguments[filterParam.propertyIdentifier] {
                    filters.append(QueryFilter(
                        propertyIdentifier: filterParam.propertyIdentifier,
                        comparatorType: filterParam.comparators[0].comparatorType,
                        value: value
                    ))
                }
            } else {
                // Multiple comparators → property_comparator
                for comp in filterParam.comparators {
                    let paramName = "\(filterParam.propertyIdentifier)_\(comp.comparatorType)"
                    if let value = arguments[paramName] {
                        filters.append(QueryFilter(
                            propertyIdentifier: filterParam.propertyIdentifier,
                            comparatorType: comp.comparatorType,
                            value: value
                        ))
                    }
                }
            }
        }

        return QueryFilterArguments(
            searchText: searchText,
            filters: filters,
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit
        )
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

// MARK: - Query Filter Types

struct QueryFilterArguments: Sendable {
    let searchText: String?
    let filters: [QueryFilter]
    let sortBy: String?
    let sortOrder: String?
    let limit: Int?
}

struct QueryFilter: @unchecked Sendable {
    let propertyIdentifier: String
    let comparatorType: ComparatorType
    let value: Any  // always plist-safe primitives (String, Int, Double, Bool)
}
