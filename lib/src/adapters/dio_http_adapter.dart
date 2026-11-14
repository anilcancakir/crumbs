import '../records/http_request_record.dart';
import '../crumbs_store.dart';
import 'http_adapter.dart';

/// Vanilla Dio HTTP adapter. It installs no interceptor: register it with
/// `CrumbsPlugin.registerHttpAdapter(DioHttpAdapter())` and call
/// [recordRequest] from the app's own Dio interceptor (`onResponse` and
/// `onError`), as the example app does.
///
/// NOT a Magic-coupled implementation: vanilla Flutter apps using raw Dio
/// instances feed CrumbsStore via this adapter. Magic-app users get the
/// Magic.Http facade adapter via magic's MagicCrumbsIntegration instead.
///
/// V1 stub: the actual Dio Interceptor subclass requires `package:dio` which
/// is not in crumbs's pubspec (vanilla Flutter friendly, we avoid
/// declaring opinionated HTTP lib deps). Consumers add `dio` to THEIR pubspec
/// and wire this adapter manually. V1.x: move this to `crumbs_dio`
/// adapter sub-package.
class DioHttpAdapter implements CrumbsHttpAdapter {
  DioHttpAdapter();

  @override
  String get name => 'dio';

  @override
  void install() {
    // V1 stub. Consumer code wires this adapter by calling
    // `dio.interceptors.add(_DioInterceptor())` where _DioInterceptor extends
    // Dio's Interceptor class and routes onRequest/onResponse/onError to
    // CrumbsStore.recordHttp(HttpRequestRecord(...)).
    //
    // V1.x will move the Dio-coupled glue into `crumbs_dio` so
    // the core crumbs package stays HTTP-library-agnostic.
  }

  @override
  void uninstall() {
    // No-op in V1 stub.
  }

  /// V1 stub adapter does not track in-flight requests (the Dio interceptor
  /// wiring lives in consumer code). Explicit override is required because
  /// Dart's `implements` clause does not inherit default method bodies from
  /// the [CrumbsHttpAdapter] contract.
  @override
  int get pendingCount => 0;

  /// Convenience: programmatically record an HTTP request/response pair into
  /// CrumbsStore from any HTTP library wrapper (Dio, http, Chopper, raw).
  static void recordRequest({
    required String url,
    required String method,
    required int statusCode,
    required int durationMs,
    bool isError = false,
    Map<String, String>? requestHeaders,
    String? requestBody,
    String? responseBody,
  }) {
    CrumbsStore.recordHttp(
      HttpRequestRecord(
        url: url,
        method: method,
        statusCode: statusCode,
        durationMs: durationMs,
        isError: isError,
        timestamp: DateTime.now(),
        requestHeaders: requestHeaders,
        requestBody: requestBody,
        responseBody: responseBody,
      ),
    );
  }
}
