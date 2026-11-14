import 'dart:io';

import 'package:dowel/dowel.dart';

// Direct import (not the package barrel) so this entrypoint stays Flutter-free.
// The barrel re-exports CrumbsPlugin + watchers, which transitively pull in
// `dart:ui` (PlatformDispatcher, debugPrint). `dart run crumbs`
// runs on the plain Dart VM; touching `dart:ui` from this binary would break
// CLI invocation outside `flutter run`.
import 'package:crumbs/src/cli_args.dart';
import 'package:crumbs/src/crumbs_dowel_provider.dart';

/// `dart run crumbs <cmd>` ; crumbs-flavoured dowel wrapper.
///
/// Proxies the full dowel command surface (start / stop / status / doctor /
/// logs / restart / reload / hot-restart / tinker / make:* / mcp:* /
/// plugin:* / install / etc.) AND registers
/// [CrumbsDowelProvider] so the `crumbs:*` CLI commands and the
/// `crumbs_*` MCP tools surface in the same `list` output.
///
/// When forwarding `mcp:install`, [injectInvocationForMcpInstall] appends
/// `--invocation=crumbs` so the substrate writes the correct
/// `dart run crumbs mcp:serve` entry into `.mcp.json`.
///
/// When forwarding `mcp:serve`, [collectMcpTools] is forced `true` so that
/// the `crumbs_*` MCP tools surface alongside the substrate `dowel_*` tools.
///
/// Run from any consumer directory that has `crumbs` in its
/// pubspec as a dependency.
Future<void> main(List<String> args) async {
  final injected = injectInvocationForMcpInstall(args, 'crumbs');
  final firstNonFlag = injected.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  final isMcpServe = firstNonFlag == 'mcp:serve';

  exit(
    await runDowel(
      injected,
      baseProviders: [CrumbsDowelProvider()],
      collectMcpTools: isMcpServe,
      delegateToConsumer: false,
    ),
  );
}
