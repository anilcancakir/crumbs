import 'package:dowel/dowel.dart';

/// `dowel crumbs:queries` ; print recent DB query records from the
/// running Flutter app (captured by MagicQueryWatcher subscribed to magic's
/// `QueryExecuted` event).
class CrumbsQueriesCommand extends DowelCommand {
  @override
  String get name => 'crumbs:queries';

  @override
  String get description =>
      'Print recent DB query records (sql + bindings + timeMs) from the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  String get signature =>
      'crumbs:queries '
      '{--limit=50 : Maximum number of records to print (the newest N, oldest first).}';

  @override
  Future<int> handle(DowelContext ctx) async {
    final limit = int.tryParse(ctx.input.option('limit')?.toString() ?? '50');
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.crumbs.queries',
      <String, dynamic>{if (limit != null) 'limit': limit.toString()},
    );
    final records = (response['queries'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    if (records.isEmpty) {
      ctx.output.warning('No DB query records (register MagicQueryWatcher).');
      return 0;
    }
    for (final r in records) {
      ctx.output.writeln(
        '${r['time']} [${r['connectionName']}] '
        '${r['sql']} bindings=${r['bindings']} (${r['timeMs']}ms)',
      );
    }
    return 0;
  }
}
