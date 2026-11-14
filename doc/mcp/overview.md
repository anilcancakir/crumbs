# MCP Overview

How the `crumbs_*` MCP tools reach the running app: crumbs contributes them to the dowel MCP server, and each one reads an `ext.crumbs.*` VM Service extension.

- [What crumbs contributes](#what-crumbs-contributes)
- [Substrate tools and plugin tools](#substrate-vs-plugin)
- [How a tool call travels](#how-tools-surface)
- [Tool to extension routing](#vm-service-routing)
- [Architecture diagram](#architecture-diagram)
- [Related Documentation](#related-documentation)

<a name="what-crumbs-contributes"></a>
## What crumbs contributes

`crumbs` is a plugin of [dowel](https://pub.dev/packages/dowel). `CrumbsDowelProvider` contributes the `crumbs:*` CLI commands through `commands()` and the `crumbs_*` MCP tools through `mcpTools()`.

The tools give an agent read access to the ring buffers crumbs keeps inside the running Flutter app: HTTP traffic, log records, uncaught exceptions, in-app events, gate checks, `debugPrint` output, database queries, cache operations and per-frame performance. `crumbs_clear` empties every buffer as a starting point before a repro.

Reading never changes the app. `crumbs_clear` is the one tool that changes state, and only crumbs's own buffers.

<a name="substrate-vs-plugin"></a>
## Substrate tools and plugin tools

The dowel MCP server serves two kinds of tool:

- **Substrate tools** (`dowel_*`) are built into dowel and always registered: `dowel_start`, `dowel_stop`, `dowel_status`, `dowel_logs` and the rest.
- **Plugin tools** (`crumbs_*`, `tapir_*`) come from packages that extend `DowelServiceProvider`. They appear only when the provider is registered with the server (`crumbs:install` does it through `lib/app/_plugins.g.dart`, and `dart run crumbs mcp:serve` preloads it) and the server has been (re)started. They dispatch through the VM Service, so they need a running app.

The provider's `providerName` is `crumbs`, the package name that the `packages` rules of `.dowel/mcp.json` match (see [Filter crumbs tools](setup.md#filter-crumbs-tools)).

<a name="how-tools-surface"></a>
## How a tool call travels

1. `CrumbsDowelProvider.mcpTools()` returns one `McpToolDescriptor` per tool, each naming its `extensionMethod`.
2. The dowel MCP server collects the descriptors of every registered provider and lists them to the client.
3. The agent calls a tool by name, for example `crumbs_tail`, with optional parameters.
4. The server dispatches the call to the descriptor's extension, `ext.crumbs.console` for `crumbs_tail`, over the VM Service of the session dowel recorded.
5. The handler that `CrumbsPlugin.install()` registered in the app reads the matching `CrumbsStore` buffer, applies `limit` (and `level` on the log buffer) and answers JSON.
6. The server returns that JSON to the agent as the tool result.

<a name="vm-service-routing"></a>
## Tool to extension routing

| MCP tool | VM Service extension | Answer key |
|:---------|:---------------------|:-----------|
| `crumbs_tail` | `ext.crumbs.console` | `messages`, `cursor` |
| `crumbs_requests` | `ext.crumbs.requests` | `records` |
| `crumbs_exceptions` | `ext.crumbs.exceptions` | `exceptions` |
| `crumbs_events` | `ext.crumbs.events` | `events`, `cursor` |
| `crumbs_gates` | `ext.crumbs.gates` | `gates` |
| `crumbs_dumps` | `ext.crumbs.dumps` | `dumps` |
| `crumbs_queries` | `ext.crumbs.queries` | `queries` |
| `crumbs_caches` | `ext.crumbs.caches` | `caches` |
| `crumbs_frames` | `ext.crumbs.frames` | `frames`, `livenessCounter` |
| `crumbs_clear` | `ext.crumbs.clear` | `cleared` |

Four extensions have no MCP tool:

- `ext.crumbs.files` and `ext.crumbs.file` read the timeline of a running [file sink](../getting-started/file-sink.md); reach them through `crumbs:files`.
- `ext.crumbs.pause` and `ext.crumbs.resume` stop and restart recording into the store.

The `since`, `type` and `logger` parameters and the `cursor` of `ext.crumbs.console` and `ext.crumbs.events` live on the extensions and the CLI, not on the tool descriptors; see [Cursor and filters](cursor-and-filters.md).

Every extension is registered through dowel's `registerExtensionIdempotent`, so a hot restart does not fail on a duplicate registration.

<a name="architecture-diagram"></a>
## Architecture diagram

```text
  MCP client (Claude Code, Cursor, ...)
        |
        | stdio JSON-RPC (initialize, tools/list, tools/call)
        |
  ./bin/dowel mcp:serve   or   dart run crumbs mcp:serve
        |
        +-- dowel_* substrate tools (in-process commands)
        |
        +-- crumbs_* plugin tools
                  |
                  | VM Service WebSocket of the recorded session
                  |
          Flutter app isolate (debug or profile build)
                  |
          ext.crumbs.* handlers
                  |
          CrumbsStore ring buffers
          (http, logs, exceptions, events, gates, dumps,
           queries, caches, frame perf, models)
```

<a name="related-documentation"></a>
## Related Documentation

- [MCP setup](setup.md): write the `.mcp.json` entry, reconnect a client and filter tools.
- [Tool reference](tool-reference.md): every tool's input schema and output shape.
- [Cursor and filters](cursor-and-filters.md): `since`, `type`, `logger` and `cursor` on the console and events extensions.
- [dowel MCP overview](https://anilcancakir.com/dowel/docs/mcp/overview): the substrate tools and the session file.
