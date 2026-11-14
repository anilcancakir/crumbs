import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_install_command.dart';

/// Recording subprocess runner ; captures every `(executable, args)` call so
/// tests can assert ordering and per-call exit codes without spawning the
/// real Dart toolchain.
class _RecordingRunner {
  _RecordingRunner({this.exits = const <int>[]});

  /// Per-call exit codes consumed in FIFO order. Missing entries default to 0.
  final List<int> exits;
  int _i = 0;

  final List<List<String>> calls = <List<String>>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    final code = _i < exits.length ? exits[_i++] : 0;
    return ProcessResult(0, code, '', code == 0 ? '' : 'mock-stderr');
  }
}

/// Seed [tempDir] with a stub `lib/main.dart` carrying [mainDartContents] +
/// a `pubspec.yaml` that lists [pubspecDeps] entries under `dependencies:`.
///
/// Returns the absolute path to the seeded main.dart. Callers run the
/// command with `Directory.current` switched to [tempDir] so the source's
/// relative `File('lib/main.dart')` + `File('pubspec.yaml')` lookups
/// resolve against the seed.
///
/// [magicDevtoolsLibrary] names the one library the resolved `magic_devtools`
/// ships (`crumbs.dart` for a release built on crumbs, `telescope.dart` for
/// one that predates it); when set, a `.dart_tool/package_config.json`
/// resolving the package is written too. [absoluteRootUri] writes its
/// `rootUri` the way a pub-cache package carries it, rather than relative to
/// `.dart_tool`.
String _seedProject(
  Directory tempDir, {
  required String mainDartContents,
  Map<String, String> pubspecDeps = const {},
  String? magicDevtoolsLibrary,
  bool absoluteRootUri = false,
}) {
  final mainDartPath = '${tempDir.path}/lib/main.dart';
  Directory('${tempDir.path}/lib').createSync(recursive: true);
  File(mainDartPath).writeAsStringSync(mainDartContents);
  final depsBlock = pubspecDeps.entries
      .map((e) => '  ${e.key}: ${e.value}')
      .join('\n');
  final pubspec = <String>[
    'name: stub_app',
    'environment:',
    '  sdk: ">=3.4.0 <4.0.0"',
    'dependencies:',
    '  flutter:',
    '    sdk: flutter',
    if (depsBlock.isNotEmpty) depsBlock,
    '',
  ].join('\n');
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  if (magicDevtoolsLibrary != null) {
    final packageRoot = Directory('${tempDir.path}/packages/magic_devtools');
    Directory('${packageRoot.path}/lib').createSync(recursive: true);
    File('${packageRoot.path}/lib/$magicDevtoolsLibrary')
        .writeAsStringSync('// stub\n');
    Directory('${tempDir.path}/.dart_tool').createSync();
    final rootUri = absoluteRootUri
        ? packageRoot.uri.toString()
        : '../packages/magic_devtools';
    File('${tempDir.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode(<String, Object>{
        'configVersion': 2,
        'packages': <Map<String, String>>[
          <String, String>{
            'name': 'magic_devtools',
            'rootUri': rootUri,
            'packageUri': 'lib/',
            'languageVersion': '3.4',
          },
        ],
      }),
    );
  }
  return mainDartPath;
}

const _magicMain = '''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''';

/// Run `crumbs:install` with `Directory.current` switched to [projectDir]
/// (restored afterwards) and both subprocess steps stubbed, so the command
/// flows straight into the `lib/main.dart` wiring.
Future<int> _runInstallIn(Directory projectDir, BufferedOutput output) async {
  CrumbsInstallCommand.processRunner = _RecordingRunner().run;
  CrumbsInstallCommand.wrapperExistsCheck = () => true;
  final previousCwd = Directory.current;
  Directory.current = projectDir;
  try {
    return await CrumbsInstallCommand().handle(
      DowelContext.bare(MapInput(const {}), output),
    );
  } finally {
    Directory.current = previousCwd;
  }
}

// Capture the production defaults at library load so tearDown can restore
// them. Static fields would otherwise leak each test's override into the
// next via the singleton static surface.
final _originalProcessRunner = CrumbsInstallCommand.processRunner;
final _originalWrapperExistsCheck = CrumbsInstallCommand.wrapperExistsCheck;

