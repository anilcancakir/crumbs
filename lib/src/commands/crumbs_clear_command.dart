import 'package:dowel/dowel.dart';

/// `dowel crumbs:clear`: clear all crumbs buffers.
class CrumbsClearCommand extends DowelCommand {
  @override
  String get name => 'crumbs:clear';

  @override
  String get description =>
      'Clear all 10 crumbs ring buffers atomically (http, logs, '
      'exceptions, events, gates, dumps, queries, caches, magic models, '
      'frame perf).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  Future<int> handle(DowelContext ctx) async {
    await ctx.callExtension<Map<String, dynamic>>('ext.crumbs.clear');
    ctx.output.success('Cleared crumbs buffers.');
    return 0;
  }
}
