import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_exceptions_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    required this._response,
  }) : super.bare(input, output);

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
  group('CrumbsExceptionsCommand', () {
    test('name is crumbs:exceptions', () {
      expect(CrumbsExceptionsCommand().name, equals('crumbs:exceptions'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsExceptionsCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsExceptionsCommand().description, isNotEmpty);
    });

    test('configure registers --limit option with default 50', () {
      final parser = ArgParser();

      CrumbsExceptionsCommand().configure(parser);

      expect(parser.options.containsKey('limit'), isTrue);
      expect(parser.options['limit']!.defaultsTo, equals('50'));
    });

    test('configure does not register --since option', () {
      final parser = ArgParser();

      CrumbsExceptionsCommand().configure(parser);

      expect(parser.options.containsKey('since'), isFalse);
    });

    test('handle calls ext.crumbs.exceptions', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[]},
      );

      await CrumbsExceptionsCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.exceptions'));
    });

    test('handle forwards the limit param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '20'}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[]},
      );

      await CrumbsExceptionsCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '20'));
    });

    test('handle sends no limit param when none is given', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'exceptions': <dynamic>[]},
      );

      await CrumbsExceptionsCommand().handle(ctx);

      expect(ctx.lastParams, isNot(contains('limit')));
    });

    test('handle warns and exits 0 when the buffer is empty', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'exceptions': <dynamic>[]},
      );

      final code = await CrumbsExceptionsCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('No exception records'));
      expect(output.content, contains('ExceptionWatcher'));
    });

    test('handle prints a header line then the indented stack trace', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'exceptions': [
            {
              'exceptionType': 'StateError',
              'message': 'Bad state: no element',
              'time': '2026-05-18T12:00:00.000Z',
              'stackTrace':
                  '#0      main (file:///app/main.dart:10:3)\n'
                  '#1      _startIsolate (dart:isolate-patch/isolate_patch.dart:1)',
              'redacted': false,
            },
          ],
        },
      );

      final code = await CrumbsExceptionsCommand().handle(ctx);

      expect(code, equals(0));
      final lines = output.content.trimRight().split('\n');
      expect(
        lines,
        equals(<String>[
          '2026-05-18T12:00:00.000Z StateError: Bad state: no element',
          '  #0      main (file:///app/main.dart:10:3)',
          '  #1      _startIsolate (dart:isolate-patch/isolate_patch.dart:1)',
        ]),
      );
    });

    test(
      'handle indents the continuation lines of a multi-line message',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'exceptions': [
              {
                'exceptionType': 'FlutterError',
                'message':
                    'setState() called after dispose()\r\n'
                    'This error happens if you call setState() on a State object.',
                'time': '2026-05-18T12:00:02.000Z',
                'stackTrace': '#0      main (file:///app/main.dart:10:3)',
                'redacted': false,
              },
            ],
          },
        );

        await CrumbsExceptionsCommand().handle(ctx);

        expect(
          output.content.trimRight().split('\n'),
          equals(<String>[
            '2026-05-18T12:00:02.000Z FlutterError: setState() called after dispose()',
            '  This error happens if you call setState() on a State object.',
            '  #0      main (file:///app/main.dart:10:3)',
          ]),
        );
      },
    );

    test(
      'handle leaves no unindented blank line for a message with blank lines',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'exceptions': [
              {
                'exceptionType': 'FlutterError',
                'message': 'First\n\nSecond\n\n',
                'time': '2026-05-18T12:00:03.000Z',
                'redacted': false,
              },
            ],
          },
        );

        await CrumbsExceptionsCommand().handle(ctx);

        final lines = output.content.trimRight().split('\n');
        expect(
          lines,
          equals(<String>[
            '2026-05-18T12:00:03.000Z FlutterError: First',
            '  Second',
          ]),
        );
        expect(lines.where((l) => !l.startsWith(' ')), hasLength(1));
      },
    );

    test(
      'handle prints only the header when there is no stack trace',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'exceptions': [
              {
                'exceptionType': 'FormatException',
                'message': 'Unexpected character',
                'time': '2026-05-18T12:00:01.000Z',
                'redacted': false,
              },
            ],
          },
        );

        await CrumbsExceptionsCommand().handle(ctx);

        expect(
          output.content.trimRight().split('\n'),
          equals(<String>[
            '2026-05-18T12:00:01.000Z FormatException: Unexpected character',
          ]),
        );
      },
    );

    test(
      'handle prints a header for an empty or blank message and keeps going',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'exceptions': [
              {
                'exceptionType': 'String',
                'message': '',
                'time': '2026-05-18T12:00:04.000Z',
                'stackTrace': '#0      main (file:///app/main.dart:10:3)',
                'redacted': false,
              },
              {
                'exceptionType': 'Exception',
                'message': '  \n ',
                'time': '2026-05-18T12:00:05.000Z',
                'redacted': false,
              },
              {
                'exceptionType': 'StateError',
                'message': 'Bad state: no element',
                'time': '2026-05-18T12:00:06.000Z',
                'redacted': false,
              },
            ],
          },
        );

        final code = await CrumbsExceptionsCommand().handle(ctx);

        expect(code, equals(0));
        expect(
          output.content.trimRight().split('\n'),
          equals(<String>[
            '2026-05-18T12:00:04.000Z String:',
            '  #0      main (file:///app/main.dart:10:3)',
            '2026-05-18T12:00:05.000Z Exception:',
            '2026-05-18T12:00:06.000Z StateError: Bad state: no element',
          ]),
        );
      },
    );
  });
}
