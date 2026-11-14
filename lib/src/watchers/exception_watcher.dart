import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../records/exception_record.dart';
import '../crumbs_store.dart';
import 'watcher.dart';

/// Hooks both [FlutterError.onError] and [PlatformDispatcher.instance.onError]
/// to capture all unhandled exceptions in a Flutter app.
///
/// This matches the Flutter "Handling errors" canonical pattern:
/// - [FlutterError.onError] covers synchronous framework + widget errors
///   (null dereferences, assertion failures, layout overflows, etc.).
/// - [PlatformDispatcher.instance.onError] covers asynchronous errors,
///   errors from other isolates, and plugin-originated errors; paths that
///   never reach [FlutterError.onError].
///
/// Both hooks chain-preserve any previously-registered handler (Sentry,
/// Bugsnag, etc.) so that downstream observability is never silently masked.
/// The [PlatformDispatcher.onError] handler chain-preserves the previous
/// handler's return value (`_previousPlatformOnError?.call(...) ?? true`).
/// When a previously-registered handler returns `false`, this watcher also
/// returns `false`, which propagates the error to the native platform crash
/// handler. This is the Sentry-friendly contract: crumbs captures the
/// record AND lets the downstream library decide whether the error is fatal.
/// When no previous handler exists, the default is `true` (handled), so an
/// error crumbs recorded does not also reach the native crash handler.
///
/// Recording never stands between an error and the previous handler: when
/// recording throws (an error whose `toString` throws), the previous handler
/// still runs and the recording failure propagates after it.
///
/// On [uninstall], both handlers are restored to exactly the values they held
/// before [install] was called. Calling [install] while already installed is
/// a no-op (idempotent).
final class ExceptionWatcher implements CrumbsWatcher {
  @override
  String get name => 'exception';

  FlutterExceptionHandler? _previousFlutterOnError;
  ErrorCallback? _previousPlatformOnError;
  bool _installed = false;

  @override
  void install() {
    if (_installed) return;
    _installed = true;

    // 1. Chain-preserve and replace FlutterError.onError (sync framework errors).
    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      try {
        CrumbsStore.recordException(
          ExceptionRecord(
            exceptionType: details.exception.runtimeType.toString(),
            message: details.exceptionAsString(),
            time: DateTime.now(),
            stackTrace: details.stack?.toString(),
          ),
        );
      } finally {
        _previousFlutterOnError?.call(details);
      }
    };

    // 2. Chain-preserve and replace PlatformDispatcher.onError (async + isolate + plugin errors).
    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      bool? verdict;
      try {
        CrumbsStore.recordException(
          ExceptionRecord(
            exceptionType: error.runtimeType.toString(),
            message: error.toString(),
            time: DateTime.now(),
            stackTrace: stack.toString(),
          ),
        );
      } finally {
        // The previous handler's verdict is returned as is, so Sentry or
        // Bugsnag keep deciding whether the error is fatal.
        verdict = _previousPlatformOnError?.call(error, stack);
      }
      return verdict ?? true;
    };
  }

  @override
  void uninstall() {
    if (!_installed) return;

    // 3. Restore both handlers symmetrically.
    FlutterError.onError = _previousFlutterOnError;
    PlatformDispatcher.instance.onError = _previousPlatformOnError;
    _installed = false;
  }
}
