import 'dart:convert';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crumbs/src/crumbs_dowel_provider.dart';

void main() {
  group('CrumbsDowelProvider.mcpTools()', () {
    late List<McpToolDescriptor> tools;

    setUp(() {
      tools = CrumbsDowelProvider().mcpTools();
    });

    // -------------------------------------------------------------------------
    // Length
    // -------------------------------------------------------------------------

    test('returns exactly 10 descriptors', () {
      expect(tools, hasLength(10));
    });

    // -------------------------------------------------------------------------
    // Names
    // -------------------------------------------------------------------------

    test('contains all 10 expected tool names', () {
      final names = tools.map((t) => t.name).toList();
      expect(
        names,
        containsAll(<String>[
          'crumbs_tail',
          'crumbs_requests',
          'crumbs_clear',
          'crumbs_exceptions',
          'crumbs_events',
          'crumbs_gates',
          'crumbs_dumps',
          'crumbs_queries',
          'crumbs_caches',
          'crumbs_frames',
        ]),
      );
    });

    // -------------------------------------------------------------------------
    // Extension methods
    // -------------------------------------------------------------------------

    test('each descriptor maps to the correct ext.crumbs.* extension method',
        () {
      final byName = {for (final t in tools) t.name: t.extensionMethod};

      expect(byName['crumbs_tail'], equals('ext.crumbs.console'));
      expect(byName['crumbs_requests'], equals('ext.crumbs.requests'));
      expect(byName['crumbs_clear'], equals('ext.crumbs.clear'));
      expect(
          byName['crumbs_exceptions'], equals('ext.crumbs.exceptions'));
      expect(byName['crumbs_events'], equals('ext.crumbs.events'));
      expect(byName['crumbs_gates'], equals('ext.crumbs.gates'));
      expect(byName['crumbs_dumps'], equals('ext.crumbs.dumps'));
      expect(byName['crumbs_queries'], equals('ext.crumbs.queries'));
      expect(byName['crumbs_caches'], equals('ext.crumbs.caches'));
      expect(byName['crumbs_frames'], equals('ext.crumbs.frames'));
    });

    test('no two descriptors share an extensionMethod (no overlap, no gap)',
        () {
      final methods = tools.map((t) => t.extensionMethod).toList();
      expect(methods.toSet(), hasLength(tools.length));
    });

    // -------------------------------------------------------------------------
    // Input schemas : JSON round-trip
    // -------------------------------------------------------------------------

    test('every inputSchema survives a JSON encode/decode round-trip', () {
      for (final tool in tools) {
        expect(
          () => jsonDecode(jsonEncode(tool.inputSchema)),
          returnsNormally,
          reason: '${tool.name}.inputSchema failed JSON round-trip',
        );
      }
    });

    // -------------------------------------------------------------------------
    // crumbs_exceptions : specific schema shape
    // -------------------------------------------------------------------------

    test('crumbs_exceptions declares a limit integer property', () {
      final exceptions = tools.firstWhere(
        (t) => t.name == 'crumbs_exceptions',
      );
      final properties =
          exceptions.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('limit'), isTrue);
      final limit = properties['limit'] as Map<String, dynamic>;
      expect(limit['type'], equals('integer'));
    });

    test('crumbs_exceptions does not declare required params', () {
      final exceptions = tools.firstWhere(
        (t) => t.name == 'crumbs_exceptions',
      );
      expect(exceptions.inputSchema.containsKey('required'), isFalse);
    });

    // -------------------------------------------------------------------------
    // crumbs_clear : empty properties
    // -------------------------------------------------------------------------

    test('crumbs_clear has an empty properties map', () {
      final clear = tools.firstWhere((t) => t.name == 'crumbs_clear');
      final properties =
          clear.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties, isEmpty);
    });

    // -------------------------------------------------------------------------
    // crumbs_events : specific schema shape
    // -------------------------------------------------------------------------

    test('crumbs_events declares a limit integer property', () {
      final events = tools.firstWhere((t) => t.name == 'crumbs_events');
      final properties =
          events.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('limit'), isTrue);
      final limit = properties['limit'] as Map<String, dynamic>;
      expect(limit['type'], equals('integer'));
    });

    test('crumbs_events does not declare required params', () {
      final events = tools.firstWhere((t) => t.name == 'crumbs_events');
      expect(events.inputSchema.containsKey('required'), isFalse);
    });

    test('crumbs_events description contains "Usage:"', () {
      final events = tools.firstWhere((t) => t.name == 'crumbs_events');
      expect(events.description, contains('Usage:'));
    });

    // -------------------------------------------------------------------------
    // crumbs_gates : specific schema shape
    // -------------------------------------------------------------------------

    test('crumbs_gates declares a limit integer property', () {
      final gates = tools.firstWhere((t) => t.name == 'crumbs_gates');
      final properties =
          gates.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('limit'), isTrue);
      final limit = properties['limit'] as Map<String, dynamic>;
      expect(limit['type'], equals('integer'));
    });

    test('crumbs_gates does not declare required params', () {
      final gates = tools.firstWhere((t) => t.name == 'crumbs_gates');
      expect(gates.inputSchema.containsKey('required'), isFalse);
    });

    test('crumbs_gates description contains "Usage:"', () {
      final gates = tools.firstWhere((t) => t.name == 'crumbs_gates');
      expect(gates.description, contains('Usage:'));
    });

    // -------------------------------------------------------------------------
    // crumbs_dumps : specific schema shape
    // -------------------------------------------------------------------------

    test('crumbs_dumps declares a limit integer property', () {
      final dumps = tools.firstWhere((t) => t.name == 'crumbs_dumps');
      final properties =
          dumps.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('limit'), isTrue);
      final limit = properties['limit'] as Map<String, dynamic>;
      expect(limit['type'], equals('integer'));
    });

    test('crumbs_dumps does not declare required params', () {
      final dumps = tools.firstWhere((t) => t.name == 'crumbs_dumps');
      expect(dumps.inputSchema.containsKey('required'), isFalse);
    });

    test('crumbs_dumps description contains "Usage:"', () {
      final dumps = tools.firstWhere((t) => t.name == 'crumbs_dumps');
      expect(dumps.description, contains('Usage:'));
    });

    // -------------------------------------------------------------------------
    // crumbs_frames : specific schema shape
    // -------------------------------------------------------------------------

    test('crumbs_frames declares a limit integer property', () {
      final frames = tools.firstWhere((t) => t.name == 'crumbs_frames');
      final properties =
          frames.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('limit'), isTrue);
      final limit = properties['limit'] as Map<String, dynamic>;
      expect(limit['type'], equals('integer'));
    });

    test('crumbs_frames does not declare required params', () {
      final frames = tools.firstWhere((t) => t.name == 'crumbs_frames');
      expect(frames.inputSchema.containsKey('required'), isFalse);
    });

    test('crumbs_frames description contains "Usage:"', () {
      final frames = tools.firstWhere((t) => t.name == 'crumbs_frames');
      expect(frames.description, contains('Usage:'));
    });
  });

  group('CrumbsDowelProvider.commands()', () {
    test('registers every crumbs CLI command, in order', () {
      final names =
          CrumbsDowelProvider().commands().map((c) => c.name).toList();

      expect(
        names,
        equals(<String>[
          'crumbs:install',
          'crumbs:tail',
          'crumbs:requests',
          'crumbs:queries',
          'crumbs:caches',
          'crumbs:events',
          'crumbs:gates',
          'crumbs:dumps',
          'crumbs:frames',
          'crumbs:clear',
          'crumbs:files',
        ]),
      );
    });
  });
}
