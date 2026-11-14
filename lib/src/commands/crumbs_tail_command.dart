import 'dart:convert';

import 'package:dowel/dowel.dart';

import '../cursor_follow.dart';

/// `dowel crumbs:tail` ; print recent log records from the running app.
///
/// `--since` and `--logger` filter on the app side, `--json` prints one JSON
/// object per line, and `--follow` re-reads every second from the cursor the
/// previous read returned until the process is interrupted.
class CrumbsTailCommand extends DowelCommand {
  /// [_delay] waits between two `--follow` polls and [_shouldStop] ends the loop
  /// once it returns true for the number of polls made so far; both exist so
  /// a test can run the loop without a clock or a Ctrl-C.
  CrumbsTailCommand({this._delay = _wait, this._shouldStop = _never});

  static const Duration _pollInterval = Duration(seconds: 1);

  final Future<void> Function(Duration) _delay;
  final bool Function(int polls) _shouldStop;

  @override
  String get name => 'crumbs:tail';

  @override
  String get description => 'Print recent log records from the running app.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser
      ..addOption('level', help: 'Minimum level (info/warning/severe).')
      ..addOption('limit', defaultsTo: '50')
      ..addOption('since', help: 'Only records after this atUs (microseconds).')
      ..addOption('logger', help: 'Only records of this exact logger name.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print one JSON object per line.',
      )
      ..addFlag(
        'follow',
        negatable: false,
        help: 'Keep polling from the last cursor until interrupted.',
      );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final json = ctx.input.option('json') as bool? ?? false;
    final follow = ctx.input.option('follow') as bool? ?? false;
    final params = <String, dynamic>{};
    final level = ctx.input.option('level');
    if (level != null) params['level'] = level;
    final limit = ctx.input.option('limit');
    if (limit != null) params['limit'] = limit;
    final since = ctx.input.option('since');
    if (since != null) params['since'] = since;
    final logger = ctx.input.option('logger');
    if (logger != null) params['logger'] = logger;

    var polls = 0;
    await followCursor(
      interval: _pollInterval,
      delay: _delay,
      shouldStop: () => !follow || _shouldStop(polls),
      read: (int? since) async {
        polls++;
        if (since != null) params['since'] = since.toString();
        final result = await ctx.callExtension<Map<String, dynamic>>(
          'ext.crumbs.console',
          params,
        );
        final messages = ((result['messages'] as List?) ?? <dynamic>[])
            .cast<Map<String, dynamic>>();

        if (messages.isEmpty && !json && !follow) {
          ctx.output.warning('No log records.');
        }
        for (final r in messages) {
          ctx.output.writeln(
            json
                ? jsonEncode(r)
                : '${r['time']} [${r['level']}] ${r['loggerName']}: ${r['message']}',
          );
        }

        // The cursor is the last atUs seen, so the next read returns only
        // newer records and needs no limit.
        if (follow) params.remove('limit');
        return (result['cursor'] as num?)?.toInt();
      },
    );
    return 0;
  }
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

bool _never(int polls) => false;
