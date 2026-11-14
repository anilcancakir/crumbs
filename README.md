<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/crumbs/master/.github/crumbs-logo.svg" width="120" alt="Crumbs Logo" />
</p>

<h1 align="center">Crumbs</h1>

<p align="center">
  <strong>Passive runtime inspector for Flutter. Read by humans, queried by AI agents.</strong><br/>
  HTTP, logs, exceptions, <code>debugPrint</code>, DB queries, and Magic events captured over VM Service extensions, surfaced as <code>crumbs:*</code> CLI commands and as 10 MCP tools for Claude Code.
</p>

<p align="center">
  <a href="https://pub.dev/packages/crumbs"><img src="https://img.shields.io/pub/v/crumbs.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/crumbs/actions"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/crumbs/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/crumbs/score"><img src="https://img.shields.io/pub/points/crumbs" alt="pub points"></a>
  <a href="https://github.com/anilcancakir/crumbs/stargazers"><img src="https://img.shields.io/github/stars/anilcancakir/crumbs?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/crumbs">Documentation</a> ·
  <a href="https://pub.dev/packages/crumbs">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/crumbs/issues">Issues</a>
</p>

---

## Why Crumbs?

**Stop pasting stack traces into Claude. Let your agent read them itself.**

Debugging a running Flutter app has always required a mix of `print` statements, custom logging sinks, and network proxies that each tell a different slice of the story. When something breaks, you stitch together log files, Charles captures, and Flutter DevTools windows to reconstruct what happened. The AI workflow is worse: you copy the stack trace out of the console, paste it into Claude Code, copy the failing HTTP response, paste it back, repeat.

**Crumbs closes that loop.** Passive watchers and 14 VM Service extensions register at startup. Every HTTP request, log line, exception, `debugPrint` call, DB query, and Magic-framework lifecycle event lands in a ring buffer. CLI commands (`crumbs:tail`, `crumbs:requests`) stream the buffers for humans; **10 MCP tools** (`crumbs_requests`, `crumbs_exceptions`, `crumbs_tail`, ...) expose the same buffers to AI coding agents like Claude Code, Cursor, and Codex. No copy-paste, no screenshots, no SaaS account. Development-only; a `kDebugMode` or `!kReleaseMode` guard at the call site tree-shakes the entire subsystem on release builds.

```bash
# One-shot self-bootstrap install (works from a fresh consumer)
flutter pub add crumbs
dart run crumbs crumbs:install
```

The install command scaffolds the consumer dowel harness if it is missing, runs `plugin:install crumbs`, and patches `lib/main.dart` so `CrumbsPlugin.install()` runs before `Magic.init()` (or before `runApp` on vanilla Flutter). Everything is gated under `kDebugMode`; release builds tree-shake the entire subsystem.

After install, the consumer gets the dowel fast-cli at `./bin/dowel` (native AOT, ~110ms warm startup) for every subsequent crumbs command. `dart run crumbs <cmd>` keeps working as a slower (~3s cold) fallback.

## Features

