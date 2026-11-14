# crumbs architecture

## Overview

Crumbs is one pipeline split across two processes. Inside the app (a Flutter build that passes the consumer's guard, `!kReleaseMode` as `crumbs:install` writes it: debug and profile builds), producers (watchers, HTTP adapters, or host code calling `CrumbsStore.recordX`) push records into `CrumbsStore`, which redacts at insert, keeps a bounded queue per buffer and re-emits each record on a broadcast stream. The `ext.crumbs.*` handlers answer reads from the queues, and `CrumbsFileSink` listens on the streams. On the host (the plain Dart VM), the `crumbs:*` commands and dowel's MCP server reach those handlers over the VM Service; nothing flows from the host into the app except reads, `clear`, `pause` and `resume`.

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

- Owns: masking by key (HTTP headers, request and response bodies and URL query, the response list being the request list plus the names only a response carries; the Map elements of a query's bindings and a gate check's arguments, since a positional binding has no key), the host `redactor` over free text (also a gate's user id; never a gate's ability or a query's connection name), the JSON-safe pass over bindings, arguments and payloads, and the only way a record becomes `redacted` (a private `Expando`; only log, event, exception and HTTP records carry the flag).
- Must not: hold a record; it returns a record, or null when the `redactor` throws.
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
- Must not: reach the app except through `ctx.callExtension('ext.crumbs.<verb>', ...)`.
- Depends on: `dowel`.

### The Magic producers (in `magic_devtools`, not here)

In a `magic_devtools` release built on crumbs, `MagicCrumbsIntegration`, `MagicHttpFacadeAdapter` and the model, cache, event, gate and query watchers implement this package's contracts from another repository. Crumbs depends on no Magic package. `CrumbsWatcher` and `CrumbsHttpAdapter` are `abstract interface class`es for that reason: a producer in another package implements them and inherits nothing a later release could change under it (`lib/src/watchers/watcher.dart`, `lib/src/adapters/http_adapter.dart`). For the same reason the shipped watchers are `final class`.

## Invariants

| Rule | Why | Verify |
|------|-----|--------|
| Every log, event, exception, HTTP, dump, query and gate record passes `CrumbsRedaction` before it enters a queue or a stream: credential keys are masked always, free text only by the host `redactor`; model and cache records are buffered as given | Buffers are served to agents and written to disk; SECURITY.md states the same two layers | `flutter test test/src/crumbs_store_test.dart --plain-name "masks every text field"`, then `--plain-name "redaction"` |
| No binding, argument or payload value makes a read or a `recordX` call throw: `NaN`, an infinity and any object `jsonEncode` refuses are stored as text, a throwing `toString` as `<unprintable Type>` | One bad value would fail every read of its buffer until evicted, or throw into the host's code | `flutter test test/src/extensions/register_crumbs_extensions_test.dart --plain-name "non-finite numbers"`, then `test/src/crumbs_store_test.dart --plain-name "unprintable values"` |
| A record the `redactor` throws on is dropped, never buffered unmasked | Fail closed: a broken redactor must not leak | `flutter test test/src/crumbs_store_test.dart --plain-name "a throwing redactor drops the record from queue and stream"` |
| `CrumbsFileSink` writes only records with `redacted: true` | A record made before a redactor existed was never masked | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "unredacted"` |
| A caller's file name is only compared with the sink's listing, never joined into a path | Traversal through `ext.crumbs.file` | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "refuses"` |
| A failed background flush stops the sink instead of throwing | A thrown write would be recorded as an exception, written, and fail again | `flutter test test/src/crumbs_file_sink_test.dart --plain-name "a failed batch write stops the sink"` |
| A cursor read never skips or repeats a record, while insertion order is `atUs` order (a record built with an explicit `atUs` behind one already read is skipped); a non-integer `since` is refused | Agents page with `--follow` and trust an empty page | `flutter test test/src/extensions/register_crumbs_extensions_test.dart --plain-name "cursor"` |
| Replaced global hooks are chain-preserved and restored exactly, and the previous handler runs even when recording throws | Sentry and Bugsnag share them | `flutter test test/src/watchers/exception_watcher_test.dart test/src/watchers/dump_watcher_test.dart` |
| One `FramePerfWatcher` counts frames, however many are registered | A doubled `livenessCounter` hides a stalled engine | `flutter test test/src/watchers/frame_perf_watcher_test.dart --plain-name "SECOND watcher instance"` |

## Flows

Install and capture:

1. The consumer's `main()` calls `CrumbsPlugin.install()` inside its build-mode guard; `CRUMBS_DISABLE` skips it, `registerWatcher` and `registerHttpAdapter` alike, and a second call only logs: `lib/src/crumbs_plugin.dart:CrumbsPlugin.install`
2. It installs `LogWatcher` (`Logger.root.onRecord`, root level `ALL`) and registers every extension through dowel's `registerExtensionIdempotent`: `lib/src/extensions/register_crumbs_extensions.dart:registerAllCrumbsExtensions`
3. The host registers more producers (`ExceptionWatcher`, `DumpWatcher`, `FramePerfWatcher`, an adapter; on Magic, `MagicCrumbsIntegration.install()` from a `magic_devtools` release built on crumbs): `CrumbsPlugin.registerWatcher`, `CrumbsPlugin.registerHttpAdapter`
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
| A record field | `lib/src/records/<record>.dart` (`toJson`) | `crumbs_redaction.dart` rebuilds log, event, exception, HTTP, dump, query and gate records field by field, so a field it does not copy is lost once a redactor is set; the line format in the matching command |
| A buffer | `CrumbsKind` and `CrumbsStore` (queue, stream, `recordX`, `recentX`, `clear`, `resetForTesting`), a handler, a command, a descriptor | The provider test; `crumbs_clear` must empty it |
| A filter or cursor on a read | The handler (reuse `_since`, `_page`, `_cursor`), the command, `followCursor` for `--follow` | `doc/mcp/cursor-and-filters.md` |
| Redaction defaults or masking | `lib/src/internal/redaction_lists.dart`, `crumbs_redaction.dart` | `resetRedactionLists`, called by `CrumbsStore.resetForTesting` |
| The `lib/main.dart` wiring | `lib/src/commands/crumbs_install_command.dart` | The `post_install` message in `install.yaml` describes the same wiring by hand |

## Cross-cutting

- Errors: a handler never throws on bad input; it answers `invalidParams` (`since`) or `{error}` (the file handlers). The only error the store swallows is a `redactor` throw, and it drops the record.
- Concurrency: the store is synchronous and single-isolate; the sink runs every disk operation on one future chain.
- State: everything lives in statics, so a hot restart empties the buffers and tests reset through `CrumbsStore.resetForTesting()`.

## Traps

- Crumbs hooks no HTTP client: capture comes from the app's own interceptor calling `CrumbsStore.recordHttp`, and `CrumbsStore.pendingHttpCount` stays 0 until an adapter implements `pendingCount`: `lib/src/adapters/http_adapter.dart`
- The model buffer has no extension, so no agent can read it: `CrumbsStore.recentModels`
- `livenessCounter` advances from a post-frame callback, which also runs while a deferred first frame keeps frames from the engine: `lib/src/watchers/frame_perf_watcher.dart`
- `vsyncStartUs` is not proven to share the `atUs` clock: `lib/src/records/frame_perf_record.dart`

Last reviewed: 2026-11-14, after the review fixes to redaction and the shipped watchers.
