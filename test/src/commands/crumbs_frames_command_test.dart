import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_frames_command.dart';

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

Map<String, dynamic> _frame({
  int frameNumber = 12,
  int buildMicros = 5400,
  int rasterMicros = 2100,
  Map<String, dynamic> blocks = const <String, dynamic>{},
  int? atUs,
  int? vsyncStartUs,
  String? interactionId,
  String? linkedBy,
}) => <String, dynamic>{
  'time': '2026-08-25T10:00:00.000Z',
  'frameNumber': frameNumber,
  'buildMicros': buildMicros,
  'rasterMicros': rasterMicros,
  'vsyncOverheadMicros': 900,
  'totalSpanMicros': buildMicros + rasterMicros,
  'blocks': blocks,
  'atUs': ?atUs,
  'vsyncStartUs': ?vsyncStartUs,
  'interactionId': ?interactionId,
  'linkedBy': ?linkedBy,
};

void main() {
  group('CrumbsFramesCommand', () {
    test('name is crumbs:frames', () {
      expect(CrumbsFramesCommand().name, equals('crumbs:frames'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsFramesCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsFramesCommand().description, isNotEmpty);
    });

    test('signature declares --limit option with default 50', () {
      expect(CrumbsFramesCommand().signature, contains('--limit=50'));
    });

    test('handle calls ext.crumbs.frames', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'frames': <dynamic>[], 'livenessCounter': 0},
      );

      await CrumbsFramesCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.frames'));
    });

    test('handle forwards limit param when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'limit': '20'}),
        output: BufferedOutput(),
        response: const {'frames': <dynamic>[], 'livenessCounter': 0},
      );

      await CrumbsFramesCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('limit', '20'));
    });

    test('an empty buffer still reports the liveness counter', () async {
      // The whole reason the counter rides along in the same payload: an empty
      // result means either a quiet app or a stalled engine, and only the
      // second is a reason to distrust everything else. Printing the list
      // without the counter would leave the caller unable to tell them apart.
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'frames': <dynamic>[], 'livenessCounter': 4213},
      );

      final code = await CrumbsFramesCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('No frame records'));
      expect(output.content, contains('4213'));
    });

    test(
      'formats build, raster, vsync, total and the block map per frame',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'frames': [
              _frame(
                blocks: const <String, dynamic>{
                  'WDiv': {'micros': 1200, 'count': 4},
                },
              ),
            ],
            'livenessCounter': 88,
          },
        );

        final code = await CrumbsFramesCommand().handle(ctx);

        expect(code, equals(0));
        expect(output.content, contains('frame#12'));
        expect(output.content, contains('5400'));
        expect(output.content, contains('2100'));
        expect(output.content, contains('WDiv'));
        expect(output.content, contains('88'));
      },
    );

    test(
      'formats atUs, vsyncStartUs and the interaction link when present',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: {
            'frames': [
              _frame(
                atUs: 123456,
                vsyncStartUs: 100,
                interactionId: 'tap-1',
                linkedBy: 'zone',
              ),
            ],
            'livenessCounter': 5,
          },
        );

        final code = await CrumbsFramesCommand().handle(ctx);

        expect(code, equals(0));
        expect(output.content, contains('atUs=123456'));
        expect(output.content, contains('vsyncStartUs=100'));
        expect(output.content, contains('interactionId=tap-1'));
        expect(output.content, contains('linkedBy=zone'));
      },
    );

    test('omits the interaction link when interactionId is absent', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'frames': [_frame(atUs: 123456)],
          'livenessCounter': 5,
        },
      );

      final code = await CrumbsFramesCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, isNot(contains('interactionId')));
      expect(output.content, isNot(contains('linkedBy')));
    });

    test('prints linkedBy=window, which carries no interactionId', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'frames': [_frame(atUs: 123456, linkedBy: 'window')],
          'livenessCounter': 5,
        },
      );

      final code = await CrumbsFramesCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content, contains('linkedBy=window'));
      expect(output.content, isNot(contains('interactionId')));
    });

    test('a populated buffer prints one line per frame', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: {
          'frames': [
            _frame(frameNumber: 1),
            _frame(frameNumber: 2),
            _frame(frameNumber: 3),
          ],
          'livenessCounter': 3,
        },
      );

      await CrumbsFramesCommand().handle(ctx);

      expect(output.content, contains('frame#1'));
      expect(output.content, contains('frame#2'));
      expect(output.content, contains('frame#3'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'frames': <dynamic>[], 'livenessCounter': 0},
      );

      expect(await CrumbsFramesCommand().handle(ctx), equals(0));
    });
  });
}
