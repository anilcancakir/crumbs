/// CLI-side barrel ; intentionally Flutter-free.
///
/// Imported by the consumer's `lib/app/_plugins.g.dart` codegen (which runs
/// under `dart run` on the pure Dart VM, not under `flutter run`). Re-exports
/// the dowel provider class and the pure-Dart [followCursor] loop that a
/// `--follow` command builds on, so `dart run dowel list` and
/// `dart run dowel:mcp` can wire crumbs without dragging the Flutter runtime
/// into the consumer wrapper.
///
/// `dowel`'s `plugins:refresh` generates the import as
/// `<PascalCasePackageName>DowelProvider`, which for this package is
/// [CrumbsDowelProvider] itself.
///
/// Runtime / widget code keeps using `package:crumbs/crumbs.dart`
/// (the full barrel that re-exports `CrumbsPlugin` + watchers + adapters +
/// records + the store).
library;

export 'src/cursor_follow.dart' show followCursor;
export 'src/crumbs_dowel_provider.dart' show CrumbsDowelProvider;
