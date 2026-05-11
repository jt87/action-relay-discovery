import ArgumentParser
import Foundation
import MCP

@main
struct ActionRelay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action-relay",
        abstract: "Discover App Intents from a macOS app and expose them as MCP tools",
        version: "0.1.0"
    )

    @Argument(help: "App name, bundle ID, or path to .app bundle")
    var app: String

    @Flag(name: .long, help: "List discovered tools as JSON and exit")
    var list: Bool = false

    @Option(name: .long, help: "Write discovery results to a Markdown file at this path and exit")
    var output: String? = nil

    func run() async throws {
        let appPath: String
        do {
            appPath = try Discovery.resolveAppPath(app)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode.failure
        }

        let metadata: AppIntentMetadata
        do {
            metadata = try Discovery.parse(appPath: appPath)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode.failure
        }

        let tools = SchemaGenerator.generateTools(from: metadata)

        if list {
            let json = try SchemaGenerator.toolsToJSON(tools)
            print(json)
        }

        if let outputPath = output {
            let markdown = MarkdownExporter.export(metadata)
            let expanded = (outputPath as NSString).expandingTildeInPath
            try Data(markdown.utf8).write(to: URL(fileURLWithPath: expanded))
            FileHandle.standardError.write(Data("Exported: \(expanded)\n".utf8))
        }

        if list || output != nil { return }

        // Start MCP server on stdio (list_tools only — no execution)
        let server = Server(
            name: "action-relay",
            version: "0.1.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { _ in
            .init(
                content: [.text("action-relay is a discovery-only server — tool execution is not supported.")],
                isError: true
            )
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
