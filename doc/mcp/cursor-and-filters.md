# Cursor and filters

Follow the log and event buffers without re-reading them or skipping a record: the filters and the `cursor` of `ext.crumbs.console` and `ext.crumbs.events`, the matching CLI flags, and the `followCursor` loop.

The parameters belong to the VM Service extensions and the CLI, and the MCP tools declare them too: `crumbs_tail` takes `limit`, `level`, `logger` and `since`, and `crumbs_events` takes `limit`, `type` and `since`. The answer carries the same `cursor`.

- [Extension parameters](#extension-parameters)
- [Which records limit keeps](#which-records-limit-keeps)
- [The cursor](#the-cursor)
- [CLI](#cli)
- [followCursor](#followcursor)
- [Related Documentation](#related-documentation)

<a name="extension-parameters"></a>
## Extension parameters

All values are strings on the wire, as with every VM Service extension.

| Extension | Parameter | Meaning |
|---|---|---|
| `ext.crumbs.console` | `level` | Minimum `package:logging` level name. An unknown name matches nothing. |
| `ext.crumbs.console` | `logger` | Exact logger name. |
| `ext.crumbs.events` | `type` | Prefix of `eventType`. |
| both | `since` | Microseconds, exclusive, compared with the record's `atUs`. |
| both | `limit` | Applied after the filters. A zero or negative value returns nothing. |

A `since` that is not an integer is refused with `invalidParams` (`since must be an integer number of
microseconds.`) rather than read as "from the start", so a typo cannot return the whole buffer as if it
were new.

<a name="which-records-limit-keeps"></a>
## Which records limit keeps

The filters run first, then `limit`:

- With `since`, `limit` keeps the OLDEST N records after it. Paging by `cursor` then skips nothing. A page cut
  inside a run of records sharing one `atUs` keeps the whole run, so it may exceed `limit` by those ties.
- Without `since`, `limit` keeps the NEWEST N records that matched.

Records come back oldest first either way.

<a name="the-cursor"></a>
## The cursor

Both answers carry `cursor`: the largest `atUs` among the returned records, else the `since` you passed,
else null. Pass it back as `since` and the next answer holds only newer records.

The cursor assumes a buffer's insertion order is its `atUs` order, which holds while each record takes its `atUs` from the clock at construction. A record built with an explicit `atUs` behind one already returned sits at or before the cursor, so the next read skips it.

```json
{
  "messages": [
    {"level": "INFO", "message": "synced", "loggerName": "Sync", "atUs": 81234567, "redacted": true}
  ],
  "cursor": 81234567
}
```

`ext.crumbs.console` answers its records under `messages`, `ext.crumbs.events` under `events`.
Every other read extension keeps its own envelope and takes `limit` only.

<a name="cli"></a>
## CLI

`crumbs:tail` and `crumbs:events` expose the same parameters as flags:

| Flag | `crumbs:tail` | `crumbs:events` | Meaning |
|---|---|---|---|
| `--limit=<n>` | yes (50) | yes (50) | Records to print. |
| `--level=<name>` | yes | no | Minimum log level. |
| `--since=<atUs>` | yes | yes | Only records after this `atUs`. |
| `--logger=<name>` | yes | no | Exact logger name. |
| `--type=<prefix>` | no | yes | Event types starting with this prefix. |
| `--json` | yes | yes | One JSON object per line, the payload as JSON. |
| `--follow` | yes | yes | Keep polling until interrupted. |

`--follow` re-reads once a second from the cursor the previous read returned. After the first read it
drops `--limit`, since the cursor already bounds the read. A null cursor from an empty poll keeps the
previous one, so a quiet buffer never rewinds. Without `--json` an empty read prints the usual
empty-buffer hint; with `--json` or `--follow` it prints nothing.

```bash
./bin/dowel crumbs:tail --logger=Sync --json --follow
./bin/dowel crumbs:events --type=Auth --since=81234567
```

<a name="followcursor"></a>
## followCursor

The loop behind `--follow` is a pure Dart function, exported from `package:crumbs/cli.dart`
so a command that runs under `dart run` can build on it:

```dart
import 'package:crumbs/cli.dart' show followCursor;

/// [fetch] calls the extension with `since`; [handle] prints the answer. Both are the caller's.
Future<void> follow(
  Future<Map<String, dynamic>> Function(int? since) fetch,
  void Function(Map<String, dynamic> response) handle,
) =>
    followCursor(
      interval: const Duration(seconds: 1),
      read: (int? since) async {
        final response = await fetch(since);
        handle(response);
        return response['cursor'] as int?; // the next cursor
      },
    );
```

| Parameter | Default | Meaning |
|---|---|---|
| `read` | required | Called with the cursor the previous round returned; returns the next cursor. A null keeps the last one. |
| `since` | null | The cursor of the first round. |
| `interval` | 1 second | Wait between rounds. |
| `delay` | real clock | Replaceable wait, so a test runs the loop without a clock. |
| `shouldStop` | never | Asked after each read; the loop ends when it returns true. By default it ends only when the process does. |

<a name="related-documentation"></a>
## Related Documentation

- [Tool reference](tool-reference.md): the `crumbs_tail` and `crumbs_events` answers the cursor belongs to.
- [Buffers](../getting-started/buffers.md): the `atUs` clock and how `limit` and `minLevel` behave in the store.
- [File sink](../getting-started/file-sink.md): a timeline on disk for reads that must outlive the app.
