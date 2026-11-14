import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_dumps_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    required Map<String, dynamic> response,
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('CrumbsDumpsCommand', () {
    test('name is crumbs:dumps', () {
      expect(CrumbsDumpsCommand().name, equals('crumbs:dumps'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsDumpsCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsDumpsCommand().description, isNotEmpty);
    });

    test('signature declares --limit option with default 50', () {
      expect(CrumbsDumpsCommand().signature, contains('--limit=50'));
    });

    test('handle calls ext.crumbs.dumps and forwards limit', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '20'}),
        output: BufferedOutput(),
        response: const {'dumps': <dynamic>[]},
      );

      await CrumbsDumpsCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.dumps'));
      expect(ctx.lastParams, containsPair('limit', '20'));
    });

    test('handle emits warning when the buffer is empty', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'dumps': <dynamic>[]},
      );

      final code = await CrumbsDumpsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('No dump records'));
    });

    test('handle formats time and message per entry', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'dumps': [
            {
              'time': '2026-09-28T10:00:00.000Z',
              'message': 'poller tick 3',
            },
          ],
        },
      );

      final code = await CrumbsDumpsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('2026-09-28T10:00:00.000Z'));
      expect(output.content, contains('poller tick 3'));
    });
  });
}
