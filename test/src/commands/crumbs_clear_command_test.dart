import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/commands/crumbs_clear_command.dart';

/// Stubs [DowelContext.callExtension] so tests never hit a real VM Service.
class _StubContext extends DowelContext {
  _StubContext({required DowelInput input, required DowelOutput output})
    : _response = const {},
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
  group('CrumbsClearCommand', () {
    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    test('name is crumbs:clear', () {
      expect(CrumbsClearCommand().name, equals('crumbs:clear'));
    });

    test('boot is CommandBoot.connected', () {
      expect(CrumbsClearCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(CrumbsClearCommand().description, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // ArgParser flags (none expected)
    // -------------------------------------------------------------------------

    test('configure registers no options', () {
      final parser = ArgParser();

      // CrumbsClearCommand does not override configure(); invoking it is a
      // no-op but must not throw.
      CrumbsClearCommand().configure(parser);

      expect(parser.options, isEmpty);
    });

    // -------------------------------------------------------------------------
    // Extension method forwarding
    // -------------------------------------------------------------------------

    test('handle calls ext.crumbs.clear', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);

      await CrumbsClearCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.crumbs.clear'));
    });

    test('handle passes no params to callExtension', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);

      await CrumbsClearCommand().handle(ctx);

      expect(ctx.lastParams, isNull);
    });

    // -------------------------------------------------------------------------
    // Output formatting
    // -------------------------------------------------------------------------

    test('handle writes a "cleared" confirmation line', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);

      final code = await CrumbsClearCommand().handle(ctx);

      expect(code, equals(0));
      expect(output.content.toLowerCase(), contains('cleared'));
    });

    test('handle returns 0', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {}), output: output);

      final code = await CrumbsClearCommand().handle(ctx);

      expect(code, equals(0));
    });
  });
}
