import AppIntents

struct HelloWorldIntent: AppIntent {
    static var title: LocalizedStringResource = "Say Hello World"
    static var description: IntentDescription = "Returns the string hello world"

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: "hello world")
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
