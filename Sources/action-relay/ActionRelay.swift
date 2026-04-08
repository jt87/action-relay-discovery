import ArgumentParser
import Foundation
import MCP

@main
struct ActionRelay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action-relay",
        abstract: "MCP server that exposes App Intents as tools",
        version: "0.1.0"
    )

    @Argument(help: "App name, bundle ID, or path to .app bundle")
    var app: String

    @Flag(name: .long, help: "List discovered tools as JSON and exit")
    var list: Bool = false

    func run() async throws {
        // Resolve app path
        let appPath: String
        do {
            appPath = try Discovery.resolveAppPath(app)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode.failure
        }

        // Parse metadata
        let metadata: AppIntentMetadata
        do {
            metadata = try Discovery.parse(appPath: appPath)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode.failure
        }

        // Generate tools
        let tools = SchemaGenerator.generateTools(from: metadata)

        if list {
            // Print tools as JSON and exit
            let json = try SchemaGenerator.toolsToJSON(tools)
            print(json)
            return
        }

        // Start MCP server on stdio
        let server = Server(
            name: "action-relay",
            version: "0.1.0",
            capabilities: .init(tools: .init())
        )

        let executor = IntentExecutor()

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            // Convert MCP arguments to raw dict
            let mcpArgs = params.arguments ?? [:]
            var rawArgs: [String: Any] = [:]
            for (key, value) in mcpArgs {
                rawArgs[key] = valueToAny(value)
            }

            let workflowData: Data

            if params.name.hasPrefix("find_") {
                // Entity query tool
                let entityTypeName = String(params.name.dropFirst("find_".count))
                guard let entity = metadata.entities.values.first(where: { $0.typeName == entityTypeName }),
                      let query = metadata.queries.values.first(where: {
                          $0.entityType == entityTypeName && $0.isDefaultQuery
                      })
                else {
                    return .init(content: [.text("Unknown query tool: \(params.name)")], isError: true)
                }

                let queryArgs = WorkflowBuilder.convertQueryArguments(rawArgs, query: query)
                workflowData = WorkflowBuilder.buildEntityQuery(
                    bundleID: metadata.bundleIdentifier,
                    appName: metadata.appName,
                    query: query,
                    entity: entity,
                    arguments: queryArgs
                )
            } else {
                // Action intent tool
                guard let action = metadata.actions[params.name] else {
                    return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
                }

                let plistParams = WorkflowBuilder.convertArguments(
                    rawArgs, action: action, metadata: metadata
                )

                // Check if any entity parameters need auto-resolution
                var entityResolutions: [WorkflowBuilder.EntityResolution] = []
                for param in action.parameters {
                    guard case .entity(let typeName) = param.valueType,
                          let value = plistParams[param.name] as? String,
                          !value.isEmpty
                    else { continue }

                    // Find the default query for this entity type
                    guard let query = metadata.queries.values.first(where: {
                        $0.entityType == typeName && $0.isDefaultQuery
                    }) else { continue }

                    let entity = metadata.entities.values.first(where: { $0.typeName == typeName })
                    let outputName = entity?.displayTypeName ?? typeName

                    entityResolutions.append(WorkflowBuilder.EntityResolution(
                        paramName: param.name,
                        queryIdentifier: query.identifier,
                        searchString: value,
                        queryUUID: UUID().uuidString,
                        outputName: outputName
                    ))
                }

                if entityResolutions.isEmpty {
                    workflowData = WorkflowBuilder.build(
                        bundleID: metadata.bundleIdentifier,
                        appName: metadata.appName,
                        intentIdentifier: action.identifier,
                        parameters: plistParams
                    )
                } else {
                    workflowData = WorkflowBuilder.buildWithEntityResolution(
                        bundleID: metadata.bundleIdentifier,
                        appName: metadata.appName,
                        intentIdentifier: action.identifier,
                        parameters: plistParams,
                        entityResolutions: entityResolutions
                    )
                }
            }

            do {
                let result = try await executor.execute(workflowData: workflowData)
                let content = OutputExtractor.toMCPContent(result)
                let isError = OutputExtractor.isError(result)
                return .init(content: content, isError: isError)
            } catch {
                return .init(content: [.text("Execution error: \(error)")], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

/// Convert MCP Value to Any for plist serialization.
private func valueToAny(_ value: Value) -> Any {
    if let s = value.stringValue { return s }
    if let i = value.intValue { return i }
    if let d = value.doubleValue { return d }
    if let b = value.boolValue { return b }
    if let arr = value.arrayValue { return arr.map { valueToAny($0) } }
    if let obj = value.objectValue {
        var result: [String: Any] = [:]
        for (k, v) in obj {
            result[k] = valueToAny(v)
        }
        return result
    }
    return "\(value)"
}
