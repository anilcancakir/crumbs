import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/records/event_record.dart';
import 'package:crumbs/src/records/exception_record.dart';
import 'package:crumbs/src/records/http_request_record.dart';
import 'package:crumbs/src/records/log_record_entry.dart';
import 'package:crumbs/src/crumbs_redaction.dart';
import 'package:crumbs/src/crumbs_store.dart';

void main() {
  tearDown(() {
    CrumbsStore.resetForTesting();
  });

  group('CrumbsRedaction', () {
    group('redactParameters()', () {
      test('masks the value under a matching key at any depth', () {
        final Object? redacted = CrumbsRedaction.redactParameters(
          <String, dynamic>{
            'email': 'a@b.test',
            'password': 'hunter2',
            'data': <String, dynamic>{
              'token': 'abc',
              'devices': <dynamic>[
                <String, dynamic>{
                  'name': 'phone',
                  'secret': 's3',
                },
              ],
            },
          },
          <String>{
            'password',
            'token',
            'secret',
          },
        );

        expect(
          redacted,
          equals(<String, dynamic>{
            'email': 'a@b.test',
            'password': CrumbsRedaction.mask,
            'data': <String, dynamic>{
              'token': CrumbsRedaction.mask,
              'devices': <dynamic>[
                <String, dynamic>{
                  'name': 'phone',
                  'secret': CrumbsRedaction.mask,
                },
              ],
            },
          }),
        );
      });

      test('matches keys case-insensitively on both sides', () {
        final Object? redacted = CrumbsRedaction.redactParameters(
          <String, dynamic>{
            'Password': 'hunter2',
            'ACCESS_TOKEN': 'abc',
          },
          <String>{
            'PASSWORD',
            'access_token',
          },
        );

        expect(
          redacted,
          equals(<String, dynamic>{
            'Password': CrumbsRedaction.mask,
            'ACCESS_TOKEN': CrumbsRedaction.mask,
          }),
        );
      });

      test('masks a structured value under a matching key whole', () {
        final Object? redacted = CrumbsRedaction.redactParameters(
          <String, dynamic>{
            'token': <String, dynamic>{
              'plain': 'abc',
            },
          },
          <String>{
            'token',
          },
        );

        expect(
          redacted,
          equals(<String, dynamic>{
            'token': CrumbsRedaction.mask,
          }),
        );
      });

      test('leaves a null or empty credential visible', () {
        final Map<String, dynamic> empty = <String, dynamic>{
          'password': '',
          'token': null,
          'secret': false,
          'access_token': <dynamic>[],
          'refresh_token': <String, dynamic>{},
        };

        final Object? redacted = CrumbsRedaction.redactParameters(
          empty,
          <String>{
            'password',
            'token',
            'secret',
            'access_token',
            'refresh_token',
          },
        );

        expect(redacted, equals(empty));
      });

      test(
          'masks whatever lies past the depth it walks, and never overflows '
          'the stack', () {
        Object? nested = <String, dynamic>{
          'token': 'deep',
        };
        for (var i = 0; i < 20000; i++) {
          nested = <dynamic>[
            nested,
          ];
        }

        final Object? redacted = CrumbsRedaction.redactParameters(
          nested,
          <String>{
            'token',
          },
        );

        var depth = 0;
        Object? cursor = redacted;
        while (cursor is List) {
          cursor = cursor.single;
          depth++;
        }
        expect(depth, lessThan(20000));
        expect(cursor, equals(CrumbsRedaction.mask));
      });

      test('never mutates the input', () {
        final Map<String, dynamic> input = <String, dynamic>{
          'password': 'hunter2',
          'data': <String, dynamic>{
            'token': 'abc',
          },
          'items': <dynamic>[
            <String, dynamic>{
              'secret': 's3',
            },
          ],
        };

        final Object? redacted = CrumbsRedaction.redactParameters(
          input,
          <String>{
            'password',
            'token',
            'secret',
          },
        );

        expect(redacted, isNot(same(input)));
        expect(input['password'], equals('hunter2'));
        expect((input['data'] as Map<String, dynamic>)['token'], equals('abc'));
        expect(
          ((input['items'] as List<dynamic>).single
              as Map<String, dynamic>)['secret'],
          equals('s3'),
        );
      });

      test('returns a scalar or null unchanged', () {
        expect(
          CrumbsRedaction.redactParameters(
            'password',
            <String>{
              'password',
            },
          ),
          equals('password'),
        );
        expect(
          CrumbsRedaction.redactParameters(
            null,
            <String>{
              'password',
            },
          ),
          isNull,
        );
      });
    });

    group('redactBody()', () {
      test(
          'masks a JSON body, and keeps one it cannot read or need not '
          'touch as given', () {
        const Set<String> keys = <String>{
          'Password',
        };
        const String pretty = '{\n  "email": "a@b.test"\n}';
        const String text = 'password is hunter2';

        expect(
          CrumbsRedaction.redactBody('{"password":"hunter2"}', keys),
          equals('{"password":"********"}'),
        );
        expect(CrumbsRedaction.redactBody(pretty, keys), same(pretty));
        expect(CrumbsRedaction.redactBody(text, keys), same(text));
        expect(CrumbsRedaction.redactBody(null, keys), isNull);
      });

      test(
          'masks a form-encoded body pair by pair, keeping every other pair '
          'as given', () {
        const Set<String> keys = <String>{'password', 'client_secret'};

        // An OAuth password grant: the credential sits in a form body, not
        // in JSON, and used to be buffered verbatim.
        expect(
          CrumbsRedaction.redactBody(
            'grant_type=password&username=a%40b.test&PASSWORD=hunter%202'
            '&client_secret=s3cr3t&scope=',
            keys,
          ),
          equals(
            'grant_type=password&username=a%40b.test&PASSWORD=********'
            '&client_secret=********&scope=',
          ),
        );
        // A percent-encoded key still matches; an empty value stays visible.
        expect(
          CrumbsRedaction.redactBody('pass%77ord=x&client_secret=', keys),
          equals('pass%77ord=********&client_secret='),
        );
        // A bracketed key addresses its last part, as a nested JSON key is
        // masked at any depth; a list key `codes[]` addresses `codes`.
        expect(
          CrumbsRedaction.redactBody(
            'user[password]=hunter2&user%5Bemail%5D=a&client_secret[]=x'
            '&user%5Bclient_secret%5D=y',
            keys,
          ),
          equals(
            'user[password]=********&user%5Bemail%5D=a&client_secret[]=********'
            '&user%5Bclient_secret%5D=********',
          ),
        );
        const String untouched = 'username=a&remember=1';
        expect(CrumbsRedaction.redactBody(untouched, keys), same(untouched));
      });
    });

    group('hideRequestHeaders()', () {
      test('adds to the defaults, lowercased', () {
        CrumbsRedaction.hideRequestHeaders(<String>[
          'X-Auth',
        ]);

        expect(
          CrumbsRedaction.hiddenRequestHeaders,
          containsAll(<String>[
            'authorization',
            'proxy-authorization',
            'cookie',
            'set-cookie',
            'x-api-key',
            'x-auth',
          ]),
        );
      });
    });

    group('hideRequestParameters()', () {
      test('adds to the defaults, lowercased', () {
        CrumbsRedaction.hideRequestParameters(<String>[
          'PIN',
        ]);

        expect(
          CrumbsRedaction.hiddenRequestParameters,
          containsAll(<String>[
            'password',
            'password_confirmation',
            'current_password',
            'new_password',
            'token',
            'access_token',
            'refresh_token',
            'secret',
            'client_secret',
            'authorization_code',
            'id_token',
            'two_factor_token',
            'recovery_code',
            'pin',
          ]),
        );
      });
    });

    group('hideResponseParameters()', () {
      test('adds to the defaults, lowercased', () {
        CrumbsRedaction.hideResponseParameters(<String>[
          'Backup_Key',
        ]);

        expect(
          CrumbsRedaction.hiddenResponseParameters,
          containsAll(<String>[
            'token',
            'access_token',
            'refresh_token',
            'plain_text_token',
            'secret',
            'client_secret',
            'id_token',
            'two_factor_token',
            'recovery_codes',
            'qr_url',
            'qr_svg',
            'backup_key',
          ]),
        );
      });
    });

    group('redactor', () {
      test('is null until a host registers one', () {
        expect(CrumbsRedaction.redactor, isNull);
      });

      test('resetForTesting() unregisters it', () {
        CrumbsRedaction.redactor = (String s) => s;

        CrumbsRedaction.resetForTesting();

        expect(CrumbsRedaction.redactor, isNull);
      });

      test('hands the record back untouched while none is registered', () {
        final LogRecordEntry log = LogRecordEntry(
          level: 'INFO',
          levelValue: 800,
          message: 'm',
          loggerName: 'l',
          time: DateTime(2026, 1, 1),
        );
        final ExceptionRecord exception = ExceptionRecord(
          exceptionType: 'E',
          message: 'm',
          time: DateTime(2026, 1, 1),
        );

        expect(CrumbsRedaction.redactLogRecord(log), same(log));
        expect(CrumbsRedaction.redactExceptionRecord(exception),
            same(exception));
      });

      test('drops a record when the redactor throws', () {
        CrumbsRedaction.redactor = (String s) => throw StateError(s);

        expect(
          CrumbsRedaction.redactLogRecord(
            LogRecordEntry(
              level: 'INFO',
              levelValue: 800,
              message: 'm',
              loggerName: 'l',
              time: DateTime(2026, 1, 1),
            ),
          ),
          isNull,
        );
        expect(
          CrumbsRedaction.redactExceptionRecord(
            ExceptionRecord(
              exceptionType: 'E',
              message: 'm',
              time: DateTime(2026, 1, 1),
            ),
          ),
          isNull,
        );
        expect(
          CrumbsRedaction.redactEventRecord(
            EventRecord(
              eventType: 'e',
              payload: <String, dynamic>{},
              time: DateTime(2026, 1, 1),
            ),
          ),
          isNull,
        );
        expect(
          CrumbsRedaction.redactHttpRecord(
            HttpRequestRecord(
              url: 'https://host.test/',
              method: 'GET',
              statusCode: 200,
              durationMs: 1,
              isError: false,
              timestamp: DateTime(2026, 1, 1),
            ),
          ),
          isNull,
        );
      });

      test('runs every String field of a log and an exception record', () {
        CrumbsRedaction.redactor = (String s) => s.toUpperCase();

        final LogRecordEntry log = CrumbsRedaction.redactLogRecord(
          LogRecordEntry(
            level: 'info',
            levelValue: 800,
            message: 'm',
            loggerName: 'l',
            time: DateTime(2026, 1, 1),
            error: 'e',
            stackTrace: 's',
          ),
        )!;
        final ExceptionRecord exception =
            CrumbsRedaction.redactExceptionRecord(
          ExceptionRecord(
            exceptionType: 't',
            message: 'm',
            time: DateTime(2026, 1, 1),
            stackTrace: 's',
            isolate: 'i',
          ),
        )!;

        expect(
          <String?>[
            log.level,
            log.message,
            log.loggerName,
            log.error,
            log.stackTrace,
          ],
          everyElement(anyOf('INFO', 'M', 'L', 'E', 'S')),
        );
        expect(
          <String?>[
            exception.exceptionType,
            exception.message,
            exception.stackTrace,
            exception.isolate,
          ],
          equals(<String?>['T', 'M', 'S', 'I']),
        );
      });
    });

    group('resetForTesting()', () {
      test('drops every addition and keeps the defaults', () {
        CrumbsRedaction.hideRequestHeaders(<String>[
          'x-auth',
        ]);
        CrumbsRedaction.hideRequestParameters(<String>[
          'pin',
        ]);
        CrumbsRedaction.hideResponseParameters(<String>[
          'backup_key',
        ]);

        CrumbsRedaction.resetForTesting();

        expect(
            CrumbsRedaction.hiddenRequestHeaders, isNot(contains('x-auth')));
        expect(
            CrumbsRedaction.hiddenRequestHeaders, contains('authorization'));
        expect(
            CrumbsRedaction.hiddenRequestParameters, isNot(contains('pin')));
        expect(
          CrumbsRedaction.hiddenResponseParameters,
          isNot(contains('backup_key')),
        );
      });

      test('runs as part of CrumbsStore.resetForTesting()', () {
        CrumbsRedaction.hideRequestHeaders(<String>[
          'x-auth',
        ]);

        CrumbsStore.resetForTesting();

        expect(
            CrumbsRedaction.hiddenRequestHeaders, isNot(contains('x-auth')));
      });
    });
  });
}
