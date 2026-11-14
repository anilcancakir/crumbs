import 'dart:convert';

import 'package:meta/meta.dart';

import 'internal/redaction_lists.dart' as lists;
import 'records/dump_record.dart';
import 'records/event_record.dart';
import 'records/exception_record.dart';
import 'records/gate_record.dart';
import 'records/http_request_record.dart';
import 'records/log_record_entry.dart';
import 'records/query_record.dart';

/// Masks credentials in records before [CrumbsStore] buffers them.
///
/// The ring buffers are served verbatim to AI agents over `ext.crumbs.*`
/// and MCP, so a bearer header, a login body or a token in a callback URL
/// stored as captured leaks the credential into an agent transcript. The
/// model mirrors Laravel Telescope: three name lists (request headers,
/// request parameters, response parameters), matched case-insensitively,
/// extended through the `hide*` methods (additions merge with the defaults,
/// they never replace them), and every matching value replaced with [mask].
/// The request parameter list covers the request body, the query of the
/// request URL, and the structured fields of a query (`bindings`) and a gate
/// check (`arguments`).
///
/// The store only understands JSON and form-encoded bodies. An adapter that
/// holds a body as structured data (a Dart `Map` whose `toString()` is not
/// JSON) must run it through [redactParameters] before stringifying it.
final class CrumbsRedaction {
  CrumbsRedaction._();

  /// The value a hidden entry is replaced with; Laravel Telescope's mask.
  static const String mask = '********';

  /// The host's text redactor, or null while none is registered.
  ///
  /// When set, the store runs it over every text the log, event, exception
  /// and HTTP records carry (message, error, stack, URL, header values,
  /// bodies, and every String and map key inside an event payload's nested
  /// Maps and Lists) before the record enters its queue or its stream, and
  /// marks the record `redacted`. It runs as well over the message of a
  /// dump, the SQL of a query, and every String and map key inside the
  /// `bindings` of a query and the `arguments` of a gate check; those three
  /// records carry no `redacted` flag. It receives one String and returns the
  /// masked one; it must be pure and total, since a throw drops the record
  /// (neither buffered nor emitted) rather than let it through unmasked. A
  /// record buffered while this is null stays unredacted, and a consumer
  /// that persists records writes only the redacted ones.
  static String Function(String)? redactor;

  /// The records a [redactor] produced. Only this library adds to it, so no
  /// caller can build a record that claims to be redacted; the records'
  /// `redacted` getter reads it through [isRedacted].
  static final Expando<bool> _redactedRecords = Expando<bool>('redacted');

  /// Whether [record] is a copy a registered [redactor] produced here.
  @internal
  static bool isRedacted(Object record) => _redactedRecords[record] ?? false;

  /// Lowercased request header names whose values are masked.
  static Set<String> get hiddenRequestHeaders =>
      Set<String>.unmodifiable(lists.hiddenRequestHeaders);

  /// Lowercased request body keys whose values are masked.
  static Set<String> get hiddenRequestParameters =>
      Set<String>.unmodifiable(lists.hiddenRequestParameters);

  /// Lowercased response body keys whose values are masked.
  static Set<String> get hiddenResponseParameters =>
      Set<String>.unmodifiable(lists.hiddenResponseParameters);

  /// Hide the given request headers in addition to the defaults.
  static void hideRequestHeaders(Iterable<String> names) =>
      lists.hiddenRequestHeaders.addAll(names.map(_normalize));

  /// Hide the given request body keys in addition to the defaults.
  static void hideRequestParameters(Iterable<String> names) =>
      lists.hiddenRequestParameters.addAll(names.map(_normalize));

  /// Hide the given response body keys in addition to the defaults.
  static void hideResponseParameters(Iterable<String> names) =>
      lists.hiddenResponseParameters.addAll(names.map(_normalize));

  /// Return a copy of [data] with the value under every key in [keys]
  /// replaced by [mask], at any depth of nested Maps and Lists.
  ///
  /// Keys match case-insensitively. A matching key masks its whole value,
  /// structured or not. An empty value (null, false, an empty string or
  /// collection) stays visible: it is not a secret, and seeing it explains a
  /// validation failure. A subtree nested past 64 levels is masked whole.
  /// [data] is never mutated; a scalar comes back as is.
  static Object? redactParameters(Object? data, Set<String> keys) =>
      _redact(data, keys.map(_normalize).toSet());

