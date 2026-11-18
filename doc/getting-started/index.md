# Getting Started

What crumbs captures, what it needs, and where to start: installation, the quickstart, and the host features for redaction, the file sink and buffers.

- [Pick your path](#pick-your-path)
- [What crumbs is](#what-crumbs-is)
- [Requirements](#requirements)
- [What gets captured](#what-gets-captured)
- [Host features](#host-features)
- [Related Documentation](#related-documentation)

<a name="pick-your-path"></a>
## Pick your path

| You want to | Read |
|:------------|:-----|
| Add crumbs to a Flutter app | [Installation](installation.md) |
| Go from install to a first MCP tool call | [Quickstart](quickstart.md) |
| Keep secrets out of the buffers | [Redaction](redaction.md) |
| Keep a timeline on disk | [File sink](file-sink.md) |
| Size the buffers | [Buffers](buffers.md) |

<a name="what-crumbs-is"></a>
## What crumbs is

crumbs is a passive runtime inspector for Flutter apps. Watchers and HTTP adapters record what the app does into in-memory ring buffers, and `ext.crumbs.*` VM Service extensions serve those buffers to `crumbs:*` CLI commands and `crumbs_*` MCP tools on [dowel](https://pub.dev/packages/dowel). It never changes app behaviour; it only records.

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

`crumbs:install` scaffolds the dowel harness when it is missing, registers the plugin and patches `lib/main.dart` so `CrumbsPlugin.install()` runs at startup inside an `!kReleaseMode` guard. The guard belongs to the call site: `!kReleaseMode` keeps crumbs in debug and profile builds (see [Call-site guard](../watchers/index.md#call-site-guard)), and a release build tree-shakes it.

<a name="requirements"></a>
## Requirements

| Dependency | Minimum | Notes |
|:-----------|:--------|:------|
| Dart SDK | `3.13` | |
| Flutter SDK | `3.47` | The VM Service extensions need the Flutter runtime. |
| dowel | `^1.0.0` | Pulled in by crumbs; `crumbs:install` sets up the rest. |
| Magic stack | optional | `MagicCrumbsIntegration` from a `magic_devtools` release built on crumbs adds HTTP, model, cache, event, gate and query capture, and log capture from `magic_devtools` 1.1.0. |

<a name="what-gets-captured"></a>
## What gets captured

After `crumbs:install` on any Flutter app:

- **Logs**: every `package:logging` record, through `LogWatcher` (installed by `CrumbsPlugin.install()`).
- **Exceptions**: uncaught errors, through `ExceptionWatcher`, chained to any handler already set (Sentry, Bugsnag).
- **`debugPrint` output**: through `DumpWatcher`, chained to the previous override.

With the Magic stack (`MagicCrumbsIntegration.install()` after `Magic.init()`):

- **HTTP traffic** through the Magic `Http` facade.
- **Model lifecycle**: created, saved and deleted events on Magic models.
- **Cache operations**: hit, miss, put, forget and flush through the `Cache` facade.
- **In-app events**: a curated set of Magic auth, database and gate-definition events.
- **Gate checks**: every `Gate.allows` and `Gate.denies` result with the user id.
- **DB queries**: SQL, bindings and execution time through the Magic query builder.
- **Logs**: every `Log.*` call, through `MagicLogWatcher` (`magic_devtools` 1.1.0 or later); a call made during `Magic.init()` is not recorded.

`FramePerfWatcher` (frame timings) and a Dio interceptor (HTTP on a vanilla app) are opt-in on any app; see [Watchers](../watchers/index.md).

<a name="host-features"></a>
## Host features

- [Redaction](redaction.md): the credential lists, which mask by key, and `CrumbsRedaction.redactor`, the host hook that masks free text at insert.
- [File sink](file-sink.md): `CrumbsFileSink`, a rotating JSONL timeline on disk that writes only redacted records, read back through `crumbs:files`.
- [Buffers](buffers.md): per-kind capacity with `CrumbsStore.setCapacity`, the `atUs` clock, and how `limit` and `minLevel` behave.
- [Cursor and filters](../mcp/cursor-and-filters.md): `since`, `type`, `logger` and `cursor` on the read extensions, and `--json` and `--follow` on the CLI.

<a name="related-documentation"></a>
## Related Documentation

- [Installation](installation.md): the installer, manual wiring and the dowel provider.
- [Quickstart](quickstart.md): install, start the app and make the first MCP tool call.
- [Watchers](../watchers/index.md): every watcher and adapter, and the call-site guard.
- [MCP overview](../mcp/overview.md): how the `crumbs_*` tools reach the running app.
