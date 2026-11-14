import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_requests_command.dart';

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
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('CrumbsRequestsCommand', () {
    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    test('name is crumbs:requests', () {
      expect(CrumbsRequestsCommand().name, equals('crumbs:requests'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsRequestsCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsRequestsCommand().description, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // ArgParser flags
    // -------------------------------------------------------------------------

    test('configure registers --limit option with default 50', () {
      final parser = ArgParser();

      CrumbsRequestsCommand().configure(parser);

      expect(parser.options.containsKey('limit'), isTrue);
      expect(parser.options['limit']!.defaultsTo, equals('50'));
    });

    test('configure does not register --level option', () {
      final parser = ArgParser();

      CrumbsRequestsCommand().configure(parser);

      expect(parser.options.containsKey('level'), isFalse);
    });

    // -------------------------------------------------------------------------
    // Extension method forwarding
    // -------------------------------------------------------------------------

    test('handle calls ext.crumbs.requests', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'records': <dynamic>[]},
      );

      await CrumbsRequestsCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.requests'));
    });

    test('handle forwards limit param when provided', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'limit': '20'}),
        output: output,
        response: const {'records': <dynamic>[]},
      );

      await CrumbsRequestsCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '20'));
    });

    // -------------------------------------------------------------------------
    // Output formatting
    // -------------------------------------------------------------------------

    test('handle emits warning when records list is empty', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'records': <dynamic>[]},
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('No HTTP records'));
    });

    test('handle formats method, url, statusCode, durationMs per entry',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'records': [
            {
              'timestamp': '2026-05-18T12:00:00.000Z',
              'method': 'GET',
              'url': 'https://api.example.com/monitors',
              'statusCode': 200,
              'durationMs': 142,
            },
          ],
        },
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('GET'));
      expect(output.content, contains('https://api.example.com/monitors'));
      expect(output.content, contains('200'));
      expect(output.content, contains('142'));
    });

    test('formats atUs, requestId and the interaction link when present',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'records': [
            {
              'timestamp': '2026-05-18T12:00:00.000Z',
              'method': 'GET',
              'url': 'https://api.example.com/monitors',
              'statusCode': 200,
              'durationMs': 142,
              'atUs': 123456,
              'requestId': 'req-42',
              'interactionId': 'tap-1',
              'linkedBy': 'zone',
            },
          ],
        },
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('atUs=123456'));
      expect(output.content, contains('requestId=req-42'));
      expect(output.content, contains('interactionId=tap-1'));
      expect(output.content, contains('linkedBy=zone'));
    });

    test('omits requestId and the interaction link when absent', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'records': [
            {
              'timestamp': '2026-05-18T12:00:00.000Z',
              'method': 'GET',
              'url': 'https://api.example.com/monitors',
              'statusCode': 200,
              'durationMs': 142,
              'atUs': 123456,
            },
          ],
        },
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, isNot(contains('requestId')));
      expect(output.content, isNot(contains('interactionId')));
      expect(output.content, isNot(contains('linkedBy')));
    });

    test('prints linkedBy=window, which carries no interactionId', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'records': [
            {
              'timestamp': '2026-05-18T12:00:00.000Z',
              'method': 'GET',
              'url': 'https://api.example.com/users',
              'statusCode': 200,
              'durationMs': 142,
              'atUs': 123456,
              'linkedBy': 'window',
            },
          ],
        },
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('linkedBy=window'));
      expect(output.content, isNot(contains('interactionId')));
    });

    test('handle returns 0 on success', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'records': <dynamic>[]},
      );

      final code = await CrumbsRequestsCommand().handle(ctx);

      expect(code, equals(0));
    });
  });
}
