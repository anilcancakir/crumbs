# File sink

`CrumbsFileSink` keeps a timeline on disk that outlives the in-memory buffers: a rotating set of JSONL files of the redacted log, event and exception records, read back through the VM Service, `crumbs:files`, or any tool that reads the directory.

The package looks up no directory. The host passes one, so it chooses where the files live (an app support directory, a temp directory, a path inside a test sandbox). The sink writes through `dart:io`, so it is not available on the web.

- [Start and stop](#start-and-stop)
- [What is written](#what-is-written)
- [Fail closed](#fail-closed)
- [Write failures](#write-failures)
- [Reading it back](#reading-it-back)
- [Related Documentation](#related-documentation)

<a name="start-and-stop"></a>
## Start and stop

```dart
import 'package:crumbs/crumbs.dart';

Future<void> startTimeline(String supportPath, String Function(String) maskSecrets) async {
  CrumbsRedaction.redactor = maskSecrets; // required, see "Fail closed"
  CrumbsPlugin.install();
  await CrumbsFileSink.start(
    directory: '$supportPath/crumbs',
    maxFileBytes: 1048576, // default: 1 MiB per file
    maxFiles: 8, // default: keep 8 timeline files
  );
}
```

| Member | Meaning |
|---|---|
| `CrumbsFileSink.start({required directory, maxFileBytes = 1048576, maxFiles = 8})` | Creates the directory, opens the first file, subscribes to the store, and returns the running sink. A sink already running is stopped first. Throws a `FileSystemException` when the directory or first file cannot be created; the sink then neither listens nor becomes current. |
| `CrumbsFileSink.current` | The running sink, or null. |
| `files()` | `[{name, bytes}]` for every timeline file in the directory, earlier launches included, newest first. |
| `read(name, {offset = 0, maxBytes = 65536})` | Whole lines of one file as `{lines, next}`. Null when refused. |
| `flush()` | Writes the batched lines now. Throws a `FileSystemException` when the write fails. |
| `stop()` | Flushes, closes the file, and clears `current`. Safe to call twice. |
| `droppedUnredacted` | Count of records refused because `redacted` was false. |
| `writeFailures` | Count of background batch writes that failed. |

`maxFileBytes` must be at least 1 and `maxFiles` at least 1. A single line larger than `maxFileBytes` still
gets a file of its own.

<a name="what-is-written"></a>
## What is written

Every record from `onLogRecord`, `onEventRecord` and `onExceptionRecord` becomes one line:

```json
{"kind": "log", "level": "INFO", "message": "...", "atUs": 81234567, "redacted": true}
```

`kind` is `log`, `event` or `exception`; the rest is the record's `toJson()`. Lines are batched and written
at 64 lines or 500 ms, whichever comes first. A new file starts before a line would pass `maxFileBytes`.
Files are named `timeline-<launch stamp>-<n>.jsonl`, where the stamp is the UTC launch time
(`yyyyMMddTHHmmssZ`) and `n` counts rotations within the launch. After each rotation the sink deletes the
oldest timeline files in the directory beyond `maxFiles`, earlier launches included. It only ever touches
names its own pattern produces.

The stamp has second precision, so a sink started again within the same second (a restart, or `start()` while
one runs) names the file of the sink it replaced. The new sink appends to that file and counts its existing
bytes toward `maxFileBytes`; it never truncates it.

<a name="fail-closed"></a>
## Fail closed

The sink writes only redacted records. A record whose `redacted` flag is false, which means it was buffered
while no `CrumbsRedaction.redactor` was registered, is never written and is counted in
`droppedUnredacted`. Register the redactor before the sink starts (see [Redaction](redaction.md)); with
none registered the sink stays empty and the counter climbs.

<a name="write-failures"></a>
## Write failures

A batch write that no caller awaits (the 64-line or 500 ms flush) and that fails does not raise into the
zone, where an exception watcher would record it and the sink would accept that record in turn. The sink
counts the failure in `writeFailures`, stops writing, and is no longer `current`. Start it again once the
cause is fixed. A failure inside an awaited `flush()` is thrown to the caller instead.

<a name="reading-it-back"></a>
## Reading it back

`files()` and `read()` expose the timeline files in the directory and nothing else. `read` compares `name`
against the files `files()` lists before it ever builds a path, so a path, a `..` segment, a link, or any
other file in the directory reaches nothing: the answer is null.

`read` returns whole lines within `maxBytes` of `offset`, without their newline, and `next`, the offset to
pass to continue. A line longer than `maxBytes` is returned whole. At the end of a file `lines` is empty and
`next` equals `offset`. A negative `offset` or a `maxBytes` below 1 is refused. An `offset` inside a
multi-byte character decodes the cut bytes as U+FFFD rather than throwing. Both calls flush first, so a
read sees every accepted line.

### VM extensions

| Extension | Params | Answer |
|---|---|---|
| `ext.crumbs.files` | none | `{files: [{name, bytes}]}`, newest first |
| `ext.crumbs.file` | `name`, `offset` (default 0), `maxBytes` (default 65536) | `{lines, next}` |

Both answer `{error: "No timeline file sink is running."}` when `CrumbsFileSink.current` is null.
`ext.crumbs.file` answers one fixed `{error}` message for every refusal (unknown name, bad offset, bad
`maxBytes`), so the answer leaks nothing about the file system. The extensions have no MCP tool; reach them
through the CLI or the VM service directly.

### CLI

```bash
./bin/dowel crumbs:files                       # list: "<name> <bytes>" per line
./bin/dowel crumbs:files --name=timeline-20261010T091500Z-0.jsonl
./bin/dowel crumbs:files --name=<file> --offset=<next>
```

| Option | Default | Meaning |
|---|---|---|
| `--name=<file>` | none | Print the lines of this file, as listed, instead of the list. |
| `--offset=<n>` | `0` | Byte offset to start from: 0 or a previous `next`. |

Printing a file ends with `next offset: <n>`, shown at `-v` only, so pass `-v` to page through a long file.
An empty directory prints `No timeline files.` and exits 0. When no sink runs the command prints the
extension's error message, not a stack, and exits 1.

<a name="related-documentation"></a>
## Related Documentation

- [Redaction](redaction.md): the redactor the sink depends on, and the `redacted` flag.
- [Buffers](buffers.md): the in-memory buffers the sink subscribes to.
- [Cursor and filters](../mcp/cursor-and-filters.md): follow a buffer live instead of reading a file.