void main() {
  group('CrumbsInstallCommand', () {
    tearDown(() {
      CrumbsInstallCommand.processRunner = _originalProcessRunner;
      CrumbsInstallCommand.wrapperExistsCheck = _originalWrapperExistsCheck;
    });

    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    test('name is crumbs:install', () {
      expect(CrumbsInstallCommand().name, equals('crumbs:install'));
    });

    test('boot is CommandBoot.none (does not require a running app)', () {
      expect(CrumbsInstallCommand().boot, equals(CommandBoot.none));
    });

    test('description is non-empty', () {
      expect(CrumbsInstallCommand().description, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // Wrapper-presence branch: skip install when wrapper exists
    // -------------------------------------------------------------------------

    test('skips install when bin/dispatcher.dart already exists; '
        'plugin:install still runs via dart run crumbs', () async {
      final runner = _RecordingRunner();
      CrumbsInstallCommand.processRunner = runner.run;
      CrumbsInstallCommand.wrapperExistsCheck = () => true;

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      expect(
        runner.calls,
        hasLength(1),
        reason: 'only plugin:install should run when wrapper present',
      );
      expect(
        runner.calls.single,
        equals(['dart', 'run', 'crumbs', 'plugin:install', 'crumbs']),
      );
    });

    // -------------------------------------------------------------------------
    // Wrapper-missing branch: run install then plugin:install
    // -------------------------------------------------------------------------

    test('runs install then plugin:install (both via dart run crumbs) '
        'when bin/dispatcher.dart is missing (correct ordering)', () async {
      final runner = _RecordingRunner();
      CrumbsInstallCommand.processRunner = runner.run;
      CrumbsInstallCommand.wrapperExistsCheck = () => false;

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(0));
      expect(runner.calls, hasLength(2));
      expect(
        runner.calls[0],
        equals(['dart', 'run', 'crumbs', 'install']),
        reason: 'install must run first (scaffolds dispatcher.dart + dowel)',
      );
      expect(
        runner.calls[1],
        equals(['dart', 'run', 'crumbs', 'plugin:install', 'crumbs']),
        reason:
            'plugin:install must run after scaffold via the crumbs CLI '
            'wrapper (no bin/dowel dependency at this stage)',
      );
    });

    // -------------------------------------------------------------------------
    // Failure propagation
    // -------------------------------------------------------------------------

    test('returns scaffold exit code (and skips plugin:install) when '
        'install fails', () async {
      final runner = _RecordingRunner(exits: <int>[2]);
      CrumbsInstallCommand.processRunner = runner.run;
      CrumbsInstallCommand.wrapperExistsCheck = () => false;

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(2));
      expect(
        runner.calls,
        hasLength(1),
        reason:
            'plugin:install must not run after scaffold failure (fail-fast)',
      );
      expect(runner.calls.single.contains('install'), isTrue);
    });

    test('returns plugin:install exit code when scaffold passes but '
        'plugin:install fails', () async {
      // First call (scaffold) succeeds; second call (plugin:install) fails.
      final runner = _RecordingRunner(exits: <int>[0, 3]);
      CrumbsInstallCommand.processRunner = runner.run;
      CrumbsInstallCommand.wrapperExistsCheck = () => false;

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );

      expect(exit, equals(3));
      expect(runner.calls, hasLength(2));
    });

    // -------------------------------------------------------------------------
    // Magic-stack branch: pubspec lists `magic_devtools:`, main.dart has
    // `await Magic.init(` and the resolved magic_devtools ships
    // `lib/crumbs.dart`; injected magic import must reference the
    // magic_devtools crumbs barrel (`package:magic_devtools/crumbs.dart`),
    // NOT the removed package:magic sub-barrel.
    // -------------------------------------------------------------------------

    test('magic-stack app whose resolved magic_devtools ships crumbs.dart: '
        'injects import for the magic_devtools crumbs barrel (not the removed '
        'package:magic sub-barrel) plus the integration install call after '
        'Magic.init', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'crumbs_install_magic_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final mainDartPath = _seedProject(
        tempDir,
        pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
        magicDevtoolsLibrary: 'crumbs.dart',
        absoluteRootUri: true,
        mainDartContents: '''
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
      );

      // Stub subprocesses (install + plugin:install) so the
      // command flows straight into step 3 (lib/main.dart wiring).
      final runner = _RecordingRunner();
      CrumbsInstallCommand.processRunner = runner.run;
      // Skip install; only plugin:install will record.
      CrumbsInstallCommand.wrapperExistsCheck = () => true;

      // Switch cwd to the seeded temp dir so the source's relative
      // `File('lib/main.dart')` (L107) + `File('pubspec.yaml')` (L209)
      // lookups resolve against the fixture instead of the host project.
      final previousCwd = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = previousCwd);

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );
      expect(exit, equals(0));

      final result = File(mainDartPath).readAsStringSync();

      // The magic-detect branch (_hasMagicDevtoolsDep + Magic.init anchor)
      // must inject the magic_devtools crumbs barrel; never the removed
      // package:magic sub-barrel.
      expect(
        result.contains("import 'package:magic_devtools/crumbs.dart';"),
        isTrue,
        reason:
            'magic-stack inject must reference the magic_devtools crumbs '
            'barrel, not the removed package:magic sub-barrel',
      );

      // The integration install call lands after Magic.init(), under the
      // same !kReleaseMode guard as the crumbs block.
      final magicInitIdx = result.indexOf('await Magic.init(');
      final integrationIdx = result.indexOf(
        'MagicCrumbsIntegration.install();',
      );
      expect(integrationIdx, greaterThan(magicInitIdx));
      expect(
        result,
        contains('if (!kReleaseMode) {\n    MagicCrumbsIntegration'),
      );
      expect(result, isNot(contains('kDebugMode')));

      // Sanity: plugin:install ran (wrapper present, scaffold skipped).
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.contains('plugin:install'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Vanilla app with magic_devtools in pubspec but NO Magic.init anchor:
    // the magic-side import must NOT be injected (would be an unused import
    // that breaks `dart analyze` in the consumer).
    // -------------------------------------------------------------------------

    test('vanilla app with magic_devtools dep but no Magic.init anchor: '
        'must NOT inject the magic_devtools import or MagicCrumbsIntegration.install()', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'crumbs_install_vanilla_magic_dep_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final mainDartPath = _seedProject(
        tempDir,
        // magic_devtools is listed as a dep but the app has no Magic.init.
        pubspecDeps: const {'magic_devtools': 'any'},
        mainDartContents: '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}
''',
      );

      final runner = _RecordingRunner();
      CrumbsInstallCommand.processRunner = runner.run;
      CrumbsInstallCommand.wrapperExistsCheck = () => true;

      final previousCwd = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = previousCwd);

      final exit = await CrumbsInstallCommand().handle(
        DowelContext.bare(MapInput(const {}), BufferedOutput()),
      );
      expect(exit, equals(0));

      final result = File(mainDartPath).readAsStringSync();

      // The magic_devtools import must NOT appear: injecting it without a
      // Magic.init call would leave it unused and break `dart analyze`.
      expect(
        result.contains("import 'package:magic_devtools/crumbs.dart';"),
        isFalse,
        reason:
            'no Magic.init anchor means there is no MagicCrumbsIntegration '
            'call site; the import would be unused and break dart analyze',
      );

      // The integration install call must NOT appear either.
      expect(
        result.contains('MagicCrumbsIntegration.install();'),
        isFalse,
        reason:
            'MagicCrumbsIntegration.install() has nowhere to land without '
            'a Magic.init anchor; it must not be injected',
      );

      // The vanilla CrumbsPlugin wiring must still be present (unaffected).
      expect(
        result.contains('CrumbsPlugin.install();'),
        isTrue,
        reason: 'vanilla wiring is unconditional and must still be injected',
      );
    });

    // -------------------------------------------------------------------------
    // Magic guard: a magic_devtools release that predates crumbs ships no
    // `lib/crumbs.dart`, so wiring its integration would leave a main.dart
    // that does not compile.
    // -------------------------------------------------------------------------

    group('Magic guard', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('crumbs_install_guard_');
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      test('magic-stack app whose resolved magic_devtools has no crumbs.dart: '
          'no Magic lines, one upgrade warning, exit 0', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
          magicDevtoolsLibrary: 'telescope.dart',
          mainDartContents: _magicMain,
        );
        final output = BufferedOutput();

        final exit = await _runInstallIn(tempDir, output);

        expect(exit, equals(0));
        final result = File(mainDartPath).readAsStringSync();
        expect(result.contains('CrumbsPlugin.install();'), isTrue);
        expect(result.contains('magic_devtools'), isFalse);
        expect(result.contains('MagicCrumbsIntegration'), isFalse);
        expect(
          'has no crumbs integration yet'.allMatches(output.content).length,
          equals(1),
        );
        expect(output.content, contains('(no lib/crumbs.dart)'));
        expect(output.content, contains('dart run crumbs crumbs:install'));
      });

      test('magic-stack app with magic_devtools in pubspec but no '
          'package_config.json: no Magic lines, the pub get warning', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
          mainDartContents: _magicMain,
        );
        final output = BufferedOutput();

        final exit = await _runInstallIn(tempDir, output);

        expect(exit, equals(0));
        final result = File(mainDartPath).readAsStringSync();
        expect(result.contains('MagicCrumbsIntegration'), isFalse);
        expect(output.content, contains('has no crumbs integration yet'));
        expect(output.content, contains('flutter pub get'));
      });

      test('an invalid package_config.json leaves no Magic lines, and the '
          'installer still exits 0 with the warning', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
          mainDartContents: _magicMain,
        );
        Directory('${tempDir.path}/.dart_tool').createSync();
        File('${tempDir.path}/.dart_tool/package_config.json')
            .writeAsStringSync('{ not json');
        final output = BufferedOutput();

        final exit = await _runInstallIn(tempDir, output);

        expect(exit, equals(0));
        expect(
          File(mainDartPath).readAsStringSync(),
          isNot(contains('MagicCrumbsIntegration')),
        );
        expect(output.content, contains('has no crumbs integration yet'));
      });

      test('a consumer without magic_devtools gets the vanilla wiring and no '
          'warning', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any'},
          mainDartContents: _magicMain,
        );
        final output = BufferedOutput();

        await _runInstallIn(tempDir, output);

        final result = File(mainDartPath).readAsStringSync();
        expect(result.contains('CrumbsPlugin.install();'), isTrue);
        expect(result.contains('MagicCrumbsIntegration'), isFalse);
        expect(output.content, isNot(contains('crumbs integration')));
      });

      test('magicDevtoolsCrumbsSupport reads the package root from '
          'package_config.json', () {
        expect(
          CrumbsInstallCommand.magicDevtoolsCrumbsSupport(tempDir.path),
          equals(MagicDevtoolsCrumbsSupport.unresolved),
        );

        _seedProject(
          tempDir,
          mainDartContents: '',
          magicDevtoolsLibrary: 'telescope.dart',
        );
        expect(
          CrumbsInstallCommand.magicDevtoolsCrumbsSupport(tempDir.path),
          equals(MagicDevtoolsCrumbsSupport.missing),
        );

        File('${tempDir.path}/packages/magic_devtools/lib/crumbs.dart')
            .writeAsStringSync('// stub\n');
        expect(
          CrumbsInstallCommand.magicDevtoolsCrumbsSupport(tempDir.path),
          equals(MagicDevtoolsCrumbsSupport.available),
        );
      });

      test('an invalid package_config.json reads as unresolved', () {
        Directory('${tempDir.path}/.dart_tool').createSync();
        File('${tempDir.path}/.dart_tool/package_config.json')
            .writeAsStringSync('{ not json');

        expect(
          CrumbsInstallCommand.magicDevtoolsCrumbsSupport(tempDir.path),
          equals(MagicDevtoolsCrumbsSupport.unresolved),
        );
      });

      for (final MapEntry<String, Map<String, Object>> malformed
          in <String, Map<String, Object>>{
            'no rootUri': <String, Object>{
              'name': 'magic_devtools',
              'packageUri': 'lib/',
            },
            'a numeric rootUri': <String, Object>{
              'name': 'magic_devtools',
              'rootUri': 42,
              'packageUri': 'lib/',
            },
            'a numeric packageUri': <String, Object>{
              'name': 'magic_devtools',
              'rootUri': '../packages/magic_devtools',
              'packageUri': 7,
            },
            'a rootUri that does not parse': <String, Object>{
              'name': 'magic_devtools',
              'rootUri': 'file://[bad',
              'packageUri': 'lib/',
            },
          }.entries) {
        test(
          'a magic_devtools entry with ${malformed.key} reads as unresolved',
          () {
            Directory('${tempDir.path}/.dart_tool').createSync();
            File('${tempDir.path}/.dart_tool/package_config.json')
                .writeAsStringSync(
                  jsonEncode(<String, Object>{
                    'configVersion': 2,
                    'packages': <Map<String, Object>>[malformed.value],
                  }),
                );

            expect(
              CrumbsInstallCommand.magicDevtoolsCrumbsSupport(tempDir.path),
              equals(MagicDevtoolsCrumbsSupport.unresolved),
            );
          },
        );
      }

      group('in a pub workspace', () {
        // The workspace lives under the system temp directory, outside this
        // repository, so the upward walk can only find the configs written
        // here: a member with no config of its own and no workspace config
        // above it reads as unresolved.
        late Directory member;

        setUp(() {
          member = Directory('${tempDir.path}/packages/app')
            ..createSync(recursive: true);
          File('${member.path}/pubspec.yaml').writeAsStringSync(
            'name: app\n'
            'environment:\n'
            '  sdk: ^3.6.0\n'
            'resolution: workspace\n',
          );
        });

        test('a member without its own package config walks up to the '
            'workspace root config', () {
          expect(
            CrumbsInstallCommand.magicDevtoolsCrumbsSupport(member.path),
            equals(MagicDevtoolsCrumbsSupport.unresolved),
          );

          _seedProject(
            tempDir,
            mainDartContents: '',
            magicDevtoolsLibrary: 'crumbs.dart',
          );
          expect(
            CrumbsInstallCommand.magicDevtoolsCrumbsSupport(member.path),
            equals(MagicDevtoolsCrumbsSupport.available),
          );
        });

        test('a member-local package config takes precedence over the '
            'workspace root config', () {
          _seedProject(
            tempDir,
            mainDartContents: '',
            magicDevtoolsLibrary: 'crumbs.dart',
          );
          final oldRelease = Directory('${member.path}/old/magic_devtools/lib')
            ..createSync(recursive: true);
          File('${oldRelease.path}/telescope.dart')
              .writeAsStringSync('// stub\n');
          Directory('${member.path}/.dart_tool').createSync();
          File('${member.path}/.dart_tool/package_config.json')
              .writeAsStringSync(
                jsonEncode(<String, Object>{
                  'configVersion': 2,
                  'packages': <Map<String, String>>[
                    <String, String>{
                      'name': 'magic_devtools',
                      'rootUri': '../old/magic_devtools',
                      'packageUri': 'lib/',
                    },
                  ],
                }),
              );

          expect(
            CrumbsInstallCommand.magicDevtoolsCrumbsSupport(member.path),
            equals(MagicDevtoolsCrumbsSupport.missing),
          );
        });
      });

      group('with a path dependency outside the project', () {
        // `magic_devtools: path: ../magic_devtools` from a project in
        // `<tempDir>/app`: pub writes a `rootUri` that climbs out of both
        // `.dart_tool` and the project, two levels in all.
        late Directory project;
        late Directory library;

        setUp(() {
          project = Directory('${tempDir.path}/app')..createSync();
          library = Directory('${tempDir.path}/magic_devtools/lib')
            ..createSync(recursive: true);
          Directory('${project.path}/.dart_tool').createSync();
          File('${project.path}/.dart_tool/package_config.json')
              .writeAsStringSync(
                jsonEncode(<String, Object>{
                  'configVersion': 2,
                  'packages': <Map<String, String>>[
                    <String, String>{
                      'name': 'magic_devtools',
                      'rootUri': '../../magic_devtools',
                      'packageUri': 'lib/',
                    },
                  ],
                }),
              );
        });

        test('resolves the package root two levels up', () {
          File('${library.path}/telescope.dart').writeAsStringSync('// stub\n');
          expect(
            CrumbsInstallCommand.magicDevtoolsCrumbsSupport(project.path),
            equals(MagicDevtoolsCrumbsSupport.missing),
          );

          File('${library.path}/crumbs.dart').writeAsStringSync('// stub\n');
          expect(
            CrumbsInstallCommand.magicDevtoolsCrumbsSupport(project.path),
            equals(MagicDevtoolsCrumbsSupport.available),
          );
        });

        test('the installer wires the Magic lines', () async {
          File('${library.path}/crumbs.dart').writeAsStringSync('// stub\n');
          final mainDartPath = _seedProject(
            project,
            pubspecDeps: const {
              'magic': 'any',
              'magic_devtools': '\n    path: ../magic_devtools',
            },
            mainDartContents: _magicMain,
          );
          final output = BufferedOutput();

          final exit = await _runInstallIn(project, output);

          expect(exit, equals(0));
          final result = File(mainDartPath).readAsStringSync();
          expect(
            result,
            contains("import 'package:magic_devtools/crumbs.dart';"),
          );
          expect(result, contains('MagicCrumbsIntegration.install();'));
          expect(output.content, isNot(contains('crumbs integration')));
        });
      });

      test('a Magic app already calling CrumbsPlugin.install() gets the '
          'Magic lines and no second crumbs block', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
          magicDevtoolsLibrary: 'crumbs.dart',
          mainDartContents: '''
import 'package:crumbs/crumbs.dart';
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  CrumbsPlugin.install(); // Unconditional on purpose.
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
        );

        await _runInstallIn(tempDir, BufferedOutput());

        final result = File(mainDartPath).readAsStringSync();
        expect('CrumbsPlugin.install('.allMatches(result).length, equals(1));
        expect('ExceptionWatcher()'.allMatches(result).length, equals(0));
        expect(
          "import 'package:crumbs/crumbs.dart';".allMatches(result).length,
          equals(1),
        );
        expect(
          result,
          contains("import 'package:magic_devtools/crumbs.dart';"),
        );
        expect(result, contains('MagicCrumbsIntegration.install();'));
        expect(result, contains('show kReleaseMode;'));
      });

      test('re-running with crumbs.dart available is idempotent', () async {
        final mainDartPath = _seedProject(
          tempDir,
          pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
          magicDevtoolsLibrary: 'crumbs.dart',
          mainDartContents: _magicMain,
        );

        await _runInstallIn(tempDir, BufferedOutput());
        final afterFirst = File(mainDartPath).readAsStringSync();
        await _runInstallIn(tempDir, BufferedOutput());
        final afterSecond = File(mainDartPath).readAsStringSync();

        expect(afterSecond, equals(afterFirst));
        expect(
          'MagicCrumbsIntegration.install();'.allMatches(afterSecond).length,
          equals(1),
        );
        expect(
          "import 'package:magic_devtools/crumbs.dart';"
              .allMatches(afterSecond)
              .length,
          equals(1),
        );
      });
    });

    // -------------------------------------------------------------------------
    // Already wired: any existing `CrumbsPlugin.install(` call means the app
    // is wired, whatever its shape. A second block would chain the watchers
    // and record every exception and debugPrint twice.
    // -------------------------------------------------------------------------

    group('an app that already calls CrumbsPlugin.install()', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('crumbs_install_wired_');
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      for (final MapEntry<String, String> wired in <String, String>{
        'with comments between the calls': '''
import 'package:flutter/foundation.dart';
import 'package:crumbs/crumbs.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // 1. Install core watcher.
    CrumbsPlugin.install();
    // 2. Opt-in exception + dump watchers.
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }
  runApp(const App());
}
''',
        'in a different shape': '''
