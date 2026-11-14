# CLI command reference

Per-command flags, defaults, output format, and exit codes for the 11
`crumbs:*` CLI commands. Two invocation forms reach the same code
path:

- `./bin/dowel crumbs:<cmd> [flags]` (native AOT, ~110ms warm) is the
  default after `crumbs:install` has scaffolded the wrapper.
- `dart run crumbs crumbs:<cmd> [flags]` (~3s cold)
  works without prior install; this is how `crumbs:install` itself
  runs the first time.

All read commands boot in `connected` mode: they attach to the running
app's VM Service before issuing the extension call, and fail with "VM
Service URI absent" if the app is not running. Output is human-readable
(formatted lines) by default; `crumbs:tail` and `crumbs:events`
print one JSON object per line with `--json`. Prefer the MCP tools when
the agent needs structured data, and `--json` when it needs the `atUs`
cursor.

## Contents

- [Contents](#contents)
- [crumbs:install](#crumbsinstall)
- [crumbs:tail](#crumbstail)
- [crumbs:requests](#crumbsrequests)
- [crumbs:queries](#crumbsqueries)
- [crumbs:caches](#crumbscaches)
- [crumbs:events](#crumbsevents)
- [crumbs:gates](#crumbsgates)
- [crumbs:dumps](#crumbsdumps)
- [crumbs:frames](#crumbsframes)
- [crumbs:clear](#crumbsclear)
- [crumbs:files](#crumbsfiles)
- [Why exceptions is MCP-only](#why-exceptions-is-mcp-only)
- [Common output behaviour](#common-output-behaviour)

## Contents

- [`crumbs:install`](#crumbsinstall)
- [`crumbs:tail`](#crumbstail)
- [`crumbs:requests`](#crumbsrequests)
- [`crumbs:queries`](#crumbsqueries)
- [`crumbs:caches`](#crumbscaches)
- [`crumbs:events`](#crumbsevents)
- [`crumbs:gates`](#crumbsgates)
- [`crumbs:dumps`](#crumbsdumps)
- [`crumbs:frames`](#crumbsframes)
- [`crumbs:clear`](#crumbsclear)
- [`crumbs:files`](#crumbsfiles)
- [Why exceptions is MCP-only](#why-exceptions-is-mcp-only)
- [Common output behaviour](#common-output-behaviour)

---

## crumbs:install

Bootstrap crumbs in a consumer Flutter app. Idempotent: safe to
re-run.

**Flags:** none.

**What it does (3 steps):**

1. `dart run dowel install` scaffolds `bin/dispatcher.dart`,
   `bin/dowel`, and `lib/app/_plugins.g.dart` (skipped when the wrapper
   already exists).
2. `./bin/dowel plugin:install crumbs` registers the
   plugin in `.dowel/plugins.json` and regenerates
   `lib/app/_plugins.g.dart`.
3. Patches `lib/main.dart` via `MainDartEditor`:
   - Adds imports for `kDebugMode` and `package:crumbs/crumbs.dart`.
   - Injects a `kDebugMode` block before `await Magic.init(` (Magic
     apps) or `runApp(` (vanilla) with:
     ```dart
     CrumbsPlugin.install();
     CrumbsPlugin.registerWatcher(ExceptionWatcher());
     CrumbsPlugin.registerWatcher(DumpWatcher());
     ```
   - When pubspec contains `magic_devtools:` (as a dependency or
     dev_dependency) and `lib/main.dart` contains `await Magic.init(`,
     also injects `import 'package:magic_devtools/crumbs.dart';`
     plus `MagicCrumbsIntegration.install();` inside a second
     `kDebugMode` block after `Magic.init()` completes.

All three sub-steps check for a string anchor before inserting, so the
command is idempotent.

**Output:** human-readable status lines (info / success / error).

**Exit codes:** `0` on success. Non-zero only when an inner subprocess
(dowel install or plugin install) fails.

**Example:**

```bash
$ dart run crumbs crumbs:install
[info] Scaffolding bin/dispatcher.dart, bin/dowel, lib/app/_plugins.g.dart...
[ok]   Wrapper ready.
[info] Registering crumbs plugin...
[ok]   Plugin registered.
[info] Patching lib/main.dart...
[ok]   CrumbsPlugin.install() injected before await Magic.init(...).
[ok]   import 'package:magic_devtools/crumbs.dart' injected.
[ok]   MagicCrumbsIntegration.install() injected after Magic.init(...).
[ok]   Done.
```

---

## crumbs:tail

Print recent log records.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--level=<NAME>` | (none, no filter) | Minimum-threshold filter, accepts `info`, `warning`, `severe`, `shout`, `fine`, etc. A name that is not a level prints nothing. |
| `--limit=<N>` | `50` | Max records to print (most-recent N from the buffer; with `--since`, the oldest N after it). |
| `--since=<atUs>` | (none) | Only records whose `atUs` (microseconds) is greater than this. A non-integer value is refused. |
| `--logger=<name>` | (none) | Only records of this exact logger name. |
| `--json` | off | Print one JSON object per line (the record's `toJson()`, `atUs` and `redacted` included) instead of formatted text. |
| `--follow` | off | Keep polling every second from the cursor the previous read returned, until interrupted. Drops `--limit` after the first read. |

**VM extension:** `ext.crumbs.console`. The filters run on the app
side before `limit`.

**Output format:** one line per record:

```
2026-05-25T09:14:22.318Z [WARNING] UserController: User 42 reload returned no data
```

**Empty-buffer hint:** `"No log records."` (warning style, exit 0).
Suppressed under `--json` and `--follow`, where an empty poll prints
nothing.

**Exit codes:** always `0` (success or empty).

**Example:**

```bash
./bin/dowel crumbs:tail --level=warning --limit=20
./bin/dowel crumbs:tail --logger=Sync --json --follow
```

---

## crumbs:requests

Print recent HTTP records.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.crumbs.requests`.

**Output format:**

```
2026-05-25T09:14:22.318Z GET https://api.example.test/users → 200 (184ms) atUs=81234567 requestId=r12 interactionId=i3 linkedBy=zone
2026-05-25T09:14:23.121Z POST https://api.example.test/users → 422 (97ms) atUs=82037120 linkedBy=window
```

`requestId`, `interactionId` and `linkedBy` are printed only when the record carries them. `linkedBy=window` comes without an `interactionId`: no interaction was open, so the record joins by `atUs`.

**Empty-buffer hint:** `"No HTTP records (register a CrumbsHttpAdapter)."`

**Exit codes:** always `0`.

**Example:**

```bash
./bin/dowel crumbs:requests --limit=10
```

---

## crumbs:queries

Print recent DB queries.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.crumbs.queries`.

**Output format:**

```
2026-05-25T09:14:22.318Z [default] SELECT * FROM users WHERE team_id = ? bindings=[team_3] (4ms)
```

**Empty-buffer hint:** `"No DB query records (register MagicQueryWatcher)."`

**Exit codes:** always `0`.

---

## crumbs:frames

Print recent per-frame performance records.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Cap the window to the most recent N records, printed oldest to newest. |

**VM extension:** `ext.crumbs.frames`.

**Output format:**

```
2026-08-25T10:46:51.145Z frame#409 atUs=81234567 vsyncStartUs=81170266 build=57301us raster=2901us vsync=0us total=64301us blocks={WDiv: {micros: 518300, selfMicros: 402100, count: 122}, ...} interactionId=i3 linkedBy=frame
livenessCounter=415
```

**Empty-buffer hint:** `"No frame records (register FramePerfWatcher). livenessCounter=<N>"`. The counter is printed even when the list is empty, and that is the point: an empty result means either a quiet app or an engine that stopped rendering, and only the second is a reason to distrust every other number in a session.

**Buffer size:** 3600 records, not the 500 the other nine use. That is about a minute at 60fps, and it has its own capacity field so raising it does not inflate the other buffers.

**Exit codes:** always `0`.

---

## crumbs:caches

Print recent Magic Cache operations.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.crumbs.caches`.

**Output format:**

```
2026-05-25T09:14:22.318Z [hit] team:3:users ttl=300000ms
2026-05-25T09:14:25.812Z [miss] user:7:profile
```

**Empty-buffer hint:** `"No cache records (register MagicCacheWatcher)."`

**Exit codes:** always `0`.

Note: the buffer is currently a placeholder, see the cache section in
`mcp-tools.md`.

---

## crumbs:events

Print recent in-app events dispatched through Magic's `Event` facade.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print (most-recent N; with `--since`, the oldest N after it). |
| `--since=<atUs>` | (none) | Only records whose `atUs` (microseconds) is greater than this. |
| `--type=<prefix>` | (none) | Only event types that start with this prefix. |
| `--json` | off | Print one JSON object per line (payload as JSON, `atUs` and `redacted` included). |
| `--follow` | off | Keep polling every second from the last cursor until interrupted. |

**VM extension:** `ext.crumbs.events`. The filters run on the app
side before `limit`.

**Output format:**

```
2026-09-28T10:00:00.000Z MonitorCreated {id: 7} listeners=2
```

`listeners=<N>` is omitted when the watcher did not record a count.

**Empty-buffer hint:** `"No event records (register MagicEventWatcher)."`
Suppressed under `--json` and `--follow`.

**Exit codes:** always `0`.

**Example:**

```bash
./bin/dowel crumbs:events --type=Auth --since=81234567 --json
```

---

## crumbs:gates

Print recent Gate authorization checks.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.crumbs.gates`.

**Output format:**

```
2026-09-28T10:00:00.000Z monitors.update denied user=3 arguments=[Monitor]
```

`user=<id>` is omitted when no user was authenticated at check time.

**Empty-buffer hint:** `"No gate records (register MagicGateWatcher)."`

**Exit codes:** always `0`.

---

## crumbs:dumps

Print recent `debugPrint` output.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--limit=<N>` | `50` | Max records to print. |

**VM extension:** `ext.crumbs.dumps`.

**Output format:**

```
2026-09-28T10:00:00.000Z poller tick 3
```

**Empty-buffer hint:** `"No dump records (install DumpWatcher in debug mode)."`

**Exit codes:** always `0`.

---

## crumbs:clear

Wipe all 10 ring buffers atomically.

**Flags:** none.

**VM extension:** `ext.crumbs.clear`.

**Output:**

```
Cleared crumbs buffers.
```

**Exit codes:** always `0`. Idempotent.

---

## crumbs:files

List the timeline files of the running app's `CrumbsFileSink`, or print
the lines of one. Reads through `ext.crumbs.files` and
`ext.crumbs.file`, so a name is only ever one the sink listed.

**Flags:**

| Flag | Default | Help |
|---|---|---|
| `--name=<file>` | (none) | Print the lines of this file, as listed, instead of the list. |
| `--offset=<n>` | `0` | Byte offset to start reading from: `0` or a previous `next`. |

**VM extensions:** `ext.crumbs.files` (`{files: [{name, bytes}]}`, newest
first, earlier launches included) and `ext.crumbs.file`
(`{lines, next}`, whole lines within 64 KiB of the offset).

**Output format:** the list prints one `<name> <bytes>` line per file:

```
timeline-20261010T091500Z-1.jsonl 4096
timeline-20261010T091500Z-0.jsonl 1048512
```

With `--name`, it prints each JSONL line as stored
(`{"kind":"log",...}`), then `next offset: <n>` at `-v` only. Pass that
number as `--offset` to continue; at the end of the file no lines print
and `next` equals the offset.

**Empty hint:** `"No timeline files."` (warning, exit 0).

**Errors:** when no sink runs the command prints the extension's message
(`No timeline file sink is running.`) and exits `1`, not a stack. A name
the sink did not list, a negative offset or a bad `maxBytes` all answer
one fixed message (`Unknown timeline file, or offset or maxBytes out of
range.`), exit `1`.

**Example:**

```bash
./bin/dowel crumbs:files
./bin/dowel crumbs:files --name=timeline-20261010T091500Z-0.jsonl -v
```

---

## Why exceptions is MCP-only

V1 ships 11 CLI commands and 10 MCP tools. `exceptions` is the one buffer
without a `crumbs:*` mirror: its records carry full stack traces that do
not fit a single line. From a shell, `tapir:exceptions` reads the same buffer.

---

## Common output behaviour

- **Boot mode `connected`:** all read commands wait for the running
  app's VM Service before issuing the extension call. If the app is
  not running, the command exits with a "VM Service URI absent" error
  and a non-zero status from the substrate wrapper.

- **Always exit 0 on read commands:** even with an empty buffer or a
  hint message; the human-facing wording signals the cause. Scripting
  against an empty buffer must grep the output, not the exit code.

- **JSON only where asked.** `crumbs:tail` and `crumbs:events`
  print JSON lines with `--json`; every other command prints formatted
  text. Use the MCP tools when the agent needs structured data from the
  other buffers. `--follow` (tail, events) polls until the process is
  interrupted, so run it in the background or under a timeout. The
  loop behind it, `followCursor`, is exported from
  `package:crumbs/cli.dart`.

- **Stale AOT recovery.** If `./bin/dowel crumbs:<cmd>` deadlocks on
  the lock file, run `rm -rf .dowel/.dowel.lock && ./bin/dowel list` to
  reclaim. The lock is PID-aware in current builds and should not
  normally need manual intervention.

- **Fallback when AOT is broken.** `dart run crumbs
  crumbs:<cmd>` reaches the same providers but boots in ~3s
  instead of ~110ms; use it during install or when the AOT bundle is
  stale.
