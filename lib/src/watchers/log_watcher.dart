import 'dart:async';

import 'package:logging/logging.dart';

import '../records/log_record_entry.dart';
import '../crumbs_store.dart';
import 'watcher.dart';

/// Subscribes to [Logger.root.onRecord] and feeds [CrumbsStore.recordLog].
///
/// Auto-installed by [CrumbsPlugin.install]. Zero ceremony — the package
/// `package:logging` is the de-facto standard for structured logging in Dart
/// + Flutter; if the app doesn't use it, this watcher is dormant (no log
/// records flow through Logger.root).
class LogWatcher implements CrumbsWatcher {
  @override
  String get name => 'log';

  StreamSubscription<LogRecord>? _sub;

  @override
  void install() {
    if (_sub != null) return; // idempotent
    // Enable hierarchical logging so all loggers funnel through root.
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.ALL;
    _sub = Logger.root.onRecord.listen((record) {
      CrumbsStore.recordLog(LogRecordEntry.fromLogRecord(record));
    });
  }

  @override
  void uninstall() {
    _sub?.cancel();
    _sub = null;
  }
}
