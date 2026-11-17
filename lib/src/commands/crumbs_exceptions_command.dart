import 'dart:convert';

import 'package:dowel/dowel.dart';

/// `dowel crumbs:exceptions`: print recent captured exception records.
class CrumbsExceptionsCommand extends DowelCommand {
  @override
  String get name => 'crumbs:exceptions';

  @override
  String get description =>
      'Print recent exception records, with stack traces, from the running app.';

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
      'ext.crumbs.exceptions',
      params,
    );
    final records = (result['exceptions'] as List?) ?? [];
    if (records.isEmpty) {
      ctx.output.warning(
        'No exception records (register an ExceptionWatcher).',
      );
      return 0;
    }
    for (final m in records) {
      final r = m as Map<String, dynamic>;
      // A FlutterError message spans several lines; only the header stays
      // unindented, so a caller keys records on the unindented lines.
      final messageLines = const LineSplitter().convert(
        '${r['message']}'.trim(),
      );
      ctx.output.writeln(
        '${r['time']} ${r['exceptionType']}: ${messageLines.first}',
      );
      final stackTrace = r['stackTrace'] as String?;
      final continuation = [
        ...messageLines.skip(1),
        if (stackTrace != null) ...const LineSplitter().convert(stackTrace),
      ];
      for (final line in continuation) {
        if (line.trim().isEmpty) continue;
        ctx.output.writeln('  $line');
      }
    }
    return 0;
  }
}
