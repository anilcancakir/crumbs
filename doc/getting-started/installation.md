# Installation

- [Requirements](#requirements)
- [Option A: one-shot install via dowel](#option-a-one-shot-install)
- [Option B: manual wiring](#option-b-manual-wiring)
- [Wire the Dowel provider](#wire-the-dowel-provider)
- [Verify installation](#verify-installation)

`crumbs` works from a fresh Flutter project. The recommended install path
uses crumbs's own bootstrap entry point (`dart run crumbs crumbs:install`)
which carries the dowel substrate, so no prior `dowel` setup is required.

<a name="requirements"></a>
## Requirements

| Dependency | Minimum Version | Notes |
|:-----------|:----------------|:------|
| Dart SDK | `>= 3.4.0` | |
| Flutter SDK | `>= 3.22.0` | VM Service extensions require the Flutter runtime. |
| dowel | `^0.0.20` | Pulled in transitively by crumbs; no manual setup needed for the install path. |
| Magic stack | optional | Enables 6 additional Magic-specific watchers. |

<a name="option-a-one-shot-install"></a>
## Option A: one-shot self-bootstrap install (recommended)

Add `crumbs` to your project, then bootstrap via crumbs's own CLI entry
point. The standalone binary carries the dowel substrate, so this works from a completely
fresh consumer with no prior `dowel` wiring:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

`flutter pub add` writes the dependency to `pubspec.yaml` and runs `dart pub get` in one
step. The `dart run` line then invokes crumbs's standalone CLI to scaffold and patch
the consumer.

The command performs three operations in order:

1. Scaffolds the consumer dowel harness (`bin/dispatcher.dart`, `lib/app/_plugins.g.dart`)
   if it is missing. This is a no-op when the harness is already present.
2. Runs `plugin:install crumbs`, which registers `CrumbsDowelProvider`
   in `.dowel/plugins.json` and refreshes the codegen barrel.
3. Patches `lib/main.dart` to call `CrumbsPlugin.install()` before `runApp`. When the
   consumer's `pubspec.yaml` lists `magic_devtools:` (as a dependency or dev_dependency) and
   `lib/main.dart` contains `await Magic.init(`, the patch also injects
   `import 'package:magic_devtools/crumbs.dart';` plus a `MagicCrumbsIntegration.install()`
   block after `Magic.init()`. All patches are wrapped in a `kDebugMode` guard automatically.

The command is idempotent. Re-running it when the files are already patched is safe.

### After install: prefer the dowel fast-cli

The dowel scaffold ships a precompiled launcher at `./bin/dowel` (native AOT, ~110ms warm
startup). For everyday crumbs work, use it instead of `dart run`:

```bash
./bin/dowel crumbs:tail
./bin/dowel crumbs:requests
./bin/dowel crumbs:clear
```

`dart run crumbs <cmd>` and `dart run dowel <cmd>` keep working
as ~3-second cold-start fallbacks; they are useful in CI or before the AOT bundle is built.

<a name="option-b-manual-wiring"></a>
## Option B: manual wiring

Use this path when you need fine-grained control over the install, or when the automated
patch cannot locate the correct anchor in `lib/main.dart`.

### 1. Add the dependency

Add `crumbs` to `pubspec.yaml`. For Magic-stack apps, also add `magic_devtools`
to `dev_dependencies`: that package ships `MagicCrumbsIntegration` and the 5 Magic-specific
watchers (previously part of the `magic` core package).

```yaml
dependencies:
  crumbs: ^0.0.4

# Magic-stack apps only:
dev_dependencies:
  magic_devtools: any
```

Then fetch dependencies:

```bash
dart pub get
```

### 2. Wire CrumbsPlugin in lib/main.dart

Install Crumbs before `runApp`, wrapped in a mode guard at the call site. `crumbs:install`
writes `kDebugMode`; the snippets below use `!kReleaseMode`, which also keeps crumbs in profile
builds (what a performance measurement needs, and what `magic_devtools` documents). Both tree-shake
release builds; see [Call-site guard](../watchers/index.md#call-site-guard). When using the Magic
framework, place the call before `Magic.init()` so the Http facade is wired before
MagicCrumbsIntegration runs:

```dart
import 'package:flutter/foundation.dart';
import 'package:crumbs/crumbs.dart';
import 'package:magic_devtools/crumbs.dart'; // magic_devtools dev_dependency (Magic-stack apps only)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kReleaseMode) {
    // 1. Install Crumbs core (LogWatcher auto-installs, VM extensions register).
    CrumbsPlugin.install();

    // 2. Opt-in to exception and debugPrint capture.
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }

  // 3. Framework init (e.g. Magic.init()) runs after Crumbs so the Http facade
  //    is wired before MagicCrumbsIntegration tries to wrap it.
  await Magic.init(configFactories: [...]);

  if (!kReleaseMode) {
    // 4. Magic-specific adapters resolve framework internals from the IoC container;
    //    they must run after Magic.init(). MagicCrumbsIntegration ships in
    //    magic_devtools; add it to dev_dependencies alongside crumbs.
    MagicCrumbsIntegration.install();
  }

  runApp(MyApp());
}
```

For vanilla Flutter (no Magic stack), omit `Magic.init()` and the
`MagicCrumbsIntegration.install()` call. Wire `DioHttpAdapter` instead if you use Dio:

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerHttpAdapter(DioHttpAdapter(dio));
  CrumbsPlugin.registerWatcher(ExceptionWatcher());
  CrumbsPlugin.registerWatcher(DumpWatcher());
}
```

<a name="wire-the-dowel-provider"></a>
## Wire the Dowel provider

If you used Option A (`crumbs:install`), the provider registration is written
automatically: `plugin:install crumbs` adds `FluttersdkCrumbsDowelProvider`
to `lib/app/_plugins.g.dart`, which the scaffolded `bin/dispatcher.dart` reads via
`plugins.autoDiscoveredProviders()`. No manual edit is required.

If you used Option B (manual wiring), import the provider in your `bin/dispatcher.dart`
yourself:

```dart
import 'package:dowel/dowel.dart';
import 'package:crumbs/cli.dart' show FluttersdkCrumbsDowelProvider;

Future<void> main(List<String> args) async {
  exit(await runDowel(
    args,
    baseProviders: [
      FluttersdkCrumbsDowelProvider(),
      // ...other providers (TapirDowelProvider, etc.)
    ],
  ));
}
```

<a name="verify-installation"></a>
## Verify installation

Start your Flutter app and confirm Crumbs is active by tailing the log buffer:

```bash
./bin/dowel crumbs:tail
```

Expected output on a running app shows the most recent log records from the ring buffer.
If you see `Error: no running app found`, the dowel state file is missing: run
`./bin/dowel start` first, then retry `crumbs:tail`.

To confirm all 11 CLI commands are registered, list the dowel command catalog:

```bash
./bin/dowel list
```

The output includes the `crumbs:` namespace with `crumbs:install`, `crumbs:tail`,
`crumbs:requests`, `crumbs:queries`, `crumbs:caches`, `crumbs:events`,
`crumbs:gates`, `crumbs:dumps`, `crumbs:frames`, and `crumbs:clear`. If
the fast-cli is missing for any reason, the same commands run via `dart run crumbs list`
or `dart run dowel list`.
