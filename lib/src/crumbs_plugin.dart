import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'adapters/http_adapter.dart';
import 'extensions/register_crumbs_extensions.dart';
import 'internal/http_adapter_registry.dart';
import 'watchers/log_watcher.dart';
import 'watchers/watcher.dart';

/// crumbs plugin install entry. Idempotent.
///
/// Auto-installs [LogWatcher] (zero ceremony, package:logging is the
/// de-facto standard). ExceptionWatcher, DumpWatcher and FramePerfWatcher
/// are opt-in through [registerWatcher]; HTTP adapters are registered via
/// [registerHttpAdapter].
///
/// With `CRUMBS_DISABLE` set, every entry point returns without installing
/// anything: no extension is registered, and no watcher or adapter replaces
/// a global hook to fill buffers nobody can read.
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
    if (_disabled) return;
    _httpAdapters.add(adapter);
    httpAdapterRegistry.add(adapter);
    adapter.install();
  }

  /// Register an additional watcher (model, cache, custom). The watcher's
  /// install() is called immediately.
  static void registerWatcher(CrumbsWatcher watcher) {
    if (_disabled) return;
    _watchers.add(watcher);
    watcher.install();
  }

  /// Idempotent install. Auto-installs LogWatcher + registers extensions.
  static void install() {
    if (_disabled) {
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

  static bool get _disabled {
    final disable = crumbsDisableEnvValue.toLowerCase().trim();
    return disable == '1' || disable == 'true' || disable == 'yes';
  }

  @visibleForTesting
  static int get installCount => _installCount;

  @visibleForTesting
  static String crumbsDisableEnvValue = const String.fromEnvironment(
    'CRUMBS_DISABLE',
    defaultValue: '',
  );
}
