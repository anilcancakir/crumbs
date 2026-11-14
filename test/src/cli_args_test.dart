import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/cli_args.dart';

void main() {
  group('injectInvocationForMcpInstall()', () {
    test('returns args unchanged when first non-flag arg is not mcp:install',
        () {
      final result = injectInvocationForMcpInstall(
        ['list'],
        'crumbs',
      );
      expect(result, equals(['list']));
    });

    test('appends --invocation flag when first non-flag arg is mcp:install',
        () {
      final result = injectInvocationForMcpInstall(
        ['mcp:install'],
        'crumbs',
      );
      expect(
        result,
        equals(['mcp:install', '--invocation=crumbs']),
      );
    });

    test(
        'preserves user-supplied --invocation=foo equal-form without injecting',
        () {
      final result = injectInvocationForMcpInstall(
        ['mcp:install', '--invocation=foo'],
        'crumbs',
      );
      expect(result, equals(['mcp:install', '--invocation=foo']));
    });

    test(
        'preserves user-supplied --invocation whitespace-form without injecting',
        () {
      final result = injectInvocationForMcpInstall(
        ['mcp:install', '--invocation', 'foo'],
        'crumbs',
      );
      expect(result, equals(['mcp:install', '--invocation', 'foo']));
    });
  });
}
