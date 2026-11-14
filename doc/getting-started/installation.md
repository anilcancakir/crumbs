# Installation

Add `crumbs` to a Flutter app, install it behind a call-site guard, register it with dowel, and optionally write the MCP entry for your AI client.

The recommended path is one command, `dart run crumbs crumbs:install`, which patches `lib/main.dart` and registers the plugin with dowel; the manual route is described step by step below.

- [Quick Reference](#quick-reference)
- [Requirements](#requirements)
- [Run the installer](#run-the-installer)
- [Manual wiring](#manual-wiring)
- [Register with dowel](#register-with-dowel)
- [Wire MCP tools](#wire-mcp-tools)
- [Verify installation](#verify-installation)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Step | Command | Result |
|:-----|:--------|:-------|
| 1. Add the package | `flutter pub add crumbs` | `crumbs` is a dependency; `dowel` comes with it. |
| 2. Wire the app | `dart run crumbs crumbs:install` | The dowel harness exists, crumbs is a registered plugin, and `lib/main.dart` installs crumbs in an `!kReleaseMode` block. |
| 3. Register the MCP server (optional) | `dart run crumbs mcp:install` | A `dowel` entry in `.mcp.json` at the project root. |
| 4. Start the app | `dart run crumbs start --device=chrome` | dowel records the session every `crumbs:*` command dials. |
| 5. Read a buffer | `dart run crumbs crumbs:tail` | The newest log records of the running app. |

<a name="requirements"></a>
## Requirements

`crumbs` is a Flutter package: the VM Service extensions register inside a running Flutter app, so a pure Dart program is not supported.

| Dependency | Minimum | Notes |
|:-----------|:--------|:------|
| Dart | `3.13` | |
| Flutter | `3.47` | |
| dowel | `^0.0.21` | A dependency of crumbs. When `crumbs:install` scaffolds the harness, dowel's `install` step adds `dowel: any` to the app's `pubspec.yaml`, because the generated barrels import it. |

<a name="run-the-installer"></a>
## Run the installer

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

`dart run crumbs` is crumbs's own entry point: it carries the whole dowel CLI plus the crumbs commands, so the installer works on a project that has no dowel setup yet. It runs three steps in order:

1. When `bin/dispatcher.dart` is missing, it runs `dart run crumbs install`, which scaffolds the dowel harness: `bin/dispatcher.dart`, the fast `./bin/dowel` launcher and the codegen barrels under `lib/app/`. A project that already has the dispatcher skips this step.
2. It runs `dart run crumbs plugin:install crumbs`, which records crumbs in `.dowel/plugins.json` and regenerates `lib/app/_plugins.g.dart`.
3. It patches `lib/main.dart`: the `kReleaseMode` and `package:crumbs/crumbs.dart` imports (no `show kReleaseMode` import when the file already imports `package:flutter/foundation.dart` in full), `WidgetsFlutterBinding.ensureInitialized()` when missing, and an `!kReleaseMode` block with `CrumbsPlugin.install()` and the exception and dump watchers. The block lands before `await Magic.init(` on a Magic app, so `ExceptionWatcher` sees boot errors, and before `runApp(` otherwise. Without a `lib/main.dart` the step is skipped with a message.

On a Magic app whose `pubspec.yaml` lists `magic_devtools`, step 3 also adds `import 'package:magic_devtools/crumbs.dart';` and an `!kReleaseMode` block with `MagicCrumbsIntegration.install()` after `Magic.init()`. That library exists only in a `magic_devtools` release built on crumbs, so the installer writes these lines only when the resolved `magic_devtools` ships it; with an older release it warns and leaves the Magic lines out. Until that release ships, `MagicTelescopeIntegration` feeds `fluttersdk_telescope`, not crumbs, so the HTTP, event, gate, query and cache buffers of crumbs stay empty in a Magic app.

Every step is idempotent: re-running `crumbs:install` changes nothing. A `main.dart` wired by an earlier crumbs with a `kDebugMode` guard keeps that block and keeps working, and a Magic block a rerun adds takes the same guard; switch both to `!kReleaseMode` to get frame-performance data in profile builds.

<a name="manual-wiring"></a>
## Manual wiring

Skip the installer and edit `lib/main.dart` directly. Call `CrumbsPlugin.install()` inside a guard, after `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kReleaseMode) {
    CrumbsPlugin.install(); // LogWatcher and the ext.crumbs.* extensions.
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }

  runApp(const MyApp()); // MyApp is the host app's root widget.
}
```

`!kReleaseMode` keeps crumbs in debug and profile builds, and a frame measurement needs a profile build. It tree-shakes a release build; see [Call-site guard](../watchers/index.md#call-site-guard). `CrumbsPlugin.install()` is idempotent, so a hot restart registers each extension once.

On a Magic app, install crumbs before `Magic.init()` and the Magic integration after it, because the integration resolves the Http facade and the event dispatcher from the container:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_devtools/crumbs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kReleaseMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }

  await Magic.init(configFactories: appConfigFactories); // The host's config list.

  if (!kReleaseMode) {
    MagicCrumbsIntegration.install();
  }

  runApp(const MyApp());
}
```

On a vanilla app that uses Dio, route Dio traffic into the HTTP buffer from an interceptor; crumbs has no `dio` dependency, so the interceptor lives in the app (the bundled `example/` app has a complete one):

```dart
import 'package:crumbs/crumbs.dart';
import 'package:dio/dio.dart';

class CrumbsDioInterceptor extends Interceptor {
  final Map<RequestOptions, Stopwatch> _watches = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _watches[options] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    CrumbsStore.recordHttp(
      HttpRequestRecord(
        url: options.uri.toString(),
        method: options.method,
        statusCode: response.statusCode ?? 0,
        durationMs: _watches.remove(options)?.elapsedMilliseconds ?? 0,
        isError: false,
        timestamp: DateTime.now(),
      ),
    );
    handler.next(response);
  }
}
```

Add it with `dio.interceptors.add(CrumbsDioInterceptor())`. `CrumbsStore.recordHttp` masks the credentials before it buffers the record, so no `CrumbsHttpAdapter` is needed; write one only to report in-flight requests through `pendingCount`.

<a name="register-with-dowel"></a>
## Register with dowel

`crumbs:install` already does this. `plugin:install crumbs` writes `CrumbsDowelProvider` into `lib/app/_plugins.g.dart`, which the scaffolded `bin/dispatcher.dart` reads through `plugins.autoDiscoveredProviders()`, so `./bin/dowel list` shows the `crumbs:*` commands and `./bin/dowel mcp:serve` serves the `crumbs_*` tools.

To finish a skipped step by hand:

```bash
dart run crumbs install               # only when bin/dispatcher.dart is missing
dart run crumbs plugin:install crumbs # idempotent; refreshes the barrel on re-run
```

A dispatcher wired by hand imports the provider from the Flutter-free `cli.dart` barrel, the same import `plugins:refresh` generates:

```dart
import 'dart:io';

import 'package:crumbs/cli.dart' show CrumbsDowelProvider;
import 'package:dowel/dowel.dart';

Future<void> main(List<String> args) async {
  exit(
    await runDowel(
      args,
      baseProviders: [CrumbsDowelProvider()],
      delegateToConsumer: false,
      collectMcpTools: args.isNotEmpty && args.first == 'mcp:serve',
    ),
  );
}
```

<a name="wire-mcp-tools"></a>
## Wire MCP tools

```bash
dart run crumbs mcp:install
```

This writes (or updates) the `dowel` entry in `.mcp.json` at the project root and keeps other entries. With `./bin/dowel` present on a POSIX host the entry runs `./bin/dowel mcp:serve`; otherwise, and always on Windows, it runs `dart run crumbs mcp:serve`. Reconnect the client afterwards (`/mcp reconnect dowel` in Claude Code). See [MCP setup](../mcp/setup.md) for other clients and tool filtering.

<a name="verify-installation"></a>
## Verify installation

Start the app through dowel, so the session (the VM Service URI every `crumbs:*` command dials) is recorded:

```bash
dart run crumbs start --device=chrome
```

Then read the log buffer and list the commands:

```bash
./bin/dowel crumbs:tail
./bin/dowel list
```

`crumbs:tail` prints the newest log records; `list` shows the `crumbs:` namespace. `dart run crumbs <command>` runs the same commands when `./bin/dowel` is not built. If a command finds no app, start it with `dart run crumbs start` first; if it finds the app but no `ext.crumbs.*` extension, confirm `CrumbsPlugin.install()` is reachable in `main.dart` and that the app is a debug build (or a profile build under `!kReleaseMode`). Stop the app with `dart run crumbs stop`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `CrumbsPlugin.install()` sits outside a guard. | Wrap it in `if (!kReleaseMode)`; crumbs installs no guard of its own. `--dart-define=CRUMBS_DISABLE=1` also stops the install, the watchers and the HTTP adapters of a build that must not expose the extensions. |
| The guard sits inside a helper function. | Keep it at the call site in `main()`; the tree-shake depends on it. |
| `crumbs_exceptions` stays empty after a crash. | Register `ExceptionWatcher`: `CrumbsPlugin.install()` installs only `LogWatcher`. |
| `MagicCrumbsIntegration.install()` runs before `Magic.init()`. | Call it after `Magic.init()`; the HTTP adapter registers nothing while the network driver is unbound. |
| The installer warned and wrote no Magic lines. | The resolved `magic_devtools` predates crumbs; upgrade it and rerun `crumbs:install`. |
| The app was started with a plain `flutter run`. | Start it with `dart run crumbs start`, which records the session the commands dial. |
| `.mcp.json` points at the wrong launcher. | Rerun `dart run crumbs mcp:install`; it picks the launcher from the scaffold state. |

<a name="related-documentation"></a>
## Related Documentation

- [Quickstart](quickstart.md): install, start the app and make the first MCP tool call.
- [Watchers](../watchers/index.md): every watcher and adapter, and the call-site guard.
- [MCP setup](../mcp/setup.md): client configuration, reconnecting and tool filtering.
- [Redaction](redaction.md): mask secrets before a record is buffered.
