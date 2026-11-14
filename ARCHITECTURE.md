# crumbs architecture

## Overview

Crumbs is one pipeline split across two processes. Inside the app (a Flutter debug or profile build), producers (watchers, HTTP adapters, or host code calling `CrumbsStore.recordX`) push records into `CrumbsStore`, which redacts at insert, keeps a bounded queue per buffer and re-emits each record on a broadcast stream. The `ext.crumbs.*` handlers answer reads from the queues, and `CrumbsFileSink` listens on the streams. On the host (the plain Dart VM), the `crumbs:*` commands and dowel's MCP server reach those handlers over the VM Service; nothing flows from the host into the app except reads, `clear`, `pause` and `resume`.

```text
watchers, adapters, host ──recordX──▶ CrumbsStore ──redact──▶ queue + stream
                                           │                      │
                  ext.crumbs.* handlers ◀──┘          CrumbsFileSink (JSONL, redacted only)
                            ▲
          VM Service ───────┴─────── crumbs:* commands, dowel MCP server (crumbs_* tools)
```

## Codemap

### `CrumbsStore` (`lib/src/crumbs_store.dart`)

- Owns: every buffered record, in static process-wide state; caps per `CrumbsKind`; `pendingHttpCount`.
- Must not: know about watchers, extensions or the VM Service.
- Depends on: the records, `CrumbsRedaction`, `lib/src/internal/`.

### `CrumbsRedaction` (`lib/src/crumbs_redaction.dart`, `lib/src/internal/redaction_lists.dart`)

- Owns: credential masking of HTTP records, the host `redactor`, and the only way a record becomes `redacted` (a private `Expando`).
- Must not: hold a record; it returns a copy or null.
- Depends on: the records.

### `CrumbsFileSink` (`lib/src/crumbs_file_sink.dart`)

- Owns: the timeline files in the directory the host passes, their rotation, pruning and reads.
- Must not: read the queues, or touch a file outside its own name pattern.
- Depends on: the store's streams, `dart:io`.

### `lib/src/extensions/`

- Owns: the JSON answers of `ext.crumbs.*`, their filters and the cursor.
- Must not: keep state.
- Depends on: `CrumbsStore`, `CrumbsFileSink.current`, `FramePerfWatcher.livenessCounter`.

### The host half (`lib/src/commands/`, `CrumbsDowelProvider`, `cursor_follow.dart`, `cli_args.dart`, `bin/crumbs.dart`, `lib/cli.dart`)

- Owns: the commands, the MCP descriptors, the `--follow` loop, the CLI wrapper.
- Must not: import Flutter, `dart:ui` or `lib/crumbs.dart`; it reaches the app only through `ctx.callExtension('ext.crumbs.<verb>', ...)`.
- Depends on: `dowel`.

### The Magic producers (in `magic_devtools`, not here)

`MagicCrumbsIntegration`, `MagicHttpFacadeAdapter` and the model, cache, event, gate and query watchers implement this package's contracts from another repository. Crumbs depends on no Magic package.

## Invariants

