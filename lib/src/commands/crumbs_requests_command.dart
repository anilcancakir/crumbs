import 'package:dowel/dowel.dart';

/// `dowel crumbs:requests`: print recent HTTP request records.
class CrumbsRequestsCommand extends DowelCommand {
  @override
  String get name => 'crumbs:requests';

  @override
  String get description =>
      'Print recent HTTP request records from the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption('limit', defaultsTo: '50');
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final params = <String, dynamic>{};
    final limit = ctx.input.option('limit');
    if (limit != null) params['limit'] = limit;
    final result = await ctx.callExtension<Map<String, dynamic>>(
      'ext.crumbs.requests',
      params,
    );
    final records = (result['records'] as List?) ?? [];
    if (records.isEmpty) {
      ctx.output.warning('No HTTP records (register a CrumbsHttpAdapter).');
      return 0;
    }
    for (final m in records) {
      final r = m as Map<String, dynamic>;
      final requestIdSuffix = r['requestId'] != null
          ? ' requestId=${r['requestId']}'
          : '';
      // Each half on its own: `linkedBy=window` is the case with no
      // interactionId, so gating both on the id hid it.
      final linkSuffix = [
        if (r['interactionId'] != null) ' interactionId=${r['interactionId']}',
        if (r['linkedBy'] != null) ' linkedBy=${r['linkedBy']}',
      ].join();
      ctx.output.writeln(
        '${r['timestamp']} ${r['method']} ${r['url']} → ${r['statusCode']} '
        '(${r['durationMs']}ms) atUs=${r['atUs']}$requestIdSuffix$linkSuffix',
      );
    }
    return 0;
  }
}
