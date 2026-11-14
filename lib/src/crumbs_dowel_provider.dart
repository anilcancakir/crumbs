import 'package:dowel/dowel.dart';

import 'commands/crumbs_caches_command.dart';
import 'commands/crumbs_clear_command.dart';
import 'commands/crumbs_dumps_command.dart';
import 'commands/crumbs_events_command.dart';
import 'commands/crumbs_files_command.dart';
import 'commands/crumbs_frames_command.dart';
import 'commands/crumbs_gates_command.dart';
import 'commands/crumbs_install_command.dart';
import 'commands/crumbs_queries_command.dart';
import 'commands/crumbs_requests_command.dart';
import 'commands/crumbs_tail_command.dart';

/// Contributes crumbs:* commands and MCP tool descriptors to the dowel
/// dispatcher.
///
/// The commands (crumbs:install, crumbs:tail, crumbs:requests,
/// crumbs:queries, crumbs:caches, crumbs:events, crumbs:gates,
/// crumbs:dumps, crumbs:frames, crumbs:clear, crumbs:files) and the MCP tools
/// are backed by ext.crumbs.* VM Service extensions registered by
/// [registerAllCrumbsExtensions]. The pause, resume and timeline file
/// extensions have no MCP tool on purpose; the timeline files are read
/// through crumbs:files.
class CrumbsDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'crumbs';

  @override
  List<DowelCommand> commands() => <DowelCommand>[
    CrumbsInstallCommand(),
    CrumbsTailCommand(),
    CrumbsRequestsCommand(),
    CrumbsQueriesCommand(),
    CrumbsCachesCommand(),
    CrumbsEventsCommand(),
    CrumbsGatesCommand(),
    CrumbsDumpsCommand(),
    CrumbsFramesCommand(),
    CrumbsClearCommand(),
    CrumbsFilesCommand(),
  ];

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
    McpToolDescriptor(
      name: 'crumbs_tail',
      description:
          'Return recent log records from the running Flutter '
          'app.\n'
          '\n'
          'Reads the Crumbs log ring buffer (populated by every '
          '`package:logging` Logger call in the app) and returns the '
          'most recent entries. Each record carries timestamp, level, '
          'logger name, message, and any attached error / stackTrace. '
          'Use this to inspect what the app logged without scraping '
          'flutter run stdout via dowel_logs.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer; cap is ring-buffer '
          'size).\n'
          '- Pass `level: "<name>"` (e.g. `"WARNING"`, `"SEVERE"`) to '
          'filter by minimum log level; omit for all levels.\n'
          '- Pass `logger: "<name>"` to keep one logger\'s records.\n'
          '- Pass the returned `cursor` back as `since` to read only newer '
          'records; with `since`, `limit` keeps the oldest N after it.\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before a '
          'repro to isolate just the relevant logs.\n'
          '- For HTTP traffic use crumbs_requests; for crashes use '
          'crumbs_exceptions; this tool covers general logs only.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'level': {
            'type': 'string',
            'description':
                'Minimum log level to include. Common '
                'values: `FINE`, `INFO`, `WARNING`, `SEVERE`, '
                '`SHOUT`. Omit for all levels.',
          },
          'logger': {
            'type': 'string',
            'description':
                'Exact logger name to include. Omit for every logger.',
          },
          'since': {
            'type': 'integer',
            'description':
                'Microseconds, exclusive, compared with each record\'s '
                '`atUs`: pass the `cursor` of the previous answer to read '
                'only newer records. A value that is not an integer is '
                'refused.',
          },
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.console',
    ),
    McpToolDescriptor(
      name: 'crumbs_requests',
      description:
          'Return recent HTTP request records from the '
          'running Flutter app.\n'
          '\n'
          'Reads the Crumbs HTTP ring buffer (populated by an HTTP '
          'adapter, or by the app\'s own interceptor calling '
          '`CrumbsStore.recordHttp`). Each record carries method, url, status code, '
          'duration, request headers, response body snippet, and '
          'error if the call failed. Use this to debug API issues '
          'without instrumenting the app or watching network panels '
          'in DevTools.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap the response size; default '
          'returns the whole buffer.\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear to '
          'isolate traffic from a specific user action.\n'
          '- Only HTTP calls that go through an installed Crumbs '
          'adapter are recorded; raw `dart:io HttpClient` calls are '
          'invisible to this tool.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of HTTP records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer.',
          },
        },
      },
      extensionMethod: 'ext.crumbs.requests',
    ),
    McpToolDescriptor(
      name: 'crumbs_clear',
      description:
          'Clear every Crumbs ring buffer in one call.\n'
          '\n'
          'Wipes all 10 ring buffers atomically (http, logs, '
          'exceptions, events, gates, dumps, queries, caches, '
          'models, frame perf) so the next crumbs_* read returns only '
          'records '
          'produced AFTER this clear. Useful as a "set zero" before '
          'reproducing a bug or capturing the output of a specific '
          'user action. Returns `{"cleared": true}` on success.\n'
          '\n'
          'Usage:\n'
          '- No parameters; clears all 10 buffers in a single atomic '
          'pass.\n'
          '- Idempotent: safe to call when buffers are already empty.\n'
          '- Does NOT affect the live `package:logging` stream or any '
          'upstream sink (Sentry, Bugsnag); only the captured ring '
          'buffers in the running app are wiped.',
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
      extensionMethod: 'ext.crumbs.clear',
    ),
    McpToolDescriptor(
      name: 'crumbs_exceptions',
      description:
          'Return recent uncaught exception records from the '
          'running Flutter app.\n'
          '\n'
          'Reads the Crumbs exception ring buffer (populated by '
          'the `FlutterError.onError` and `PlatformDispatcher.onError` '
          'hooks of the ExceptionWatcher). Each record carries timestamp, exception type, '
          'message, library, and full stackTrace. Use this when a '
          'crash or `Exception` was thrown and you need the stack '
          'without scraping flutter run stdout.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer).\n'
          '- Returned oldest-first (last entry is newest).\n'
          '- Covers uncaught exceptions only; expected `try / catch` '
          'flows do not surface here. Pair with crumbs_tail to '
          'see what the app logged around the crash.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of exception records to '
                'return (oldest-first; last entry is newest). Omit for the whole buffer.',
          },
        },
      },
      extensionMethod: 'ext.crumbs.exceptions',
    ),
    McpToolDescriptor(
      name: 'crumbs_events',
      description:
          'Return recent in-app event records from the running '
          'Flutter app.\n'
          '\n'
          'Reads the Crumbs events ring buffer (populated by the '
          'MagicEventWatcher whenever `Event.dispatch()` is called). '
          'Each record carries timestamp, event class name, and a JSON '
          'snapshot of the event payload. Use this to trace event-driven '
          'side effects (cache invalidation, broadcast echoes, model '
          'lifecycle transitions) without adding debug print statements '
          'to the codebase.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer; cap is ring-buffer '
          'size).\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before a '
          'repro to isolate just the relevant event sequence.\n'
          '- Pass `type: "<prefix>"` to keep the events whose type starts '
          'with it.\n'
          '- Pass the returned `cursor` back as `since` to read only newer '
          'records; with `since`, `limit` keeps the oldest N after it.\n'
          '- Only events a host records into the store are returned '
          "(magic_devtools records Magic's events); raw "
          '`ChangeNotifier.notifyListeners` calls are invisible to this '
          'tool.\n'
          '- For HTTP traffic use crumbs_requests; for gate '
          'checks use crumbs_gates.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of event records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
          'type': {
            'type': 'string',
            'description':
                'Prefix of the event type to include. Omit for every '
                'event.',
          },
          'since': {
            'type': 'integer',
            'description':
                'Microseconds, exclusive, compared with each record\'s '
                '`atUs`: pass the `cursor` of the previous answer to read '
                'only newer records. A value that is not an integer is '
                'refused.',
          },
        },
      },
      extensionMethod: 'ext.crumbs.events',
    ),
    McpToolDescriptor(
      name: 'crumbs_gates',
      description:
          'Return recent Gate authorization check records from '
          'the running Flutter app.\n'
          '\n'
          'Reads the Crumbs gates ring buffer (populated by the '
          'MagicGateWatcher on every `Gate.allows / Gate.denies` call). '
          'Each record carries timestamp, ability name, result (allowed '
          'or denied), authenticated user id, and the argument class '
          'name if one was provided. Use this to debug authorization '
          'issues (why a button is hidden, why a route is blocked) '
          'without modifying policy classes.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer).\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before '
          'walking a guarded flow to isolate just the relevant checks.\n'
          '- Only checks a host records into the store are returned '
          "(magic_devtools records checks through Magic's `Gate` "
          'facade); direct policy class calls are not captured.\n'
          '- For event side effects use crumbs_events; for HTTP '
          'traffic use crumbs_requests.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of gate check records to '
                'return (oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.gates',
    ),
    McpToolDescriptor(
      name: 'crumbs_dumps',
      description:
          'Return recent debug dump records from the running '
          'Flutter app.\n'
          '\n'
          'Reads the Crumbs dumps ring buffer (populated by the '
          'DumpWatcher which overrides `debugPrint` globally). Each '
          'record carries timestamp and the full message string that '
          'was passed to `debugPrint` (a plain `print()` is not '
          'captured). Use this to read `debugPrint()` output from within '
          'the running app without scraping flutter run stdout.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer).\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before '
          'a repro to isolate just the relevant print output.\n'
          '- Only output routed through `debugPrint` (the global '
          'override point) is captured; `dart:io stdout.write` calls '
          'are invisible to this tool.\n'
          '- For structured logs use crumbs_tail; for crashes use '
          'crumbs_exceptions.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of dump records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.dumps',
    ),
    McpToolDescriptor(
      name: 'crumbs_queries',
      description:
          'Return recent database query records from the '
          'running Flutter app.\n'
          '\n'
          'Reads the Crumbs queries ring buffer (populated by the '
          'MagicQueryWatcher subscribed to magic\'s `QueryExecuted` '
          'event). Each record carries timestamp, SQL string, bindings '
          'list, execution time (ms), and connection name. Use this to '
          'inspect what queries the QueryBuilder dispatched without '
          'attaching a separate SQL profiler.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer).\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before '
          'a repro to isolate the queries from a specific user action.\n'
          '- Only queries that go through magic\'s QueryBuilder (and '
          'dispatch `QueryExecuted` via EventDispatcher) are recorded; '
          'raw SQL on a direct sqlite3/dio client bypasses this tool.\n'
          '- For Magic Cache traffic use crumbs_caches; for HTTP '
          'use crumbs_requests; for app log lines use crumbs_tail.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of query records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.queries',
    ),
    McpToolDescriptor(
      name: 'crumbs_caches',
      description:
          'Return recent Magic Cache operation records from '
          'the running Flutter app.\n'
          '\n'
          'Reads the Crumbs caches ring buffer (populated by the '
          'MagicCacheWatcher subscribed to magic\'s CacheHit / CacheMiss '
          '/ CachePut / CacheForget / CacheFlush events). Each record '
          'carries timestamp, operation tag (`hit | miss | put | forget '
          '| flush`), cache key, and optional TTL. Use this to inspect '
          'cache traffic without instrumenting the consumer code.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer).\n'
          '- Returned oldest-first (last entry is newest); pair with crumbs_clear before '
          'a repro to isolate the cache traffic of a specific action.\n'
          '- Only cache operations a host records into the store are '
          "returned (magic_devtools records Magic's `Cache` facade "
          'calls); raw driver-level cache calls bypass this tool.\n'
          '- For DB queries use crumbs_queries; for HTTP use '
          'crumbs_requests.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of cache records to return '
                '(oldest-first; last entry is newest). Omit for the whole buffer (cap '
                'enforced by the ring-buffer size, typically 500).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.caches',
    ),
    McpToolDescriptor(
      name: 'crumbs_frames',
      description:
          'Return recent per-frame performance records from the '
          'running Flutter app.\n'
          '\n'
          'Reads the Crumbs frame-perf ring buffer (populated by '
          'FramePerfWatcher, which joins SchedulerBinding frame timings '
          'with a per-frame FlutterTimeline block-attribution drain). '
          'Each record carries frame number, build/raster/vsync-overhead '
          '/total-span durations in microseconds, a timestamp, and a '
          '`blocks` map of named spans to their aggregated duration and '
          'call count. The response also carries a `livenessCounter`: a '
          'monotonic count of frames actually drawn, present even when '
          'the record list is empty, so a caller can tell a quiet app '
          'from a stalled engine. Use this to attribute jank to a '
          'specific widget or layout phase after driving an interaction.\n'
          '\n'
          'Usage:\n'
          '- Pass `limit: <n>` to cap how many records come back '
          '(default returns the whole buffer; the frame-perf buffer '
          'holds about a minute of frames at 60fps).\n'
          '- Returned oldest-first (last entry is newest); pair with '
          'crumbs_clear before a repro to isolate just the relevant '
          'frames.\n'
          '- FramePerfWatcher is opt-in and not auto-installed; an '
          'empty list with a non-advancing livenessCounter means it is '
          'not registered, not that the app is idle.\n'
          '- `blocks` is only populated while a measurement session has '
          'FlutterTimeline collection enabled; otherwise records carry '
          'frame magnitude with an empty `blocks` map.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of frame records to return '
                '(oldest-first; last entry is newest). Omit for the '
                'whole buffer (cap enforced by the frame-perf buffer '
                'size, default 3600).',
          },
        },
      },
      extensionMethod: 'ext.crumbs.frames',
    ),
  ];
}
