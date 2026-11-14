# Crumbs MCP Setup

`crumbs` extends the dowel MCP server with 10 runtime-inspection tools
(`crumbs_*`). This page covers everything needed to make those tools appear in Claude Code,
Cursor, or any other MCP-compatible client.

**Prerequisite:** no prior dowel setup is required. Crumbs's `crumbs:install` command
scaffolds the dowel harness on first run, and `dowel` is pulled in transitively
through crumbs's pubspec.

---

## Step 1: Add the dependency

Add `crumbs` to your `pubspec.yaml` under `dependencies` (not `dev_dependencies`,
because `CrumbsPlugin` is imported by `lib/main.dart`):

```yaml
# pubspec.yaml
dependencies:
  crumbs: ^0.0.4
```

Run `dart pub get` after editing.

### Step 1a: bootstrap with `crumbs:install` (optional but recommended)

If you only want the MCP tools, jump to Step 2. If you also want the 11 CLI commands wired
to the dowel dispatcher, run the one-shot bootstrap now; it scaffolds `bin/dispatcher.dart`,
registers the plugin, and patches `lib/main.dart` in one go:

```bash
dart run crumbs crumbs:install
```

After install, the consumer's fast-cli is available at `./bin/dowel` (native AOT, ~110ms warm).

---

## Step 2: Install the Flutter-side plugin

Inside `lib/main.dart`, install `CrumbsPlugin` before `runApp`, gated at the call site so the
entire subsystem tree-shakes out of release builds. `crumbs:install` writes `kDebugMode`; the
snippet below uses `!kReleaseMode`, which also keeps crumbs in profile builds (see
[Call-site guard](../watchers/index.md#call-site-guard)). When using the Magic framework, place
the call before `Magic.init()` so the Http facade is wired in time:

```dart
import 'package:flutter/foundation.dart';
import 'package:crumbs/crumbs.dart';
import 'package:magic_devtools/crumbs.dart'; // magic_devtools dev_dependency (Magic-stack apps only)

Future<void> main() async {
  if (!kReleaseMode) {
    CrumbsPlugin.install();
  }
  await Magic.init(...);
  if (!kReleaseMode) {
    // Optional: when using the Magic framework, register its adapters and watchers.
    // Call MagicCrumbsIntegration.install() after Magic.init(). Ships in the
    // magic_devtools dev_dependency (import 'package:magic_devtools/crumbs.dart').
    MagicCrumbsIntegration.install();
  }
  runApp(MagicApplication());
}
```

`CrumbsPlugin.install()` registers all `ext.crumbs.*` VM Service extensions and starts the
ring buffers. Extensions are registered via `registerExtensionIdempotent` (from dowel), so hot
restarts are safe.

---

## Step 3: Register CrumbsDowelProvider in bin/dispatcher.dart

If you ran Step 1a (`crumbs:install`), the provider is registered automatically via
`lib/app/_plugins.g.dart` (the codegen barrel auto-discovered by `bin/dispatcher.dart`); skip
to Step 4.

For manual wiring, open `bin/dispatcher.dart` and add `FluttersdkCrumbsDowelProvider()`
to the `baseProviders` list:

```dart
import 'package:dowel/dowel.dart';
import 'package:crumbs/cli.dart';  // FluttersdkCrumbsDowelProvider typedef

Future<void> main(List<String> args) async {
  exit(await runDowel(
    args,
    baseProviders: [
      FluttersdkCrumbsDowelProvider(),
      // ...other providers (TapirDowelProvider, etc.)
    ],
  ));
}
```

The `cli.dart` barrel exports `FluttersdkCrumbsDowelProvider` (a typedef alias for
`CrumbsDowelProvider`) so consumer-side auto-discovery can use a stable name.

---

## Step 4: Ensure the dowel MCP server entry is present

The crumbs tools surface through dowel's MCP server. The `.mcp.json` entry must point at
`dart run dowel:mcp` (not a separate crumbs entry). If you ran
`dart run dowel mcp:install` during dowel setup, the entry is already in place:

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "dart",
      "args": ["run", "dowel:mcp"],
      "cwd": "."
    }
  }
}
```

The `cwd` field must resolve to the directory containing `pubspec.yaml` and `bin/dispatcher.dart`.
The server reads both at startup: `pubspec.yaml` for the project root detection and
`bin/dispatcher.dart` (via the registered providers) for the plugin tool catalog.

---

## Step 5: Reconnect the MCP server

After editing `bin/dispatcher.dart` or `.mcp.json`, the running MCP server process must be
restarted for the new tools to appear in the catalog:

**Claude Code:**

```
/mcp reconnect fluttersdk
```

**Cursor / Windsurf:** Reload the MCP panel or restart the IDE session.

**Claude Desktop:** Fully quit and relaunch.

---

## Step 6: Start the Flutter app and verify

Start the app via dowel so the state file is written:

```bash
./bin/dowel start              # web (chrome, default)
./bin/dowel start --device=macos  # desktop
```

Then ask the agent to check crumbs connectivity:

```
crumbs_tail limit=5
```

A successful response returns a JSON array of recent log records. An empty array means the app is
running but no logs have been emitted yet. An error response means the VM Service URI in
`~/.dowel/state.json` is stale; run `./bin/dowel stop && ./bin/dowel start` to refresh it.

---

## Filtering crumbs tools

To hide specific crumbs tools from the agent's catalog, add deny rules to `.dowel/mcp.json`:

```json
{
  "packages": {
    "allow": null,
    "deny": []
  },
  "tools": {
    "allow": null,
    "deny": ["crumbs_dumps", "crumbs_gates"]
  }
}
```

To expose only crumbs tools (hiding substrate and tapir tools):

```json
{
  "packages": {
    "allow": ["crumbs"],
    "deny": []
  },
  "tools": {
    "allow": null,
    "deny": []
  }
}
```

After editing `.dowel/mcp.json`, run `/mcp reconnect fluttersdk` in Claude Code to reload the
filter. See the [dowel filter reference](https://anilcancakir.com/dowel/docs/mcp/tool-reference#filter-configuration)
for the full three-layer precedence rules (file, env vars, CLI flags).

---

## Related

- [dowel MCP setup](https://anilcancakir.com/dowel/docs/mcp/setup): full client matrix (Cursor, Claude
  Desktop, VS Code, Windsurf, JetBrains, Cline, OpenCode, Gemini CLI).
- [Overview](overview.md): how the 10 tools surface through `CrumbsDowelProvider` and route
  through the VM Service.
- [Tool reference](tool-reference.md): per-tool input schema, output shape, and example invocations.
