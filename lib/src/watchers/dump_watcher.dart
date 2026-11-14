import 'package:flutter/foundation.dart';

import '../records/dump_record.dart';
import '../crumbs_store.dart';
import 'watcher.dart';

/// Captures all [debugPrint] output by overriding the global callback.
///
/// Installs by replacing the global [debugPrint] function with an interceptor
/// that records a [DumpRecord] to [CrumbsStore] AND calls the previous
/// [debugPrint] value (chain-preserve; Sentry/Bugsnag pattern). On [uninstall],
/// restores the previous reference exactly.
///
/// This watcher is opt-in and NOT auto-installed by [CrumbsPlugin.install].
/// Register it explicitly:
///
/// ```dart
/// CrumbsPlugin.registerWatcher(DumpWatcher());
/// ```
///
/// [install] is gated on [kDebugMode] (or [allowInRelease] set to true before
/// calling [install]). In a release build it returns without replacing
/// [debugPrint]. [allowInRelease] is read at runtime, so the watcher's code
/// still ships in a release build that references it; keeping it out is the
/// consumer's build-mode guard around the registration.
final class DumpWatcher implements CrumbsWatcher {
  /// Allow capturing in release builds. Defaults to false; override before
  /// calling [install] only when you explicitly need release-build capture.
  bool allowInRelease = false;

  @override
  String get name => 'dump';

  /// Holds the live `debugPrint` reference captured at install time. Typed
  /// non-nullable so `uninstall()` can restore it literally without a fallback.
  late DebugPrintCallback _previous;
  bool _installed = false;

  @override
  void install() {
    // Release-build gate: skip unless the caller has opted in explicitly.
    if (!kDebugMode && !allowInRelease) return;

    if (_installed) return;
    _installed = true;

    // Chain-preserve: save whatever is registered as debugPrint right now
    // so Sentry, Bugsnag, or user-defined handlers are not silently masked.
    _previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      CrumbsStore.recordDump(
        DumpRecord(
          message: message ?? '',
          time: DateTime.now(),
          wrapWidth: wrapWidth,
        ),
      );
      _previous(message, wrapWidth: wrapWidth);
    };
  }

  @override
  void uninstall() {
    if (!_installed) return;
    debugPrint = _previous;
    _installed = false;
  }
}
