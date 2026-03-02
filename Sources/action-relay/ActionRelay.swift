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
            guard let action = metadata.actions[params.name] else {
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }

            // Convert MCP arguments to plist parameters
            let mcpArgs = params.arguments ?? [:]
            var rawArgs: [String: Any] = [:]
            for (key, value) in mcpArgs {
                rawArgs[key] = valueToAny(value)
            }

            let plistParams = WorkflowBuilder.convertArguments(
                rawArgs, action: action, metadata: metadata
            )

            let workflowData = WorkflowBuilder.build(
                bundleID: metadata.bundleIdentifier,
                appName: metadata.appName,
                intentIdentifier: action.identifier,
                parameters: plistParams
            )

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