import 'package:crumbs/crumbs.dart' show CrumbsPlugin;
import 'package:flutter/widgets.dart';

void main() {
  const bool wireCrumbs = !bool.fromEnvironment('dart.vm.product');
  if (wireCrumbs) CrumbsPlugin.install();
  runApp(const App());
}
''',
      }.entries) {
        test('${wired.key} is left byte-identical', () async {
          final mainDartPath = _seedProject(
            tempDir,
            mainDartContents: wired.value,
          );

          final exit = await _runInstallIn(tempDir, BufferedOutput());

          expect(exit, equals(0));
          expect(File(mainDartPath).readAsStringSync(), equals(wired.value));
        });
      }

      test('a re-run on a freshly wired file is a no-op', () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const App());
}
''',
        );

        await _runInstallIn(tempDir, BufferedOutput());
        final afterFirst = File(mainDartPath).readAsStringSync();
        await _runInstallIn(tempDir, BufferedOutput());

        expect(
          'CrumbsPlugin.install('.allMatches(afterFirst).length,
          equals(1),
        );
        expect(File(mainDartPath).readAsStringSync(), equals(afterFirst));
      });
    });

    group('the kReleaseMode guard and import', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('crumbs_install_debug_');
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      test('is skipped when foundation.dart is already imported in full, '
          'which would make it an unnecessary_import', () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(const App());
}
''',
        );

        await _runInstallIn(tempDir, BufferedOutput());

        final result = File(mainDartPath).readAsStringSync();
        expect(result, isNot(contains('show kReleaseMode')));
        expect(result, contains('if (!kReleaseMode) {'));
        expect(result, contains("import 'package:crumbs/crumbs.dart';"));
      });

      test('is added when foundation.dart is not imported', () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const App());
}
''',
        );

        await _runInstallIn(tempDir, BufferedOutput());

        expect(
          File(mainDartPath).readAsStringSync(),
          contains(
            "import 'package:flutter/foundation.dart' show kReleaseMode;",
          ),
        );
      });

      test('a fresh install writes the !kReleaseMode block and the import, '
          'and a re-run adds no second block', () async {
        final mainDartPath = _seedProject(
          tempDir,
          mainDartContents: '''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const App());
}
''',
        );

        await _runInstallIn(tempDir, BufferedOutput());
        final afterFirst = File(mainDartPath).readAsStringSync();

        expect(
          afterFirst,
          contains(
            "import 'package:flutter/foundation.dart' show kReleaseMode;",
          ),
        );
        expect(
          afterFirst,
          contains(
            '  if (!kReleaseMode) {\n'
            '    CrumbsPlugin.install();\n'
            '    CrumbsPlugin.registerWatcher(ExceptionWatcher());\n'
            '    CrumbsPlugin.registerWatcher(DumpWatcher());\n'
            '  }\n'
            '  runApp(',
          ),
        );
        expect(afterFirst, isNot(contains('kDebugMode')));

        await _runInstallIn(tempDir, BufferedOutput());

        expect(File(mainDartPath).readAsStringSync(), equals(afterFirst));
        expect(
          'CrumbsPlugin.install('.allMatches(afterFirst).length,
          equals(1),
        );
      });

      test('a main.dart wired by an earlier crumbs with the kDebugMode block '
          'is left byte-identical, not given a second block', () async {
        const legacy = '''
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';

void main() {
  if (kDebugMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }
  runApp(const App());
}
''';
        final mainDartPath = _seedProject(tempDir, mainDartContents: legacy);

        await _runInstallIn(tempDir, BufferedOutput());

        expect(File(mainDartPath).readAsStringSync(), equals(legacy));
      });

      test(
        'a Magic main.dart wired by an earlier crumbs with the kDebugMode '
        'block gets the Magic block behind the same kDebugMode guard',
        () async {
          final mainDartPath = _seedProject(
            tempDir,
            pubspecDeps: const {'magic': 'any', 'magic_devtools': 'any'},
            magicDevtoolsLibrary: 'crumbs.dart',
            mainDartContents: '''
import 'package:crumbs/crumbs.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    CrumbsPlugin.install();
    CrumbsPlugin.registerWatcher(ExceptionWatcher());
    CrumbsPlugin.registerWatcher(DumpWatcher());
  }
  await Magic.init(configFactories: [() => {}]);
  runApp(const MagicApplication());
}
''',
          );

          await _runInstallIn(tempDir, BufferedOutput());

          final result = File(mainDartPath).readAsStringSync();
          expect(
            result,
            contains(
              '  if (kDebugMode) {\n'
              '    MagicCrumbsIntegration.install();\n'
              '  }\n',
            ),
          );
          expect(result, isNot(contains('kReleaseMode')));
          expect('CrumbsPlugin.install('.allMatches(result).length, equals(1));
        },
      );
    });
  });
}
