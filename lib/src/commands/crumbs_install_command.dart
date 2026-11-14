import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';

/// `dowel crumbs:install` ; one-shot bootstrap for the crumbs plugin.
///
/// Runs the canonical install sequence in the consumer project:
///
///   1. `dart run crumbs install` (only when
///      `bin/dispatcher.dart` is missing; idempotent skip otherwise). This
///      step produces `bin/dispatcher.dart`, `bin/dowel` (the AOT fast-cli),
///      `lib/app/_plugins.g.dart`, and `lib/app/commands/_index.g.dart`.
///   2. `dart run crumbs plugin:install crumbs`
///      (always; the underlying plugin:install + plugins:refresh are
///      idempotent so re-runs are safe). Routes through the crumbs CLI
///      wrapper (`bin/crumbs.dart`) which preloads
///      `CrumbsDowelProvider` and sets `delegateToConsumer: false`, so
///      no `bin/dowel` AOT scaffold dependency exists at this stage and the
///      consumer can complete the chain on a clean checkout where dowel has
///      not been compiled yet.
///   3. Inject the runtime wiring into `lib/main.dart` via
///      [MainDartEditor]: imports plus the `kDebugMode`-gated
///      [CrumbsPlugin.install] + [ExceptionWatcher] + [DumpWatcher]
///      block before `runApp(`. When the consumer's pubspec lists `magic_devtools`
///      as a dependency, `lib/main.dart` contains an `await Magic.init(`
///      call AND the resolved release ships `lib/crumbs.dart`, also injects
///      `MagicCrumbsIntegration.install()` after it; a release without
///      `lib/crumbs.dart` gets a warning instead.
///      All steps idempotent; re-runs are no-ops.
///
/// Steps 1 and 2 are invoked as subprocesses so this command does not
/// depend on the consumer wrapper already wiring `CrumbsDowelProvider`
/// (the bootstrap chicken-and-egg case). Step 3 calls [MainDartEditor]
/// directly because it runs in the same process as the wrapper.
class CrumbsInstallCommand extends DowelCommand {
  @override
  String get name => 'crumbs:install';