| | Feature | Description |
|:--|:--------|:------------|
| 👁 | **10 Watchers** | LogWatcher, ExceptionWatcher, DumpWatcher, FramePerfWatcher, plus 6 Magic-specific adapters covering HTTP, models, cache, events, gates, and DB queries |
| 🤖 | **10 MCP Tools** | `crumbs_requests`, `crumbs_tail`, `crumbs_exceptions`, `crumbs_events`, `crumbs_gates`, `crumbs_dumps`, `crumbs_queries`, `crumbs_caches`, `crumbs_frames`, `crumbs_clear` |
| 🖥 | **11 CLI Commands** | `crumbs:install`, `crumbs:tail`, `crumbs:requests`, `crumbs:queries`, `crumbs:caches`, `crumbs:events`, `crumbs:gates`, `crumbs:dumps`, `crumbs:frames`, `crumbs:clear`, `crumbs:files` |
| 🔌 | **Adapter Contract** | `CrumbsHttpAdapter` (abstract, 3-method shape) for plugging any HTTP client; ships `DioHttpAdapter` for vanilla Dio |
| 📋 | **10 Record Types** | Immutable: `HttpRequestRecord`, `LogRecordEntry`, `ExceptionRecord`, `MagicModelRecord`, `MagicCacheRecord`, `EventRecord`, `GateRecord`, `DumpRecord`, `QueryRecord`, `FramePerfRecord` |
| 📡 | **VM Service Extensions** | 14 extensions: `ext.crumbs.requests`, `.console`, `.exceptions`, `.events`, `.gates`, `.dumps`, `.queries`, `.caches`, `.frames`, `.clear`, `.pause`, `.resume`, `.files`, `.file`. `.console` and `.events` take `since` and answer a `cursor`; `.events` also takes `type`, `.console` also `logger` |
| ✨ | **Magic Integration** | `MagicCrumbsIntegration.install()` wires Http facade adapter + model/cache/event/gate watchers in one call (ships in the `magic_devtools` dev_dependency) |
| 🙈 | **Credential Redaction** | HTTP records are masked before they are buffered (Laravel Telescope's model): `Authorization`, `Cookie`, `X-Api-Key` headers and `password` / `token` style JSON keys read `********`; extend the lists with `CrumbsRedaction.hide*` |
| 🧽 | **Text Redactor** | `CrumbsRedaction.redactor`, a host `String Function(String)` hook run at insert over every log, event, exception and HTTP record (payload keys included). A redactor that throws drops the record; records carry a read-only `redacted` flag |
| 💾 | **File Sink** | `CrumbsFileSink.start(directory:, maxFileBytes:, maxFiles:)` writes a rotating JSONL timeline of redacted log, event and exception records; read it with `crumbs:files`, `ext.crumbs.files` and `ext.crumbs.file`. It writes only redacted records and halts on a write failure |
| 🔒 | **Call-site Gate** | The consumer guards install at the call site: `kDebugMode` (what `crumbs:install` writes) or `!kReleaseMode` (also keeps profile builds); release builds tree-shake the entire crumbs branch on all platforms |
| 🔄 | **Idempotent Install** | Every `registerExtension` call routes through `registerExtensionIdempotent`; hot-restart safe, no `ArgumentError` on re-registration |

## Quick Start

### Option A (recommended): one-shot install

Add the dependency, then let crumbs bootstrap itself via its own CLI entry point. No prior `dowel` wiring is required; crumbs's binary carries the dowel substrate so the install works from a fresh consumer:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

The command scaffolds the consumer dowel harness if it's missing (`bin/dispatcher.dart` + `lib/app/_plugins.g.dart`), runs `plugin:install crumbs`, and patches `lib/main.dart` so `CrumbsPlugin.install()` runs before `Magic.init()` (or before `runApp` on vanilla Flutter). Idempotent; safe to re-run.

For everyday repeat usage, the consumer's `./bin/dowel` (dowel native AOT binary built during install) gives ~110ms warm startup:

```bash
./bin/dowel crumbs:tail
./bin/dowel crumbs:requests
```

`dart run crumbs <cmd>` remains a slower (~3s cold) fallback that always works without the AOT bundle.

### Option B: manual wiring

#### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  crumbs: ^0.0.4
```

#### 2. Install in `main.dart`

Install Crumbs before `Magic.init()` (or before `runApp` for plain Flutter). Wrap every install call in a mode guard at the call site so the entire tooling branch is tree-shaken in release builds: `kDebugMode`, which is what `crumbs:install` writes, or `!kReleaseMode`, which also keeps profile builds (what a performance measurement needs, and what `magic_devtools` uses).

```dart
import 'package:flutter/foundation.dart';
import 'package:crumbs/crumbs.dart';
import 'package:magic_devtools/crumbs.dart'; // magic_devtools dev_dependency (Magic-stack apps only)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Install Crumbs core (auto-installs LogWatcher + registers VM extensions).
  if (!kReleaseMode) {
    CrumbsPlugin.install();

    // 2. Opt-in watchers registered after install().
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }

  // 3. Magic-side adapters run AFTER Magic.init() because they resolve
  //    framework internals (Http facade, Gate manager) from the IoC container.
  await Magic.init(configFactories: [...]);

  if (!kReleaseMode) {
    // MagicCrumbsIntegration ships in magic_devtools (not magic core).
    // Add magic_devtools to dev_dependencies in pubspec.yaml.
    MagicCrumbsIntegration.install();
  }

  runApp(MyApp());
}
```

#### 3. Register the Dowel provider (MCP tools)

In the consumer's `bin/dispatcher.dart` (generated by `dart run dowel install`), crumbs is auto-discovered through `lib/app/_plugins.g.dart` after `plugin:install crumbs`. If you are wiring providers by hand, add `FluttersdkCrumbsDowelProvider()` to the `baseProviders` list so the 10 `crumbs_*` MCP tools are visible to Claude Code and other MCP clients:

```dart
import 'package:dowel/dowel.dart';
import 'package:crumbs/cli.dart' show FluttersdkCrumbsDowelProvider;

