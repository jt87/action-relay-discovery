# App Intents → MCP Bridge: Research Workspace

## Project Goal

Build an MCP server that automatically discovers App Intents from any installed macOS application and exposes them as MCP tools, enabling LLMs to invoke app-specific actions programmatically — without requiring pre-created shortcuts.

No one has built this. Apple is working on native MCP support in App Intents (spotted in macOS Tahoe 26.1 beta) but it's incomplete. We're building the bridge that doesn't exist yet.

## Environment

- **macOS** (Apple Silicon)
- **Tool management**: mise (use `mise install` for tool dependencies)
- **Dynamic instrumentation**: Frida is installed (`frida`, `frida-trace`, `frida-ps`)
- **Languages**: Swift, Objective-C, Python (for Frida scripts), Rust (optional for MCP server)
- **SIP status**: Assume SIP is ENABLED on host unless explicitly told otherwise. Design approaches that work under SIP where possible.

## Architecture Overview

### Discovery Layer (metadata parsing — no private APIs needed)

Every app with App Intents ships a `Metadata.appintents/extract.actionsdata` JSON file inside its `.app` bundle. This contains:
- Intent names, descriptions, parameter schemas
- Entity and query definitions  
- Mangled Swift type names for each intent struct
- Parameter types, defaults, and display info

**Location pattern**: `/Applications/*.app/Contents/Resources/Metadata.appintents/extract.actionsdata` (macOS) or embedded in app bundle.

Scan all installed apps → parse this JSON → generate MCP tool schemas. This is the easy part and can be done right now, no hacks required.

### Execution Layer (the hard part — three approaches ranked by tractability)

#### Approach 1: WorkflowKit / BackgroundShortcutRunner (RECOMMENDED FIRST)

Programmatically construct single-action workflows and execute them via the same XPC pipeline that `shortcuts` CLI uses.

**Execution chain on macOS:**
```
shortcuts CLI → XPC → BackgroundShortcutRunner.xpc → WFWorkflowRunner
```

**Key files:**
- `BackgroundShortcutRunner.xpc`: `/System/Library/PrivateFrameworks/WorkflowKit.framework/XPCServices/BackgroundShortcutRunner.xpc`
- Action identifiers list: `/System/Library/PrivateFrameworks/WorkflowKit.framework/WFActions.plist`
- `siriactionsd`: `/System/Library/PrivateFrameworks/VoiceShortcuts.framework/Support/siriactionsd` — coordinates shortcut execution

**What to reverse-engineer:**
1. Class-dump `BackgroundShortcutRunner.xpc` — find XPC protocol, method signatures
2. Check `shouldAcceptNewConnection` — does it require entitlements/code signing?
3. Determine if it accepts `WFWorkflowRecord` objects directly or only via database lookup
4. Check Console.app for "unexpected class" allowlist errors when connecting

**WFWorkflowRecord structure** (well-documented):
```objc
NSDictionary *action = @{
    @"WFWorkflowActionIdentifier": @"com.someapp.SomeIntent",
    @"WFWorkflowActionParameters": @{ /* intent params */ }
};
```

**Key references:**
- The Apple Wiki WorkflowKit docs: https://theapplewiki.com/wiki/Dev:WorkflowKit.framework
- 0xilis/ShortcutsCLI: open-source reimplementation of `shortcuts` CLI using WorkflowKit
- theevilbit's Monterey Shortcuts tracing: https://theevilbit.github.io/posts/monterey_shortcuts/
- noppefoxwolf/WorkflowKit: Swift library parsing `.shortcut` files

#### Approach 2: Dylib Injection + In-Process Intent Execution

Inject a dylib into a target app. From inside the process, use the Swift runtime to discover and invoke App Intents directly.

**How App Intents types are discovered at runtime:**
- `__TEXT.__swift5_proto` Mach-O section contains protocol conformance records
- `__TEXT.__swift5_types` lists all nominal type descriptors
- `_typeByName(mangledName)` resolves a mangled Swift type name → `Any.Type`
- The `extract.actionsdata` JSON contains mangled names for each intent type

**Dylib injection flow:**
```
MCP Server → Unix socket → dylib inside app → _typeByName() → AppIntent.perform()
```

**Injection methods (SIP intact, non-App Store apps only):**
- Copy app, add dylib with `install_name_tool -add_rpath` or modify load commands
- Re-sign with `codesign --force --deep -s -`
- Launch modified copy

**The hard sub-problems:**
1. Instantiating Swift structs with `@Parameter` property wrappers from outside — need to understand memory layout or find framework's internal instantiation API
2. Setting parameter values — `@Parameter` wraps internal storage, not trivially settable via reflection
3. Calling `perform()` through the protocol witness table on an `Any.Type`

**Key runtime function to investigate:**
```
nm -g /System/Library/Frameworks/AppIntents.framework/AppIntents | swift demangle | grep -i "resolve\|dispatch\|execute\|perform\|run"
```

#### Approach 3: `shortcuts` CLI Wrapper (Boring Fallback)

Wrap the existing `shortcuts` CLI. Requires pre-created shortcuts. This is what every existing MCP server does. Not our goal, but useful as a baseline/fallback.

```bash
shortcuts run "ShortcutName" --input-path /tmp/input.json --output-path /tmp/output.json
```

## Research Methodology

### Static Analysis (host Mac, SIP intact)