  /// Return [record] with its hidden request headers masked and the hidden
  /// keys of a JSON or form-encoded request or response body masked, then,
  /// when a [redactor] is registered, every text field run through it.
  ///
  /// Any other body is kept as is, and so is a body with nothing to hide
  /// (byte for byte, so its formatting survives). Returns [record] itself
  /// when nothing was masked and no [redactor] is registered. Never throws on
  /// a malformed body. Returns null, the record dropped, when the [redactor]
  /// throws.
  static HttpRequestRecord? redactHttpRecord(HttpRequestRecord record) {
    final HttpRequestRecord keyed = _redactHttpKeys(record);
    final String Function(String)? redact = _guardedRedactor();
    if (redact == null) return keyed;

    return _dropOnRedactorFailure(
      () => _markRedacted(
        HttpRequestRecord(
          url: redact(keyed.url),
          method: redact(keyed.method),
          statusCode: keyed.statusCode,
          durationMs: keyed.durationMs,
          isError: keyed.isError,
          timestamp: keyed.timestamp,
          requestHeaders: keyed.requestHeaders?.map(
            (String name, String value) =>
                MapEntry<String, String>(name, redact(value)),
          ),
          requestBody: _text(keyed.requestBody, redact),
          responseBody: _text(keyed.responseBody, redact),
          attributedHeuristically: keyed.attributedHeuristically,
          requestId: _text(keyed.requestId, redact),
          startUs: keyed.startUs,
          endUs: keyed.endUs,
          atUs: keyed.atUs,
          interactionId: _text(keyed.interactionId, redact),
          linkedBy: _text(keyed.linkedBy, redact),
        ),
      ),
    );
  }

  /// Return [record] with every text field run through the [redactor] and
  /// `redacted` set, or [record] itself when none is registered. Returns
  /// null, the record dropped, when the [redactor] throws.
  static LogRecordEntry? redactLogRecord(LogRecordEntry record) {
    final String Function(String)? redact = _guardedRedactor();
    if (redact == null) return record;

    return _dropOnRedactorFailure(
      () => _markRedacted(
        LogRecordEntry(
          level: redact(record.level),
          levelValue: record.levelValue,
          message: redact(record.message),
          loggerName: redact(record.loggerName),
          time: record.time,
          error: _text(record.error, redact),
          stackTrace: _text(record.stackTrace, redact),
          atUs: record.atUs,
        ),
      ),
    );
  }

  /// Return [record] with every text field run through the [redactor] and
  /// `redacted` set, or [record] itself when none is registered. Returns
  /// null, the record dropped, when the [redactor] throws.
  static ExceptionRecord? redactExceptionRecord(ExceptionRecord record) {
    final String Function(String)? redact = _guardedRedactor();
    if (redact == null) return record;

    return _dropOnRedactorFailure(
      () => _markRedacted(
        ExceptionRecord(
          exceptionType: redact(record.exceptionType),
          message: redact(record.message),
          time: record.time,
          stackTrace: _text(record.stackTrace, redact),
          isolate: _text(record.isolate, redact),
        ),
      ),
    );
  }

  /// Return [record] with a JSON-safe payload, and with every text field run
  /// through the [redactor] and `redacted` set when one is registered.
  ///
  /// The payload is walked at any depth of Maps and Lists, and the redactor
  /// runs over every map key as well as every String value. A value
  /// `jsonEncode` cannot write (a `DateTime`, a `Duration`, any object) is
  /// stored as its `toString()` and a non-String map key as its
  /// `toString()`, so one bad payload cannot fail a whole events response.
  /// A subtree nested past 64 levels is masked whole. Returns [record]
  /// itself when there is nothing to change, and null, the record dropped,
  /// when the [redactor] throws.
  static EventRecord? redactEventRecord(EventRecord record) {
    final String Function(String)? redact = _guardedRedactor();

    return _dropOnRedactorFailure(() {
      final Map<String, dynamic> payload =
          _scrub(record.payload, redact) as Map<String, dynamic>;
      if (redact == null && identical(payload, record.payload)) return record;

      final EventRecord scrubbed = EventRecord(
        eventType: _text(record.eventType, redact)!,
        payload: payload,
        time: record.time,
        listenerCount: record.listenerCount,
        atUs: record.atUs,
        interactionId: _text(record.interactionId, redact),
        linkedBy: _text(record.linkedBy, redact),
      );
      // Without a redactor only the JSON-safe pass ran; a copy of a record a
      // redactor already produced stays as redacted as its source.
      return redact != null || record.redacted
          ? _markRedacted(scrubbed)
          : scrubbed;
    });
  }

