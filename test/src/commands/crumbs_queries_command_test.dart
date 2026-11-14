import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_queries_command.dart';

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
  group('CrumbsQueriesCommand', () {
    test('name is crumbs:queries', () {
      expect(CrumbsQueriesCommand().name, equals('crumbs:queries'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsQueriesCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsQueriesCommand().description, isNotEmpty);
    });

    test('signature declares --limit option with default 50', () {
      expect(CrumbsQueriesCommand().signature, contains('--limit=50'));
    });

    test('handle calls ext.crumbs.queries', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'queries': <dynamic>[]},
      );

      await CrumbsQueriesCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.queries'));
    });

    test('handle forwards limit param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '20'}),
        output: BufferedOutput(),
        response: const {'queries': <dynamic>[]},
      );

      await CrumbsQueriesCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '20'));
    });

    test('handle emits warning when queries list is empty', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'queries': <dynamic>[]},
      );

      final code = await CrumbsQueriesCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('No DB query records'));
    });

    test('handle formats sql, connection, bindings, timeMs per entry',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'queries': [
            {
              'time': '2026-05-19T03:00:00.000Z',
              'sql': 'SELECT * FROM monitors WHERE id = ?',
              'bindings': [42],
              'timeMs': 12,
              'connectionName': 'primary',
            },
          ],
        },
      );

      final code = await CrumbsQueriesCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('SELECT * FROM monitors'));
      expect(output.content, contains('[primary]'));
      expect(output.content, contains('[42]'));
      expect(output.content, contains('12ms'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'queries': <dynamic>[]},
      );

      expect(await CrumbsQueriesCommand().handle(ctx), equals(0));
    });
  });
}
