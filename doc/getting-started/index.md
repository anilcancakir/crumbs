# Getting Started

Everything you need to add `crumbs` to your project, wire the watchers,
and start inspecting runtime state from the CLI or an MCP-connected AI agent.

## Pick your path

- [**Installation**](installation): Add crumbs to a Flutter project step by step.
- [**Quickstart**](quickstart): 3-step end-to-end walkthrough from install to first MCP tool call.

## What is crumbs?

Crumbs is a passive runtime inspector for Flutter apps. It registers a set of watchers and VM
Service extensions at startup, captures every HTTP request, log line, exception, `debugPrint` call,
DB query, and Magic-framework lifecycle event into ring buffers, then surfaces those buffers through
CLI commands and MCP tools without ever modifying app behavior.

One `crumbs:install` command wires everything end-to-end. Crumbs ships its own
bootstrap CLI entry point so the command works from a fresh consumer without any prior
`dowel` wiring:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

The command scaffolds the consumer dowel harness if it is missing, runs
`plugin:install crumbs`, and patches `lib/main.dart` so
`CrumbsPlugin.install()` runs at startup inside a `kDebugMode` guard. Release builds
tree-shake the entire subsystem; there is zero production overhead. The guard belongs to the call
site: `kDebugMode` is what the installer writes, and `!kReleaseMode` is the guard to use when profile
builds should carry crumbs too (see [Call-site guard](../watchers/index.md#call-site-guard)).

After install, the dowel native AOT launcher at `./bin/dowel` gives ~110ms warm startup
for every subsequent crumbs command (`./bin/dowel crumbs:tail`, etc.).

## Requirements

| Dependency | Minimum Version | Notes |
|:-----------|:----------------|:------|
| Dart SDK | `>= 3.4.0` | Required. |
| Flutter SDK | `>= 3.22.0` | Required. Crumbs needs the Flutter runtime for VM Service extensions. |
| dowel | `^0.0.20` | Pulled in transitively by crumbs; the install command and MCP tools work without prior setup. |
| Magic stack | optional | Enables 6 additional watchers: HTTP facade, models, cache, events, gates, queries. |

Crumbs is a development package: it must never run in a release build. A `kDebugMode` or
`!kReleaseMode` guard at the consumer install site is load-bearing, because all release-mode
tree-shaking depends on it. Crumbs itself installs no guard.

## What gets captured

Out of the box after `crumbs:install`, Crumbs captures:

- **Logs**: all `package:logging` records via `LogWatcher` (auto-installed).
- **Exceptions**: uncaught errors via `ExceptionWatcher` (opt-in, chain-preserves Sentry/Bugsnag).
- **debugPrint output**: via `DumpWatcher` (opt-in, chain-preserves prior override).

With the Magic stack (`MagicCrumbsIntegration.install()` from `magic_devtools`):

- **HTTP traffic** through the Magic `Http` facade.
- **Model lifecycle**: create, save, delete events on Magic Eloquent models.
- **Cache operations**: hit, miss, put, forget, flush via the `Cache` facade.
- **In-app events** dispatched through `Event.dispatch`.
- **Gate checks**: every `Gate.allows` / `Gate.denies` call with result + user id.
- **DB queries**: SQL, bindings, and execution time via the magic database connector.

## Host features

- [**Redaction**](redaction): the credential lists and `CrumbsRedaction.redactor`, the host hook that
  masks every log, event, exception and HTTP record at insert.
- [**File sink**](file-sink): `CrumbsFileSink`, a rotating JSONL timeline on disk that writes only
  redacted records, read back through `crumbs:files`.
- [**Buffers**](buffers): per-kind capacity with `CrumbsStore.setCapacity`, the `atUs` clock, and how
  `limit` and `minLevel` behave.
- [**Cursor and filters**](../mcp/cursor-and-filters): `since`, `type`, `logger` and `cursor` on the read
  extensions, and `--json` / `--follow` on the CLI.

## Next steps

- New here? Start with [Installation](installation).
- Already installed? Run the [Quickstart](quickstart).
- Full reference at [anilcancakir.com/crumbs](https://anilcancakir.com/crumbs).