exit(await runDowel(
  args,
  baseProviders: [
    FluttersdkCrumbsDowelProvider(),
    // ...other providers (TapirDowelProvider, etc.)
  ],
));
```

## Watchers

| Watcher | Captures | Auto-install? | Notes |
|---------|----------|---------------|-------|
| `LogWatcher` | All `package:logging` Logger calls | Yes | Installed automatically by `CrumbsPlugin.install()`. |
| `ExceptionWatcher` | Unhandled exceptions via `FlutterError.onError` + `PlatformDispatcher.onError` | No | Call `CrumbsPlugin.registerWatcher(ExceptionWatcher())` after install. Both hooks chain-preserve any previously registered handler (Sentry, Bugsnag, etc.). |
| `DumpWatcher` | `debugPrint` + `print` output | No | Overrides `debugPrint` globally; chain-preserves previous override. Active in debug mode only. |
| `MagicHttpFacadeAdapter` | HTTP traffic through the Magic `Http` facade | No | Register via `CrumbsPlugin.registerHttpAdapter(MagicHttpFacadeAdapter())`. Requires Magic framework. |
| `MagicModelWatcher` | Magic Eloquent model `create`, `save`, `delete` lifecycle events | No | Register via `CrumbsPlugin.registerWatcher(MagicModelWatcher())`. Requires Magic framework. |
| `MagicCacheWatcher` | `Cache.get` / `put` / `forget` / `flush` (hit + miss + put + forget + flush operations) | No | Subscribes to magic-side `CacheHit` / `CacheMiss` / `CachePut` / `CacheForget` / `CacheFlush` events. Requires Magic framework. |
| `MagicEventWatcher` | Events dispatched through the Magic `Event` facade | No | Register via `CrumbsPlugin.registerWatcher(MagicEventWatcher())`. Requires Magic framework. |
| `MagicGateWatcher` | `Gate.allows` / `Gate.denies` authorization checks | No | Register via `CrumbsPlugin.registerWatcher(MagicGateWatcher())`. Requires Magic framework. |
| `MagicQueryWatcher` | Magic SQLite + remote DB queries (sql, bindings, timeMs, connection) | No | Subscribes to the magic-side `QueryExecuted` event dispatched by the database connector. Requires Magic framework. |
| `FramePerfWatcher` | Per-frame build/raster/vsync-overhead timings joined with `FlutterTimeline` block attribution | No | Register via `CrumbsPlugin.registerWatcher(FramePerfWatcher())`. Exposes a static `livenessCounter` alongside every read. |

## MCP Tools

Exposed via `CrumbsDowelProvider` when the consumer registers it (auto-wired by `crumbs:install` through `lib/app/_plugins.g.dart` + `bin/dispatcher.dart`). All tools route through `ext.crumbs.*` VM Service extensions and require a running Flutter app.

| Tool | Extension method | Captures |
|------|-----------------|----------|
| `crumbs_tail` | `ext.crumbs.console` | Log ring buffer (`package:logging` records); filter by level + limit. |
| `crumbs_requests` | `ext.crumbs.requests` | HTTP request ring buffer (method, URL, status, duration, headers, body snippet). |
| `crumbs_exceptions` | `ext.crumbs.exceptions` | Uncaught exception ring buffer (type, message, stack trace). |
| `crumbs_clear` | `ext.crumbs.clear` | Wipes all ring buffers atomically. No parameters. |
| `crumbs_events` | `ext.crumbs.events` | In-app event ring buffer (Magic `Event.dispatch` calls; event type + payload). |
| `crumbs_gates` | `ext.crumbs.gates` | Gate authorization check ring buffer (ability, result, user id, argument type). |
| `crumbs_dumps` | `ext.crumbs.dumps` | `debugPrint` output ring buffer (message + timestamp). |
| `crumbs_queries` | `ext.crumbs.queries` | DB query ring buffer (sql, bindings, timeMs, connectionName). |
| `crumbs_caches` | `ext.crumbs.caches` | Cache operation ring buffer (operation: hit / miss / put / forget / flush; key; ttlMs). |
| `crumbs_frames` | `ext.crumbs.frames` | Per-frame performance ring buffer (build/raster/vsync-overhead/total-span micros, block attribution) plus the `livenessCounter`. |

## CLI Commands

Registered via `CrumbsDowelProvider.commands()`. After `crumbs:install` you can invoke any command three ways: through the consumer's fast-cli (`./bin/dowel <command>`, recommended), through crumbs's standalone bin (`dart run crumbs <command>`), or through the consumer dispatcher fallback (`dart run dowel <command>`).

| Command | Purpose |
|---------|---------|
| `crumbs:install` | One-shot bootstrap: scaffolds consumer dowel harness, runs `plugin:install crumbs`, and injects `CrumbsPlugin.install()` into `lib/main.dart`. Detects Magic-stack apps via the `await Magic.init(` anchor and injects BEFORE Magic.init; falls back to `runApp(` for vanilla Flutter. |
| `crumbs:tail` | Print the log buffer. Filter with `--level`, `--limit`, `--since <atUs>` and `--logger <name>`; `--json` prints one JSON object per line; `--follow` keeps polling from the returned cursor until interrupted. |
| `crumbs:requests` | Print the HTTP request buffer (paginated). |
| `crumbs:queries` | Print the DB query buffer (paginated). |
| `crumbs:caches` | Print the cache operation buffer (paginated). |
| `crumbs:events` | Print the in-app event buffer. Filter with `--limit`, `--since <atUs>` and `--type <prefix>`; `--json` and `--follow` as on `crumbs:tail`. |
| `crumbs:gates` | Print the Gate authorization check buffer (paginated). |
| `crumbs:dumps` | Print the `debugPrint` dump buffer (paginated). |
| `crumbs:frames` | Print the per-frame performance buffer (paginated). |
| `crumbs:clear` | Flush all buffers atomically. |
| `crumbs:files` | List the timeline files of the running file sink, or print the lines of one with `--name=<file>` and `--offset=<n>` (0 or a previous `next`; `-v` shows the next offset). |

`followCursor`, the pure Dart loop behind both `--follow` flags, is exported from `package:crumbs/cli.dart`.

## Examples

### `example/`

Vanilla Flutter app (no Magic framework) that exercises every framework-agnostic capture surface: HTTP traffic via the Crumbs Dio interceptor, log output via `package:logging`, uncaught exceptions via `ExceptionWatcher`, and `debugPrint` output via `DumpWatcher`. Demonstrates the minimal install pattern and the in-app overlay dashboard.

```bash
cd example && flutter run -d chrome
```

## Architecture

Crumbs is subsystem-first under `lib/src/`, every directory owns a single concern:

```
lib/
├── crumbs.dart              # Single barrel, re-exports the full public API
├── cli.dart                    # Flutter-free codegen barrel (FluttersdkCrumbsDowelProvider typedef, followCursor)
└── src/
    ├── watchers/               # CrumbsWatcher abstract contract + LogWatcher, ExceptionWatcher, DumpWatcher
    ├── adapters/               # CrumbsHttpAdapter abstract contract + DioHttpAdapter concrete impl
    ├── records/                # Immutable record types: HttpRequestRecord, LogRecordEntry, ExceptionRecord, etc.
    ├── extensions/             # registerAllCrumbsExtensions() aggregator + per-concern VM Service handlers
    ├── commands/               # CrumbsInstallCommand + 10 read/clear/files commands
    ├── crumbs_store.dart    # 10-buffer ring store (singleton); Queue<T> per buffer + broadcast StreamController<T>
    ├── crumbs_redaction.dart # credential lists + the host text redactor applied at insert
    ├── crumbs_file_sink.dart # CrumbsFileSink: rotating JSONL timeline of redacted records
    ├── cursor_follow.dart      # followCursor, the loop behind --follow (exported from cli.dart)
    ├── crumbs_plugin.dart   # CrumbsPlugin.install() entry + registerHttpAdapter() + registerWatcher()
    └── crumbs_dowel_provider.dart  # CrumbsDowelProvider: 11 commands + 10 MCP tool descriptors
```

Boot flow:

```
CrumbsPlugin.install()
    ↓
Register default watchers (LogWatcher auto-installs)
    ↓
registerAllCrumbsExtensions()   # 14 ext.crumbs.* VM Service extensions, idempotent
    ↓
Consumer registers CrumbsDowelProvider (auto-wired by `crumbs:install` via bin/dispatcher.dart + _plugins.g.dart)
    ↓
dowel mcp:serve   ->   10 crumbs_* tools surface to MCP clients (Claude Code, Cursor, etc.)
```

Every concrete watcher and record type is a `final class`. The two adapter contracts (`CrumbsWatcher`, `CrumbsHttpAdapter`) are `abstract class` with frozen 3-method signatures (`name`, `install`, `uninstall`). Magic-side glue (`MagicHttpFacadeAdapter`, `MagicModelWatcher`, etc.) depends on these contracts; any signature change requires a coordinated bump across both repos.

## Compared to

| Tool | What it does | Where crumbs wins |
|---|---|---|
| **[Sentry Flutter](https://pub.dev/packages/sentry_flutter)** | Production crash + perf reporting via external SaaS | Local-only; debug-only; CLI + MCP queryable from your agent; no DSN, no SaaS account |
| **[Talker / talker_flutter](https://pub.dev/packages/talker_flutter)** | In-app log overlay, Dio interceptor | VM Service surface (queryable by tools); MCP server for AI agents; framework-aware model / cache / event / gate watchers |
| **[Alice](https://pub.dev/packages/alice)** | In-app HTTP request overlay UI | Captures 10 buffers (not just HTTP); passive (no shake-to-open overlay); CLI streaming; AI agent access; debug tree-shake |
| **[Flutter DevTools](https://docs.flutter.dev/tools/devtools/overview)** | Official browser-based inspector | Programmatic access (CLI + MCP), not just human-via-browser; ring-buffered records you can query between iterations; domain-aware (Magic) watchers |
| **[mcp_flutter](https://github.com/Arenukvern/mcp_flutter)** | MCP toolkit for AI-driven UI interaction (tap, scroll, snapshot) | Complementary, not competitive: crumbs owns runtime telemetry (HTTP, exceptions, queries); mcp_flutter owns UI automation |

## AI Agent Integration

Crumbs is the first Flutter MCP server focused on **runtime observability** (HTTP, exceptions, queries, cache) rather than UI automation. The 10 `crumbs_*` tools give Claude Code, Cursor, Codex, or any MCP-compatible agent direct read access to every runtime buffer: inspect HTTP traffic without a proxy, read logs without grepping output, catch exceptions without scrolling DevTools.

### One-line `.mcp.json` install

`crumbs:install` auto-writes `.mcp.json` for you. Or wire it manually for any MCP-compatible client:

```jsonc
// .mcp.json (project root) — Claude Code / Codex / Cursor / Goose / VS Code Copilot
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/dowel",
      "args": ["mcp:serve"],
      "cwd": "."
    }
  }
}
```

After this, restart your MCP client. The 10 `crumbs_*` tools (plus the substrate's `dowel_*` tools) surface automatically in `/mcp`.

### Before / after

| Without crumbs | With crumbs |
|---|---|
| Stack trace appears in your console. You copy it. You paste it into Claude. Claude asks for the HTTP response that triggered it. You scroll, copy, paste. | Claude calls `crumbs_exceptions` → reads the last 500 captured exceptions with timestamps + stack traces. Claude calls `crumbs_requests` → reads matched HTTP records. Claude proposes the fix. |
| You hot-reload, retry, paste again. | Claude calls `crumbs_clear` between iterations. The fix loop closes without you in the middle. |

### Typical agent session

```
[agent] dowel_start { device: chrome }          // launch the app
[agent] <exercise the feature under inspection>
[agent] crumbs_requests {}                     // inspect all HTTP calls made
[agent] crumbs_tail { level: warning }         // filter logs to warnings and above
[agent] crumbs_exceptions {}                   // check for any uncaught exceptions
[agent] crumbs_queries {}                      // review DB queries and timings
[agent] crumbs_clear {}                        // flush buffers before the next scenario
[agent] dowel_stop                              // tear down
```

For agents that read structured project context at attach time, the canonical entry point is [`llms.txt`](llms.txt) at the repo root (also published at `https://anilcancakir.com/crumbs/docs/llms.txt`). It enumerates the watcher surface, the VM extension catalog, and every MCP tool input schema in agent-readable form.

