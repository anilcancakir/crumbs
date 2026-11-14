# Quickstart

A 3-step walkthrough taking a fresh Flutter project from zero to a working Crumbs setup
with runtime buffers populated and the first MCP tool call returning live data.

Prerequisites: Flutter SDK 3.22+, Dart SDK 3.4+, a Flutter project (any vanilla
`flutter create` output works). `dowel` is pulled in transitively by
crumbs; you do not need to install it separately. The `crumbs:install` command
scaffolds `bin/dispatcher.dart` for you on first run.

---

### 1. Install Crumbs

Add the dependency, then run the one-shot install through crumbs's own bootstrap entry
point. The install command scaffolds the dowel harness if needed, registers the plugin,
and patches `lib/main.dart` with the `kDebugMode`-guarded install call:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

The command outputs a summary of every file it touched. For a fresh project the summary
looks like:

```
[plugin:install] registered CrumbsDowelProvider
[main.dart]      injected CrumbsPlugin.install() before framework init
[main.dart]      injected import 'package:magic_devtools/crumbs.dart';
[main.dart]      injected MagicCrumbsIntegration.install() after Magic.init() (when magic_devtools is in pubspec)
crumbs:install done
```

When the consumer's `pubspec.yaml` lists `magic_devtools:` and `lib/main.dart` contains
`await Magic.init(`, the install command also injects the `package:magic_devtools/crumbs.dart`
import and a `MagicCrumbsIntegration.install()` block after `Magic.init()` so all 10 watchers
activate automatically. `MagicCrumbsIntegration` ships in the `magic_devtools` package (not in
the `magic` core). On a vanilla Flutter app only the core watchers (`LogWatcher`, plus any you opt
into manually) are wired.

Verify the provider registered correctly. From now on, the dowel fast-cli at `./bin/dowel`
(native AOT, ~110ms warm) is the recommended entry point for every subsequent command:

```bash
./bin/dowel list
```

You should see the `crumbs:` namespace with 11 commands: `crumbs:install`,
`crumbs:tail`, `crumbs:requests`, `crumbs:queries`, `crumbs:caches`,
`crumbs:events`, `crumbs:gates`, `crumbs:dumps`, `crumbs:frames`,
`crumbs:clear`, `crumbs:files`. The same surface is also reachable via the ~3s cold-start fallbacks
`dart run crumbs list` and `dart run dowel list`.

---

### 2. Start the app and generate traffic

Boot the Flutter app via dowel so the VM Service URI is recorded to the state file.
Dowel resolves the running instance from this file for every subsequent CLI and MCP call.

```bash
./bin/dowel start --device=chrome
```

The command scrapes the VM Service URI from `flutter run` output, normalizes it to a
WebSocket address, and writes the full process state (PID, URI, device, project root)
to `~/.dowel/state.json`.

With the app running, navigate the UI to generate HTTP traffic, logs, and any exceptions.
When using the Magic framework, every HTTP call through the `Http` facade, every model save,
and every cache read goes straight into the Crumbs ring buffers. On a vanilla Flutter app,
`package:logging` output and `debugPrint` calls fill the log and dump buffers.

You can also exercise the watchers programmatically from the app:

```dart
// Generates a LogRecordEntry in the console buffer.
Logger('MyFeature').info('quickstart test log');

// Generates a DumpRecord in the dump buffer.
debugPrint('quickstart test dump');
```

---

### 3. Query the buffers from Claude Code (MCP)

Start the dowel MCP server. When your project has `.mcp.json` wired with
`dart run dowel:mcp` as the entry point (written by
`dowel mcp:install`), Claude Code launches the server automatically on attach.
To start it manually:

```bash
./bin/dowel mcp:serve
```

Inside a Claude Code session, the 10 `crumbs_*` tools are now available. A typical
inspection flow:

```
[agent] crumbs_tail {}
```

Returns the most recent log records from the ring buffer, newest first. Filter by level:

```
[agent] crumbs_tail { "level": "warning", "limit": 20 }
```

Inspect HTTP traffic:

```
[agent] crumbs_requests {}
```

Returns every captured HTTP request with method, URL, status code, duration in ms, request
headers, and a body snippet. Useful for verifying what the app actually sent to the API.

Check for uncaught exceptions:

```
[agent] crumbs_exceptions {}
```

Review DB queries with timings:

```
[agent] crumbs_queries {}
```

Clear all buffers before the next test scenario:

```
[agent] crumbs_clear {}
```

All 10 tools follow the same pattern: they query the `ext.crumbs.*` VM Service
extensions registered by `registerAllCrumbsExtensions()` at startup. No source changes
are needed between queries; the buffers update passively as the app runs.

---

## What's next?

- Read the full [Installation](installation) doc for manual wiring options and the
  `DioHttpAdapter` setup for vanilla Flutter.
- Browse the watcher catalog at [anilcancakir.com/crumbs/watchers](https://anilcancakir.com/crumbs/docs/watchers)
  to learn which watchers are opt-in and how chain-preservation works with Sentry and Bugsnag.
- See the full MCP tool input schemas at [anilcancakir.com/crumbs/mcp](https://anilcancakir.com/crumbs/docs/mcp).
- Mask secrets in every record with [Redaction](redaction), persist a timeline with the
  [File sink](file-sink), and follow a buffer with [Cursor and filters](../mcp/cursor-and-filters).

---

All three steps above use only the `crumbs ^0.0.4` package and its
`dowel` dependency. No additional packages are required for the core
watcher surface. Magic-specific watchers activate automatically when `magic_devtools`
is in `dev_dependencies` and `MagicCrumbsIntegration.install()` is called after
`Magic.init()`. `MagicCrumbsIntegration` ships in `magic_devtools`, not in the
`magic` core package.
