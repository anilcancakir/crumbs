# Watchers

Every watcher and HTTP adapter that feeds crumbs: what each captures, how it is installed, and the guard and chaining rules they share.

Each unit implements one of two contracts: `CrumbsWatcher` (hook and event capture) or `CrumbsHttpAdapter` (HTTP capture). Both are `abstract interface class`es: a collector from another package implements them, and extending them is not possible. The shipped watchers (`ExceptionWatcher`, `LogWatcher`, `DumpWatcher`, `FramePerfWatcher`) are `final class`: write your own `CrumbsWatcher` rather than subclass one. Both feed a ring buffer in `CrumbsStore`, which a VM Service extension serves to the CLI and the MCP tools. An app that records HTTP from its own interceptor needs no adapter: it calls `CrumbsStore.recordHttp` (see [HTTP adapters](#http-adapters)).

- [Quick Reference](#quick-reference)
- [Call-site guard](#call-site-guard)
- [Chain-preserve pattern](#chain-preserve-pattern)
- [Framework-agnostic watchers](#framework-agnostic-watchers)
- [HTTP adapters](#http-adapters)
  - [Credential redaction](#credential-redaction)
- [Magic-stack watchers](#magic-stack-watchers)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Unit | Contract | Installed by | Buffer (`CrumbsKind`) | Read with |
|:-----|:---------|:-------------|:----------------------|:----------|
| `LogWatcher` | `CrumbsWatcher` | `CrumbsPlugin.install()` | `logs` | `crumbs:tail`, `crumbs_tail` |
| `ExceptionWatcher` | `CrumbsWatcher` | `CrumbsPlugin.registerWatcher()` | `exceptions` | `crumbs_exceptions` |
| `DumpWatcher` | `CrumbsWatcher` | `CrumbsPlugin.registerWatcher()` | `dumps` | `crumbs:dumps`, `crumbs_dumps` |
| `FramePerfWatcher` | `CrumbsWatcher` | `CrumbsPlugin.registerWatcher()` | `framePerf` | `crumbs:frames`, `crumbs_frames` |
| `MagicHttpFacadeAdapter` | `CrumbsHttpAdapter` | `MagicCrumbsIntegration.install()` | `http` | `crumbs:requests`, `crumbs_requests` |
| `MagicModelWatcher` | `CrumbsWatcher` | `MagicCrumbsIntegration.install()` | `models` | `CrumbsStore.recentModels()` in the app |
| `MagicCacheWatcher` | `CrumbsWatcher` | `MagicCrumbsIntegration.install()` | `caches` | `crumbs:caches`, `crumbs_caches` |
| `MagicEventWatcher` | `CrumbsWatcher` | `MagicCrumbsIntegration.install()` | `events` | `crumbs:events`, `crumbs_events` |
| `MagicGateWatcher` | `CrumbsWatcher` | `MagicCrumbsIntegration.install()` | `gates` | `crumbs:gates`, `crumbs_gates` |
| `MagicQueryWatcher` | `CrumbsWatcher` | `MagicCrumbsIntegration.install()` | `queries` | `crumbs:queries`, `crumbs_queries` |

`crumbs:install` registers `ExceptionWatcher` and `DumpWatcher` for you; a hand wiring registers them itself.

<a name="call-site-guard"></a>
## Call-site guard

`CrumbsPlugin.install()` installs no mode guard of its own. The app gates the whole crumbs install at the call site, and `!kReleaseMode` tree-shakes it from a release build:

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  // register additional watchers here
}
```

- `!kReleaseMode` is what `crumbs:install` writes into `lib/main.dart`. Debug and profile builds carry crumbs; a release build does not.
- Profile builds matter when you measure performance: debug frame timings do not describe a shipped app, so a frame measurement needs a profile build. Keep the guard at the call site, never inside a helper, or the call stays live in release and the tree-shake is lost.
- An app wired by an earlier crumbs with a `kDebugMode` guard keeps working, and `crumbs:install` leaves that block as it is. Switch it to `!kReleaseMode` to get frame-performance data in profile builds.

The snippets on this page use `!kReleaseMode`. Individual watchers need no guard of their own, except that `DumpWatcher` has an internal `kDebugMode` check (see below) and so captures nothing in a profile build unless `allowInRelease` is set.

`--dart-define=CRUMBS_DISABLE=1` (or `true`, `yes`) turns the whole install off in a build that must not expose the extensions: `CrumbsPlugin.install()`, `registerWatcher()` and `registerHttpAdapter()` each return without installing anything, so no watcher replaces a global hook to fill a buffer nobody can read.

<a name="chain-preserve-pattern"></a>
## Chain-preserve pattern

A watcher that replaces a global Dart or Flutter hook saves the previous handler, calls it from the new one, and restores it on `uninstall()`. That is how crumbs coexists with Sentry and Bugsnag: it records the error and forwards it to whatever was registered before it. `ExceptionWatcher` is the reference:

```dart
// 1. Chain-preserve FlutterError.onError (sync framework errors).
_previousFlutterOnError = FlutterError.onError;
FlutterError.onError = (FlutterErrorDetails details) {
  CrumbsStore.recordException(/* ... */);
  _previousFlutterOnError?.call(details);
};

// 2. Chain-preserve PlatformDispatcher.instance.onError (async and isolate errors).
_previousPlatformOnError = PlatformDispatcher.instance.onError;
PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
  CrumbsStore.recordException(/* ... */);
  return _previousPlatformOnError?.call(error, stack) ?? true;
};
```

<a name="framework-agnostic-watchers"></a>
## Framework-agnostic watchers

These units ship in `crumbs` and depend on no application framework.

### LogWatcher

| Field | Value |
|---|---|
| Contract | `CrumbsWatcher` |
| Name | `log` |
| Installed by | `CrumbsPlugin.install()`, always |
| Buffer | `CrumbsKind.logs` |
| VM extension | `ext.crumbs.console` |

Subscribes to `Logger.root.onRecord` from `package:logging`. Every record that reaches the root logger, at any level, becomes a `LogRecordEntry` (stamped with a monotonic `atUs`) and goes to the store, through `CrumbsRedaction.redactor` when the host set one.

Install sets `hierarchicalLoggingEnabled` to `true` so named child loggers (`Logger('http')`, `Logger('auth')`) reach the root, and sets `Logger.root.level` to `Level.ALL` so fine-grained levels are emitted too. A second install while the subscription is live is a no-op, and `uninstall()` puts the root level and the hierarchical flag back to the values they held before the install. An app that does not use `package:logging` simply produces no records; adding it later needs no crumbs change. `CrumbsPlugin.install()` offers no way to leave `LogWatcher` out. A level the app sets on `Logger.root` after the install still decides which records are emitted at all.

### ExceptionWatcher

| Field | Value |
|---|---|
| Contract | `CrumbsWatcher` |
| Name | `exception` |
| Installed by | `CrumbsPlugin.registerWatcher(ExceptionWatcher())` (written by `crumbs:install`) |
| Buffer | `CrumbsKind.exceptions` |
| VM extension | `ext.crumbs.exceptions` |

Hooks `FlutterError.onError` (synchronous framework and widget errors) and `PlatformDispatcher.instance.onError` (asynchronous errors, isolate errors, plugin errors), both through the chain-preserve pattern. The `PlatformDispatcher` handler returns the previous handler's answer, so a reporter that returns `false` to let the native crash reporter take over keeps that behaviour; with no previous handler it returns `true` (handled), as before install.

Recording never stands between an error and the previous handler: when recording itself throws (an error whose `toString()` throws), the previous handler still runs, and the recording failure propagates after it.

`uninstall()` restores both handlers to exactly what they held before `install()`; a second `install()` is a no-op.

To coexist with Sentry, initialise Sentry first: the watcher wraps the handlers that already exist, so a reporter installed after crumbs keeps receiving errors only if it chains as well.

```dart
// sentryDsn is the host's; SentryFlutter.init sets both error hooks.
await SentryFlutter.init((options) => options.dsn = sentryDsn);
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(ExceptionWatcher()); // wraps Sentry's handlers; Sentry still fires
}
```

### DumpWatcher

| Field | Value |
|---|---|
| Contract | `CrumbsWatcher` |
| Name | `dump` |
| Installed by | `CrumbsPlugin.registerWatcher(DumpWatcher())` (written by `crumbs:install`) |
| Buffer | `CrumbsKind.dumps` |
| VM extension | `ext.crumbs.dumps` |

Replaces the global `debugPrint` callback with an interceptor that records a `DumpRecord` and calls the previous callback. `uninstall()` restores the previous callback exactly. `print()` does not go through `debugPrint` and is not captured.

`install()` is a no-op outside a debug build unless `allowInRelease` is set to `true` before it runs. `allowInRelease` is read at runtime, so the watcher's code still ships in a release build that references it; keeping it out of release is the job of the call-site guard around `registerWatcher`.

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(DumpWatcher());
}
```

### FramePerfWatcher

| Field | Value |
|---|---|
| Contract | `CrumbsWatcher` |
| Name | `frame_perf` |
| Installed by | `CrumbsPlugin.registerWatcher(FramePerfWatcher())`, never automatically |
| Buffer | `CrumbsKind.framePerf` |
| VM extension | `ext.crumbs.frames` |

Joins frame magnitude from `SchedulerBinding.addTimingsCallback` with per-frame attribution drained from `FlutterTimeline`, and exposes a static `livenessCounter` with every `ext.crumbs.frames` answer. See [FramePerfWatcher](frames.md) for liveness, attribution and the clock.

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(FramePerfWatcher());
}
```

<a name="http-adapters"></a>
## HTTP adapters

HTTP adapters implement `CrumbsHttpAdapter`: `name`, `install`, `uninstall` and `pendingCount`, which has no default body: an adapter that does not track in-flight requests returns 0. They feed `CrumbsStore.recordHttp`, and their in-flight counts add up in `CrumbsStore.pendingHttpCount`, which tapir's `wait_for_network_idle` reads. Register an adapter with `CrumbsPlugin.registerHttpAdapter()`, which calls its `install()` at once.

<a name="credential-redaction"></a>
### Credential redaction

The HTTP buffer is served to AI agents, so `CrumbsStore.recordHttp` masks credentials before it buffers a record, and `onHttpRecord` subscribers receive the masked copy too. The model is Laravel Telescope's: three name lists, matched case-insensitively, each value under a matching name replaced with `********`.

| List | Applies to | Defaults |
|---|---|---|
| Request headers | `requestHeaders` | `authorization`, `proxy-authorization`, `cookie`, `set-cookie`, `x-api-key` |
| Request parameters | keys of a JSON or form `requestBody`, at any depth; the query parameters of the `url`; the keys of the Map elements of a query's `bindings` and a gate check's `arguments` (a positional binding has no key) | `password`, `password_confirmation`, `current_password`, `new_password`, `token`, `access_token`, `refresh_token`, `secret`, `client_secret`, `authorization_code`, `id_token`, `two_factor_token`, `recovery_code`, `api_key`, `apikey`, `signature`, `sig`, `x-amz-signature`, `x-amz-credential`, `x-amz-security-token` |
| Response parameters | keys of a JSON or form `responseBody`, at any depth | every request parameter name above, plus `plain_text_token`, `recovery_codes`, `qr_url`, `qr_svg` |

Extend a list at install time; an addition merges with the defaults and never replaces them:

```dart
CrumbsRedaction.hideRequestHeaders(['X-Auth']);
CrumbsRedaction.hideRequestParameters(['pin']);
CrumbsRedaction.hideResponseParameters(['recovery_codes']);
```

An empty value (null, `false`, `''`, `[]`, `{}`) stays visible: it is not a secret, and it explains a validation failure. A subtree nested deeper than 64 levels is masked whole, which keeps `recordHttp` from overflowing the stack on a pathological body. A bare list with no key (recovery codes returned directly under `data`, for example) has nothing to match and is not masked.

The store reads bodies that parse as a JSON object or array, and form-encoded bodies (`grant_type=password&password=...`), where only the value of a matching pair changes and a bracketed key (`user[password]`, `codes[]`) matches on its last part. Anything else (plain text, a truncated JSON snippet, a Dart `Map.toString()`) is buffered as the adapter handed it over, so an adapter masks a body before it stringifies or truncates it:

```dart
// A body held as a Dart structure.
final Object? safe = CrumbsRedaction.redactParameters(
  data,
  CrumbsRedaction.hiddenRequestParameters,
);

// A body held as a string, before it is cut to size.
final String? safeText = CrumbsRedaction.redactBody(
  text,
  CrumbsRedaction.hiddenResponseParameters,
);
```

Both return a masked copy and never mutate their input. In a URL only the value of a matching query parameter changes; the scheme, host, path and every other pair stay as captured. Free text (a log message, a dump, the SQL of a query) has no keys to match, so only a `CrumbsRedaction.redactor` the host sets masks it, after the key masking, over the text of the log, event, exception and HTTP records, a dump's message, a query's SQL and bindings, and a gate's arguments and user id; a redactor that throws drops the record. Model and cache records are buffered as given. See [Redaction](../getting-started/redaction.md).

### Recording from your own interceptor

crumbs depends on no HTTP client, so an app that does not use Magic records its own traffic: an interceptor builds an `HttpRequestRecord` and passes it to `CrumbsStore.recordHttp`, which applies the credential masking like any adapter. No `CrumbsHttpAdapter` is needed, and without one `CrumbsStore.pendingHttpCount` stays 0. The sample uses Dio, which the app adds itself:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:dio/dio.dart';

class CrumbsDioInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    CrumbsStore.recordHttp(
      HttpRequestRecord(
        url: response.requestOptions.uri.toString(),
        method: response.requestOptions.method,
        statusCode: response.statusCode ?? 0,
        durationMs: 0, // time the request in onRequest for a real duration
        isError: false,
        timestamp: DateTime.now(),
      ),
    );
    handler.next(response);
  }
}
```

Add it with `dio.interceptors.add(CrumbsDioInterceptor())`. The bundled `example/` app has a complete interceptor that times each request and records errors.

### MagicHttpFacadeAdapter

| Field | Value |
|---|---|
| Contract | `CrumbsHttpAdapter` |
| Name | `magic_http_facade` |
| Package | `magic_devtools` (`package:magic_devtools/crumbs.dart`) |
| Installed by | `MagicCrumbsIntegration.install()` |
| Buffer | `CrumbsKind.http` |
| VM extension | `ext.crumbs.requests` |

Captures every request through Magic's `network` driver by registering a `MagicNetworkInterceptor` that pairs `onRequest` with `onResponse` or `onError` through a FIFO in-flight list. The pairing is by call order, since the interceptor contract carries no correlation handle, so records carry `attributedHeuristically: true`. `pendingCount` is the length of that in-flight list.

The adapter masks request and response bodies before it truncates them, and `MagicCrumbsIntegration.install()` hides the header named by Magic's `auth.token.header` config (default `Authorization`) on top of the defaults. Its `install()` registers nothing while the `network` driver is not bound, so call `MagicCrumbsIntegration.install()` after `Magic.init()`.

<a name="magic-stack-watchers"></a>
## Magic-stack watchers

These watchers ship in `magic_devtools`, not in `crumbs` and not in `magic` core, and one `MagicCrumbsIntegration.install()` call after `Magic.init()` registers all of them with `MagicHttpFacadeAdapter`:

```dart
import 'package:magic_devtools/crumbs.dart';

if (!kReleaseMode) {
  MagicCrumbsIntegration.install(); // after Magic.init()
}
```

`magic_devtools` 1.0.0 and later ship the crumbs integration (`package:magic_devtools/crumbs.dart`); with an earlier release the installer warns and skips the Magic wiring. Each watcher subscribes through Magic's `EventDispatcher`, which has no per-listener removal, so its `uninstall()` is a no-op; a test that needs a clean dispatcher calls `EventDispatcher.instance.clear()` in `setUp`.

| Watcher | Name | Subscribes to | Record |
|:--------|:-----|:--------------|:-------|
| `MagicModelWatcher` | `magic_model` | `ModelCreated`, `ModelSaved`, `ModelDeleted` | `ModelRecord`: `modelClass`, `event` (`created`, `saved`, `deleted`), `modelKey`, `time`, a snapshot of `attributes` |
| `MagicCacheWatcher` | `magic_cache` | `CacheHit`, `CacheMiss`, `CachePut`, `CacheForget`, `CacheFlush` | `CacheRecord`: `operation`, `key` (`*` for a flush), `time`, `ttl` on a put |
| `MagicEventWatcher` | `magic_event` | `AuthLogin`, `AuthLogout`, `AuthFailed`, `AuthRestored`, `DatabaseConnected`, `GateAbilityDefined`, `GateBeforeRegistered` | `EventRecord` with an empty `payload`; model and gate-result events stay with their own watchers |
| `MagicGateWatcher` | `magic_gate` | `GateAccessChecked` (covers allows and denies; `GateAccessDenied` is skipped to avoid a double record) | `GateRecord`: `ability`, `result`, `arguments` (the single argument wrapped in a list), `userId` (stringified, null without a user) |
| `MagicQueryWatcher` | `magic_query` | `QueryExecuted`, dispatched by the query builder after every SQL run | `QueryRecord`: `sql`, `bindings`, `timeMs`, `connectionName`, `time` |

The model buffer has no extension and no MCP tool: read it in the app through `CrumbsStore.recentModels()` or `CrumbsStore.onModelRecord`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `crumbs_exceptions` stays empty after a crash. | Register `ExceptionWatcher`; `CrumbsPlugin.install()` installs only `LogWatcher`. |
| Sentry stops receiving errors. | Initialise Sentry before registering `ExceptionWatcher`, so crumbs chains to it. |
| `crumbs_dumps` is empty in a profile build. | `DumpWatcher` installs only in debug builds; set `allowInRelease` before `registerWatcher` to capture in profile. |
| `print()` output is missing from the dump buffer. | Use `debugPrint`; `print` bypasses the hook `DumpWatcher` replaces. |
| Dio traffic does not show up. | crumbs hooks no HTTP client: add an interceptor that calls `CrumbsStore.recordHttp`, or register a `CrumbsHttpAdapter` that does. |
| `crumbs_frames` answers an empty list. | Register `FramePerfWatcher`; a `livenessCounter` that does not advance means it is missing or the engine draws nothing. |
| The Magic buffers stay empty. | Call `MagicCrumbsIntegration.install()` after `Magic.init()`, from a `magic_devtools` release built on crumbs. |

<a name="related-documentation"></a>
## Related Documentation

- [FramePerfWatcher](frames.md): liveness, attribution and the frame clock.
- [Redaction](../getting-started/redaction.md): the text redactor and the `redacted` flag.
- [Installation](../getting-started/installation.md): where each watcher is registered in `main.dart`.
- [Tool reference](../mcp/tool-reference.md): the output shape of each buffer over MCP.