| Rule | Why | Verify |
|------|-----|--------|
| Every log, event, exception and HTTP record passes `CrumbsRedaction` before it enters a queue or a stream | Buffers are served to agents and written to disk | `flutter test test/src/crumbs_store_test.dart --plain-name "masks every text field"` |
| A record the `redactor` throws on is dropped, never buffered unmasked | Fail closed: a broken redactor must not leak | `flutter test test/src/crumbs_store_test.dart --plain-name "a throwing redactor drops the record from queue and stream"` |
| `CrumbsFileSink` writes only records with `redacted: true` | A record made before a redactor existed was never masked | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "unredacted"` |
| A caller's file name is only compared with the sink's listing, never joined into a path | Traversal through `ext.crumbs.file` | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "refuses"` |
| A failed background flush stops the sink instead of throwing | A thrown write would be recorded as an exception, written, and fail again | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "a failed batch write stops the sink"` |
| A cursor read never skips or repeats a record; a non-integer `since` is refused | Agents page with `--follow` and trust an empty page | `flutter test test/src/extensions/register_crumbs_extensions_test.dart --plain-name "cursor"` |
| Replaced global hooks are chain-preserved and restored exactly | Sentry and Bugsnag share them | `flutter test test/src/watchers/exception_watcher_test.dart test/src/watchers/dump_watcher_test.dart` |
| One `FramePerfWatcher` counts frames, however many are registered | A doubled `livenessCounter` hides a stalled engine | `flutter test test/src/watchers/frame_perf_watcher_test.dart --plain-name "SECOND watcher instance"` |
| The host half imports no Flutter | It runs under `dart run` on the plain VM | `rg -n -e "^import 'package:flutter" -e "^import 'dart:ui" bin lib/cli.dart lib/src/commands lib/src/crumbs_dowel_provider.dart lib/src/cursor_follow.dart lib/src/cli_args.dart` prints nothing |
| Tool names, extension methods and command order hold | Frozen for agents and `magic_devtools` | `flutter test test/crumbs_dowel_provider_mcp_tools_test.dart` |
| `server.json` version equals `pubspec.yaml` | The MCP registry entry | `flutter test test/server_json_version_test.dart` |

## Flows

Install and capture:

1. The consumer's `main()` calls `CrumbsPlugin.install()` inside its build-mode guard; `CRUMBS_DISABLE` skips it and a second call only logs: `lib/src/crumbs_plugin.dart:CrumbsPlugin.install`
2. It installs `LogWatcher` (`Logger.root.onRecord`, root level `ALL`) and registers every extension through dowel's `registerExtensionIdempotent`: `lib/src/extensions/register_crumbs_extensions.dart:registerAllCrumbsExtensions`
3. The host registers more producers (`ExceptionWatcher`, `DumpWatcher`, `FramePerfWatcher`, an adapter; on Magic, `MagicCrumbsIntegration.install()`): `CrumbsPlugin.registerWatcher`, `CrumbsPlugin.registerHttpAdapter`
4. A producer records: return while paused, redact, append, evict from the front past the cap, emit: `lib/src/crumbs_store.dart:CrumbsStore.recordLog` and its siblings

Read with a cursor:

1. `crumbs:tail` or the `crumbs_tail` tool calls `ext.crumbs.console`: `lib/src/commands/crumbs_tail_command.dart:CrumbsTailCommand.handle`
2. The handler refuses a bad `since`, filters by `level`, `logger` and `since`, pages, and answers `{messages, cursor}`: `lib/src/extensions/register_crumbs_extensions.dart:consoleHandler`
3. With `--follow`, the read repeats every second from the last `cursor`: `lib/src/cursor_follow.dart:followCursor`

Timeline on disk:

1. The host starts a sink; a running one is stopped first, and the new one subscribes before its first disk await: `lib/src/crumbs_file_sink.dart:CrumbsFileSink.start`
2. Each redacted log, event or exception record becomes one JSON line, batched at 64 lines or 500 ms, on one serial queue that also runs rotation, pruning and reads: `CrumbsFileSink._accept`, `CrumbsFileSink._serial`
3. `crumbs:files` lists and reads through the running sink: `lib/src/extensions/register_crumbs_extensions.dart:filesHandler`, `fileHandler`

## Decisions

| Decision | Why | Rejected alternatives | Status |
|----------|-----|-----------------------|--------|
| Redact at insert in the store | One pass covers the buffers, the streams and the sink, so nothing unmasked is ever held | Masking in each handler or in the sink: one forgotten path leaks | Active |
| `redacted` read from a private `Expando` | No caller can build a record that claims to be redacted | A constructor argument | Active |
| Frame perf has its own capacity (3600) | A useful frame window is an order of magnitude larger than an exception buffer | One shared cap, which would inflate every buffer | Active |
| `tapir` reads crumbs through pointers the host assigns | Neither package depends on the other; `magic_devtools` wires both | A tapir dependency on crumbs | Active |

## Change guide

| To change | Touch | Also check |
|-----------|-------|------------|
| A record field | `lib/src/records/<record>.dart` (`toJson`) | `crumbs_redaction.dart` rebuilds log, event, exception and HTTP records field by field, so a field it does not copy is lost once a redactor is set; the line format in the matching command |
| A buffer | `CrumbsKind` and `CrumbsStore` (queue, stream, `recordX`, `recentX`, `clear`, `resetForTesting`), a handler, a command, a descriptor | The provider test; `crumbs_clear` must empty it |
| A filter or cursor on a read | The handler (reuse `_since`, `_page`, `_cursor`), the command, `followCursor` for `--follow` | `doc/mcp/cursor-and-filters.md` |
| Redaction defaults or masking | `lib/src/internal/redaction_lists.dart`, `crumbs_redaction.dart` | `resetRedactionLists`, called by `CrumbsStore.resetForTesting` |
| The `lib/main.dart` wiring | `lib/src/commands/crumbs_install_command.dart` | The `post_install` message in `install.yaml` describes the same wiring by hand |

## Cross-cutting

- Errors: a handler never throws on bad input; it answers `invalidParams` (`since`) or `{error}` (the file handlers). The only error the store swallows is a `redactor` throw, and it drops the record.
- Concurrency: the store is synchronous and single-isolate; the sink runs every disk operation on one future chain.
- State: everything lives in statics, so a hot restart empties the buffers and tests reset through `CrumbsStore.resetForTesting()`.

## Traps

- `DioHttpAdapter` installs nothing and reports `pendingCount` 0; capture comes from the app's own interceptor calling `DioHttpAdapter.recordRequest`: `lib/src/adapters/dio_http_adapter.dart`
- The model buffer has no extension, so no agent can read it: `CrumbsStore.recentModels`
- `livenessCounter` advances from a post-frame callback, which also runs while a deferred first frame keeps frames from the engine: `lib/src/watchers/frame_perf_watcher.dart`
- `vsyncStartUs` is not proven to share the `atUs` clock: `lib/src/records/frame_perf_record.dart`
- `crumbs:queries` and `crumbs:caches` describe `--limit` as "newest first", but every read prints oldest first: `lib/src/commands/`

Last reviewed: 2026-11-14 after the rename to crumbs.
