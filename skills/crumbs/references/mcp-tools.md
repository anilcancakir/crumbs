# MCP tool reference

Per-tool schema, response envelope, and example calls for the 10
`crumbs_*` MCP tools. Every read tool returns a single
`{"<key>": [<record>, ...]}` JSON object inside a single `text` content
block; parse the `text` body as JSON before reasoning over fields.

For per-record field shape (every key inside the record objects), see
`records.md`.

## Contents

- [`crumbs_requests`](#crumbs_requests)
- [`crumbs_tail`](#crumbs_tail)
- [`crumbs_exceptions`](#crumbs_exceptions)
- [`crumbs_events`](#crumbs_events)
- [`crumbs_gates`](#crumbs_gates)
- [`crumbs_dumps`](#crumbs_dumps)
- [`crumbs_queries`](#crumbs_queries)
- [`crumbs_caches`](#crumbs_caches)
- [`crumbs_frames`](#crumbs_frames)
- [`crumbs_clear`](#crumbs_clear)
- [Common semantics](#common-semantics)
- [Empty-buffer diagnosis](#empty-buffer-diagnosis)

---

## crumbs_requests

Outbound HTTP records captured by the registered `CrumbsHttpAdapter`.

**VM extension:** `ext.crumbs.requests`.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. Bad value silently falls back to whole buffer. |

**Response:**

```json
{
  "records": [
    {
      "url": "https://api.example.test/users",
      "method": "GET",
      "statusCode": 200,
      "durationMs": 184,
      "isError": false,
      "timestamp": "2026-05-25T09:14:22.318Z",
      "requestHeaders": { "Authorization": "********" },
      "responseBody": "{\"data\":[...]}"
    }
  ]
}
```

**Origin:** populated only when a `CrumbsHttpAdapter` is registered.
Magic-stack apps get `MagicHttpFacadeAdapter` via
`MagicCrumbsIntegration.install()`. Vanilla Dio apps register
`DioHttpAdapter` manually. Raw `dart:io HttpClient` is invisible.

**Common pattern:** call right after a `tapir_tap` that submitted a
form; filter the `records` array on `method == 'POST'` and a URL
substring to find the call of interest.

---

## crumbs_tail

Structured log records from `package:logging`.

**VM extension:** `ext.crumbs.console`.

**Input:**

```json
{ "level": "WARNING", "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `level` | string | no filter | Minimum-threshold filter. Uppercase names from `package:logging` (`FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`). Case-insensitive inside the handler. |
| `limit` | integer | whole buffer | Cap on records returned. |

The extension also accepts `since` (an `atUs`, microseconds, exclusive)
and `logger` (exact name), but the tool descriptor declares neither; from
a shell use `crumbs:tail --since --logger --json --follow`. With
`since`, `limit` keeps the OLDEST N after it (plus any ties on the last
`atUs`); without, the newest N.

**Response:**

```json
{
  "messages": [
    {
      "level": "WARNING",
      "levelValue": 900,
      "message": "User 42 reload returned no data",
      "loggerName": "UserController",
      "time": "2026-05-25T09:14:22.318Z",
      "atUs": 81234567,
      "redacted": false,
      "error": "...",
      "stackTrace": "..."
    }
  ],
  "cursor": 81234567
}
```

`cursor` is the largest `atUs` returned, else the `since` given, else
`null`; pass it back as `since` to read only newer records.

**Level threshold semantics:** `level: "WARNING"` returns WARNING (900)
+ SEVERE (1000) + SHOUT (1200) only. `level: "INFO"` adds INFO (800) on
top. Omit `level` to get every level. A `level` that is not one of the
eight names matches nothing and returns `{"messages": [], "cursor": null}`.

**Capture gate:** `LogWatcher` sets `Logger.root.level = Level.ALL`,
so every record is captured regardless of named-logger thresholds.
The `level` filter only narrows what comes back from the buffer; the
buffer itself still holds the lower-level records (re-querying without
the filter recovers them).

**Origin:** `LogWatcher` auto-installs as part of
`CrumbsPlugin.install()`. Always wired in a crumbs-enabled app.

---

## crumbs_exceptions

Uncaught exception records.

**VM extension:** `ext.crumbs.exceptions`. **MCP-only**, no CLI
mirror in V1.

**Input:**

```json
{ "limit": 5 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "exceptions": [
    {
      "exceptionType": "AuthorizationException",
      "message": "Ability 'users.destroy' denied",
      "time": "2026-05-25T09:14:22.318Z",
      "stackTrace": "...",
      "isolate": "main"
    }
  ]
}
```

**Capture surface:** `FlutterError.onError` and
`PlatformDispatcher.instance.onError`, chained over any prior handler
(Sentry / Bugsnag still receive the same throw). Swallowed `try /
catch` is invisible by design; pair with `crumbs_tail` to catch a
breadcrumb the swallower logged.

**Origin:** populated only when `ExceptionWatcher` is registered (opt-
in via `CrumbsPlugin.registerWatcher(ExceptionWatcher())`).
`crumbs:install` adds this line during bootstrap.

---

## crumbs_events

In-app events dispatched through Magic's `Event` facade.

**VM extension:** `ext.crumbs.events`. CLI mirror: `crumbs:events`.

**Input:**

```json
{ "limit": 10 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

The extension also accepts `since` (an `atUs`, microseconds, exclusive)
and `type` (prefix of `eventType`), but the tool descriptor declares
neither; from a shell use `crumbs:events --since --type --json
--follow`.

**Response:**

```json
{
  "events": [
    {
      "eventType": "AuthLoginSucceeded",
      "payload": {},
      "time": "2026-05-25T09:14:22.318Z",
      "listenerCount": 3,
      "atUs": 81234567,
      "redacted": false
    }
  ],
  "cursor": 81234567
}
```

`cursor` works as on `crumbs_tail`. Payload values `jsonEncode`
cannot write are stored as their `toString()`.

**Coverage:** `MagicEventWatcher` listens for `AuthLogin`,
`AuthLogout`, `AuthFailed`, `AuthRestored`, `DatabaseConnected`,
`GateAbilityDefined`, `GateBeforeRegistered`, plus `ModelCreated`,
`ModelSaved`, `ModelDeleted`. To inspect Magic model lifecycle from
the agent, query this buffer and filter on `eventType` containing
`Model`.

`payload` is `{}` in the V1 release (placeholder; structured payload
extraction is V1.x backlog). Raw
`ChangeNotifier.notifyListeners` calls are not captured.

**Origin:** requires `MagicCrumbsIntegration.install()`. Without
it the buffer stays empty.

---

## crumbs_gates

Gate authorization checks.

**VM extension:** `ext.crumbs.gates`. CLI mirror: `crumbs:gates`.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "gates": [
    {
      "ability": "users.destroy",
      "result": false,
      "arguments": ["User#42"],
      "time": "2026-05-25T09:14:22.318Z",
      "userId": "user_7"
    }
  ]
}
```

**Coverage:** every `Gate.allows(...)` / `Gate.denies(...)` call.
`result` is the bool the facade returned; `arguments` is the list
passed positionally (each entry serialized as its `runtimeType.toString()`
unless it has its own `toJson`). `userId` is the authenticated user's
id at the time of the check (string-stringified), or absent for guest.

**Origin:** requires `MagicCrumbsIntegration.install()`.

---

## crumbs_dumps

`debugPrint` captures.

**VM extension:** `ext.crumbs.dumps`. CLI mirror: `crumbs:dumps`.

**Input:**

```json
{ "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "dumps": [
    {
      "message": "UserController: rxState=loaded",
      "time": "2026-05-25T09:14:22.318Z",
      "wrapWidth": 80
    }
  ]
}
```

**Capture surface:** global `debugPrint` override that chains the
prior implementation. Only calls that go through the `debugPrint`
callback are captured. Plain Dart `print(...)` does NOT route through
`debugPrint`, so `print("...")` output is invisible to this buffer;
callers must use `debugPrint(...)` to land in `crumbs_dumps`. Raw
`dart:io stdout.write` and `stderr.write` are also invisible.

**Origin:** populated only when `DumpWatcher` is registered (opt-in
via `CrumbsPlugin.registerWatcher(DumpWatcher())`).
`crumbs:install` adds this line during bootstrap. The watcher
self-gates on `kDebugMode` and never captures in release builds.

---

## crumbs_queries

DB queries via Magic's QueryBuilder.

**VM extension:** `ext.crumbs.queries`.

**Input:**

```json
{ "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "queries": [
    {
      "sql": "SELECT * FROM users WHERE team_id = ?",
      "bindings": ["team_3"],
      "timeMs": 4,
      "connectionName": "default",
      "time": "2026-05-25T09:14:22.318Z"
    }
  ]
}
```

**Coverage:** every query dispatched via `MagicQueryWatcher` listening
on the `QueryExecuted` event. Raw `sqlite3` / `drift` / `package:sqflite`
calls are invisible.

**Origin:** requires `MagicCrumbsIntegration.install()`.

---

## crumbs_frames

Return recent per-frame performance records from the running app.

**Extension:** `ext.crumbs.frames`.

**Input schema:** `limit` (integer, optional, default 50).

**Returns:** `{"frames": [...], "livenessCounter": <int>}`. Each frame carries `frameNumber`, `buildMicros`, `rasterMicros`, `vsyncOverheadMicros`, `totalSpanMicros`, `time`, `atUs`, a `blocks` map of `{name: {micros, selfMicros, count}}`, and when known `vsyncStartUs`, `interactionId` and `linkedBy` (field notes in `records.md`).

`livenessCounter` is present on every response, including an empty one. It is a monotonic count of frames actually drawn, and it is the only reliable proof the engine is rendering: `SchedulerBinding.framesEnabled` was measured reporting `true`, with a `resumed` lifecycle, on a backgrounded Chrome page that had produced one frame in two seconds. If the counter does not advance across an interaction, every number in the response is a zero that reads as "fast".

Requires `CrumbsPlugin.registerWatcher(FramePerfWatcher())`; it is opt-in and not auto-installed.

---

## crumbs_caches

Magic Cache operations.

**VM extension:** `ext.crumbs.caches`.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "caches": [
    {
      "operation": "hit",
      "key": "team:3:users",
      "time": "2026-05-25T09:14:22.318Z",
      "ttlMs": 300000
    }
  ]
}
```

`operation` is one of `put`, `hit`, `miss`, `forget`, `flush`. `ttlMs`
is the TTL in milliseconds (converted from `Duration` on the producer
side); absent for operations that do not carry a TTL.

**Current state:** placeholder. Magic's `Cache` facade does not yet
emit the cache events `MagicCacheWatcher` subscribes to, so this
buffer reads as `{"caches": []}` in current builds. The watcher is
wired and ready for when Magic ships the events.

**Origin:** requires `MagicCrumbsIntegration.install()` (when
events ship).

---

## crumbs_clear

Wipe all 10 ring buffers atomically.

**VM extension:** `ext.crumbs.clear`.

**Input:**

```json
{}
```

No parameters.

**Response:**

```json
{ "cleared": true }
```

Idempotent: safe to call when buffers are already empty. Does NOT
affect live subscriptions (`package:logging` Logger streams, the
`onXRecord` broadcast streams inside the running app); only the
captured ring buffers are emptied.

`ext.crumbs.pause` and `ext.crumbs.resume` exist as VM
extensions for completeness but are deliberately not surfaced as MCP
tools in V1. Reach for them only from Dart code via
`CrumbsStore.pause()` / `.resume()` in a custom helper.

---

## Common semantics

- **Envelope wrapping.** MCP returns the JSON object as a single
  `text` content block: `{ "content": [{ "type": "text", "text":
  "<json string>" }], "isError": false }`. Parse the `text` body as
  JSON before reasoning over fields.

- **Tool naming.** Tools surface to the model as
  `mcp__fluttersdk__crumbs_<name>` (the `.mcp.json` server key is
  `fluttersdk`). The `crumbs_` prefix is part of the tool name, not
  the server.

- **Ordering.** Records come back in chronological order (oldest at
  index 0). The handler does not reverse the queue. Iterate from the
  end for newest-first.

- **Cap.** Each ring buffer holds 500 records by default; older
  entries evict silently on overflow. Without `limit`, the response
  carries up to 500 records per buffer.

- **Bad input.** Invalid `limit` (non-numeric string) coerces to null,
  returning the whole buffer; a zero or negative `limit` returns
  nothing. An unknown `level` (a name not in the `package:logging`
  order list) matches nothing, so an empty answer is not proof of a
  clean log: check the name. A `since` that is not an integer is
  refused with `kInvalidParams` ("since must be an integer number of
  microseconds."), never read as "from the start".

- **Hot-restart safety.** All 14 extensions register via
  `registerExtensionIdempotent` from `dowel`. Hot
  restart re-runs the install code without re-registration errors.

- **Redaction.** Log, event, exception and HTTP records are run through
  the host's `CrumbsRedaction.redactor` at insert, when one is set,
  and carry `redacted: true`. A record the redactor threw on is dropped
  and never appears.

- **Timeline files have no MCP tool.** `ext.crumbs.files` and
  `ext.crumbs.file` read the host's `CrumbsFileSink` (answering
  `{error}` when none runs) and are reached with `crumbs:files`.

- **Pause / resume gating.** When `CrumbsStore.pause()` is called
  (no MCP tool, Dart-only), all `recordX` methods early-return. The
  buffers retain their existing records; reading still works.
  `resume()` re-enables recording.

---

## Empty-buffer diagnosis

When a tool returns an empty array on an active app, the watcher /
adapter is the most likely missing piece:

| Tool empty | Likely cause | Fix |
|---|---|---|
| `crumbs_requests` | No `CrumbsHttpAdapter` registered | Call `MagicCrumbsIntegration.install()` (Magic) or `CrumbsPlugin.registerHttpAdapter(DioHttpAdapter(dio))` (vanilla). |
| `crumbs_tail` | `LogWatcher` not auto-installed (very rare; only if `CrumbsPlugin.install()` was skipped) | Confirm `CrumbsPlugin.install()` runs inside the `kDebugMode` block in `main.dart`. |
| `crumbs_exceptions` | `ExceptionWatcher` not registered | Add `CrumbsPlugin.registerWatcher(ExceptionWatcher())`. |
| `crumbs_dumps` | `DumpWatcher` not registered, or the code uses `dart:io stdout.write` | Add `CrumbsPlugin.registerWatcher(DumpWatcher())`; rewrite calls to `debugPrint`. |
| `crumbs_events` | `MagicCrumbsIntegration.install()` not called | Add the call after `Magic.init()` inside the `kDebugMode` block. |
| `crumbs_gates` | Same as events | Same fix. |
| `crumbs_queries` | Same as events, or queries use `sqlite3` directly | Same fix; or migrate the call to the Magic QueryBuilder. |
| `crumbs_caches` | Magic does not yet emit cache events (V1 placeholder) | Wait for Magic to ship cache events; nothing to fix in crumbs. |

If every tool reads empty: the app is not running, the VM Service is
not reachable, or `CrumbsPlugin.install()` itself was skipped.
Confirm with `./bin/dowel status`.
