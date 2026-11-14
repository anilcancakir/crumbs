import 'package:dowel/dowel.dart';

/// `dowel crumbs:frames` ; print recent per-frame performance records
/// from the running Flutter app (captured by `FramePerfWatcher` joining
/// `SchedulerBinding` timings with a `FlutterTimeline` block-attribution
/// drain).
class CrumbsFramesCommand extends DowelCommand {
  @override
  String get name => 'crumbs:frames';

  @override
  String get description =>
      'Print recent per-frame performance records (build/raster/vsync micros + block attribution) from the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  String get signature => 'crumbs:frames '
      '{--limit=50 : Cap the window to the most recent N records, printed '
      'oldest to newest.}';

  @override
  Future<int> handle(DowelContext ctx) async {
    final limit = int.tryParse(ctx.input.option('limit')?.toString() ?? '50');
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.crumbs.frames',
      <String, dynamic>{if (limit != null) 'limit': limit.toString()},
    );
    final records = (response['frames'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final livenessCounter = response['livenessCounter'];
    if (records.isEmpty) {
      ctx.output.warning(
        'No frame records (register FramePerfWatcher). '
        'livenessCounter=$livenessCounter',
      );
      return 0;
    }
    for (final r in records) {
      // Each half on its own: `linkedBy=window` is the case with no
      // interactionId, so gating both on the id hid it.
      final linkSuffix = [
        if (r['interactionId'] != null) ' interactionId=${r['interactionId']}',
        if (r['linkedBy'] != null) ' linkedBy=${r['linkedBy']}',
      ].join();
      ctx.output.writeln(
        '${r['time']} frame#${r['frameNumber']} atUs=${r['atUs']} '
        'vsyncStartUs=${r['vsyncStartUs']} '
        'build=${r['buildMicros']}us raster=${r['rasterMicros']}us '
        'vsync=${r['vsyncOverheadMicros']}us total=${r['totalSpanMicros']}us '
        'blocks=${r['blocks']}$linkSuffix',
      );
    }
    ctx.output.writeln('livenessCounter=$livenessCounter');
    return 0;
  }
}
