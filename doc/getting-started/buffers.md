# Buffers

How `CrumbsStore` holds records: one in-memory ring buffer per record kind, their capacities, the `atUs` clock, and what `limit` and `minLevel` return.

- [Quick Reference](#quick-reference)
- [Capacity](#capacity)
- [Monotonic timestamps](#monotonic-timestamps)
- [Reading with limit and minLevel](#reading-with-limit-and-minlevel)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Call | Effect |
|:-----|:-------|
| `CrumbsStore.setCapacity(2000)` | Caps every buffer except frame performance. |
| `CrumbsStore.setCapacity(5000, kind: CrumbsKind.logs)` | Caps one buffer. |
| `CrumbsStore.setFramePerfCapacity(7200)` | Caps the frame buffer; same as `kind: CrumbsKind.framePerf`. |
| `CrumbsStore.recentLogs(limit: 20, minLevel: 'WARNING')` | The newest 20 log records at `WARNING` or above, oldest first. |
| `CrumbsStore.clear()` | Empties every buffer. |

Each buffer is a FIFO queue: once it is over its capacity the oldest record is evicted, silently.

<a name="capacity"></a>
## Capacity

Every buffer holds 500 records by default, except frame performance, which holds 3600 (about a minute at 60fps).

```dart
CrumbsStore.setCapacity(2000); // every buffer but frame perf
CrumbsStore.setCapacity(5000, kind: CrumbsKind.logs); // one buffer
CrumbsStore.setCapacity(7200, kind: CrumbsKind.framePerf);
```

`CrumbsKind` names the buffers: `http`, `logs`, `exceptions`, `models`, `caches`, `events`, `gates`, `dumps`, `queries`, `framePerf`.

- A cap for one kind wins over the shared cap, whichever was set last. The shared call leaves a kind cap alone.
- A cap below the buffer's current length trims on the next record, not retroactively.
- A cap of zero or less keeps nothing.
- `CrumbsStore.resetForTesting()` (tests only) empties the buffers, restores both default caps, clears the per-kind caps and unregisters `CrumbsRedaction.redactor`.

<a name="monotonic-timestamps"></a>
## Monotonic timestamps

`LogRecordEntry` and `EventRecord` carry `atUs`, stamped at construction from `FlutterTimeline.now` and serialised in `toJson`, so a log line orders against an event whatever the wall clock did. `time` stays the wall-clock field for display. `atUs` is also the cursor that `ext.crumbs.console` and `ext.crumbs.events` page on (see [Cursor and filters](../mcp/cursor-and-filters.md)).

<a name="reading-with-limit-and-minlevel"></a>
## Reading with limit and minLevel

`CrumbsStore.recentX(limit:)` returns the newest `limit` records, oldest first; without `limit` it returns the whole buffer.

- A zero or negative `limit` returns an empty list.
- `recentLogs(minLevel:)` keeps records at or above the named `package:logging` level (`FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`, any case). A name that is not a level matches nothing and returns an empty list, so a typo never reads as a clean log.

<a name="related-documentation"></a>
## Related Documentation

- [Cursor and filters](../mcp/cursor-and-filters.md): `since`, `type`, `logger` and `cursor` on the read extensions.
- [Redaction](redaction.md): what the store masks before a record enters its buffer.
- [File sink](file-sink.md): a timeline on disk that outlives the in-memory buffers.
