# Workflows

Composed loops that combine `crumbs_*` tools (and pair with tapir
where useful) for the most common agent tasks. Read top to bottom; the
order goes from highest-frequency to specialised.

## Contents

- [1. Zero, repro, inspect](#1-zero-repro-inspect)
- [2. Crash hunt](#2-crash-hunt)
- [3. Magic facade trace](#3-magic-facade-trace)
- [4. Log filtering by minimum level](#4-log-filtering-by-minimum-level)
- [5. Tapir pairing for state verification](#5-tapir-pairing-for-state-verification)
- [6. Long-running app: when to clear vs not](#6-long-running-app-when-to-clear-vs-not)
- [7. Working around the cache no-op](#7-working-around-the-cache-no-op)
- [8. Reading Magic model lifecycle via events](#8-reading-magic-model-lifecycle-via-events)
- [9. Network-idle without crumbs](#9-network-idle-without-crumbs)
- [10. Sentry / Bugsnag coexistence](#10-sentry--bugsnag-coexistence)
- [11. Follow a buffer with a cursor](#11-follow-a-buffer-with-a-cursor)
- [12. Read the timeline on disk](#12-read-the-timeline-on-disk)

---

## 1. Zero, repro, inspect

Default loop. Use whenever the question is "did action X cause effect
Y?".

```
1. crumbs_clear
2. <drive the app: tapir_tap / tapir_type / tapir_navigate, or human>
3. tapir_wait_for_network_idle           // skip when action is local
4. crumbs_requests { limit: 20 }
5. crumbs_exceptions
6. crumbs_tail { limit: 50 }
```

The clear in step 1 keeps the read scope tight. Without it,
`crumbs_tail` floods with startup noise (every controller's INFO
line from `MagicApp.bootstrap()`).

`tapir_wait_for_network_idle` (step 3) reads crumbs's
`MagicHttpFacadeAdapter.pendingCount`. With crumbs unwired, that
count is always 0 and the wait returns immediately with
`matched: true`, defeating the purpose. Verify with one
`crumbs_requests` call first if you suspect a wiring gap.

---

## 2. Crash hunt

When an exception has already fired and you need to reason about it.
Do not clear; clearing discards evidence.

```
1. crumbs_exceptions { limit: 5 }
   Pick the offender. Read its exceptionType + message + stackTrace.

2. crumbs_tail { limit: 100 }
   Logs around the crash. Look for the breadcrumb just before the
   throw, usually a WARNING that names the upstream cause.

3. crumbs_requests { limit: 20 }
   HTTP around the crash. A 5xx response right before the throw is
   the most common root cause.

4. crumbs_gates { limit: 10 }
   When the exception type is AuthorizationException, the denying
   ability + arguments lands here. The gate record is older than the
   exception by one or two records.
```

For a recurring crash, follow with workflow 1 to isolate the trigger:
clear, reproduce the action you suspect, re-read.

---

## 3. Magic facade trace

The canonical "what just happened" view for Magic-stack apps. Combines
events + queries + requests + gates into one timeline.

```
1. crumbs_clear
2. <user action: model save, login, form submit>
3. crumbs_events   { limit: 10 }     What dispatched.
4. crumbs_queries  { limit: 20 }     What hit SQLite.
5. crumbs_requests { limit: 20 }     What hit the API.
6. crumbs_gates    { limit: 10 }     What was authorized.
```

Read in order:

- **Events** name the intent (`AuthLoginSucceeded`, `ModelSaved`).
- **Queries** show the persistence side (UPSERT, SELECT for refresh).
- **Requests** show the API side (POST `/users`, GET `/auth/me`).
- **Gates** show authorization decisions (the policy checks that
  guarded the action).

Cross-reference by `time` to reconstruct the actual flow:

```
event AuthLoginSucceeded   2026-05-25T09:14:20.001Z
gate  users.read=true      2026-05-25T09:14:20.004Z
query SELECT * FROM users  2026-05-25T09:14:20.007Z (3ms)
request GET /auth/me       2026-05-25T09:14:20.040Z (200, 142ms)
```

---

## 4. Log filtering by minimum level

`crumbs_tail` accepts a `level` parameter that filters at read time,
not at capture time. Capture is always at `Level.ALL` (every log line
is in the buffer); the filter just narrows the response.

```
crumbs_tail { level: "WARNING", limit: 50 }
  Returns WARNING + SEVERE + SHOUT only.

crumbs_tail { level: "INFO", limit: 50 }
  Returns INFO + WARNING + SEVERE + SHOUT (everything except
  FINE / FINER / FINEST / CONFIG).

crumbs_tail { limit: 50 }
  No filter: every level, including FINEST / FINER / FINE / CONFIG.
```

Recovery pattern: hunt with `level: "SEVERE"` first to find the worst,
then re-query with `level: "WARNING"` to read the breadcrumb context,
then drop the filter when you need full FINE-level tracing. The buffer
holds everything; no recapture is needed.

An unknown level name matches nothing (an empty answer), not every
level: when a filtered read comes back empty, check the spelling before
concluding the log is clean.

Levels and their values (low to high):
`FINEST` (300), `FINER` (400), `FINE` (500), `CONFIG` (700),
`INFO` (800), `WARNING` (900), `SEVERE` (1000), `SHOUT` (1200).

---

## 5. Tapir pairing for state verification

Tapir drives, crumbs reads. Two patterns are standard:

**Pattern A: post-gesture verification.**

```
1. tapir_tap { ref: "e7" }                Pre-action snap minted e7.
2. tapir_wait_for_network_idle            Block on HTTP completion.
3. crumbs_requests { limit: 5 }       Was the POST made? Status?
4. crumbs_exceptions                  Anything throw downstream?
5. tapir_snap                             Confirm the UI rebuilt.
```

**Pattern B: form submit with field-level trace.**

```
1. crumbs_clear
2. tapir_observe { intent: "login form", roles: "textbox,button" }
3. tapir_type { ref: "q3", text: "user@example.com" }
4. tapir_type { ref: "q4", text: "hunter2" }
5. tapir_tap  { ref: "q5" }
6. tapir_wait_for_network_idle { idleMs: 800 }
7. crumbs_requests { limit: 5 }
8. crumbs_events   { limit: 10 }      AuthLoginSucceeded?
9. crumbs_gates    { limit: 10 }      What got authorized
                                          immediately after login?
```

The clear in step 1 isolates this submit from earlier traffic. Steps
7-9 read the side effects in order: HTTP first (was the request
made?), events next (did the auth listener fire?), gates last (what
abilities did the new session unlock?).

---

## 6. Long-running app: when to clear vs not

`crumbs_clear` is cheap (one VM extension call, no app pause), but
it discards evidence. Rule of thumb:

| Situation | Clear before? |
|---|---|
| Reproducing a bug you can trigger on demand | Yes. Tight read scope wins. |
| Hunting a flaky bug you cannot trigger | No. Wait for the bug, then read the buffer with `limit: <full ring>` (omit to read up to 500). |
| Investigating a crash that already fired | No. The exception is in the buffer; clearing destroys it. |
| Tracing a session login at app start | No. The login fires before you can react; read with a high limit instead. |
| Periodic health check during a long session | Sometimes. Clear every N minutes to keep the working set small, but only when you have a steady-state baseline you do not need to retain. |

The ring buffer caps at 500 records per buffer; older entries evict
silently. For a busy app, the 500 cap is reached in under a minute;
clear strategically rather than letting eviction silently consume your
history.

---

## 7. Working around the cache no-op

`MagicCacheWatcher` is wired but `MagicCacheRecord` records never
arrive in current builds (Magic does not yet dispatch
`CacheHit / CacheMiss / CachePut / CacheForget / CacheFlush`). The
buffer is reachable, but always empty.

Workaround for now: inspect cache behaviour through the side channel
it leaves elsewhere.

- **Cache hit:** no HTTP request, no DB query for the cached
  resource. `crumbs_requests` and `crumbs_queries` show
  nothing.
- **Cache miss:** an HTTP request or DB query fires. Both buffers
  carry the trace.
- **Cache invalidation:** a `Cache.forget` or `Cache.flush` is
  followed by the next read producing an HTTP / DB record.

Stop checking `crumbs_caches` once you confirm it is empty for the
current Magic version. Move on; revisit when Magic ships the events.

---

## 8. Reading Magic model lifecycle via events

The agent cannot reach `MagicModelRecord` directly (no MCP tool).
`MagicModelWatcher` does populate the events buffer with
`ModelCreated`, `ModelSaved`, `ModelDeleted` though, so
`crumbs_events` is the agent-facing path.

```
1. crumbs_clear
2. <save a model / delete a model / etc.>
3. crumbs_events { limit: 20 }
4. <filter the array on eventType matching /^Model(Created|Saved|Deleted)$/>
```

The events carry empty `payload` in the current build, but the
`eventType` + `time` is enough to confirm the lifecycle fired.
Correlate with `crumbs_queries` for the actual UPSERT / DELETE
SQL, and with `crumbs_requests` for the API call that mirrored
the change.

---

## 9. Network-idle without crumbs

`tapir_wait_for_network_idle` requires a `CrumbsHttpAdapter` to
expose `pendingCount`. Without it, tapir returns immediately with
`matched: true` even when HTTP is in flight, breaking the wait.

Diagnose with one direct call:

```
crumbs_requests { limit: 1 }
```

If the response is `{"records": []}` on a known-active app, the
adapter is the missing piece. Fix by ensuring
`MagicCrumbsIntegration.install()` (from `magic_devtools`, import
`package:magic_devtools/crumbs.dart`) runs after `Magic.init()` in
`lib/main.dart`. For non-Magic apps, register `DioHttpAdapter`
manually:

```dart
final dio = Dio();
CrumbsPlugin.registerHttpAdapter(DioHttpAdapter(dio));
```

Without an adapter, the agent must fall back to polling
`tapir_snap` for the expected post-action UI state, or to
`tapir_wait_for { text: "..." }` against a known post-action label.

---

## 10. Sentry / Bugsnag coexistence

Crumbs's `ExceptionWatcher` and `LogWatcher` chain over any prior
global handler (`FlutterError.onError`, `Logger.root.onRecord`,
`debugPrint`). Sentry / Bugsnag installed before crumbs still
receive every throw and every log; installed after, they receive them
too as long as they preserve the chain.

The implication for the agent: if Sentry is configured to mute certain
exceptions, crumbs still captures them (it runs at the
`FlutterError.onError` hook directly). If a "swallowed" exception is
not in `crumbs_exceptions`, it was caught in a `try / catch` block
that never re-threw or logged. Trace the breadcrumb in
`crumbs_tail` instead.

When `uninstall()` is called on a watcher (rare in V1; mostly for
test isolation), the previous handler is restored exactly. The chain
is non-destructive.

---

## 11. Follow a buffer with a cursor

`ext.crumbs.console` and `ext.crumbs.events` answer a `cursor`, the
largest `atUs` returned, so a reader never re-reads or skips a record.
The CLI wraps it:

```bash
# Stream one logger as JSON lines until interrupted (run in the background).
./bin/dowel crumbs:tail --logger=Sync --json --follow

# Page by hand: read, keep the cursor, read again from it.
./bin/dowel crumbs:events --type=Auth --json --limit=20
./bin/dowel crumbs:events --type=Auth --json --since=<atUs of the last line>
```

With `--since`, `--limit` keeps the OLDEST N after the cursor, so paging
skips nothing; without it, the newest N of what matched. `--follow` polls
every second and drops `--limit` after the first read; an empty poll
prints nothing and keeps the cursor. The MCP tools do not declare
`since`, `type` or `logger`, so this loop is CLI (or raw VM extension)
only.

---

## 12. Read the timeline on disk

When the host runs a `CrumbsFileSink`, the redacted log, event and
exception records outlive the ring buffers and the launch:

```bash
./bin/dowel crumbs:files                                  # newest first
./bin/dowel crumbs:files --name=timeline-20261010T091500Z-0.jsonl -v
./bin/dowel crumbs:files --name=<same file> --offset=<next offset>
```

Each line is `{"kind": "log"|"event"|"exception", ...}` with `atUs`
where the record has one; join across kinds on `atUs`. `next offset` (at
`-v`) is where to continue; at the end of the file no lines print.
Earlier launches are listed too, so a crash from the last run is still
readable. If the list is empty or the command answers "No timeline file
sink is running.", the host has not started a sink; if the sink runs but
stays empty, the host has set no `CrumbsRedaction.redactor` (the sink
writes only redacted records) or the sink halted on a write failure.
