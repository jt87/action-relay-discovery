# action-relay

Discovery tool that reads App Intents metadata from any macOS app and exposes the discovered intents as MCP tools.

No pre-created Shortcuts required. No hand-coded actions per app. It reads the intent metadata that Apple's toolchain bakes into every `.app` bundle and generates tool definitions automatically.

## How it works

1. **Discovery** — finds `Metadata.appintents/extract.actionsdata` inside the app bundle and parses the JSON into typed intent/parameter metadata
2. **Schema generation** — converts each intent into an MCP tool with a proper JSON Schema (types, required/optional, defaults, enums)
3. **List** — exposes the tools via MCP `list_tools` so any MCP client can see what intents the app supports

This is a read-only discovery tool. It does not execute intents.

## Requirements

- macOS (Apple Silicon)
- Swift 6.0+

No special entitlements or security configuration needed.

## Build

```
./build.sh
```

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

Starts a stdio MCP server. MCP clients can call `list_tools` to see every discovered intent as a tool definition.

### Add to Claude Code

```
claude mcp add my-notes-tools -- /path/to/action-relay Notes
```

Then restart Claude Code. The discovered intents appear as tools Claude can inspect.

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

## Project structure

```
Package.swift
Sources/action-relay/
  ActionRelay.swift        # CLI entry + MCP server
  Discovery.swift          # extract.actionsdata parser
  SchemaGenerator.swift    # metadata → MCP tools
build.sh                   # build script
example-app/               # test app with HelloWorldIntent + GreetIntent
```