## Documentation

Full docs with live examples at **[anilcancakir.com/crumbs](https://anilcancakir.com/crumbs)**.

| Topic | |
|:------|:-|
| [Getting Started](https://anilcancakir.com/crumbs/docs/getting-started/) | Overview, requirements, first install |
| [Watchers](https://anilcancakir.com/crumbs/docs/watchers/) | All 10 watchers: setup, chain-preserve pattern, Magic adapters |
| [MCP Tools](https://anilcancakir.com/crumbs/docs/mcp/) | Every tool, every input schema, filter parameters |
| [Redaction](doc/getting-started/redaction.md) | Credential lists, `CrumbsRedaction.redactor`, the `redacted` flag |
| [File sink](doc/getting-started/file-sink.md) | `CrumbsFileSink`, rotation, fail-closed writes, `crumbs:files` |
| [Buffers](doc/getting-started/buffers.md) | `CrumbsStore.setCapacity`, `CrumbsKind`, `atUs`, `limit` and `minLevel` semantics |
| [Cursor and filters](doc/mcp/cursor-and-filters.md) | `since` / `type` / `logger` / `cursor` on the read extensions, `--follow`, `followCursor` |

## Contributing

```bash
git clone https://github.com/anilcancakir/crumbs.git
cd crumbs && dart pub get
flutter test && dart analyze
```

The baseline is 497 tests green. New behavior ships with the matching test (red, green, refactor). `dart format lib/ test/ bin/` must produce no diff and `dart analyze` must report zero issues across `lib/`, `test/`, and `bin/`.

Before opening a pull request, also run:

```bash
dart format lib/ test/ bin/         # zero diff
dart analyze                         # zero issues
dart pub publish --dry-run           # validate the publish archive
```

[Report a bug](https://github.com/anilcancakir/crumbs/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/anilcancakir/crumbs/issues/new?template=feature_request.yml)

## Inspiration

Crumbs is inspired by [**Laravel Telescope**](https://laravel.com/docs/telescope), the elegant developer-tools assistant for Laravel that records every request, exception, log, query, cache hit, and event into a queryable timeline. The same pattern, ported to Flutter, with two additions that make sense for 2026: a CLI-first surface for terminal-native developers and a 10-tool MCP server so AI coding agents can read the timeline directly.

## Part of the Magic SDK suite

Crumbs is one of seven packages in the [FlutterSDK Magic suite](https://fluttersdk.com), a Laravel-inspired Flutter ecosystem:

- **[magic](https://pub.dev/packages/magic)** — Laravel-style framework (facades, ORM, providers, controllers, routing)
- **[wind](https://pub.dev/packages/wind_kit)** — Tailwind-style className UI primitives for Flutter
- **[dowel](https://pub.dev/packages/dowel)** — Pure Dart CLI + MCP substrate that crumbs extends
- **[tapir](https://pub.dev/packages/tapir)** — E2E gesture / snapshot driver via VM extensions
- **crumbs** (this package) — Runtime observability via VM extensions + MCP
- **[magic_tinker](https://pub.dev/packages/magic_tinker)** — Connected REPL into the running app
- **[magic_starter](https://pub.dev/packages/magic_starter)** — Auth / profile / teams scaffolding

## License

MIT, see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If Crumbs saves you debugging time, <a href="https://github.com/anilcancakir/crumbs">give it a star</a>, it helps others discover it.</sub>
</p>
