# action-relay

MCP server that exposes macOS App Intents as tools. Point it at any app that ships App Intents and it'll discover every intent, parse parameter schemas, and let you call them from any MCP client.

No pre-created Shortcuts required. No hand-coded actions per app. It reads the intent metadata that Apple's toolchain bakes into every `.app` bundle and generates the tool definitions automatically.

## How it works

1. **Discovery** — finds `Metadata.appintents/extract.actionsdata` inside the app bundle and parses the JSON into typed intent/parameter metadata
2. **Schema generation** — converts each intent into an MCP tool with a proper JSON Schema (types, required/optional, defaults, enums)
3. **Execution** — builds a single-action workflow plist and sends it to `BackgroundShortcutRunner.xpc` over XPC, the same pipeline that Shortcuts.app uses internally
4. **Output** — extracts return values from the NSKeyedArchiver response and returns them as MCP tool content

## Requirements

- macOS (Apple Silicon)
- Swift 6.0+
- **SIP and AMFI disabled** for raw workflow execution (Option B). Without this, you can only discover intents but not execute them.
- A signing identity with `com.apple.shortcuts.background-running` entitlement (the build script handles this automatically)

## Build

```
./build.sh
```

This runs `swift build` and signs the binary with the right entitlements if AMFI is disabled.

## Usage

### List discovered intents

```
action-relay Notes --list
action-relay UTM --list
action-relay /path/to/SomeApp.app --list
```

Accepts an app name (searched in `/Applications` and `/System/Applications`), a bundle ID, or a direct path.

### Run as MCP server

```
action-relay Notes
```

Starts a stdio MCP server exposing every discovered intent as a tool.

### Add to Claude Code

```
claude mcp add my-notes-tools -- /path/to/action-relay Notes
```

Then restart Claude Code. The tools show up automatically.

## What it looks like

```
$ action-relay UTM --list
[
  {
    "name": "UTMStartActionIntent",
    "description": "Start Virtual Machine — Start a virtual machine.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "vmEntity": { "type": "string" },
        "isRecovery": { "type": "boolean" },
        "isDisposible": { "type": "boolean" }
      },
      "required": ["vmEntity", "isRecovery", "isDisposible"]
    }
  },
  ...
]
```

Notes gives you 47 tools. UTM gives you 9. Any app with App Intents works.

## Limitations

- Execution requires SIP + AMFI disabled (this is a dev/research tool, not something you'd ship)
- Entity parameters (like "which VM" or "which note") currently take string IDs — there's no entity resolution yet, so you need to know the entity identifier
- File parameters (`IntentFile`) are passed as path strings — the actual encoding may need more work for some apps
- Apple is building native MCP support into App Intents (spotted in macOS Tahoe 26.1 beta) which will eventually make this unnecessary

## Project structure

```
Package.swift
Sources/action-relay/
  ActionRelay.swift        # CLI entry + MCP server
  Discovery.swift          # extract.actionsdata parser
  SchemaGenerator.swift    # metadata → MCP tools
  WorkflowBuilder.swift    # workflow plist builder
  IntentExecutor.swift     # async XPC client
  OutputExtractor.swift    # NSKeyedArchiver → MCP content
build.sh                   # build + sign
example-app/               # test app with HelloWorldIntent + GreetIntent
research/                  # reverse engineering notes, Frida scripts, prototypes
```
