# Crumbs MCP Integration Overview

<a name="toc"></a>

- [What Crumbs Contributes](#what-crumbs-contributes)
- [Substrate Tools vs Plugin Tools](#substrate-vs-plugin)
- [How the 10 Tools Surface](#how-tools-surface)
- [VM Service Extension Routing](#vm-service-routing)
- [Architecture Diagram](#architecture-diagram)
- [Related](#related)

---

<a name="what-crumbs-contributes"></a>

## What Crumbs Contributes

`crumbs` is a plugin for `dowel`. It contributes **10 MCP tools** via
`CrumbsDowelProvider.mcpTools()` and **11 CLI commands** via `CrumbsDowelProvider.commands()`.

The 10 MCP tools give an LLM agent read-only access to ring buffers that crumbs maintains inside the
running Flutter app. Each tool reads one buffer type: HTTP traffic, log lines, uncaught exceptions,
in-app events, Gate authorization checks, `debugPrint` output, database queries, cache operations, and
per-frame performance. A tenth tool (`crumbs_clear`) wipes all buffers at once as a "set zero" before
a repro.

The tools share a single design rule: **no side effects on the running app**. Reading a buffer is
non-destructive; only `crumbs_clear` mutates state, and that mutation is intentional.

---

<a name="substrate-vs-plugin"></a>

## Substrate Tools vs Plugin Tools

dowel's MCP server distinguishes two categories of tools. Understanding the distinction explains
why crumbs tools appear or disappear in Claude Code's tool list depending on registration.

**Substrate tools** (`dowel_*` prefix) are built into `dowel` itself. They are always
registered when the MCP server starts; they require no plugin, no running app (for most of them), and
no VM Service connection. Examples: `dowel_start`, `dowel_stop`, `dowel_status`, `dowel_logs`.

**Plugin tools** (`crumbs_*` prefix, `tapir_*` prefix, etc.) are contributed by packages that
extend `DowelServiceProvider`. They surface in the MCP catalog **only when** the plugin's provider
is registered in the consumer's `bin/dispatcher.dart` (auto-wired by `crumbs:install`) and the MCP server is (re)started. Plugin tools
always dispatch via the VM Service and therefore require a running Flutter app.

`CrumbsDowelProvider` contributes the `crumbs` plugin tools. Its `providerName`
is `crumbs`, which is the key used in `.dowel/mcp.json` package filter rules.

---

<a name="how-tools-surface"></a>

## How the 10 Tools Surface

The call chain from Claude Code to the Crumbs ring buffer:

1. `CrumbsDowelProvider.mcpTools()` returns a `List<McpToolDescriptor>` with the 10 descriptors.
2. `McpServer.initialize()` collects descriptors from every registered provider and sends the full
   catalog to the MCP client (Claude Code) in the `initialize` response.
3. The agent invokes a tool by name (e.g. `crumbs_tail`) with optional parameters.
4. `McpServer` looks up the `McpToolDescriptor.extensionMethod` for that tool name (e.g.
   `ext.crumbs.console`) and dispatches via `VmServiceClient.callServiceExtension`.
5. The VM Service handler registered by `registerAllCrumbsExtensions()` in the running Flutter app
   reads the matching `CrumbsStore` ring buffer, applies any `limit` / `level` filter params, and
   returns a JSON-encoded payload.
6. `McpServer` wraps the payload in a `CallToolResult` text content block and returns it to the agent.

The pause/resume extensions (`ext.crumbs.pause` / `ext.crumbs.resume`) are registered inside
the app but intentionally absent from `mcpTools()` in the current release; they are V1.x backlog.

---

<a name="vm-service-routing"></a>

## VM Service Extension Routing

Each MCP tool maps to exactly one VM Service extension:

| MCP tool | VM Service extension |
|---|---|
| `crumbs_tail` | `ext.crumbs.console` |
| `crumbs_requests` | `ext.crumbs.requests` |
| `crumbs_exceptions` | `ext.crumbs.exceptions` |
| `crumbs_events` | `ext.crumbs.events` |
| `crumbs_gates` | `ext.crumbs.gates` |
| `crumbs_dumps` | `ext.crumbs.dumps` |
| `crumbs_queries` | `ext.crumbs.queries` |
| `crumbs_caches` | `ext.crumbs.caches` |
| `crumbs_frames` | `ext.crumbs.frames` |
| `crumbs_clear` | `ext.crumbs.clear` |

Crumbs registers 14 `ext.crumbs.*` extensions; four have no MCP tool. `ext.crumbs.pause` and
`ext.crumbs.resume` are V1.x backlog. `ext.crumbs.files` and `ext.crumbs.file` read the timeline
files of a running [file sink](../getting-started/file-sink.md) and are reached through the
`crumbs:files` CLI command. The `since`, `type`, `logger` and `cursor` parameters of
`ext.crumbs.console` and `ext.crumbs.events` are likewise CLI and extension surface, see
[Cursor and filters](cursor-and-filters.md).
Every extension is registered via `registerExtensionIdempotent` (from `dowel`) so that
Flutter hot restarts do not throw `ArgumentError` on duplicate registration. `VmServiceClient` inside
dowel lazy-reconnects on every dispatch call, so `dowel_start` followed immediately by a
`crumbs_*` call picks up the new VM Service URI automatically from `~/.dowel/state.json`.

---

<a name="architecture-diagram"></a>

## Architecture Diagram

```
  Claude Code (MCP client)
        |
        | stdio JSON-RPC  (initialize / tools/call)
        |
  dart run dowel:mcp
        |
   McpServer
        |
        +-- substrate tools (dowel_start, dowel_stop, ...)
        |         |
        |         v
        |   DowelRegistry  (in-process command dispatch)
        |
        +-- crumbs_* plugin tools
                  |
                  | VM Service WebSocket
                  | ws://localhost:PORT/<token>/ws
                  |
             VmServiceClient
                  |
                  | ext.crumbs.*
                  |
          Flutter app isolate (debug mode)
                  |
          CrumbsStore (ring buffers)
          +--------+----------+---------+----------+
          |        |          |         |          |
       console  requests  exceptions  events    gates
          |        |          |         |          |
       dumps   queries    caches    frames    (+ files / file
                                              when a file sink runs)
```

**Flow summary:**

1. The MCP client connects to the server over stdio and calls `initialize`.
2. `McpServer` collects `McpToolDescriptor` instances from `CrumbsDowelProvider.mcpTools()` (and
   any other registered provider) and sends the unified catalog to the client.
3. On each `crumbs_*` tool call, `McpServer` routes via `VmServiceClient` to the matching
   `ext.crumbs.*` handler in the running Flutter isolate.
4. The handler reads the `CrumbsStore` ring buffer, applies filter parameters, and returns JSON.
5. Results return as `CallToolResult` text content; errors carry `isError: true` with an actionable
   message.

---

<a name="related"></a>

## Related

- [dowel MCP overview](https://anilcancakir.com/dowel/docs/mcp/overview): full substrate tool catalog,
  state file contract, and dowel's own architecture diagram.
- [Setup guide](setup.md): how to wire `CrumbsDowelProvider` and enable the 10 tools in Claude
  Code or Cursor.
- [Cursor and filters](cursor-and-filters.md): `since`, `type`, `logger` and `cursor` on the console and
  events extensions, and the `--follow` CLI loop.
- [Tool reference](tool-reference.md): per-tool input schema, output shape, example invocations, and
  the VM Service extension each tool routes through.
