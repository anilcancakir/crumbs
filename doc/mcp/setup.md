# MCP Setup

Make the `crumbs_*` tools appear in Claude Code, Cursor or any other MCP client: install crumbs, write the `dowel` entry in `.mcp.json`, reconnect, and optionally filter the tools.

- [Quick Reference](#quick-reference)
- [Install crumbs](#install-crumbs)
- [Write the MCP entry](#write-the-mcp-entry)
- [Clients](#clients)
- [Start the app and verify](#start-and-verify)
- [Filter crumbs tools](#filter-crumbs-tools)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Step | Command |
|:-----|:--------|
| 1. Install | `flutter pub add crumbs`, then `dart run crumbs crumbs:install` |
| 2. Write the entry | `dart run crumbs mcp:install` |
| 3. Reconnect | `/mcp reconnect dowel` in Claude Code |
| 4. Start the app | `./bin/dowel start --device=chrome`, or the `dowel_start` tool |
| 5. Verify | Call `crumbs_tail` with `{"limit": 5}` |

<a name="install-crumbs"></a>
## Install crumbs

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

`crumbs` goes under `dependencies`, not `dev_dependencies`, because `lib/main.dart` imports it. The installer scaffolds the dowel harness, registers `CrumbsDowelProvider` through `lib/app/_plugins.g.dart` and installs crumbs in `lib/main.dart`; see [Installation](../getting-started/installation.md) for the manual route.

<a name="write-the-mcp-entry"></a>
## Write the MCP entry

The `crumbs_*` tools ride on the dowel MCP server, so there is no separate crumbs entry: the server key is `dowel`.

```bash
dart run crumbs mcp:install
```

The command writes the `dowel` entry into `.mcp.json` at the project root, keeps any other entry, and replaces its own on a rerun:

| Scaffold state | Entry |
|:---------------|:------|
| `./bin/dowel` exists, POSIX host | `./bin/dowel mcp:serve` |
| No `./bin/dowel`, or a Windows host | `dart run crumbs mcp:serve` |

```json
{
  "mcpServers": {
    "dowel": {
      "command": "./bin/dowel",
      "args": ["mcp:serve"],
      "cwd": "."
    }
  }
}
```

`cwd` must resolve to the project root, the directory with `pubspec.yaml` and `bin/dispatcher.dart`.

<a name="clients"></a>
## Clients

A client reads its server list at startup and does not reload a changed entry on its own.

| Client | Install or reload |
|:-------|:------------------|
| Claude Code | Reads `.mcp.json` from the project, or `claude mcp add dowel -- ./bin/dowel mcp:serve`; run `/mcp reconnect dowel` after a change |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user); reload the MCP panel |
| Windsurf | `~/.codeium/windsurf/mcp_config.json`; reload the MCP panel |
| Claude Desktop | `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`, Windows: `%APPDATA%\Claude\`); quit and relaunch |

<a name="start-and-verify"></a>
## Start the app and verify

```bash
./bin/dowel start                 # chrome, the default device
./bin/dowel start --device=macos  # a desktop build
```

Then ask the agent for a small read:

```text
crumbs_tail {"limit": 5}
```

A working setup answers `{"messages": [...], "cursor": ...}`; an empty `messages` list means the app runs but has logged nothing yet. An error that says no session is recorded means the app was not started through dowel; one that names a missing `ext.crumbs.*` method means `CrumbsPlugin.install()` did not run in this build. Restart the app with `./bin/dowel restart` when the session is stale.

<a name="filter-crumbs-tools"></a>
## Filter crumbs tools

To hide some crumbs tools from the agent, add deny rules to `.dowel/mcp.json` in the project root:

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

To serve only the crumbs tools, hiding the substrate and every other plugin:

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

Reconnect the client after editing the file. The [dowel filter reference](https://anilcancakir.com/dowel/docs/mcp/tool-reference#filter-configuration) covers the environment variables, the CLI flags and how the three layers combine.

<a name="related-documentation"></a>
## Related Documentation

- [MCP overview](overview.md): how the tools reach the running app.
- [Tool reference](tool-reference.md): every tool's input schema and output shape.
- [Installation](../getting-started/installation.md): the installer and the manual wiring.
- [dowel MCP setup](https://anilcancakir.com/dowel/docs/mcp/setup): the client matrix of the substrate.
