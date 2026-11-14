import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/adapters/http_adapter.dart';
import 'package:crumbs/src/internal/http_adapter_registry.dart';
import 'package:crumbs/src/records/dump_record.dart';
import 'package:crumbs/src/records/event_record.dart';
import 'package:crumbs/src/records/exception_record.dart';
import 'package:crumbs/src/records/frame_perf_record.dart';
import 'package:crumbs/src/records/gate_record.dart';
import 'package:crumbs/src/records/http_request_record.dart';
import 'package:crumbs/src/records/log_record_entry.dart';
import 'package:crumbs/src/records/magic_cache_record.dart';
import 'package:crumbs/src/records/magic_model_record.dart';
import 'package:crumbs/src/records/query_record.dart';
import 'package:crumbs/src/crumbs_redaction.dart';
import 'package:crumbs/src/crumbs_store.dart';

void main() {
  // Statics persist across tests within the run; reset before every test.
  setUp(() {
    CrumbsStore.resetForTesting();
  });

  group('CrumbsStore redactor hook', () {
    String redactor(String s) => s.replaceAll('p@ss', '***');

    test('masks an event payload before the queue and the stream', () async {
      CrumbsRedaction.redactor = redactor;
      final Future<EventRecord> emitted = CrumbsStore.onEventRecord.first;

      CrumbsStore.recordEvent(
        EventRecord(
          eventType: 'player.open',
          payload: <String, dynamic>{
            'line': 'x p@ss',
            'count': 3,
            'nested': <String, dynamic>{
              'l': <dynamic>['p@ss', 7],
            },
          },
          time: DateTime(2026, 1, 1),
        ),
      );

      final EventRecord queued = CrumbsStore.recentEvents().single;
      final EventRecord streamed = await emitted;
      for (final EventRecord record in <EventRecord>[queued, streamed]) {
        expect(jsonEncode(record.toJson()), isNot(contains('p@ss')));
        expect(record.redacted, isTrue);
        expect(record.toJson()['redacted'], isTrue);
        expect(
          record.payload,
          equals(<String, dynamic>{
            'line': 'x ***',
            'count': 3,
            'nested': <String, dynamic>{
              'l': <dynamic>['***', 7],
            },
          }),
        );
      }
    });

    test('keeps every other field of a redacted event', () {
      CrumbsRedaction.redactor = redactor;
      final EventRecord original = EventRecord(
        eventType: 'player.open',
        payload: <String, dynamic>{'a': 'b'},
        time: DateTime(2026, 1, 1),
        listenerCount: 2,
        atUs: 42,
        interactionId: 'i1',
        linkedBy: 'zone',
      );

      CrumbsStore.recordEvent(original);

      final Map<String, dynamic> stored =
          CrumbsStore.recentEvents().single.toJson();
      expect(stored, equals(original.toJson()..['redacted'] = true));
    });

    test('a record made before the redactor was set stays unredacted', () {
      CrumbsStore.recordEvent(_event('before'));
      CrumbsRedaction.redactor = redactor;
      CrumbsStore.recordEvent(_event('after'));

      final List<EventRecord> recent = CrumbsStore.recentEvents();
      expect(recent.first.redacted, isFalse);
      expect(recent.last.redacted, isTrue);
    });

    test('leaves a record untouched when no redactor is set', () {
      final EventRecord record = EventRecord(
        eventType: 'e',
        payload: <String, dynamic>{'line': 'x p@ss'},
        time: DateTime(2026, 1, 1),
      );

      CrumbsStore.recordEvent(record);

      expect(CrumbsStore.recentEvents().single, same(record));
      expect(record.redacted, isFalse);
    });

    test('masks every text field of a log record', () async {
      CrumbsRedaction.redactor = redactor;
      final Future<LogRecordEntry> emitted = CrumbsStore.onLogRecord.first;

      CrumbsStore.recordLog(
        LogRecordEntry(
          level: 'INFO',
          levelValue: 800,
          message: 'open p@ss',
          loggerName: 'mpv',
          time: DateTime(2026, 1, 1),
          error: 'bad p@ss',
          stackTrace: '#0 f (p@ss.dart:1)',
          atUs: 77,
        ),
      );

      final LogRecordEntry queued = CrumbsStore.recentLogs().single;
      final LogRecordEntry streamed = await emitted;
      for (final LogRecordEntry record in <LogRecordEntry>[queued, streamed]) {
        expect(jsonEncode(record.toJson()), isNot(contains('p@ss')));
        expect(record.redacted, isTrue);
        expect(record.atUs, equals(77));
        expect(record.message, equals('open ***'));
        expect(record.error, equals('bad ***'));
        expect(record.stackTrace, equals('#0 f (***.dart:1)'));
      }
    });

    test('masks every text field of an exception record', () async {
      CrumbsRedaction.redactor = redactor;
      final Future<ExceptionRecord> emitted =
          CrumbsStore.onExceptionRecord.first;

      CrumbsStore.recordException(
        ExceptionRecord(
          exceptionType: 'StateError',
          message: 'boom p@ss',
          time: DateTime(2026, 1, 1),
          stackTrace: '#0 f (p@ss.dart:1)',
          isolate: 'main',
        ),
      );

      final ExceptionRecord queued = CrumbsStore.recentExceptions().single;
      final ExceptionRecord streamed = await emitted;
      for (final ExceptionRecord record in <ExceptionRecord>[
        queued,
        streamed,
      ]) {
        expect(jsonEncode(record.toJson()), isNot(contains('p@ss')));
        expect(record.redacted, isTrue);
        expect(record.message, equals('boom ***'));
        expect(record.stackTrace, equals('#0 f (***.dart:1)'));
        expect(record.isolate, equals('main'));
      }
    });

    test('masks an http record after its key redaction ran', () async {
      CrumbsRedaction.redactor = redactor;
      final Future<HttpRequestRecord> emitted =
          CrumbsStore.onHttpRecord.first;

      CrumbsStore.recordHttp(
        _httpWith(
          requestHeaders: <String, String>{
            'Authorization': 'Bearer abc',
            'X-Note': 'p@ss',
          },
          requestBody: '{"token":"abc","note":"p@ss"}',
          responseBody: 'plain p@ss',
        ),
      );

      final HttpRequestRecord queued = CrumbsStore.recentHttp().single;
      final HttpRequestRecord streamed = await emitted;
      for (final HttpRequestRecord record in <HttpRequestRecord>[
        queued,
        streamed,
      ]) {
        expect(jsonEncode(record.toJson()), isNot(contains('p@ss')));
        expect(record.redacted, isTrue);
        expect(record.requestHeaders!['Authorization'], equals('********'));
        expect(record.requestHeaders!['X-Note'], equals('***'));
        expect(
          jsonDecode(record.requestBody!),
          equals(<String, dynamic>{'token': '********', 'note': '***'}),
        );
        expect(record.responseBody, equals('plain ***'));
      }
    });

    test('masks the url of an http record', () {
      CrumbsRedaction.redactor = redactor;

      CrumbsStore.recordHttp(
        HttpRequestRecord(
          url: 'https://u:p@ss@host.test/x',
          method: 'GET',
          statusCode: 200,
          durationMs: 1,
          isError: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      );

      expect(
        CrumbsStore.recentHttp().single.url,
        equals('https://u:***@host.test/x'),
      );
    });

    test('masks a secret held in an event payload key', () {
      CrumbsRedaction.redactor = redactor;

      CrumbsStore.recordEvent(
        EventRecord(
          eventType: 'player.open',
          payload: <String, dynamic>{
            'u:p@ss': 'v',
            'nested': <Object, dynamic>{
              7: <String, dynamic>{
                'p@ss': 1,
              },
            },
          },
          time: DateTime(2026, 1, 1),
        ),
      );

      final EventRecord record = CrumbsStore.recentEvents().single;
      expect(jsonEncode(record.toJson()), isNot(contains('p@ss')));
      expect(
        record.payload,
        equals(<String, dynamic>{
          'u:***': 'v',
          'nested': <String, dynamic>{
            '7': <String, dynamic>{
              '***': 1,
            },
          },
        }),
      );
    });

    test('a throwing redactor drops the record from queue and stream',
        () async {
      CrumbsRedaction.redactor = (String s) => throw StateError(s);
      final List<Object> streamed = <Object>[];
      final List<StreamSubscription<Object>> subscriptions =
          <StreamSubscription<Object>>[
        CrumbsStore.onHttpRecord.listen(streamed.add),
        CrumbsStore.onLogRecord.listen(streamed.add),
        CrumbsStore.onExceptionRecord.listen(streamed.add),
        CrumbsStore.onEventRecord.listen(streamed.add),
      ];
      addTearDown(() async {
        for (final StreamSubscription<Object> s in subscriptions) {
          await s.cancel();
        }
      });

      CrumbsStore.recordHttp(_http(1));
      CrumbsStore.recordLog(_log('info', 'p@ss'));
      CrumbsStore.recordException(_exception('p@ss'));
      CrumbsStore.recordEvent(_event('p@ss'));
      await Future<void>.delayed(Duration.zero);

      expect(CrumbsStore.recentHttp(), isEmpty);
      expect(CrumbsStore.recentLogs(), isEmpty);
      expect(CrumbsStore.recentExceptions(), isEmpty);
      expect(CrumbsStore.recentEvents(), isEmpty);
      expect(streamed, isEmpty);
    });

    test('resetForTesting() drops the redactor', () {
      CrumbsRedaction.redactor = redactor;

      CrumbsStore.resetForTesting();

      expect(CrumbsRedaction.redactor, isNull);
    });
  });

  group('CrumbsStore per-kind capacity', () {
    test('caps one kind and leaves the shared cap for the others', () {
      CrumbsStore.setCapacity(3, kind: CrumbsKind.events);

      for (var i = 0; i < 600; i++) {
        CrumbsStore.recordEvent(_event('E$i'));
        CrumbsStore.recordLog(_log('info', 'm$i'));
      }

      expect(
        CrumbsStore.recentEvents().map((r) => r.eventType).toList(),
        equals(['E597', 'E598', 'E599']),
      );
      expect(CrumbsStore.recentLogs(), hasLength(500));
    });

    test('a kind cap wins over the shared cap whichever was set last', () {
      CrumbsStore.setCapacity(4, kind: CrumbsKind.logs);
      CrumbsStore.setCapacity(2);

      for (var i = 0; i < 6; i++) {
        CrumbsStore.recordLog(_log('info', 'm$i'));
        CrumbsStore.recordEvent(_event('E$i'));
      }

      expect(CrumbsStore.recentLogs(), hasLength(4));
      expect(CrumbsStore.recentEvents(), hasLength(2));
    });

    test('the frame-perf kind sets the frame buffer cap', () {
      CrumbsStore.setCapacity(2, kind: CrumbsKind.framePerf);

      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordFramePerf(_frame(i));
      }

      expect(
        CrumbsStore.recentFramePerf().map((r) => r.frameNumber).toList(),
        equals([3, 4]),
      );
    });

    test('every kind addresses its own buffer', () {
      for (final CrumbsKind kind in CrumbsKind.values) {
        CrumbsStore.setCapacity(1, kind: kind);
      }

      for (var i = 0; i < 3; i++) {
        CrumbsStore.recordHttp(_http(i));
        CrumbsStore.recordLog(_log('info', 'm$i'));
        CrumbsStore.recordException(_exception('e$i'));
        CrumbsStore.recordMagicModel(_model('User', 'created'));
        CrumbsStore.recordMagicCache(_cache('k$i'));
        CrumbsStore.recordEvent(_event('E$i'));
        CrumbsStore.recordGate(_gate('g$i', true));
        CrumbsStore.recordDump(_dump('d$i'));
        CrumbsStore.recordQuery(_query(i));
        CrumbsStore.recordFramePerf(_frame(i));
      }

      expect(CrumbsStore.recentHttp(), hasLength(1));
      expect(CrumbsStore.recentLogs(), hasLength(1));
      expect(CrumbsStore.recentExceptions(), hasLength(1));
      expect(CrumbsStore.recentModels(), hasLength(1));
      expect(CrumbsStore.recentCaches(), hasLength(1));
      expect(CrumbsStore.recentEvents(), hasLength(1));
      expect(CrumbsStore.recentGates(), hasLength(1));
      expect(CrumbsStore.recentDumps(), hasLength(1));
      expect(CrumbsStore.recentQueries(), hasLength(1));
      expect(CrumbsStore.recentFramePerf(), hasLength(1));
    });

    test('resetForTesting() drops every kind cap', () {
      CrumbsStore.setCapacity(1, kind: CrumbsKind.events);
      CrumbsStore.resetForTesting();

      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordEvent(_event('E$i'));
      }

      expect(CrumbsStore.recentEvents(), hasLength(5));
    });
  });

  group('CrumbsStore reads', () {
    test('an unknown minLevel matches nothing', () {
      CrumbsStore.recordLog(_log('info', 'a'));
      CrumbsStore.recordLog(_log('severe', 'b'));

      expect(CrumbsStore.recentLogs(minLevel: 'bogus'), isEmpty);
    });

    test('a zero or negative limit returns an empty list', () {
      CrumbsStore.recordEvent(_event('A'));
      CrumbsStore.recordLog(_log('info', 'a'));

      expect(CrumbsStore.recentEvents(limit: 0), isEmpty);
      expect(CrumbsStore.recentEvents(limit: -1), isEmpty);
      expect(CrumbsStore.recentLogs(limit: -1), isEmpty);
      expect(CrumbsStore.recentLogs(limit: -1, minLevel: 'info'), isEmpty);
    });
  });

  group('CrumbsStore event payloads', () {
    test('stores a value that cannot be encoded as its toString()', () {
      final DateTime when = DateTime.utc(2026, 1, 2, 3);

      CrumbsStore.recordEvent(
        EventRecord(
          eventType: 'player.tick',
          payload: <String, dynamic>{
            'at': when,
            'list': <dynamic>[when, 1],
            'nested': <Object, dynamic>{
              'd': const Duration(seconds: 2),
              1: 'numeric key',
            },
          },
          time: DateTime(2026, 1, 1),
        ),
      );

      final EventRecord stored = CrumbsStore.recentEvents().single;
      expect(
        stored.payload,
        equals(<String, dynamic>{
          'at': when.toString(),
          'list': <dynamic>[when.toString(), 1],
          'nested': <String, dynamic>{
            'd': '0:00:02.000000',
            '1': 'numeric key',
          },
        }),
      );
      expect(() => jsonEncode(stored.toJson()), returnsNormally);
    });

    test('keeps an encodable payload as the very same record', () {
      final EventRecord record = EventRecord(
        eventType: 'e',
        payload: <String, dynamic>{
          'a': <dynamic>[1, 'b', null, true, 1.5],
        },
        time: DateTime(2026, 1, 1),
      );

      CrumbsStore.recordEvent(record);

      expect(CrumbsStore.recentEvents().single, same(record));
    });

    test('masks a payload nested past the depth it walks', () {
      CrumbsRedaction.redactor = (s) => s.replaceAll('p@ss', '***');
      Object? deep = 'p@ss';
      for (var i = 0; i < 20000; i++) {
        deep = <dynamic>[deep];
      }

      CrumbsStore.recordEvent(
        EventRecord(
          eventType: 'e',
          payload: <String, dynamic>{'deep': deep},
          time: DateTime(2026, 1, 1),
        ),
      );

      expect(
        CrumbsStore.recentEvents().single.payload.toString(),
        isNot(contains('p@ss')),
      );
    });
  });

  group('CrumbsStore default capacity', () {
    test('default cap is 500 (raised from prior 100)', () {
      // 1. Push 600 records into the http buffer with no setCapacity call.
      for (var i = 0; i < 600; i++) {
        CrumbsStore.recordHttp(_http(i));
      }

      final recent = CrumbsStore.recentHttp();

      // 2. Capacity bound is exactly 500; oldest 100 evicted FIFO.
      expect(recent.length, equals(500));
      expect(recent.first.method, equals('GET-100'));
      expect(recent.last.method, equals('GET-599'));
    });

    test('resetForTesting() restores cap to 500', () {
      CrumbsStore.setCapacity(7);
      CrumbsStore.resetForTesting();

      for (var i = 0; i < 600; i++) {
        CrumbsStore.recordHttp(_http(i));
      }

      expect(CrumbsStore.recentHttp().length, equals(500));
    });
  });

  group('CrumbsStore new buffers (events / gates / dumps)', () {
    // -------------------------------------------------------------------------
    // recordEvent + recentEvents + onEventRecord
    // -------------------------------------------------------------------------

    test('recordEvent appends and recentEvents returns in order', () {
      CrumbsStore.recordEvent(_event('A'));
      CrumbsStore.recordEvent(_event('B'));
      CrumbsStore.recordEvent(_event('C'));

      final recent = CrumbsStore.recentEvents();

      expect(recent.map((r) => r.eventType).toList(), equals(['A', 'B', 'C']));
    });

    test('events buffer enforces FIFO eviction at capacity', () {
      CrumbsStore.setCapacity(3);

      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordEvent(_event('E$i'));
      }

      final recent = CrumbsStore.recentEvents();

      expect(recent.length, equals(3));
      expect(
        recent.map((r) => r.eventType).toList(),
        equals(['E2', 'E3', 'E4']),
      );
    });

    test('recentEvents respects limit (newest-last sublist)', () {
      for (var i = 0; i < 10; i++) {
        CrumbsStore.recordEvent(_event('E$i'));
      }

      final recent = CrumbsStore.recentEvents(limit: 3);

      expect(recent.length, equals(3));
      expect(
        recent.map((r) => r.eventType).toList(),
        equals(['E7', 'E8', 'E9']),
      );
    });

    test('onEventRecord stream emits on recordEvent', () async {
      final record = _event('Streamed');

      final future = expectLater(
        CrumbsStore.onEventRecord,
        emits(same(record)),
      );

      CrumbsStore.recordEvent(record);

      await future;
    });

    // -------------------------------------------------------------------------
    // recordGate + recentGates + onGateRecord
    // -------------------------------------------------------------------------

    test('recordGate appends and recentGates returns in order', () {
      CrumbsStore.recordGate(_gate('monitors.view', true));
      CrumbsStore.recordGate(_gate('monitors.destroy', false));

      final recent = CrumbsStore.recentGates();

      expect(recent.length, equals(2));
      expect(recent.first.ability, equals('monitors.view'));
      expect(recent.first.result, isTrue);
      expect(recent.last.result, isFalse);
    });

    test('gates buffer enforces FIFO eviction at capacity', () {
      CrumbsStore.setCapacity(2);

      CrumbsStore.recordGate(_gate('g1', true));
      CrumbsStore.recordGate(_gate('g2', true));
      CrumbsStore.recordGate(_gate('g3', false));

      final recent = CrumbsStore.recentGates();

      expect(recent.length, equals(2));
      expect(recent.map((r) => r.ability).toList(), equals(['g2', 'g3']));
    });

    test('recentGates respects limit', () {
      for (var i = 0; i < 6; i++) {
        CrumbsStore.recordGate(_gate('g$i', true));
      }

      final recent = CrumbsStore.recentGates(limit: 2);

      expect(recent.length, equals(2));
      expect(recent.map((r) => r.ability).toList(), equals(['g4', 'g5']));
    });

    test('onGateRecord stream emits on recordGate', () async {
      final record = _gate('streamed', true);

      final future = expectLater(
        CrumbsStore.onGateRecord,
        emits(same(record)),
      );

      CrumbsStore.recordGate(record);

      await future;
    });

    // -------------------------------------------------------------------------
    // recordDump + recentDumps + onDumpRecord
    // -------------------------------------------------------------------------

    test('recordDump appends and recentDumps returns in order', () {
      CrumbsStore.recordDump(_dump('hello'));
      CrumbsStore.recordDump(_dump('world'));

      final recent = CrumbsStore.recentDumps();

      expect(recent.map((r) => r.message).toList(), equals(['hello', 'world']));
    });

    test('dumps buffer enforces FIFO eviction at capacity', () {
      CrumbsStore.setCapacity(2);

      CrumbsStore.recordDump(_dump('d1'));
      CrumbsStore.recordDump(_dump('d2'));
      CrumbsStore.recordDump(_dump('d3'));
      CrumbsStore.recordDump(_dump('d4'));

      final recent = CrumbsStore.recentDumps();

      expect(recent.length, equals(2));
      expect(recent.map((r) => r.message).toList(), equals(['d3', 'd4']));
    });

    test('recentDumps respects limit', () {
      for (var i = 0; i < 8; i++) {
        CrumbsStore.recordDump(_dump('d$i'));
      }

      final recent = CrumbsStore.recentDumps(limit: 3);

      expect(recent.length, equals(3));
      expect(
        recent.map((r) => r.message).toList(),
        equals(['d5', 'd6', 'd7']),
      );
    });

    test('onDumpRecord stream emits on recordDump', () async {
      final record = _dump('streamed');

      final future = expectLater(
        CrumbsStore.onDumpRecord,
        emits(same(record)),
      );

      CrumbsStore.recordDump(record);

      await future;
    });
  });

  group('CrumbsStore pause/resume covers all 8 buffers', () {
    test('pause() suppresses every recordX call across all 8 buffers', () {
      CrumbsStore.pause();

      CrumbsStore.recordHttp(_http(0));
      CrumbsStore.recordLog(_log('info', 'm'));
      CrumbsStore.recordException(_exception('boom'));
      CrumbsStore.recordMagicModel(_model('User', 'created'));
      CrumbsStore.recordMagicCache(_cache('k1'));
      CrumbsStore.recordEvent(_event('E'));
      CrumbsStore.recordGate(_gate('g', true));
      CrumbsStore.recordDump(_dump('d'));

      expect(CrumbsStore.recentHttp(), isEmpty);
      expect(CrumbsStore.recentLogs(), isEmpty);
      expect(CrumbsStore.recentExceptions(), isEmpty);
      expect(CrumbsStore.recentModels(), isEmpty);
      expect(CrumbsStore.recentCaches(), isEmpty);
      expect(CrumbsStore.recentEvents(), isEmpty);
      expect(CrumbsStore.recentGates(), isEmpty);
      expect(CrumbsStore.recentDumps(), isEmpty);
    });

    test('resume() restores recording across all 8 buffers', () {
      CrumbsStore.pause();
      CrumbsStore.recordEvent(_event('dropped'));

      CrumbsStore.resume();
      CrumbsStore.recordEvent(_event('kept'));
      CrumbsStore.recordGate(_gate('g', true));
      CrumbsStore.recordDump(_dump('d'));

      expect(CrumbsStore.recentEvents().single.eventType, equals('kept'));
      expect(CrumbsStore.recentGates(), hasLength(1));
      expect(CrumbsStore.recentDumps(), hasLength(1));
    });
  });

  group('CrumbsStore clear() covers all 8 buffers', () {
    test('clear() empties every buffer in a single call', () {
      CrumbsStore.recordHttp(_http(0));
      CrumbsStore.recordLog(_log('info', 'm'));
      CrumbsStore.recordException(_exception('boom'));
      CrumbsStore.recordMagicModel(_model('User', 'created'));
      CrumbsStore.recordMagicCache(_cache('k1'));
      CrumbsStore.recordEvent(_event('E'));
      CrumbsStore.recordGate(_gate('g', true));
      CrumbsStore.recordDump(_dump('d'));

      CrumbsStore.clear();

      expect(CrumbsStore.recentHttp(), isEmpty);
      expect(CrumbsStore.recentLogs(), isEmpty);
      expect(CrumbsStore.recentExceptions(), isEmpty);
      expect(CrumbsStore.recentModels(), isEmpty);
      expect(CrumbsStore.recentCaches(), isEmpty);
      expect(CrumbsStore.recentEvents(), isEmpty);
      expect(CrumbsStore.recentGates(), isEmpty);
      expect(CrumbsStore.recentDumps(), isEmpty);
    });
  });

  group('CrumbsStore existing 5-buffer contract regression', () {
    // -------------------------------------------------------------------------
    // recordHttp / onHttpRecord
    // -------------------------------------------------------------------------

    test('recordHttp appends and onHttpRecord emits', () async {
      final record = _http(42);

      final future = expectLater(
        CrumbsStore.onHttpRecord,
        emits(same(record)),
      );

      CrumbsStore.recordHttp(record);

      expect(CrumbsStore.recentHttp().single, same(record));
      await future;
    });

    // -------------------------------------------------------------------------
    // recordLog / onLogRecord
    // -------------------------------------------------------------------------

    test('recordLog appends and onLogRecord emits', () async {
      final record = _log('info', 'hello');

      final future = expectLater(
        CrumbsStore.onLogRecord,
        emits(same(record)),
      );

      CrumbsStore.recordLog(record);

      expect(CrumbsStore.recentLogs().single, same(record));
      await future;
    });

    // -------------------------------------------------------------------------
    // recordException / onExceptionRecord
    // -------------------------------------------------------------------------

    test('recordException appends and onExceptionRecord emits', () async {
      final record = _exception('boom');

      final future = expectLater(
        CrumbsStore.onExceptionRecord,
        emits(same(record)),
      );

      CrumbsStore.recordException(record);

      expect(CrumbsStore.recentExceptions().single, same(record));
      await future;
    });

    // -------------------------------------------------------------------------
    // recordMagicModel / onModelRecord
    // -------------------------------------------------------------------------

    test('recordMagicModel appends and onModelRecord emits', () async {
      final record = _model('User', 'created');

      final future = expectLater(
        CrumbsStore.onModelRecord,
        emits(same(record)),
      );

      CrumbsStore.recordMagicModel(record);

      expect(CrumbsStore.recentModels().single, same(record));
      await future;
    });

    // -------------------------------------------------------------------------
    // recordMagicCache / onCacheRecord
    // -------------------------------------------------------------------------

    test('recordMagicCache appends and onCacheRecord emits', () async {
      final record = _cache('k1');

      final future = expectLater(
        CrumbsStore.onCacheRecord,
        emits(same(record)),
      );

      CrumbsStore.recordMagicCache(record);

      expect(CrumbsStore.recentCaches().single, same(record));
      await future;
    });

    // -------------------------------------------------------------------------
    // setCapacity contract preserved
    // -------------------------------------------------------------------------

    test('setCapacity bounds future inserts on the existing 5 buffers', () {
      CrumbsStore.setCapacity(2);

      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordHttp(_http(i));
        CrumbsStore.recordLog(_log('info', 'm$i'));
        CrumbsStore.recordException(_exception('e$i'));
        CrumbsStore.recordMagicModel(_model('User', 'created'));
        CrumbsStore.recordMagicCache(_cache('k$i'));
      }

      expect(CrumbsStore.recentHttp(), hasLength(2));
      expect(CrumbsStore.recentLogs(), hasLength(2));
      expect(CrumbsStore.recentExceptions(), hasLength(2));
      expect(CrumbsStore.recentModels(), hasLength(2));
      expect(CrumbsStore.recentCaches(), hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Backfill: boundary cases for the original 5-buffer surface.
  // ---------------------------------------------------------------------------

  group('CrumbsStore FIFO eviction on original 5 buffers (order check)', () {
    test('recordLog enforces FIFO: oldest entries evicted, newest retained',
        () {
      CrumbsStore.setCapacity(3);

      for (var i = 0; i < 6; i++) {
        CrumbsStore.recordLog(_log('info', 'msg$i'));
      }

      final recent = CrumbsStore.recentLogs();
      expect(recent.length, equals(3));
      expect(recent.first.message, equals('msg3'));
      expect(recent.last.message, equals('msg5'));
    });

    test(
        'recordException enforces FIFO: oldest entries evicted, newest retained',
        () {
      CrumbsStore.setCapacity(3);

      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordException(_exception('err$i'));
      }

      final recent = CrumbsStore.recentExceptions();
      expect(recent.length, equals(3));
      expect(recent.first.message, equals('err2'));
      expect(recent.last.message, equals('err4'));
    });

    test(
        'recordMagicModel enforces FIFO: oldest entries evicted, newest retained',
        () {
      CrumbsStore.setCapacity(2);

      CrumbsStore.recordMagicModel(_model('User', 'created'));
      CrumbsStore.recordMagicModel(_model('Team', 'updated'));
      CrumbsStore.recordMagicModel(_model('Monitor', 'deleted'));

      final recent = CrumbsStore.recentModels();
      expect(recent.length, equals(2));
      expect(recent.first.modelClass, equals('Team'));
      expect(recent.last.modelClass, equals('Monitor'));
    });

    test(
        'recordMagicCache enforces FIFO: oldest entries evicted, newest retained',
        () {
      CrumbsStore.setCapacity(2);

      CrumbsStore.recordMagicCache(_cache('k1'));
      CrumbsStore.recordMagicCache(_cache('k2'));
      CrumbsStore.recordMagicCache(_cache('k3'));

      final recent = CrumbsStore.recentCaches();
      expect(recent.length, equals(2));
      expect(recent.first.key, equals('k2'));
      expect(recent.last.key, equals('k3'));
    });
  });

  group('CrumbsStore recentX(limit:) on original 5 buffers', () {
    test('recentHttp(limit:) returns at most limit items, newest-last', () {
      for (var i = 0; i < 10; i++) {
        CrumbsStore.recordHttp(_http(i));
      }

      final recent = CrumbsStore.recentHttp(limit: 4);
      expect(recent.length, equals(4));
      expect(recent.first.method, equals('GET-6'));
      expect(recent.last.method, equals('GET-9'));
    });

    test('recentLogs(limit:) returns at most limit items, newest-last', () {
      for (var i = 0; i < 8; i++) {
        CrumbsStore.recordLog(_log('info', 'msg$i'));
      }

      final recent = CrumbsStore.recentLogs(limit: 3);
      expect(recent.length, equals(3));
      expect(recent.first.message, equals('msg5'));
      expect(recent.last.message, equals('msg7'));
    });

    test('recentExceptions(limit:) returns at most limit items, newest-last',
        () {
      for (var i = 0; i < 6; i++) {
        CrumbsStore.recordException(_exception('err$i'));
      }

      final recent = CrumbsStore.recentExceptions(limit: 2);
      expect(recent.length, equals(2));
      expect(recent.first.message, equals('err4'));
      expect(recent.last.message, equals('err5'));
    });

    test('recentModels(limit:) returns at most limit items, newest-last', () {
      final classes = ['User', 'Team', 'Monitor', 'Metric', 'Incident'];
      for (final c in classes) {
        CrumbsStore.recordMagicModel(_model(c, 'created'));
      }

      final recent = CrumbsStore.recentModels(limit: 2);
      expect(recent.length, equals(2));
      expect(recent.first.modelClass, equals('Metric'));
      expect(recent.last.modelClass, equals('Incident'));
    });

    test('recentCaches(limit:) returns at most limit items, newest-last', () {
      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordMagicCache(_cache('k$i'));
      }

      final recent = CrumbsStore.recentCaches(limit: 3);
      expect(recent.length, equals(3));
      expect(recent.first.key, equals('k2'));
      expect(recent.last.key, equals('k4'));
    });
  });

  group('CrumbsStore _meetsLevel boundary cases (via recentLogs minLevel:)',
      () {
    test('minLevel equal to record level passes (warning >= warning)', () {
      CrumbsStore.recordLog(_log('warning', 'at-boundary'));

      final recent = CrumbsStore.recentLogs(minLevel: 'warning');
      expect(recent, hasLength(1));
      expect(recent.single.message, equals('at-boundary'));
    });

    test('record level below minLevel is filtered out (info < warning)', () {
      CrumbsStore.recordLog(_log('info', 'too-low'));

      final recent = CrumbsStore.recentLogs(minLevel: 'warning');
      expect(recent, isEmpty);
    });

    test('_meetsLevel is case-insensitive (WARNING matches warning)', () {
      CrumbsStore.recordLog(_log('WARNING', 'upper'));
      CrumbsStore.recordLog(_log('info', 'lower'));

      final recent = CrumbsStore.recentLogs(minLevel: 'Warning');
      expect(recent, hasLength(1));
      expect(recent.single.message, equals('upper'));
    });

    test('severe passes when minLevel is warning (severe > warning)', () {
      CrumbsStore.recordLog(_log('severe', 'critical'));
      CrumbsStore.recordLog(_log('info', 'dropped'));

      final recent = CrumbsStore.recentLogs(minLevel: 'warning');
      expect(recent, hasLength(1));
      expect(recent.single.message, equals('critical'));
    });
  });

  group('CrumbsStore clear() does not close streams', () {
    test('onHttpRecord stream remains usable after clear()', () async {
      CrumbsStore.recordHttp(_http(1));
      CrumbsStore.clear();

      final record = _http(2);

      final future = expectLater(
        CrumbsStore.onHttpRecord,
        emits(same(record)),
      );

      CrumbsStore.recordHttp(record);
      expect(CrumbsStore.recentHttp().single, same(record));
      await future;
    });

    test('onLogRecord stream remains usable after clear()', () async {
      CrumbsStore.recordLog(_log('info', 'before'));
      CrumbsStore.clear();

      final record = _log('info', 'after');

      final future = expectLater(
        CrumbsStore.onLogRecord,
        emits(same(record)),
      );

      CrumbsStore.recordLog(record);
      expect(CrumbsStore.recentLogs().single, same(record));
      await future;
    });
  });

  group(
      'CrumbsStore setCapacity() does not trim existing entries retroactively',
      () {
    test(
        'reducing capacity leaves existing entries untouched until next record',
        () {
      // 1. Fill 5 entries at default capacity.
      for (var i = 0; i < 5; i++) {
        CrumbsStore.recordHttp(_http(i));
      }

      // 2. Lower capacity below current count; no eviction yet.
      CrumbsStore.setCapacity(3);

      expect(CrumbsStore.recentHttp(), hasLength(5));

      // 3. Next record triggers eviction down to the new cap.
      CrumbsStore.recordHttp(_http(5));

      final recent = CrumbsStore.recentHttp();
      expect(recent.length, equals(3));
      expect(recent.first.method, equals('GET-3'));
      expect(recent.last.method, equals('GET-5'));
    });
  });

  group('CrumbsStore resetForTesting() full contract', () {
    test('resetForTesting() clears all buffers', () {
      CrumbsStore.recordHttp(_http(0));
      CrumbsStore.recordLog(_log('info', 'm'));
      CrumbsStore.recordException(_exception('e'));
      CrumbsStore.recordMagicModel(_model('User', 'created'));
      CrumbsStore.recordMagicCache(_cache('k'));
      CrumbsStore.recordEvent(_event('E'));
      CrumbsStore.recordGate(_gate('g', true));
      CrumbsStore.recordDump(_dump('d'));

      CrumbsStore.resetForTesting();

      expect(CrumbsStore.recentHttp(), isEmpty);
      expect(CrumbsStore.recentLogs(), isEmpty);
      expect(CrumbsStore.recentExceptions(), isEmpty);
      expect(CrumbsStore.recentModels(), isEmpty);
      expect(CrumbsStore.recentCaches(), isEmpty);
      expect(CrumbsStore.recentEvents(), isEmpty);
      expect(CrumbsStore.recentGates(), isEmpty);
      expect(CrumbsStore.recentDumps(), isEmpty);
    });

    test('resetForTesting() resets capacity to 500', () {
      CrumbsStore.setCapacity(10);
      CrumbsStore.resetForTesting();

      // Push 501 records; only 500 should be retained.
      for (var i = 0; i < 501; i++) {
        CrumbsStore.recordHttp(_http(i));
      }

      expect(CrumbsStore.recentHttp(), hasLength(500));
    });

    test('resetForTesting() unsets pause so recording resumes immediately', () {
      CrumbsStore.pause();
      CrumbsStore.resetForTesting();

      CrumbsStore.recordHttp(_http(0));
      CrumbsStore.recordLog(_log('info', 'm'));

      expect(CrumbsStore.recentHttp(), hasLength(1));
      expect(CrumbsStore.recentLogs(), hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Step 3.4 — pendingHttpCount getter.
  // ---------------------------------------------------------------------------

  group('CrumbsStore.pendingHttpCount', () {
    test('returns 0 when no HTTP adapter is registered', () {
      // resetForTesting() in the outer setUp should have cleared the adapter
      // registry; the getter falls back to 0 for the empty-registry path.
      expect(CrumbsStore.pendingHttpCount, equals(0));
    });

    test('returns 0 when the registered adapter does not override pendingCount',
        () {
      httpAdapterRegistry.add(_DefaultHttpAdapter());
      expect(CrumbsStore.pendingHttpCount, equals(0));
    });

    test('delegates to the registered adapter\'s pendingCount when overridden',
        () {
      final adapter = _CountingHttpAdapter(7);
      httpAdapterRegistry.add(adapter);

      expect(CrumbsStore.pendingHttpCount, equals(7));

      adapter.pendingCount = 12;
      expect(CrumbsStore.pendingHttpCount, equals(12));
    });

    test('sums pendingCount across multiple registered adapters', () {
      httpAdapterRegistry.add(_CountingHttpAdapter(3));
      httpAdapterRegistry.add(_CountingHttpAdapter(5));
      httpAdapterRegistry.add(_DefaultHttpAdapter());

      // 3 + 5 + 0 (default adapter contributes 0).
      expect(CrumbsStore.pendingHttpCount, equals(8));
    });

    test('resetForTesting() clears the adapter registry', () {
      httpAdapterRegistry.add(_CountingHttpAdapter(9));
      expect(CrumbsStore.pendingHttpCount, equals(9));

      CrumbsStore.resetForTesting();
      expect(CrumbsStore.pendingHttpCount, equals(0));
    });
  });

  group('CrumbsStore', () {
    group('recordHttp() redaction', () {
      test(
          'masks a hidden request header whatever its case, and keeps the '
          'rest', () {
        CrumbsStore.recordHttp(
          _httpWith(
            requestHeaders: <String, String>{
              'Authorization': 'Bearer abc',
              'COOKIE': 'session=xyz',
              'Accept': 'application/json',
            },
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(
          stored.requestHeaders,
          equals(<String, String>{
            'Authorization': '********',
            'COOKIE': '********',
            'Accept': 'application/json',
          }),
        );
        expect(stored.toJson().toString(), isNot(contains('abc')));
      });

      test('masks hidden parameters in a JSON request body', () {
        CrumbsStore.recordHttp(
          _httpWith(
            requestBody: '{"email":"a@b.test","password":"hunter2"}',
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(
          jsonDecode(stored.requestBody!),
          equals(<String, dynamic>{
            'email': 'a@b.test',
            'password': '********',
          }),
        );
      });

      test('masks hidden parameters nested in a JSON response body', () {
        CrumbsStore.recordHttp(
          _httpWith(
            responseBody: '{"data":{"token":"abc","user":{"id":1}}}',
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(
          jsonDecode(stored.responseBody!),
          equals(<String, dynamic>{
            'data': <String, dynamic>{
              'token': '********',
              'user': <String, dynamic>{
                'id': 1,
              },
            },
          }),
        );
      });

      test(
          'reads the response body against the response list, not the '
          'request list', () {
        CrumbsRedaction.hideRequestParameters(<String>[
          'pin',
        ]);

        CrumbsStore.recordHttp(
          _httpWith(
            requestBody: '{"pin":"1234"}',
            responseBody: '{"pin":"1234"}',
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(stored.requestBody, equals('{"pin":"********"}'));
        expect(stored.responseBody, equals('{"pin":"1234"}'));
      });

      test('honours a header added through hideRequestHeaders()', () {
        CrumbsRedaction.hideRequestHeaders(<String>[
          'X-Auth',
        ]);

        CrumbsStore.recordHttp(
          _httpWith(
            requestHeaders: <String, String>{
              'x-auth': 'Bearer abc',
            },
          ),
        );

        expect(
          CrumbsStore.recentHttp().single.requestHeaders,
          equals(<String, String>{
            'x-auth': '********',
          }),
        );
      });

      test('masks a form body and leaves one it cannot read untouched', () {
        const String truncated = '{"password":"hunter2", "da... [truncated]';

        CrumbsStore.recordHttp(
          _httpWith(
            requestBody: 'email=a%40b.test&password=hunter2',
            responseBody: truncated,
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(
            stored.requestBody, equals('email=a%40b.test&password=********'));
        expect(stored.responseBody, equals(truncated));
      });

      test('masks hidden parameters inside a top-level JSON array body', () {
        CrumbsStore.recordHttp(
          _httpWith(
            responseBody: '[{"name":"ci","token":"abc"}]',
          ),
        );

        expect(
          CrumbsStore.recentHttp().single.responseBody,
          equals('[{"name":"ci","token":"********"}]'),
        );
      });

      test(
          'masks the two-factor setup answer, the secret inside the QR url '
          'included', () {
        CrumbsStore.recordHttp(
          _httpWith(
            responseBody: jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'secret': 'JBSWY3DP',
                'qr_url': 'otpauth://totp/app?secret=JBSWY3DP',
                'qr_svg': '<svg>JBSWY3DP</svg>',
                'recovery_codes': <String>[
                  'r1-r1',
                ],
              },
            }),
          ),
        );

        final String stored = CrumbsStore.recentHttp().single.responseBody!;
        expect(stored, isNot(contains('JBSWY3DP')));
        expect(stored, isNot(contains('r1-r1')));
      });

      test('never throws on a JSON body nested past the depth it walks', () {
        final String deep = '${'[' * 20000}{"token":"deep"}${']' * 20000}';

        CrumbsStore.recordHttp(
          _httpWith(
            responseBody: deep,
          ),
        );

        expect(
          CrumbsStore.recentHttp().single.responseBody,
          isNot(contains('"deep"')),
        );
      });

      test('keeps a JSON body byte for byte when it holds no hidden key', () {
        const String pretty = '{\n  "email": "a@b.test"\n}';

        CrumbsStore.recordHttp(
          _httpWith(
            requestBody: pretty,
            responseBody: '"token"',
          ),
        );

        final HttpRequestRecord stored = CrumbsStore.recentHttp().single;
        expect(stored.requestBody, equals(pretty));
        expect(stored.responseBody, equals('"token"'));
      });

      test('keeps every other field of the record', () {
        final HttpRequestRecord original = HttpRequestRecord(
          url: 'https://example.test/login',
          method: 'POST',
          statusCode: 200,
          durationMs: 42,
          isError: false,
          timestamp: DateTime(2026, 1, 1),
          requestHeaders: <String, String>{
            'Authorization': 'Bearer abc',
          },
          attributedHeuristically: true,
          requestId: 'r1',
          startUs: 10,
          endUs: 20,
          atUs: 30,
          interactionId: 'i1',
          linkedBy: 'zone',
        );

        CrumbsStore.recordHttp(original);

        final Map<String, dynamic> stored =
            CrumbsStore.recentHttp().single.toJson();
        final Map<String, dynamic> expected = original.toJson()
          ..['requestHeaders'] = <String, String>{
            'Authorization': '********',
          };
        expect(stored, equals(expected));
      });

      test('emits the masked record to onHttpRecord subscribers', () async {
        final Future<HttpRequestRecord> emitted =
            CrumbsStore.onHttpRecord.first;

        CrumbsStore.recordHttp(
          _httpWith(
            requestHeaders: <String, String>{
              'Authorization': 'Bearer abc',
            },
            responseBody: '{"token":"abc"}',
          ),
        );

        final HttpRequestRecord record = await emitted;
        expect(record.requestHeaders!['Authorization'], equals('********'));
        expect(record.responseBody, equals('{"token":"********"}'));
      });
    });
  });
}

HttpRequestRecord _httpWith({
  Map<String, String>? requestHeaders,
  String? requestBody,
  String? responseBody,
}) =>
    HttpRequestRecord(
      method: 'POST',
      url: 'https://example.test/login',
      statusCode: 200,
      durationMs: 1,
      isError: false,
      timestamp: DateTime(2026, 1, 1),
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      responseBody: responseBody,
    );

// ---------------------------------------------------------------------------
// Record fixture helpers (keep tests terse; each helper carries a unique
// distinguishing field so order assertions stay readable).
// ---------------------------------------------------------------------------

HttpRequestRecord _http(int n) => HttpRequestRecord(
      method: 'GET-$n',
      url: 'https://example.test/$n',
      statusCode: 200,
      durationMs: 1,
      isError: false,
      timestamp: DateTime(2026, 1, 1),
    );

LogRecordEntry _log(String level, String message) => LogRecordEntry(
      level: level,
      levelValue: 800,
      loggerName: 'test',
      message: message,
      time: DateTime(2026, 1, 1),
    );

ExceptionRecord _exception(String message) => ExceptionRecord(
      exceptionType: 'TestException',
      message: message,
      time: DateTime(2026, 1, 1),
    );

MagicModelRecord _model(String modelClass, String event) => MagicModelRecord(
      modelClass: modelClass,
      event: event,
      modelKey: '1',
      time: DateTime(2026, 1, 1),
    );

MagicCacheRecord _cache(String key) => MagicCacheRecord(
      operation: 'get',
      key: key,
      time: DateTime(2026, 1, 1),
    );

EventRecord _event(String eventType) => EventRecord(
      eventType: eventType,
      payload: const {},
      time: DateTime(2026, 1, 1),
    );

FramePerfRecord _frame(int n) => FramePerfRecord(
      frameNumber: n,
      buildMicros: 1,
      rasterMicros: 1,
      vsyncOverheadMicros: 1,
      totalSpanMicros: 2,
      time: DateTime(2026, 1, 1),
      blocks: const {},
    );

QueryRecord _query(int n) => QueryRecord(
      sql: 'select $n',
      bindings: const [],
      timeMs: 1,
      time: DateTime(2026, 1, 1),
    );

GateRecord _gate(String ability, bool result) => GateRecord(
      ability: ability,
      result: result,
      arguments: const [],
      time: DateTime(2026, 1, 1),
    );

DumpRecord _dump(String message) => DumpRecord(
      message: message,
      time: DateTime(2026, 1, 1),
    );

// ---------------------------------------------------------------------------
// Step 3.4 — pendingHttpCount delegate
// ---------------------------------------------------------------------------

/// Fake adapter that overrides `pendingCount` so the delegate path can be
/// exercised without spinning up Magic's network interceptor.
class _CountingHttpAdapter extends CrumbsHttpAdapter {
  _CountingHttpAdapter(this._count);

  int _count;

  @override
  String get name => 'counting';

  @override
  void install() {}

  @override
  void uninstall() {}

  @override
  int get pendingCount => _count;

  set pendingCount(int value) => _count = value;
}

/// Adapter that does NOT override `pendingCount`, exercising the abstract
/// contract's default value (= 0).
class _DefaultHttpAdapter extends CrumbsHttpAdapter {
  @override
  String get name => 'default';

  @override
  void install() {}

  @override
  void uninstall() {}

  // Intentionally does NOT override `pendingCount` — relies on the default
  // body declared on the abstract contract (returns 0).
}
