/// Contract for HTTP capture adapters that feed [CrumbsStore].
///
/// [install] hooks the underlying HTTP library (Dio interceptor,
/// package:http overrides, Chopper interceptor, or Magic's Http facade).
/// [uninstall] is the inverse for test isolation.
///
/// V1 ships [DioHttpAdapter] (vanilla Dio). Magic ships
/// `MagicHttpFacadeAdapter` inside the magic package (wraps Magic.Http via
/// MagicNetworkInterceptor + feeds CrumbsStore).
abstract class CrumbsHttpAdapter {
  /// Human-readable adapter name.
  String get name;

  /// Wire the HTTP capture hook.
  void install();

  /// Tear down the hook (test isolation).
  void uninstall();

  /// Number of HTTP requests currently in flight on this adapter.
  ///
  /// Default body returns 0 ; existing implementations (DioHttpAdapter and
  /// third-party adapters) get the default without changes.
  /// Implementations that track in-flight requests (e.g. magic's
  /// `MagicHttpFacadeAdapter`) override this to expose the live count.
  ///
  /// Surfaced by [CrumbsStore.pendingHttpCount] (sum across all
  /// registered adapters); consumed by tools that synchronise on
  /// "network idle" (tapir `wait_for_network_idle`).
  int get pendingCount => 0;
}