  /// Return [record] with its `bindings` masked and made JSON-safe (see
  /// [_structured]), and with the SQL run through the [redactor] when one is
  /// registered. Returns [record] itself when there is nothing to change,
  /// and null, the record dropped, when the [redactor] throws.
  static QueryRecord? redactQueryRecord(QueryRecord record) {
    final String Function(String)? redact = _guardedRedactor();

    return _dropOnRedactorFailure(() {
      final List<Object?> bindings = _structured(record.bindings, redact);
      if (redact == null && identical(bindings, record.bindings)) return record;

      return QueryRecord(
        sql: _text(record.sql, redact)!,
        bindings: bindings,
        timeMs: record.timeMs,
        time: record.time,
        connectionName: record.connectionName,
        atUs: record.atUs,
        interactionId: record.interactionId,
        linkedBy: record.linkedBy,
      );
    });
  }

  /// Return [record] with its `arguments` masked and made JSON-safe (see
  /// [_structured]). Returns [record] itself when there is nothing to
  /// change, and null, the record dropped, when the [redactor] throws.
  static GateRecord? redactGateRecord(GateRecord record) {
    final String Function(String)? redact = _guardedRedactor();

    return _dropOnRedactorFailure(() {
      final List<Object?> arguments = _structured(record.arguments, redact);
      if (identical(arguments, record.arguments)) return record;

      return GateRecord(
        ability: record.ability,
        result: record.result,
        arguments: arguments,
        time: record.time,
        userId: record.userId,
      );
    });
  }

  /// Return [record] with its message run through the [redactor], or
  /// [record] itself when none is registered. A dump is free text with no
  /// keys to match, so nothing else masks it. Returns null, the record
  /// dropped, when the [redactor] throws.
  static DumpRecord? redactDumpRecord(DumpRecord record) {
    final String Function(String)? redact = _guardedRedactor();
    if (redact == null) return record;

    return _dropOnRedactorFailure(
      () => DumpRecord(
        message: redact(record.message),
        time: record.time,
        wrapWidth: record.wrapWidth,
      ),
    );
  }

  /// [values] with the value under every hidden request parameter key masked
  /// at any depth, then made JSON-safe and run through [redact] by [_scrub],
  /// so one `DateTime` cannot fail a whole read; [values] itself when
  /// nothing changed.
  static List<Object?> _structured(
    List<Object?> values,
    String Function(String)? redact,
  ) {
    final Set<String> hidden = lists.hiddenRequestParameters;
    final Object? keyed = _mentions(values, hidden)
        ? _redact(values, hidden)
        : values;

    return _scrub(keyed, redact) as List<Object?>;
  }

  /// The registered [redactor], wrapped so a throw inside it surfaces as a
  /// [_RedactorFailure] and nothing else does; null when none is registered.
  static String Function(String)? _guardedRedactor() {
    final String Function(String)? redact = redactor;
    if (redact == null) return null;

    return (String text) {
      try {
        return redact(text);
      } on Object {
        throw const _RedactorFailure();
      }
    };
  }

  /// Build a record with [build], or drop it (null) when the redactor threw
  /// inside it: a record that could not be masked is never buffered.
  static T? _dropOnRedactorFailure<T extends Object>(T Function() build) {
    try {
      return build();
    } on _RedactorFailure {
      return null;
    }
  }

  static T _markRedacted<T extends Object>(T record) {
    _redactedRecords[record] = true;
    return record;
  }

  static String? _text(String? text, String Function(String)? redact) =>
      text == null || redact == null ? text : redact(text);

  /// A String or a map key is run through [redactor] when one is given; a
  /// scalar stays;
  /// a Map or List is rebuilt only when something inside it changed, so an
  /// already-safe payload keeps its identity; anything else becomes its
  /// `toString()`.
  static Object? _scrub(
    Object? value,
    String Function(String)? redact, [
    int depth = 0,
  ]) {
    if (value == null || value is bool || value is num) return value;
    if (depth >= _maxDepth) return mask;
    if (value is String) return _text(value, redact);

    if (value is Map) {
      bool changed = value is! Map<String, dynamic>;
      final Map<String, dynamic> scrubbed = <String, dynamic>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final String key = _text('${entry.key}', redact)!;
        final Object? item = _scrub(entry.value, redact, depth + 1);
        changed = changed || key != entry.key || !identical(item, entry.value);
        scrubbed[key] = item;
      }
      return changed ? scrubbed : value;
    }

