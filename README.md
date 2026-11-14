<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/crumbs/master/.github/crumbs-logo.svg" width="120" alt="Crumbs logo" />
</p>

<h1 align="center">Crumbs</h1>

<p align="center">
  <strong>Let your AI agent read what your Flutter app just did.</strong><br/>
  HTTP traffic, logs, uncaught exceptions, debug prints, events, gate checks, DB queries and cache operations, captured in memory while the app runs and read from one CLI and one MCP server. No stack traces pasted into the chat, no proxy, no SaaS account.
</p>

<p align="center">
  <a href="https://pub.dev/packages/crumbs"><img src="https://img.shields.io/pub/v/crumbs.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/crumbs/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/crumbs/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/crumbs"><img src="https://codecov.io/gh/anilcancakir/crumbs/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/crumbs/score"><img src="https://img.shields.io/pub/points/crumbs" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/crumbs">Documentation</a> ·
  <a href="https://pub.dev/packages/crumbs">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/crumbs/issues">Issues</a>
</p>

crumbs is a passive inspector: it records what the app does and drives nothing. Watchers hook `package:logging`, `FlutterError.onError`, `debugPrint` and the frame scheduler, and call any handler set before them; the log watcher also turns on hierarchical logging and sets `Logger.root.level` to `Level.ALL`, so every log record reaches the buffer. HTTP adapters and the Magic watchers feed the rest. Every record lands in a ring buffer inside the app, and `ext.crumbs.*` VM Service extensions serve those buffers to `crumbs:*` commands and `crumbs_*` MCP tools on [`dowel`](https://pub.dev/packages/dowel). Its sibling [`tapir`](https://pub.dev/packages/tapir) drives the app; crumbs reads what the app captured. crumbs is inspired by [Laravel Telescope](https://laravel.com/docs/telescope), which records the requests, exceptions, logs, queries, cache hits and events of a Laravel app into a queryable timeline; crumbs serves the same kind of timeline to a terminal and an AI agent instead of a web dashboard.

## At a glance

| Fact | Value |
|---|---|
| Package | [`crumbs`](https://pub.dev/packages/crumbs) |
| Install | `flutter pub add crumbs`, then `dart run crumbs crumbs:install` |
| Import | `package:crumbs/crumbs.dart` (`CrumbsPlugin.install()`, behind `if (!kReleaseMode)`) |
| Entry points | `dart run crumbs <command>`, `./bin/dowel <command>`, `CrumbsPlugin.install()`, `CrumbsPlugin.registerWatcher()`, `CrumbsPlugin.registerHttpAdapter()`, `CrumbsStore`, `CrumbsRedaction`, `CrumbsFileSink`, `CrumbsDowelProvider` (`package:crumbs/cli.dart`), `dart run crumbs mcp:serve` |
| Platforms | Any Flutter target that exposes a VM Service in a debug or profile build: Android, iOS, web, macOS, Windows, Linux. `CrumbsFileSink` writes through `dart:io`, so the timeline on disk is not available on the web; on a Windows host `mcp:install` writes a `dart run` entry, never `./bin/dowel` |
| Requires | Dart 3.13, Flutter 3.47; a plugin of [`dowel`](https://pub.dev/packages/dowel) (`^0.0.21`) |
| Dependencies | `dowel`, `logging`, `meta`, the Flutter SDK |
| License | MIT |

## Install

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
dart run crumbs start --device=macos   # dowel records the session every crumbs:* command dials
dart run crumbs crumbs:tail
```

`crumbs:install` scaffolds the dowel harness when `bin/dispatcher.dart` is missing (including the fast `./bin/dowel` launcher), registers crumbs as a dowel plugin, and patches `lib/main.dart`: the imports, `WidgetsFlutterBinding.ensureInitialized()` when missing, and an `!kReleaseMode` block that installs crumbs with the exception and dump watchers, placed before `await Magic.init(` on a Magic app and before `runApp(` otherwise. Re-running it changes nothing. Wired by hand, `main.dart` looks like this:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }
  runApp(const MyApp()); // MyApp is the host app's root widget.
}
```

The guard belongs to the call site: crumbs installs none of its own. `!kReleaseMode` is what the installer writes: it keeps crumbs in debug and profile builds, and a frame measurement needs a profile build. A release build tree-shakes crumbs. Without a guard crumbs ships in release, and anyone who reaches that app's VM Service can read every buffer. `--dart-define=CRUMBS_DISABLE=1` makes `CrumbsPlugin.install()`, `registerWatcher()` and `registerHttpAdapter()` return without installing anything, in a build that must not expose the extensions. The [`example/`](example/) app wires the core watchers and routes Dio traffic into the HTTP buffer.

On a [Magic](https://pub.dev/packages/magic) app, `MagicCrumbsIntegration.install()` from `package:magic_devtools/crumbs.dart`, called after `Magic.init()`, registers the Magic HTTP adapter and the model, cache, event, gate and query watchers. It exists only in a [`magic_devtools`](https://pub.dev/packages/magic_devtools) release built on crumbs: `crumbs:install` writes those lines when the resolved `magic_devtools` ships it, and warns and skips them otherwise. Until that release ships, `MagicTelescopeIntegration` feeds `fluttersdk_telescope`, not crumbs, so the HTTP, event, gate, query and cache buffers of crumbs stay empty in a Magic app.

## What it captures

| Record | Captured by | CLI | MCP tool |
|---|---|---|---|
| `package:logging` records | `LogWatcher`, installed by `CrumbsPlugin.install()` | `crumbs:tail` | `crumbs_tail` |
| Uncaught exceptions | `ExceptionWatcher` (`FlutterError.onError` and `PlatformDispatcher.onError`, chained to any handler already set, such as Sentry's) | none | `crumbs_exceptions` |
| `debugPrint` output | `DumpWatcher` (debug builds only unless `allowInRelease` is set) | `crumbs:dumps` | `crumbs_dumps` |
| Frame timings and build attribution | `FramePerfWatcher` | `crumbs:frames` | `crumbs_frames` |
| HTTP requests | The app's own interceptor (Dio, `package:http`) calling `CrumbsStore.recordHttp`, or a `CrumbsHttpAdapter`; on Magic, `MagicHttpFacadeAdapter` | `crumbs:requests` | `crumbs_requests` |
| In-app events | `MagicEventWatcher` | `crumbs:events` | `crumbs_events` |
| Gate checks | `MagicGateWatcher` | `crumbs:gates` | `crumbs_gates` |
| DB queries | `MagicQueryWatcher` | `crumbs:queries` | `crumbs_queries` |
| Cache operations | `MagicCacheWatcher` | `crumbs:caches` | `crumbs_caches` |
| Model lifecycle | `MagicModelWatcher` | none (`CrumbsStore.recentModels()` in the app) | none |

`crumbs:clear` and `crumbs_clear` empty every buffer, which turns the next read into the output of one action. Each buffer keeps the newest 500 records by default and the frame buffer 3600; `CrumbsStore.setCapacity()` changes one or all of them. A read returns records oldest first. `crumbs:tail` and `crumbs:events` take `--since`, `--json` and `--follow` to stream a buffer from a cursor.

## Secrets and the timeline on disk

| Surface | Behaviour |
|---|---|
| Credential masking | Records are masked by key before they are buffered, with no setup: `Authorization`, `Cookie`, `X-Api-Key` and similar headers, `password`, `token` style keys in a JSON or form body, credential-named parameters in the URL query (`access_token`, `api_key`, the `X-Amz-*` signature of a presigned URL), and the same keys inside the structured bindings of a query and arguments of a gate check, read `********`. Extend the lists with `CrumbsRedaction.hideRequestHeaders()`, `hideRequestParameters()` and `hideResponseParameters()` |
| Text redactor | `CrumbsRedaction.redactor`, a `String Function(String)` you set, runs at insert over the free text of a log, event, exception, HTTP, dump, query and gate record. Without one, a credential written into a log line, a `debugPrint` or a SQL literal is buffered as written; model attributes and cache records are never masked. A redactor that throws drops the record rather than let it through unmasked; the log, event, exception and HTTP records carry a read-only `redacted` flag |
| File sink | `CrumbsFileSink.start(directory: ...)` writes a rotating JSONL timeline of log, event and exception records, and writes only records whose `redacted` flag is true. Read it back with `crumbs:files` |

```dart
CrumbsRedaction.redactor = (String text) => text.replaceAll(RegExp(r'\b\d{13,19}\b'), '[card]');
await CrumbsFileSink.start(directory: '${supportDir.path}/crumbs'); // supportDir is the host's choice.
```

## MCP server and clients

The `crumbs_*` tools ride on the `dowel` MCP server, so the client config key is `dowel`. `dart run crumbs mcp:install` writes the entry into `.mcp.json`: `./bin/dowel mcp:serve` when the fast launcher exists on a POSIX host, and `dart run crumbs mcp:serve` otherwise. Standard config for any client that reads `.mcp.json`:

```json
{ "mcpServers": { "dowel": { "command": "./bin/dowel", "args": ["mcp:serve"], "cwd": "." } } }
```

| Client | Install |
|---|---|
| Claude Code | `claude mcp add dowel -- ./bin/dowel mcp:serve`, then `/mcp reconnect dowel` after a change |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (user) |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| Claude Desktop | `claude_desktop_config.json` (macOS: `~/Library/Application Support/Claude/`, Windows: `%APPDATA%\Claude\`) |

A typical agent session, the app started with `dowel_start` and driven by hand or by tapir:

```text
crumbs_clear {}
# the user (or tapir) exercises the feature
crumbs_requests {"limit": 20}
crumbs_exceptions {}
crumbs_tail {"level": "WARNING"}
crumbs_queries {}
```

| Without crumbs | With crumbs |
|---|---|
| A stack trace scrolls past in the console; you copy it into the chat, then the agent asks for the HTTP response that caused it. | The agent calls `crumbs_exceptions` and `crumbs_requests` and reads both itself. |
| You add `print` calls, hot reload and retry to see what the app sent. | The agent calls `crumbs_clear`, the action runs again, and the next read holds only its records. |

## For AI coding agents

| Do | Because |
|---|---|
| Install crumbs only behind `if (!kReleaseMode)` | Anyone who reaches the VM Service of a build that carries crumbs can read every buffer |
| Start the app with `dart run crumbs start` or `./bin/dowel start`, not `flutter run` | Every `crumbs:*` command and `crumbs_*` tool dials the session dowel records |
| Call `crumbs_clear` before a repro | A buffer holds the whole run, so an old record reads like a new one |
| Register `ExceptionWatcher` (and `DumpWatcher`) when wiring by hand | `CrumbsPlugin.install()` installs only `LogWatcher`; an empty exception buffer otherwise proves nothing |
| Read `livenessCounter` with an empty `crumbs_frames` answer | A counter that does not advance means `FramePerfWatcher` is not registered or the engine draws nothing, not a smooth app |
| Treat `********` in a record as crumbs's mask | The app sent the real credential; crumbs hid it before buffering |
| Set `CrumbsRedaction.redactor` before `CrumbsFileSink.start()` | The sink writes only redacted records and counts the rest in `droppedUnredacted` |
| Page logs and events by passing the `cursor` of one answer back as `since` (CLI: `--since`, or `--json --follow`) | `crumbs_tail` declares `since` and `logger`, `crumbs_events` declares `since` and `type`, and both answer the `cursor` |
| Point the MCP client at the `dowel` key and reconnect after `mcp:install` | The tools ride on the dowel server, and clients do not reload an entry on their own |

## Moving from fluttersdk_telescope

crumbs is the new name of `fluttersdk_telescope`, and dowel the new name of the CLI substrate it runs on. Nothing is migrated automatically:

```bash
flutter pub remove fluttersdk_telescope fluttersdk_artisan && flutter pub add crumbs dowel
mv .artisan .dowel && rm -f .dowel/plugins.json .dowel/installed/fluttersdk_telescope.json
rm bin/dispatcher.dart bin/fsa lib/app/_plugins.g.dart lib/app/commands/_index.g.dart
dart run crumbs crumbs:install
dart run dowel commands:refresh
dart run crumbs mcp:install
```

The old dispatcher and codegen barrels import `fluttersdk_artisan`, and the installer keeps a file that exists, so they go first. Rename the imports and identifiers below, and in your own commands under `lib/app/commands/` replace `package:fluttersdk_artisan/artisan.dart` with `package:dowel/dowel.dart` and `Artisan*` with `Dowel*` before `commands:refresh`. Delete the `fluttersdk` entry from `.mcp.json` and run `/mcp reconnect dowel`. On a Magic app, `MagicTelescopeIntegration` keeps feeding `fluttersdk_telescope`, not crumbs, until a `magic_devtools` release built on crumbs ships; upgrade to it then and rerun `dart run crumbs crumbs:install`.

| Before | After |
|---|---|
| `package:fluttersdk_telescope/telescope.dart` | `package:crumbs/crumbs.dart` |
| `Telescope*` identifiers (`TelescopePlugin`, `TelescopeStore`, `TelescopeRedaction`, `TelescopeFileSink`) | `Crumbs*` (`CrumbsPlugin`, `CrumbsStore`, `CrumbsRedaction`, `CrumbsFileSink`) |
| `telescope:*` commands, `telescope_*` tools, `ext.telescope.*` | `crumbs:*`, `crumbs_*`, `ext.crumbs.*` |
| `TELESCOPE_DISABLE` | `CRUMBS_DISABLE` |
| The `fluttersdk` server key in `.mcp.json` | `dowel` |
| `package:fluttersdk_artisan/artisan.dart`, `Artisan*` in your own commands | `package:dowel/dowel.dart`, `Dowel*` |

An app that already runs an earlier crumbs release renames a few things when it upgrades. The Magic prefix is gone from the model and cache pair: the store methods are `CrumbsStore.recordModel` and `recordCache`, and the records are `ModelRecord` and `CacheRecord`. The frame buffer capacity is set with `CrumbsStore.setCapacity(n, kind: CrumbsKind.framePerf)`, since the dedicated setter is removed. The bundled Dio adapter is removed too: build an `HttpRequestRecord` in your own interceptor and pass it to `CrumbsStore.recordHttp`. The HTTP read answers under the key `requests`, formerly `records`. `CrumbsWatcher` and `CrumbsHttpAdapter` are `abstract interface class`es, so an adapter or watcher `implements` them, and `pendingCount` has no default body.

The [changelog](https://github.com/anilcancakir/crumbs/blob/master/CHANGELOG.md) lists the rest.

## Dependencies

`dowel` for the CLI, the MCP server and the VM Service connection; `logging` for the log watcher; `meta`. The rest is the Flutter SDK. HTTP libraries stay out: the app adds `dio` or any other client itself.

## Links

- [Documentation](https://anilcancakir.com/crumbs/docs/getting-started/installation): installation, quickstart, watchers, redaction, the file sink, buffers, MCP setup and the [MCP tool reference](https://anilcancakir.com/crumbs/docs/mcp/tool-reference)
- [API reference](https://pub.dev/documentation/crumbs/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/crumbs/SKILL.md) for AI coding agents: `npx skills add anilcancakir/crumbs`
- [Changelog](CHANGELOG.md), [report an issue](https://github.com/anilcancakir/crumbs/issues), [security policy](https://github.com/anilcancakir/crumbs/blob/master/SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
