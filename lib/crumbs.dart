/// crumbs: passive runtime inspector for Flutter apps.
///
/// Captures HTTP traffic (a pluggable adapter), logs, uncaught exceptions,
/// debug dumps, events, gate checks, queries and cache operations into
/// in-memory ring buffers, and serves them over VM Service extensions.
///
/// Extension points:
/// - [CrumbsPlugin.registerHttpAdapter] for pluggable HTTP capture (Dio,
///   package:http, Chopper, Magic's Http facade).
/// - [CrumbsPlugin.registerWatcher] for additional data collectors (model
///   lifecycle, cache operations, custom domain events).
///
/// Records are read via [CrumbsStore.recent<X>(limit)]. Live updates via
/// broadcast streams ([CrumbsStore.onHttpRecord], etc.).
library;

export 'src/adapters/http_adapter.dart';
export 'src/records/cache_record.dart';
export 'src/records/dump_record.dart';
export 'src/records/event_record.dart';
export 'src/records/exception_record.dart';
export 'src/records/frame_perf_record.dart';
export 'src/records/gate_record.dart';
export 'src/records/http_request_record.dart';
export 'src/records/log_record_entry.dart';
export 'src/records/model_record.dart';
export 'src/records/query_record.dart';
export 'src/crumbs_dowel_provider.dart';
export 'src/crumbs_file_sink.dart';
export 'src/crumbs_plugin.dart';
export 'src/crumbs_redaction.dart';
export 'src/crumbs_store.dart';
export 'src/watchers/dump_watcher.dart';
export 'src/watchers/exception_watcher.dart';
export 'src/watchers/frame_perf_watcher.dart';
export 'src/watchers/log_watcher.dart';
export 'src/watchers/watcher.dart';
