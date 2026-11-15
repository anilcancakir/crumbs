# MCP Tool Reference

Every `crumbs_*` MCP tool: what it reads, its input schema, its output shape and the `ext.crumbs.*` extension it calls in the running app.

Every tool dispatches through the VM Service, so the app must be running under dowel: start it with `./bin/dowel start` or the `dowel_start` tool, and `dowel_status` shows the recorded session.

- [Quick Reference](#quick-reference)
- [Common conventions](#common-conventions)
- [crumbs_tail](#crumbs_tail)
- [crumbs_requests](#crumbs_requests)
- [crumbs_exceptions](#crumbs_exceptions)
- [crumbs_events](#crumbs_events)
- [crumbs_gates](#crumbs_gates)
- [crumbs_dumps](#crumbs_dumps)
- [crumbs_queries](#crumbs_queries)
- [crumbs_caches](#crumbs_caches)
- [crumbs_frames](#crumbs_frames)
- [crumbs_clear](#crumbs_clear)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Tool | Reads | Parameters | Answer key |
|:-----|:------|:-----------|:-----------|
| `crumbs_tail` | `package:logging` records | `limit`, `level`, `logger`, `since` | `messages`, `cursor` |
| `crumbs_requests` | HTTP requests | `limit` | `requests` |
| `crumbs_exceptions` | Uncaught exceptions | `limit` | `exceptions` |
| `crumbs_events` | In-app events | `limit`, `type`, `since` | `events`, `cursor` |
| `crumbs_gates` | Gate checks | `limit` | `gates` |
| `crumbs_dumps` | `debugPrint` output | `limit` | `dumps` |
| `crumbs_queries` | DB queries | `limit` | `queries` |
| `crumbs_caches` | Cache operations | `limit` | `caches` |
| `crumbs_frames` | Per-frame performance | `limit` | `frames` |
| `crumbs_clear` | Empties every buffer | none | `cleared` |

<a name="common-conventions"></a>
## Common conventions

Every reading tool (all but `crumbs_clear`) follows these rules:

- **Oldest first.** Records come back in chronological order: the last entry is the newest.
- **`limit`.** Optional; keeps the newest N records. Omitted, the whole buffer comes back, up to its capacity (500 records by default, 3600 for frames; see [Buffers](../getting-started/buffers.md)). A zero or negative `limit` returns nothing.
- **Envelope.** Every tool answers a JSON object whose list sits under the answer key in the table above. An empty buffer, on a fresh start or after `crumbs_clear`, answers an empty list, not an error.
- **Redaction.** Credential-named keys are masked at insert whatever the host did: HTTP headers, bodies and URL query parameters, and the structured bindings of a query and arguments of a gate check. Free text (log, exception and dump messages, SQL, event payloads) is masked only when the host registered `CrumbsRedaction.redactor`; log, event, exception and HTTP records then carry `redacted: true`. Model and cache records are not masked. See [Redaction](../getting-started/redaction.md).
- **Errors.** When the app is not running or the VM Service cannot be reached, the tool result is an error with a plain-text message that says what to do.

<a name="crumbs_tail"></a>
## crumbs_tail

Return recent log records from the running Flutter app.

Reads the Crumbs log ring buffer populated by every `package:logging` `Logger` call in the app.
Use this to inspect what the app logged without scraping `flutter run` stdout via `dowel_logs`.

**VM Service extension:** `ext.crumbs.console`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |
| `level` | string | no | Minimum log level to include. Common values: `FINE`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`. Omit for all levels. A name that is not a level matches nothing. |
| `logger` | string | no | Exact logger name to include. Omit for every logger. |
| `since` | integer | no | Microseconds, exclusive, compared with each record's `atUs`: pass the `cursor` of the previous answer to read only newer records. A value that is not an integer is refused. |

With `since`, `limit` keeps the oldest N records after it; the answer's `cursor` is the value to pass
back. See [Cursor and filters](cursor-and-filters.md).

### Output Shape

```json
{
  "messages": [
    {
      "level": "WARNING",
      "levelValue": 900,
      "message": "Monitor check timed out after 30s",
      "loggerName": "MonitorController",
      "time": "2026-05-20T14:32:10.123",
      "atUs": 81234567,
      "redacted": false,
      "error": "TimeoutException: ...",
      "stackTrace": "#0 MonitorController.check ..."
    }
  ],
  "cursor": 81234567
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `level` | string | yes | Log level name (e.g. `INFO`, `WARNING`, `SEVERE`) |
| `levelValue` | integer | yes | Numeric level value from `package:logging` |
| `message` | string | yes | Log message string |
| `loggerName` | string | yes | Name of the `Logger` instance that emitted the record |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; join on `atUs` |
| `atUs` | integer | yes | Monotonic microseconds from `FlutterTimeline.now`, the same clock as event records |
| `redacted` | boolean | yes | True when `CrumbsRedaction.redactor` ran over the record before it was buffered |
| `error` | string | no | Error object stringified, when one was attached |
| `stackTrace` | string | no | Stack trace stringified, when one was attached |
| `cursor` | integer or null | yes (envelope) | Largest `atUs` returned, else the `since` given, else null |

### Example Invocations

```text
# Last 10 log lines at any level
crumbs_tail {"limit": 10}

# Last 20 entries at WARNING or above
crumbs_tail {"limit": 20, "level": "WARNING"}

# Every SEVERE entry in the buffer
crumbs_tail {"level": "SEVERE"}

# What one logger wrote after the cursor of the previous read
crumbs_tail {"logger": "Sync", "since": 81234567}
```

### Related Tools

- `crumbs_exceptions`: uncaught exceptions (not expected `try/catch` flows)
- `crumbs_requests`: HTTP traffic
- `crumbs_clear`: wipe the buffer before a repro

---

<a name="crumbs_requests"></a>
## crumbs_requests

Return recent HTTP request records from the running Flutter app.

Reads the HTTP buffer, filled by any `CrumbsHttpAdapter` the app registers (`MagicHttpFacadeAdapter`
from `magic_devtools` on a Magic app) or by an interceptor that calls `CrumbsStore.recordHttp`.
Use this to debug API issues without a proxy or the network panel of DevTools.

**VM Service extension:** `ext.crumbs.requests`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of HTTP records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer. |

### Output Shape

```json
{
  "requests": [
    {
      "url": "https://api.example.com/monitors",
      "method": "GET",
      "statusCode": 200,
      "durationMs": 142,
      "isError": false,
      "timestamp": "2026-05-20T14:32:11.456",
      "requestHeaders": {
        "Authorization": "********"
      },
      "responseBody": "{\"data\": []}",
      "atUs": 1234567,
      "redacted": false
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `url` | string | yes | Full request URL; the value of a credential-named query parameter reads `********` |
| `method` | string | yes | HTTP method (`GET`, `POST`, etc.) |
| `statusCode` | integer | yes | HTTP status code; 0 when the call failed before a response |
| `durationMs` | integer | yes | Round-trip time in milliseconds |
| `isError` | boolean | yes | True when the adapter classified the call as failed |
| `timestamp` | string | yes | ISO 8601 device-local wall clock of when the request was recorded, no offset; join on `atUs` |
| `requestHeaders` | object | no | Request headers as a `Map<String, String>`; credential headers read `********` (see Notes) |
| `requestBody` | string | no | Request body as a string, when present and readable; credential keys of a JSON body read `********` |
| `responseBody` | string | no | Response body snippet, when present; credential keys of a JSON body read `********` |
| `attributedHeuristically` | boolean | no | True when the adapter used best-effort FIFO attribution for concurrent requests |
| `requestId` | string | no | Adapter-assigned identifier pairing this response with its request exactly, when the adapter tracks one |
| `startUs` | integer | no | Monotonic microsecond timestamp (`FlutterTimeline.now` clock) when the request was sent, when tracked |
| `endUs` | integer | no | Monotonic microsecond timestamp (`FlutterTimeline.now` clock) when the response arrived, when tracked |
| `atUs` | integer | yes | Monotonic microsecond timestamp from `FlutterTimeline.now`, captured at record construction |
| `interactionId` | string | no | Correlates this record to others captured during the same logical interaction |
| `linkedBy` | string | no | How `interactionId` was derived: `zone` \| `frame` \| `window` |
| `redacted` | boolean | yes | True when `CrumbsRedaction.redactor` ran over the record before it was buffered |

### Example Invocations

```text
# Last 5 HTTP requests
crumbs_requests {"limit": 5}

# Every request in the buffer
crumbs_requests {}
```

### Notes

- Only HTTP calls that go through an installed Crumbs adapter are recorded. Raw
  `dart:io HttpClient` calls are invisible to this tool.
- Pair with `crumbs_clear` before a user action to isolate exactly the traffic that action
  produces.
- Credentials are masked before a record is buffered, the way Laravel Telescope does it: the
  value of a hidden header, a hidden JSON or form body key or a hidden URL query parameter reads `********`, which is crumbs's mask
  and not what the app sent. See [Credential redaction](../watchers/index.md#credential-redaction)
  for the default lists and how to extend them.

---

<a name="crumbs_exceptions"></a>
## crumbs_exceptions

Return recent uncaught exception records from the running Flutter app.

Reads the exception buffer, filled by `ExceptionWatcher` through `FlutterError.onError` and
`PlatformDispatcher.onError`. `CrumbsPlugin.install()` does not register it: `crumbs:install` does,
and a hand wiring calls `CrumbsPlugin.registerWatcher(ExceptionWatcher())`. Use this when a crash or
unhandled exception was thrown and you need the stack without scraping `flutter run` output.

**VM Service extension:** `ext.crumbs.exceptions`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of exception records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer. |

### Output Shape

```json
{
  "exceptions": [
    {
      "exceptionType": "StateError",
      "message": "Bad state: Stream has already been listened to",
      "time": "2026-05-20T14:33:00.789",
      "stackTrace": "#0 _StreamController._subscribe ...",
      "isolate": "main",
      "redacted": false
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `exceptionType` | string | yes | Runtime type name of the exception object |
| `message` | string | yes | Exception message string |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; this record has no `atUs` |
| `stackTrace` | string | no | Full stack trace, when available |
| `isolate` | string | no | Isolate name where the exception was caught |
| `redacted` | boolean | yes | True when `CrumbsRedaction.redactor` ran over the record before it was buffered |

### Example Invocations

```text
# Last 3 uncaught exceptions
crumbs_exceptions {"limit": 3}

# Every exception in the buffer
crumbs_exceptions {}
```

### Notes

- Only **uncaught** errors reach `FlutterError.onError` or `PlatformDispatcher.onError`. Expected
  `try/catch` flows do not surface here.
- The watcher chains to the handlers that were set before it (Sentry, Bugsnag), so both keep working.
- Pair with `crumbs_tail` to see what the app logged in the moments before the crash.

---

<a name="crumbs_events"></a>
## crumbs_events

Return recent in-app event records from the running Flutter app.

Reads the event buffer. On a Magic app `MagicEventWatcher` fills it from a curated set of Magic auth,
database and gate-definition events; any app can add its own through `CrumbsStore.recordEvent`. Use this
to trace event-driven side effects without adding `print` statements.

**VM Service extension:** `ext.crumbs.events`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of event records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |
| `type` | string | no | Prefix of the event type to include. Omit for every event. |
| `since` | integer | no | Microseconds, exclusive, compared with each record's `atUs`: pass the `cursor` of the previous answer to read only newer records. A value that is not an integer is refused. |

With `since`, `limit` keeps the oldest N records after it; the answer's `cursor` is the value to pass
back. See [Cursor and filters](cursor-and-filters.md).

### Output Shape

```json
{
  "events": [
    {
      "eventType": "MonitorChecked",
      "payload": {
        "monitorId": "abc-123",
        "status": "up"
      },
      "time": "2026-05-20T14:34:00.001",
      "listenerCount": 3,
      "atUs": 81234567,
      "redacted": false
    }
  ],
  "cursor": 81234567
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `eventType` | string | yes | Runtime class name of the dispatched event |
| `payload` | object | yes | JSON snapshot of the event payload. A value `jsonEncode` cannot write is stored as its `toString()` |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; join on `atUs` |
| `listenerCount` | integer | no | Number of listeners notified at dispatch time, when available |
| `atUs` | integer | yes | Monotonic microseconds from `FlutterTimeline.now` |
| `interactionId` | string | no | Correlates this record to others captured during the same interaction |
| `linkedBy` | string | no | How `interactionId` was derived: `zone` \| `frame` \| `window` |
| `redacted` | boolean | yes | True when `CrumbsRedaction.redactor` ran over the record before it was buffered |
| `cursor` | integer or null | yes (envelope) | Largest `atUs` returned, else the `since` given, else null |

### Example Invocations

```text
# Last 10 events
crumbs_events {"limit": 10}

# Every event in the buffer
crumbs_events {}

# Auth events after the cursor of the previous read
crumbs_events {"type": "Auth", "since": 81234567}
```

### Notes

- Only events that reach the buffer are visible: a Magic event outside the watcher's set, or a raw
  `ChangeNotifier.notifyListeners` call, does not surface here.
- `MagicEventWatcher` records an empty `payload` for every Magic event: the record carries the event
  type, never the event's own fields.
- For gate checks use `crumbs_gates`; for HTTP traffic use `crumbs_requests`.

---

<a name="crumbs_gates"></a>
## crumbs_gates

Return recent gate authorisation check records from the running Flutter app.

Reads the gate buffer, filled by `MagicGateWatcher` on every `Gate.allows` and `Gate.denies` call
through the Magic `Gate` facade. Use this to debug authorisation issues (why a button is hidden, why a
route is blocked) without modifying policy classes.

**VM Service extension:** `ext.crumbs.gates`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of gate check records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |

### Output Shape

```json
{
  "gates": [
    {
      "ability": "monitors.destroy",
      "result": false,
      "arguments": ["Monitor"],
      "time": "2026-05-20T14:35:00.010",
      "userId": "user-42"
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `ability` | string | yes | Ability name passed to `Gate.allows` / `Gate.denies` |
| `result` | boolean | yes | `true` when the gate allowed the action; `false` when denied |
| `arguments` | array | yes | List of argument values (class name strings or serialised primitives); a value under a credential-named key reads `********` |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; this record has no `atUs` |
| `userId` | string | no | Authenticated user ID at check time, when available |

### Example Invocations

```text
# Last 20 gate checks
crumbs_gates {"limit": 20}

# Every gate check in the buffer
crumbs_gates {}
```

### Notes

- Only checks a host records into the store are returned (`magic_devtools` records checks
  through Magic's `Gate` facade). Direct policy class calls are not recorded.
- Pair with `crumbs_clear` before walking a guarded flow to isolate just the relevant checks.

---

<a name="crumbs_dumps"></a>
## crumbs_dumps

Return recent `debugPrint` output records from the running Flutter app.

Reads the dump buffer, filled by `DumpWatcher`, which replaces the global `debugPrint` callback and
chains to the previous one. Use this to read `debugPrint()` output from within the running app without
scraping `flutter run` output.

**VM Service extension:** `ext.crumbs.dumps`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of dump records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |

### Output Shape

```json
{
  "dumps": [
    {
      "message": "[MonitorController] reloading monitors...",
      "time": "2026-05-20T14:36:00.200",
      "wrapWidth": 80
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `message` | string | yes | Full message string passed to `debugPrint` |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; this record has no `atUs` |
| `wrapWidth` | integer | no | Wrap width passed to the original `debugPrint` call, when provided |

### Example Invocations

```text
# Last 10 debugPrint calls
crumbs_dumps {"limit": 10}

# Every dump record in the buffer
crumbs_dumps {}
```

### Notes

- Only output routed through `debugPrint` is captured. `print()` and `stdout.write` calls are
  invisible to this tool.
- A dump is free text: a credential in a message is masked only by a host `CrumbsRedaction.redactor`.
- `DumpWatcher` installs nothing outside a debug build unless `allowInRelease` is set, so a profile
  build under `!kReleaseMode` records no dumps.
- For structured logs use `crumbs_tail`; for crashes use `crumbs_exceptions`.

---

<a name="crumbs_queries"></a>
## crumbs_queries

Return recent database query records from the running Flutter app.

Reads the query buffer, filled by `MagicQueryWatcher` from the `QueryExecuted` event the Magic query
builder dispatches after every SQL run. Use this to inspect what queries the app ran without attaching
a separate SQL profiler.

**VM Service extension:** `ext.crumbs.queries`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of query records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |

### Output Shape

```json
{
  "queries": [
    {
      "sql": "SELECT * FROM monitors WHERE team_id = ? LIMIT 50",
      "bindings": ["team-abc"],
      "timeMs": 4,
      "connectionName": "default",
      "time": "2026-05-20T14:37:00.100",
      "atUs": 1234567
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `sql` | string | yes | SQL string the query builder dispatched to the driver |
| `bindings` | array | yes | Positional or named query bindings; a value under a credential-named key of a Map element reads `********`, a positional value only a host `redactor` masks |
| `timeMs` | integer | yes | Execution time in milliseconds reported by the query builder |
| `connectionName` | string | yes | Connection name; `"default"` when the app did not name it |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; join on `atUs` |
| `atUs` | integer | yes | Monotonic microsecond timestamp from `FlutterTimeline.now` |
| `interactionId` | string | no | Correlates this record to others captured during the same interaction |
| `linkedBy` | string | no | How `interactionId` was derived: `zone` \| `frame` \| `window` |

### Example Invocations

```text
# Last 5 queries
crumbs_queries {"limit": 5}

# Every query in the buffer
crumbs_queries {}
```

### Notes

- Only queries that go through magic's QueryBuilder (dispatching `QueryExecuted` via
  `EventDispatcher`) are recorded. Raw `sqlite3` or direct Dio SQL calls bypass this tool.
- The SQL is free text: a literal in it is masked only by a host `CrumbsRedaction.redactor`.
- For Magic Cache traffic use `crumbs_caches`; for HTTP use `crumbs_requests`; for log
  lines use `crumbs_tail`.

---

<a name="crumbs_caches"></a>
## crumbs_caches

Return recent Magic cache operation records from the running Flutter app.

Reads the cache buffer, filled by `MagicCacheWatcher` from Magic's `CacheHit`, `CacheMiss`,
`CachePut`, `CacheForget` and `CacheFlush` events. Use this to inspect cache traffic without
instrumenting the app.

**VM Service extension:** `ext.crumbs.caches`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of cache records to return: the most recent N, in chronological order (oldest of that window first, newest last). Omit for the whole buffer (cap enforced by ring-buffer size, 500). |

### Output Shape

```json
{
  "caches": [
    {
      "operation": "put",
      "key": "monitors.team-abc",
      "time": "2026-05-20T14:38:00.300",
      "ttlMs": 300000,
      "atUs": 1234567
    }
  ]
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `operation` | string | yes | One of: `hit`, `miss`, `put`, `forget`, `flush` |
| `key` | string | yes | Cache key string (`*` for a flush) |
| `time` | string | yes | ISO 8601 device-local wall clock, no offset; join on `atUs` |
| `ttlMs` | integer | no | TTL in milliseconds, when the operation carried one |
| `atUs` | integer | yes | Monotonic microsecond timestamp from `FlutterTimeline.now` |
| `interactionId` | string | no | Correlates this record to others captured during the same interaction |
| `linkedBy` | string | no | How `interactionId` was derived: `zone` \| `frame` \| `window` |

### Example Invocations

```text
# Last 20 cache operations
crumbs_caches {"limit": 20}

# Every cache operation in the buffer
crumbs_caches {}
```

### Notes

- Only cache operations a host records into the store are returned (`magic_devtools` records
  Magic's `Cache` facade calls). Raw driver-level cache calls bypass this tool.
- For DB queries use `crumbs_queries`; for HTTP use `crumbs_requests`.

---

<a name="crumbs_frames"></a>
## crumbs_frames

Return recent per-frame performance records from the running Flutter app.

Reads the frame buffer, filled by `FramePerfWatcher`, which joins
`SchedulerBinding` frame timings with a per-frame `FlutterTimeline` block-attribution drain. Each
record carries frame number, build/raster/vsync-overhead/total-span durations in microseconds, a
timestamp, and a `blocks` map of named spans to their aggregated duration and call count. Use this
to attribute jank to a specific widget or layout phase after driving an interaction.

**VM Service extension:** `ext.crumbs.frames`

### Input Schema

| Parameter | Type | Required | Description |
|:---|:---|:---|:---|
| `limit` | integer | no | Maximum number of frame records to return (oldest-first; last entry is newest). Omit for the whole buffer (cap enforced by the frame-perf buffer size, default 3600). |

### Output Shape

```json
{
  "frames": [
    {
      "frameNumber": 128,
      "buildMicros": 1400,
      "rasterMicros": 2100,
      "vsyncOverheadMicros": 300,
      "totalSpanMicros": 3800,
      "time": "2026-05-20T14:38:00.300",
      "blocks": {
        "Widget.build": { "micros": 600, "selfMicros": 400, "count": 5 }
      },
      "vsyncStartUs": 998200,
      "atUs": 1234567
    }
  ],
  "livenessCounter": 128
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `frames` | array | yes | The frame records, may be empty |
| `frames[].frameNumber` | integer | yes | The engine's frame number |
| `frames[].buildMicros` | integer | yes | Build phase duration in microseconds |
| `frames[].rasterMicros` | integer | yes | Raster phase duration in microseconds |
| `frames[].vsyncOverheadMicros` | integer | yes | Vsync overhead in microseconds |
| `frames[].totalSpanMicros` | integer | yes | Total frame span in microseconds |
| `frames[].time` | string | yes | ISO 8601 device-local wall clock, no offset; join on `atUs` |
| `frames[].blocks` | object | yes | Named span to `{micros, selfMicros, count}`; empty when no measurement session is collecting. `micros` is inclusive of nested children, `selfMicros` is exclusive (`micros` minus directly nested children's combined duration) |
| `frames[].vsyncStartUs` | integer | no | Vsync signal timestamp from `FrameTiming.timestampInMicroseconds(FramePhase.vsyncStart)`. Clock parity with `atUs` is NOT proven; treat a comparison as needing a live-engine run, not a unit-test guarantee |
| `frames[].atUs` | integer | yes | Monotonic microsecond timestamp from `FlutterTimeline.now`, captured at record construction |
| `frames[].interactionId` | string | no | Correlates this record to others captured during the same logical interaction |
| `frames[].linkedBy` | string | no | How `interactionId` was derived: `zone` \| `frame` \| `window` |
| `livenessCounter` | integer | yes | Monotonic count of frames actually drawn since `FramePerfWatcher` was installed; present even when `frames` is empty, so a caller can tell a quiet app from a stalled engine |

### Example Invocations

```text
# Last 100 frames
crumbs_frames {"limit": 100}

# Every frame in the buffer
crumbs_frames {}
```

### Notes

- `FramePerfWatcher` is opt-in and not auto-installed. An empty `frames` list with a
  non-advancing `livenessCounter` means it is not registered, not that the app is idle.
- `blocks` is only populated while a measurement session has `FlutterTimeline` collection
  enabled; otherwise records carry frame magnitude with an empty `blocks` map.

---

<a name="crumbs_clear"></a>
## crumbs_clear

Clear every crumbs ring buffer.

Empties every buffer in one call, so the next read of any `crumbs_*` tool returns only records
produced **after** this clear. Use it as a starting point before reproducing a bug or capturing the
output of one user action.

**VM Service extension:** `ext.crumbs.clear`

### Input Schema

No parameters.

### Output Shape

```json
{
  "cleared": true
}
```

| Field | Type | Always present | Description |
|:---|:---|:---|:---|
| `cleared` | boolean | yes | Always `true` on success |

### Example Invocations

```text
# Clear, perform the action, then read
crumbs_clear {}
# the user action runs
crumbs_requests {"limit": 20}
crumbs_tail {"limit": 50}
```

### Notes

- Idempotent: safe to call when the buffers are already empty.
- Does not touch the live `package:logging` stream or any other sink (Sentry, Bugsnag); only the
  buffers crumbs keeps.
- `ext.crumbs.pause` and `ext.crumbs.resume`, which stop and restart recording, have no MCP tool.

---

<a name="related-documentation"></a>
## Related Documentation

- [Cursor and filters](cursor-and-filters.md): `since`, `type`, `logger` and `cursor` on the console and
  events extensions.
- [MCP overview](overview.md): how the tools reach the running app through `CrumbsDowelProvider`.
- [MCP setup](setup.md): write the `.mcp.json` entry and connect a client.
- [dowel MCP tool reference](https://anilcancakir.com/dowel/docs/mcp/tool-reference): the `dowel_*`
  substrate tools (`dowel_start`, `dowel_stop`, `dowel_status`) and filter configuration.
