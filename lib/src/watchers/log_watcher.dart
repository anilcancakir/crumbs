import 'dart:async';

import 'package:logging/logging.dart';

import '../records/log_record_entry.dart';
import '../crumbs_store.dart';
import 'watcher.dart';

/// Subscribes to [Logger.root.onRecord] and feeds [CrumbsStore.recordLog].
///
/// Auto-installed by [CrumbsPlugin.install]. Zero ceremony: the package
/// `package:logging` is the de-facto standard for structured logging in Dart
/// + Flutter; if the app doesn't use it, this watcher is dormant (no log
/// records flow through Logger.root).
///
/// [install] sets the root level to [Level.ALL] and enables hierarchical
/// logging so every logger reaches root; [uninstall] puts both back to the
/// values they held before.
final class LogWatcher implements CrumbsWatcher {
  @override
  String get name => 'log';

  StreamSubscription<LogRecord>? _sub;
  late Level _previousRootLevel;
  late bool _previousHierarchical;

  @override
  void install() {
    if (_sub != null) return; // idempotent
    _previousRootLevel = Logger.root.level;
    _previousHierarchical = hierarchicalLoggingEnabled;
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
    _sub = Logger.root.onRecord.listen((record) {
      CrumbsStore.recordLog(LogRecordEntry.fromLogRecord(record));
    });
  }

  @override
  void uninstall() {
    final StreamSubscription<LogRecord>? sub = _sub;
    if (sub == null) return;
    sub.cancel();
    _sub = null;
    Logger.root.level = _previousRootLevel;
    hierarchicalLoggingEnabled = _previousHierarchical;
  }
}
