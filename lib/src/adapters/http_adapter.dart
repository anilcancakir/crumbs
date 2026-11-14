/// Contract for HTTP capture adapters that feed [CrumbsStore].
///
/// [install] hooks the underlying HTTP library (a Dio interceptor,
/// package:http overrides, a Chopper interceptor, or Magic's Http facade)
/// and records each exchange through [CrumbsStore.recordHttp], which masks
/// the credentials. [uninstall] is the inverse for test isolation. An app
/// that wires its own interceptor needs no adapter: it calls
/// [CrumbsStore.recordHttp] directly.
abstract interface class CrumbsHttpAdapter {
  /// Human-readable adapter name.
  String get name;

  /// Wire the HTTP capture hook.
  void install();

  /// Tear down the hook (test isolation).
  void uninstall();

  /// Number of HTTP requests currently in flight on this adapter; 0 for an
  /// adapter that does not track them.
  ///
  /// Summed across every registered adapter by
  /// [CrumbsStore.pendingHttpCount], which tools that wait for a network-idle
  /// window poll.
  int get pendingCount;
}