```bash
# Dump symbols from AppIntents framework
nm -g /System/Library/Frameworks/AppIntents.framework/AppIntents | swift demangle > appintents_symbols.txt

# Dump symbols from WorkflowKit
nm -g /System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit | swift demangle > workflowkit_symbols.txt

# List intent extensions registered on system
pluginkit -m -p com.apple.intents-service

# Parse an app's extract.actionsdata
find /Applications -name "extract.actionsdata" -exec echo {} \;

# Check Mach-O sections
otool -l /System/Library/Frameworks/AppIntents.framework/AppIntents | grep swift5

# List all XPC services in WorkflowKit
find /System/Library/PrivateFrameworks/WorkflowKit.framework -name "*.xpc"
```

### Class-Dump (requires extracting from dyld shared cache)

```bash
# Extract frameworks from shared cache
dyld-shared-cache-extractor /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e /tmp/dyld-extract/

# Or use dsc_extractor if available
# Then class-dump the extracted framework binary

# Alternative: use dsdump (works on shared cache directly on some versions)
# Or check iOS Simulator frameworks as they're regular files:
# /Library/Developer/CoreSimulator/.../RuntimeRoot/System/Library/PrivateFrameworks/
```

### Dynamic Analysis with Frida

```bash
# Trace BackgroundShortcutRunner XPC
frida-trace -m "*[*BackgroundShortcut* *]" -n BackgroundShortcutRunner

# Trace WorkflowKit activity when running a shortcut
frida-trace -m "*[WFWorkflowRunner *]" -n Shortcuts
frida-trace -m "*[WFAction* *]" -n Shortcuts

# Trace AppIntents framework intent resolution
frida-trace -m "*[*Intent* perform*]" -n SomeTargetApp

# Trace XPC connections
frida-trace -m "*[NSXPCConnection *]" -n Shortcuts

# Trace siriactionsd
frida-trace -m "*[*INIntentDeliverer* *]" -n siriactionsd
```

**Note**: Frida requires SIP disabled for system processes. For third-party apps, Frida can attach with SIP enabled if you re-sign the target or use `frida-gadget`.

### XPC Protocol Reverse Engineering (Tony Gorez method)

1. Find XPC service bundles and check if process is running
2. Disassemble `shouldAcceptNewConnection` — returns 1 = accepts all connections
3. Reverse protocol interface from method signatures in disassembly
4. Build XPC client with `NSXPCConnection`
5. Handle "unexpected class" errors from Console.app by adding to allowed classes set

Reference: https://tonygo.tech/blog/2025/how-to-attack-macos-application-xpc-helpers

## Key Unknowns to Resolve (Priority Order)

1. **BackgroundShortcutRunner XPC authentication** — Does it check entitlements? Can arbitrary processes connect? (Class-dump + test connection)
2. **App Intents in-process XPC listener auth** — Each app with intents has an XPC listener. Does `shouldAcceptNewConnection` check code signature? (Class-dump AppIntents.framework)
3. **Parameter instantiation** — How does the system populate `@Parameter` property wrappers when executing an intent remotely? (Trace with Frida when Shortcuts runs an intent)
4. **`extract.actionsdata` completeness** — Does it contain mangled type names for all intents or just those exposed via `AppShortcutsProvider`? (Parse several apps and compare)

## Existing Prior Art (What NOT to Rebuild)

| Project | What it does | Limitation |
|---------|-------------|------------|
| `mcp-server-apple-shortcuts` (recursechat) | Wraps `shortcuts` CLI | Requires pre-made shortcuts |
| `shortcuts-mcp-server` (Artem Novichkov) | Swift-native CLI wrapper | Same limitation |
| `iMCP` (Mattt) | Native app, Messages/Calendar/Contacts | Hand-coded per service |
| `macos-automator-mcp` (Peter Steinberger) | 200+ AppleScript/JXA scripts | Not intent-based |
| `Apple Native Tools MCP` (Dhravya Shah) | JXA/AppleScript bridge | Hand-coded per app |

## File Organization

```
workspace/
├── CLAUDE.md                    # This file
├── discovery/                   # Metadata parsing layer
│   ├── scan_appintents.py       # Find and parse extract.actionsdata from all apps
│   └── schema_generator.py      # Convert to MCP tool schemas
├── analysis/                    # Reverse engineering output
│   ├── symbols/                 # nm dumps, class-dumps
│   ├── frida-scripts/           # Frida instrumentation scripts
│   └── notes/                   # Findings, XPC protocol descriptions
├── execution/                   # Intent execution prototypes
│   ├── workflowkit-xpc/         # Approach 1: WorkflowKit XPC client
│   ├── dylib-injection/         # Approach 2: In-process dylib
│   └── cli-wrapper/             # Approach 3: shortcuts CLI fallback
└── mcp-server/                  # Final MCP server integration
```

## Immediate Next Steps

1. **Run `find /Applications -path "*/Metadata.appintents/extract.actionsdata" 2>/dev/null`** — enumerate which apps have intent metadata
2. **Parse one app's `extract.actionsdata`** — understand the JSON schema, find mangled type names
3. **`nm` dump of AppIntents.framework and WorkflowKit** — find internal execution/dispatch symbols
4. **`pluginkit -m -p com.apple.intents-service`** — list registered intent extensions
5. **Attempt class-dump of BackgroundShortcutRunner.xpc** — find XPC protocol
6. **Write a Frida script** to trace what happens when `shortcuts run "SomeShortcut"` executes — capture the full XPC message flow

## Important Notes

- Don't install things globally without checking mise first
- Prefer Python for scripting/analysis, Swift for any code that touches Apple frameworks
- When reverse engineering, document findings in `analysis/notes/` as markdown
- Test destructive operations in a VM (UTM recommended for SIP-disabled macOS)
- Apple's native MCP integration in Tahoe 26.1 validates this direction but is too early to depend on
- Private framework headers may be browsable at limneos.net or via GitHub runtime header dumps