  @override
  String get description =>
      'Bootstrap crumbs in the current project (scaffolds '
      'consumer wrapper if missing, then registers the plugin).';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Hook for tests to inject a custom subprocess runner without touching
  /// the live Dart toolchain. Defaults to [Process.run].
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  processRunner = _defaultProcessRunner;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );

  /// Hook for tests to override the wrapper-presence check (default: real
  /// `bin/dispatcher.dart` File existence in the cwd). The dispatcher is the
  /// canonical dowel v3 wrapper produced by `dart run dowel
  /// install`; the legacy `bin/dowel.dart` name no longer applies.
  static bool Function() wrapperExistsCheck = _defaultWrapperExistsCheck;

  static bool _defaultWrapperExistsCheck() =>
      File('bin/dispatcher.dart').existsSync();

  @override
  Future<int> handle(DowelContext ctx) async {
    // 1. Scaffold the consumer wrapper when missing. Re-runs are skipped so
    //    repeated `crumbs:install` invocations on an already-bootstrapped
    //    project stay idempotent.
    if (!wrapperExistsCheck()) {
      ctx.output.info('Consumer wrapper missing; running install...');
      final scaffold = await processRunner('dart', [
        'run',
        'crumbs',
        'install',
      ]);
      stdout.write(scaffold.stdout);
      stderr.write(scaffold.stderr);
      if (scaffold.exitCode != 0) {
        ctx.output.error('install failed (exit ${scaffold.exitCode}).');
        return scaffold.exitCode;
      }
    } else {
      ctx.output.info('Consumer wrapper already present; skipping install.');
    }

    // 2. Register crumbs via plugin:install. Reads the
    //    install.yaml manifest shipped in this package and writes the entry
    //    to .dowel/plugins.json + regenerates lib/app/_plugins.g.dart.
    //    Invoked via `dart run crumbs` (the crumbs CLI
    //    wrapper which preloads `CrumbsDowelProvider` and sets
    //    `delegateToConsumer: false`) so the chain works on a clean
    //    checkout without depending on the AOT-compiled `bin/dowel`.
    ctx.output.info('Registering crumbs via plugin:install...');
    final install = await processRunner('dart', [
      'run',
      'crumbs',
      'plugin:install',
      'crumbs',
    ]);
    stdout.write(install.stdout);
    stderr.write(install.stderr);
    if (install.exitCode != 0) {
      ctx.output.error('plugin:install failed (exit ${install.exitCode}).');
      return install.exitCode;
    }

    // 3. Wire the runtime install into lib/main.dart. Fail-soft: when the
    //    file is absent or the `runApp(` anchor is missing, log and continue;
    //    the consumer can wire by hand following the post_install message.
    final mainDart = File('lib/main.dart');
    if (!mainDart.existsSync()) {
      ctx.output.info(
        'lib/main.dart not found; runtime wiring SKIPPED. Wire manually:'
        ' import crumbs + CrumbsPlugin.install() + watchers'
        ' before runApp().',
      );
    } else {
      _injectRuntimeWiring(ctx, mainDart.path);
    }

    ctx.output.success('crumbs:install complete.');
    return 0;
  }

  /// Step 3 ; idempotent inject of crumbs runtime wiring into
  /// `lib/main.dart`. Three sub-steps:
  ///
  ///   3a. Add the two required imports (kDebugMode + crumbs barrel).
  ///   3b. Inject `WidgetsFlutterBinding.ensureInitialized()` (skip when
  ///       already present) + the `kDebugMode`-gated crumbs block before
  ///       the canonical install anchor: `await Magic.init(` on Magic-stack
  ///       apps (so ExceptionWatcher captures Magic boot errors), otherwise
  ///       `runApp(` for vanilla Flutter apps. A file that already calls
  ///       `CrumbsPlugin.install(` in any shape skips 3a and 3b.
  ///   3c. When pubspec has `magic_devtools:`, its resolved release ships
  ///       `lib/crumbs.dart` AND main.dart has `await Magic.init(`, inject
  ///       `MagicCrumbsIntegration.install()` after that call.
  static void _injectRuntimeWiring(DowelContext ctx, String mainDartPath) {
    ctx.output.info('Wiring CrumbsPlugin into $mainDartPath...');

    // An app already calling CrumbsPlugin.install() is wired whatever the
    // shape of its block; a second block would chain the watchers and record
    // every exception and debugPrint twice.
    //
    // A magic_devtools release that predates crumbs has no `crumbs.dart`; its
    // import would leave a lib/main.dart that does not compile. An app already
    // carrying the integration call needs neither the check nor the warning.
    final String original = FileHelper.readFile(mainDartPath);
    final bool wiresCrumbs = !original.contains('CrumbsPlugin.install(');
    final bool wantsMagic =
        original.contains('await Magic.init(') &&
        _hasMagicDevtoolsDep() &&
        !original.contains('MagicCrumbsIntegration.install()');
    final MagicDevtoolsCrumbsSupport magicSupport = wantsMagic
        ? magicDevtoolsCrumbsSupport(Directory.current.path)
        : MagicDevtoolsCrumbsSupport.unresolved;
    final bool wiresMagic =
        magicSupport == MagicDevtoolsCrumbsSupport.available;

    // 3a. Imports first. ConfigEditor.addImportToFile (delegated by
    //     MainDartEditor.addImport) is idempotent on duplicates.
    if (wiresCrumbs || wiresMagic) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:flutter/foundation.dart' show kDebugMode;",
      );
    }
    if (wiresCrumbs) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:crumbs/crumbs.dart';",
      );
    }

    // 3b. Read once, choose the correct anchor, transform via two
    //     pure-functional injects (idempotent: each helper checks
    //     `source.contains(snippet)` before inserting), write back when
    //     changed.
    var source = FileHelper.readFile(mainDartPath);
    final before = source;

    // Magic apps run CrumbsPlugin.install BEFORE `await Magic.init(` so
    // ExceptionWatcher catches boot errors; vanilla apps inject before
    // `runApp(`. Detect via substring match on the magic boot call.
    final hasMagicInit = source.contains('await Magic.init(');
    final anchor = hasMagicInit ? 'await Magic.init(' : 'runApp(';

    // Magic apps already call WidgetsFlutterBinding.ensureInitialized()
    // before Magic.init, so skip the inject when it is already present
    // (avoids a duplicate call right above the existing one).
    if (wiresCrumbs) {
      if (!source.contains('WidgetsFlutterBinding.ensureInitialized()')) {
        source = MainDartEditor.injectBeforeAnchor(
          source: source,
          anchor: anchor,
          snippet: '  WidgetsFlutterBinding.ensureInitialized();\n',
        );
      }

      source = MainDartEditor.injectBeforeAnchor(
        source: source,
        anchor: anchor,
        snippet:
            '  if (kDebugMode) {\n'
            '    CrumbsPlugin.install();\n'
            '    CrumbsPlugin.registerWatcher(ExceptionWatcher());\n'
            '    CrumbsPlugin.registerWatcher(DumpWatcher());\n'
            '  }\n',
      );
    }

    if (source != before) {
      FileHelper.writeFile(mainDartPath, source);
    }

    // 3c. Magic-side coordinated wiring when the consumer pulls in magic_devtools.
    //     Detect via pubspec.yaml; skip silently when magic_devtools is not a dep or
    //     when main.dart has no Magic.init() anchor (vanilla Flutter app), and
    //     with a warning when the resolved release has no crumbs integration.
    if (wantsMagic && !wiresMagic) {
      final String why = magicSupport == MagicDevtoolsCrumbsSupport.unresolved
          ? 'no lib/crumbs.dart resolved; run `flutter pub get` if it has not '
                'run'
          : 'no lib/crumbs.dart';
      ctx.output.warning(
        'Skipped MagicCrumbsIntegration: the installed magic_devtools has no '
        'crumbs integration yet ($why). Upgrade magic_devtools to a release '
        'built on crumbs, then rerun `dart run crumbs crumbs:install` (it is '
        'idempotent).',
      );
    }
    if (wiresMagic) {
      MainDartEditor.addImport(
        mainDartPath,
        "import 'package:magic_devtools/crumbs.dart';",
      );
      try {
        MainDartEditor.injectAfterMagicInit(
          mainDartPath,
          '  if (kDebugMode) {\n'
          '    MagicCrumbsIntegration.install();\n'
          '  }\n',
        );
      } on StateError {
        // No Magic.init() call yet; user has not bootstrapped magic.
        // Crumbs's vanilla wiring above is enough on its own.
      }
    }
  }

  /// Whether the `magic_devtools` that [projectRoot] resolves ships
  /// `lib/crumbs.dart`, the library `MagicCrumbsIntegration` lives in.
  ///
  /// The pubspec only says the package is wanted; a release that predates
  /// crumbs ships `lib/telescope.dart` instead, and wiring its integration
  /// leaves a `lib/main.dart` that does not compile. So the answer comes from
  /// the package pub actually resolved, through
  /// `.dart_tool/package_config.json`.
  static MagicDevtoolsCrumbsSupport magicDevtoolsCrumbsSupport(
    String projectRoot,
  ) {
    // 1. No package config means `pub get` has not run: nothing is resolved.
    final File? config = _nearestPackageConfig(projectRoot);
    if (config == null) return MagicDevtoolsCrumbsSupport.unresolved;

    // 2. Find the entry pub wrote for magic_devtools. A config that cannot
    //    be read or parsed tells nothing either way, which is what
    //    `unresolved` says; the install carries on from there.
    final Object? decoded;
    try {
      decoded = jsonDecode(config.readAsStringSync());
    } on FormatException {
      return MagicDevtoolsCrumbsSupport.unresolved;
    } on FileSystemException {
      return MagicDevtoolsCrumbsSupport.unresolved;
    }
    final List<Object?> packages = switch (decoded) {
      {'packages': final List<Object?> list} => list,
      _ => const <Object?>[],
    };
    for (final Object? package in packages) {
      if (package is! Map<String, Object?> ||
          package['name'] != 'magic_devtools') {
        continue;
      }

      // 3. `rootUri` is relative to the `.dart_tool` directory (or an
      //    absolute file URI for a pub-cache package); `packageUri`, `lib/`
      //    as pub writes it, is relative to the root and defaults to it. An
      //    entry that breaks that shape is as unreadable as a broken file.
      final Object? rootUri = package['rootUri'];
      final Object packageUri = package['packageUri'] ?? '';
      if (rootUri is! String || packageUri is! String) {
        return MagicDevtoolsCrumbsSupport.unresolved;
      }
      final File crumbsLibrary;
      try {
        final Uri root = config.absolute.parent.uri.resolve(rootUri);
        final Uri rootDir = root.path.endsWith('/')
            ? root
            : root.replace(path: '${root.path}/');
        crumbsLibrary = File.fromUri(
          rootDir.resolve(packageUri).resolve('crumbs.dart'),
        );
      } on FormatException {
        return MagicDevtoolsCrumbsSupport.unresolved;
      }
      return crumbsLibrary.existsSync()
          ? MagicDevtoolsCrumbsSupport.available
          : MagicDevtoolsCrumbsSupport.missing;
    }
    return MagicDevtoolsCrumbsSupport.unresolved;
  }

  /// The package config that governs [projectRoot]: the first
  /// `.dart_tool/package_config.json` at or above it, the way the Dart tools
  /// find it. A pub workspace member has none of its own, since `pub get`
  /// writes one shared config at the workspace root. Null when the walk
  /// reaches the filesystem root without finding one.
  static File? _nearestPackageConfig(String projectRoot) {
    // Walk on directory URIs: a file path round trip keeps the trailing
    // separator, and the `<root>//.dart_tool` it leads to makes a relative
    // `rootUri` resolve one level too deep.
    Uri dir = Directory(projectRoot).absolute.uri.normalizePath();
    while (true) {
      final config = File.fromUri(
        dir.resolve('.dart_tool/package_config.json'),
      );
      if (config.existsSync()) return config;
      final Uri parent = dir.resolve('..');
      if (parent == dir) return null;
      dir = parent;
    }
  }

  /// Returns true when the consumer's pubspec.yaml lists `magic_devtools:`
  /// (the package that ships MagicCrumbsIntegration) under `dependencies:`
  /// or `dev_dependencies:` (2-space indent).
  static bool _hasMagicDevtoolsDep() {
    final pubspec = File('pubspec.yaml');
    if (!pubspec.existsSync()) return false;
    return RegExp(r'\n  magic_devtools:').hasMatch(pubspec.readAsStringSync());
  }
}

/// What the consumer's resolved `magic_devtools` offers crumbs, read by
/// [CrumbsInstallCommand.magicDevtoolsCrumbsSupport].
enum MagicDevtoolsCrumbsSupport {
  /// No `magic_devtools` in `.dart_tool/package_config.json`, or no package
  /// config at all because `pub get` has not run.
  unresolved,

  /// Resolved, but a release that predates crumbs: it has no
  /// `lib/crumbs.dart`.
  missing,

  /// Resolved and ships `lib/crumbs.dart`, so `MagicCrumbsIntegration`
  /// imports.
  available,
}
