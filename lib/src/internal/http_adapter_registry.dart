import '../adapters/http_adapter.dart';

/// Library-internal registry of HTTP adapters whose [CrumbsHttpAdapter.pendingCount]
/// feeds [CrumbsStore.pendingHttpCount].
///
/// Populated by [CrumbsPlugin.registerHttpAdapter] on every successful
/// adapter registration. Cleared by [CrumbsStore.resetForTesting] for test
/// isolation. Not exported from the public barrel (`lib/crumbs.dart`); the
/// only public surface that touches the list is [CrumbsStore.pendingHttpCount]
/// (read) and [CrumbsPlugin.registerHttpAdapter] (append).
///
/// Kept here (rather than as a private static on [CrumbsStore]) so the
/// "CrumbsStore gains exactly one new public symbol (pendingHttpCount)"
/// constraint stays intact while still letting [CrumbsPlugin] in a separate
/// file feed the list.
final List<CrumbsHttpAdapter> httpAdapterRegistry = <CrumbsHttpAdapter>[];
