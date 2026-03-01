# ActionRelayExample

Barebones macOS SwiftUI app with a single App Intent for validating the action-relay discovery and execution pipeline.

## Intent: HelloWorldIntent

- **Title**: "Say Hello World"
- **Description**: Returns the string "hello world"
- **Parameters**: None
- **Shortcut phrase**: "Say hello world with ActionRelayExample"
- **Mangled type name**: `18ActionRelayExample16HelloWorldIntentV`
- **Bundle ID**: `com.actionrelay.example`

## Building

```bash
cd example-app
xcodebuild -project ActionRelayExample.xcodeproj -scheme ActionRelayExample -configuration Debug build
```

## Usage

Launch the app once to register with LaunchServices. The intent then appears in the Shortcuts app and in `extract.actionsdata` at:

```
ActionRelayExample.app/Contents/Resources/Metadata.appintents/extract.actionsdata
```
