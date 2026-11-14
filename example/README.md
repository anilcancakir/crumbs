# crumbs showroom

A vanilla Flutter app that demonstrates every core crumbs capture surface: HTTP via `DioHttpAdapter`, structured logs via `package:logging`, exceptions via `ExceptionWatcher`, and debug prints via `DumpWatcher`. The app resolves `crumbs` directly from the sibling source tree via `path: ../`, so any edit to the parent package is immediately reflected on the next hot restart. Framework-stack integration (such as the dowel provider or watcher auto-wiring) is out of scope; this is a plain `runApp` entry point wired manually.

## How to run

```bash
cd example
flutter pub get
dart run crumbs start --device=chrome    # or macos, linux, a device id
```

`dart run crumbs start` launches the app and records the session that every `crumbs:*` command dials; a plain `flutter run` leaves the commands nothing to connect to. `dart run crumbs stop` ends it.

## Sections

| Section | Triggers | Inspect via |
|---------|----------|-------------|
| HTTP via DioHttpAdapter | GET /get, POST /post, GET /status/418, GET /delay/5 (timeout) | `dart run crumbs crumbs:requests` |
| Logs via package:logging | Logger.info, Logger.warning, Logger.severe | `dart run crumbs crumbs:tail` |
| Exceptions via ExceptionWatcher | Async throw, Sync throw (caught), Custom error | `crumbs_exceptions` MCP tool |
| Dumps via DumpWatcher | debugPrint single line, debugPrint multiline | `crumbs_dumps` MCP tool |

## Manual QA checklist

- Boot the app via `dart run crumbs start --device=chrome`.
- Tap each button at least once.
- Confirm the matching live-tail panel updates within ~1 second.
- Verify the status bar chip counters (HTTP / Log / Exception / Dump) increment per buffer.
- Tap "Clear all buffers": all chips return to 0 and live-tail panels empty (equivalent to running `dart run crumbs crumbs:clear` from the CLI).
- Tap "Pause recording": subsequent button taps do NOT update buffers (chips stay flat).
- Tap "Resume recording": buffers update again.

## Path dependency note

This example depends on the parent crumbs package via `path: ../`. Source edits to the parent require nothing more than a hot restart in the running example app. Downstream consumers that install from pub.dev use the hosted `^1.0.0` constraint instead.

## License

[MIT](../LICENSE): same license as the parent `crumbs` package.
