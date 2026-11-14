import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:crumbs/src/adapters/http_adapter.dart';
import 'package:crumbs/src/crumbs_plugin.dart';
import 'package:crumbs/src/crumbs_store.dart';
import 'package:crumbs/src/watchers/watcher.dart';

void main() {
  final String originalDisable = CrumbsPlugin.crumbsDisableEnvValue;

  setUp(CrumbsStore.resetForTesting);

  tearDown(() {
    CrumbsPlugin.crumbsDisableEnvValue = originalDisable;
    CrumbsStore.resetForTesting();
  });

  group('CrumbsPlugin', () {
    group('with CRUMBS_DISABLE set', () {
      for (final String value in <String>['1', 'true', ' YES ']) {
        test('"$value" makes install() a no-op', () {
          CrumbsPlugin.crumbsDisableEnvValue = value;

          CrumbsPlugin.install();

          expect(CrumbsPlugin.installCount, equals(0));
        });
      }

      test('registerWatcher() neither installs nor tracks the watcher', () {
        CrumbsPlugin.crumbsDisableEnvValue = '1';
        final watcher = _CountingWatcher();

        CrumbsPlugin.registerWatcher(watcher);

        expect(watcher.installs, equals(0));
      });

      test('registerHttpAdapter() neither installs nor tracks the adapter', () {
        CrumbsPlugin.crumbsDisableEnvValue = '1';
        final adapter = _CountingHttpAdapter(pending: 4);

        CrumbsPlugin.registerHttpAdapter(adapter);

        expect(adapter.installs, equals(0));
        expect(CrumbsStore.pendingHttpCount, equals(0));
      });
    });

    group('without CRUMBS_DISABLE', () {
      setUp(() => CrumbsPlugin.crumbsDisableEnvValue = '');

      test('registerWatcher() installs the watcher at once', () {
        final watcher = _CountingWatcher();

        CrumbsPlugin.registerWatcher(watcher);

        expect(watcher.installs, equals(1));
      });

      test('registerHttpAdapter() installs the adapter and counts its '
          'in-flight requests', () {
        final adapter = _CountingHttpAdapter(pending: 4);

        CrumbsPlugin.registerHttpAdapter(adapter);

        expect(adapter.installs, equals(1));
        expect(CrumbsStore.pendingHttpCount, equals(4));
      });

      // The install counter is process-wide and has no reset, so the first
      // and the repeated install share one test.
      test('install() installs the log watcher once and counts a repeated '
          'call', () async {
        CrumbsPlugin.install();
        expect(CrumbsPlugin.installCount, equals(1));

        CrumbsPlugin.install();
        expect(CrumbsPlugin.installCount, equals(2));

        Logger('crumbs_plugin_test').info('once');
        await Future<void>.delayed(Duration.zero);
        expect(
          CrumbsStore.recentLogs().map((r) => r.message),
          equals(<String>['once']),
        );
      });
    });
  });
}

final class _CountingWatcher implements CrumbsWatcher {
  int installs = 0;

  @override
  String get name => 'counting';

  @override
  void install() => installs++;

  @override
  void uninstall() {}
}

final class _CountingHttpAdapter implements CrumbsHttpAdapter {
  _CountingHttpAdapter({required this.pending});

  final int pending;
  int installs = 0;

  @override
  String get name => 'counting';

  @override
  void install() => installs++;

  @override
  void uninstall() {}

  @override
  int get pendingCount => pending;
}
