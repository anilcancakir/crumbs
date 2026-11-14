import 'package:dowel/dowel.dart';

/// `dowel crumbs:dumps` ; print recent `debugPrint` output from the
/// running Flutter app (captured by DumpWatcher's global `debugPrint`
/// override).
class CrumbsDumpsCommand extends DowelCommand {
  @override
  String get name => 'crumbs:dumps';

  @override
  String get description =>
      'Print recent debugPrint dump records from the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  String get signature =>
      'crumbs:dumps '
      '{--limit=50 : Maximum number of records to print.}';

  @override
  Future<int> handle(DowelContext ctx) async {
    final limit = int.tryParse(ctx.input.option('limit')?.toString() ?? '50');
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.crumbs.dumps',
      <String, dynamic>{if (limit != null) 'limit': limit.toString()},
    );
    final records = (response['dumps'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    if (records.isEmpty) {
      ctx.output.warning(
        'No dump records (install DumpWatcher in debug mode).',
      );
      return 0;
    }
    for (final r in records) {
      ctx.output.writeln('${r['time']} ${r['message']}');
    }
    return 0;
  }
}
