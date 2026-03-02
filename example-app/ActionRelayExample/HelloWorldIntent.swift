import AppIntents

struct HelloWorldIntent: AppIntent {
    static var title: LocalizedStringResource = "Say Hello World"
    static var description: IntentDescription = "Returns the string hello world"

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: "hello world")
    }
}

struct GreetIntent: AppIntent {
    static var title: LocalizedStringResource = "Greet Person"
    static var description: IntentDescription = "Returns a greeting for the given name"

    @Parameter(title: "Name", description: "The person's name", default: "World")
    var name: String

    @Parameter(title: "Formal", description: "Use formal greeting", default: false)
    var formal: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let greeting = formal ? "Good day, \(name)." : "Hey \(name)!"
        return .result(value: greeting)
    }
}

struct ActionRelayExampleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HelloWorldIntent(),
            phrases: ["Say hello world with \(.applicationName)"],
            shortTitle: "Hello World",
            systemImageName: "hand.wave"
        )
    }
}
