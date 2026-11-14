/// Contract for additional data collectors registered via
/// [CrumbsPlugin.registerWatcher].
///
/// Built-in: LogWatcher (auto-installed), ExceptionWatcher, DumpWatcher and
/// FramePerfWatcher (opt-in). An `interface` so a collector from another
/// package `implements` it and inherits nothing a later release could change
/// under it.
abstract interface class CrumbsWatcher {
  /// Human-readable watcher name.
  String get name;

  /// Wire the watcher's listening hook (event subscription, override, etc.).
  void install();

  /// Tear down the hook (test isolation).
  void uninstall();
}