    if (value is List) {
      bool changed = false;
      final List<Object?> scrubbed = <Object?>[];
      for (final Object? element in value) {
        final Object? item = _scrub(element, redact, depth + 1);
        changed = changed || !identical(item, element);
        scrubbed.add(item);
      }
      return changed ? scrubbed : value;
    }

    return _text(value.toString(), redact);
  }

  static HttpRequestRecord _redactHttpKeys(HttpRequestRecord record) {
    final String url = _redactUrl(record.url, lists.hiddenRequestParameters);
    final Map<String, String>? headers = _redactHeaders(record.requestHeaders);
    final String? requestBody = redactBody(
      record.requestBody,
      lists.hiddenRequestParameters,
    );
    final String? responseBody = redactBody(
      record.responseBody,
      lists.hiddenResponseParameters,
    );

    if (identical(url, record.url) &&
        identical(headers, record.requestHeaders) &&
        identical(requestBody, record.requestBody) &&
        identical(responseBody, record.responseBody)) {
      return record;
    }

    return record.copyWith(
      url: url,
      requestHeaders: headers,
      requestBody: requestBody,
      responseBody: responseBody,
    );
  }

  /// [url] with the value of every query parameter named in [hidden]
  /// masked. The scheme, host, path, fragment and every other pair stay
  /// byte for byte, and a URL [Uri.tryParse] refuses is kept as is.
  static String _redactUrl(String url, Set<String> hidden) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasQuery) return url;

    // Uri only locates the query: cutting it from the raw text keeps the
    // rest exactly as captured, where Uri would normalise its escapes. No
    // component before the query may hold a `?`, so the first one starts it.
    final int start = url.indexOf('?') + 1;
    final int hash = url.indexOf('#', start);
    final int end = hash < 0 ? url.length : hash;
    final String query = url.substring(start, end);
    final String masked = _maskPairs(query, hidden);
    if (identical(masked, query)) return url;

    return '${url.substring(0, start)}$masked${url.substring(end)}';
  }

  /// Restore the three lists to their defaults and unregister the [redactor].
  @visibleForTesting
  static void resetForTesting() {
    lists.resetRedactionLists();
    redactor = null;
  }

  static String _normalize(String name) => name.toLowerCase();

  // Real API payloads nest a handful of levels. The walk recurses and so
  // does `jsonEncode`, and a pathological body thousands of levels deep
  // would overflow the stack inside `recordHttp`; past this depth a subtree
  // is masked whole instead, which is also what keeps a credential down
  // there out of the buffer.
  static const int _maxDepth = 64;

  /// [keys] must already be normalized. An empty value (null, false, an
  /// empty string or collection) is not a secret and stays visible, the
  /// truthiness rule Laravel's `hideParameters` applies.
  static bool _hides(Object? key, Object? value, Set<String> keys) =>
      key is String && keys.contains(_normalize(key)) && !_isEmpty(value);

  static bool _isEmpty(Object? value) =>
      value == null ||
      value == false ||
      value == '' ||
      (value is Map && value.isEmpty) ||
      (value is List && value.isEmpty);

  static Object? _redact(Object? data, Set<String> keys, [int depth = 0]) {
    if (data is! Map && data is! List) return data;
    if (depth >= _maxDepth) return mask;

    if (data is Map) {
      return data.map(
        (Object? key, Object? value) => MapEntry<Object?, Object?>(
          key,
          _hides(key, value, keys) ? mask : _redact(value, keys, depth + 1),
        ),
      );
    }

    return (data as List)
        .map((Object? item) => _redact(item, keys, depth + 1))
        .toList();
  }

  static bool _mentions(Object? data, Set<String> keys, [int depth = 0]) {
    if (data is! Map && data is! List) return false;
    if (depth >= _maxDepth) return true;

    if (data is Map) {
      return data.entries.any(
        (MapEntry<Object?, Object?> entry) =>
            _hides(entry.key, entry.value, keys) ||
            _mentions(entry.value, keys, depth + 1),
      );
    }

    return (data as List).any(
      (Object? item) => _mentions(item, keys, depth + 1),
    );
  }

  /// A whole `application/x-www-form-urlencoded` body: pairs joined by `&`,
  /// no whitespace, and every percent escape well formed, so decoding a key
  /// cannot throw.
  static final RegExp _formBody = RegExp(
    r'^(?:[^\s=&%]|%[0-9A-Fa-f]{2})+=(?:[^\s&%]|%[0-9A-Fa-f]{2})*'
    r'(?:&(?:[^\s=&%]|%[0-9A-Fa-f]{2})+=(?:[^\s&%]|%[0-9A-Fa-f]{2})*)*$',
  );

  static String _redactForm(String body, Set<String> hidden) =>
      _formBody.hasMatch(body) ? _maskPairs(body, hidden) : body;

  /// Every percent escape well formed, so decoding cannot throw.
  static final RegExp _wellFormedEscapes = RegExp(
    r'^(?:[^%]|%[0-9A-Fa-f]{2})*$',
  );

  /// [pairs] (`key=value` joined by `&`, a form body or a URL query) with
  /// the value of every pair whose key is in [hidden] masked, or [pairs]
  /// itself when nothing was. A key without `=` has no value to hide, and a
  /// key whose escapes do not decode cannot name a hidden parameter; both
  /// stay as they were.
  static String _maskPairs(String pairs, Set<String> hidden) {
    bool masked = false;
    final String redacted = pairs
        .split('&')
        .map((String pair) {
          final int equals = pair.indexOf('=');
          if (equals < 0) return pair;
          final String rawKey = pair.substring(0, equals);
          if (!_wellFormedEscapes.hasMatch(rawKey)) return pair;
          // Latin-1 maps every byte, so a key that is not UTF-8 still decodes;
          // the default names are ASCII either way.
          final String key = _formLeaf(
            Uri.decodeQueryComponent(rawKey, encoding: latin1),
          );
          if (!_hides(key, pair.substring(equals + 1), hidden)) return pair;
          masked = true;
          return '${pair.substring(0, equals + 1)}$mask';
        })
        .join('&');

    return masked ? redacted : pairs;
  }

  /// The name a form key addresses, the leaf a nested JSON key would be:
  /// `user[password]` is `password`, and a list key `codes[]` is `codes`.
  static String _formLeaf(String key) {
    String name = key;
    while (name.endsWith('[]')) {
      name = name.substring(0, name.length - 2);
    }
    final int open = name.lastIndexOf('[');
    if (!name.endsWith(']') || open < 0) return name;
    return name.substring(open + 1, name.length - 1);
  }

  static Map<String, String>? _redactHeaders(Map<String, String>? headers) {
    if (headers == null ||
        !headers.entries.any(
          (MapEntry<String, String> header) =>
              _hides(header.key, header.value, lists.hiddenRequestHeaders),
        )) {
      return headers;
    }

    return headers.map(
      (String name, String value) => MapEntry<String, String>(
        name,
        _hides(name, value, lists.hiddenRequestHeaders) ? mask : value,
      ),
    );
  }

  /// Return [body] with the value under every key in [keys] masked, when
  /// it parses as a JSON object or array, or reads as a form-encoded body
  /// (`key=value&key=value`, an OAuth token call or a form login).
  ///
  /// Anything else (plain text, a truncated JSON snippet) and a body with
  /// nothing to hide come back as given, byte for byte, so the formatting
  /// survives; in a form body only the value of a matching pair changes.
  /// Never throws on a malformed body. Use it for a body an adapter holds as
  /// a string, before truncating it: a cut JSON body no longer parses, so
  /// the store could not mask it afterwards.
  static String? redactBody(String? body, Set<String> keys) {
    if (body == null || body.isEmpty) return body;
    final Set<String> hidden = keys.map(_normalize).toSet();

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      // Not JSON: a form body is masked pair by pair, and anything else
      // (plain text, a truncated payload) has no keys to find.
      return _redactForm(body, hidden);
    }

    if (!_mentions(decoded, hidden)) return body;

    return jsonEncode(_redact(decoded, hidden));
  }
}

/// A throw from [CrumbsRedaction.redactor], told apart from any other
/// error so only a redactor failure drops a record.
final class _RedactorFailure {
  const _RedactorFailure();
}
