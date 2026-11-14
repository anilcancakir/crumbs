import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'adapters/http_adapter.dart';
import 'extensions/register_crumbs_extensions.dart';
import 'internal/http_adapter_registry.dart';
import 'watchers/log_watcher.dart';
import 'watchers/watcher.dart';

/// crumbs plugin install entry. Idempotent.
///
/// V1 auto-installs [LogWatcher] (zero ceremony, package:logging is the
/// de-facto standard). ExceptionWatcher is opt-in (call install()
/// separately). HTTP adapters are registered via [registerHttpAdapter].
class CrumbsPlugin {
  CrumbsPlugin._();

  static final List<CrumbsHttpAdapter> _httpAdapters = [];
  static final List<CrumbsWatcher> _watchers = [];

  /// Register a pluggable HTTP capture adapter (Dio, package:http, Chopper,
  /// Magic's Http facade). The adapter's install() is called immediately.
  ///
  /// Also pushes the adapter onto the library-internal [httpAdapterRegistry]
  /// so [CrumbsStore.pendingHttpCount] can sum
  /// [CrumbsHttpAdapter.pendingCount] across every registered adapter
  /// without taking a new public API on [CrumbsStore].
  static void registerHttpAdapter(CrumbsHttpAdapter adapter) {
    _httpAdapters.add(adapter);
    httpAdapterRegistry.add(adapter);
    adapter.install();
  }

  /// Register an additional watcher (Magic model, Magic cache, custom).
  /// The watcher's install() is called immediately.
  static void registerWatcher(CrumbsWatcher watcher) {
    _watchers.add(watcher);
    watcher.install();
  }

  /// Idempotent install. Auto-installs LogWatcher + registers extensions.
  static void install() {
    final disable = crumbsDisableEnvValue.toLowerCase().trim();
    if (disable == '1' || disable == 'true' || disable == 'yes') {
      developer.log(
        '[crumbs] install() skipped: CRUMBS_DISABLE set.',
        name: 'crumbs',
      );
      return;
    }
    if (_installCount > 0) {
      developer.log(
        '[crumbs] install() called ${_installCount + 1} times; '
        'skipping duplicate.',
        name: 'crumbs',
      );
      _installCount++;
      return;
    }
    _installCount++;

    // Auto-install LogWatcher (zero-ceremony default).
    final logWatcher = LogWatcher();
    logWatcher.install();
    _watchers.add(logWatcher);

    registerAllCrumbsExtensions();

    developer.log(
      '[crumbs] installed (kDebugMode=$kDebugMode, kIsWeb=$kIsWeb)',
      name: 'crumbs',
    );
  }

  static int _installCount = 0;

  @visibleForTesting
  static int get installCount => _installCount;

  @visibleForTesting
  static String crumbsDisableEnvValue = const String.fromEnvironment(
    'CRUMBS_DISABLE',
    defaultValue: '',
  );
}
