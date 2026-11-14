# FramePerfWatcher

`FramePerfWatcher` records the build, raster and vsync cost of every drawn frame, with optional per-widget attribution, and proves the engine is still rendering.

- [Quick Reference](#quick-reference)
- [Liveness](#liveness)
- [Attribution](#attribution)
- [Clock and interaction link](#clock-and-interaction-link)
- [Registration](#registration)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Field | Value |
|:---|:---|
| Contract | `CrumbsWatcher` |
| Name | `frame_perf` |
| Auto-install | No (opt-in via `CrumbsPlugin.registerWatcher(FramePerfWatcher())`) |
| Buffer | `CrumbsKind.framePerf` (own capacity, default 3600, independent of the shared 500-entry cap) |
| VM extension | `ext.crumbs.frames` |
| CLI command | `crumbs:frames` |
| MCP tool | `crumbs_frames` |
| Opt-out | Do not register it; it is never auto-installed |

Captures per-frame performance by joining two sources the engine reports separately: frame
magnitude from `SchedulerBinding.addTimingsCallback`, and per-frame attribution drained from
`FlutterTimeline` at the end of every frame. The two arrive at different times, so the post-frame
drain parks its block map in a bounded pending map and the timings callback is the only emission
point, popping the matching map and writing one complete `FramePerfRecord` per `FrameTiming`.

`addTimingsCallback` appends to a list rather than replacing a single global slot, so there is
nothing to chain-preserve here: every other listener (sentry_flutter's among them) keeps receiving
timings while this watcher is installed.

<a name="liveness"></a>
## Liveness

A static `livenessCounter`, incremented once per drawn frame regardless of whether a measurement
session is running, is the only reliable proof the engine is rendering. It is exposed alongside
every `ext.crumbs.frames` response so a caller can tell an empty result caused by a quiet app
from one caused by a stalled engine (a backgrounded Chrome tab suspends `requestAnimationFrame`
while every other in-app health signal keeps reading healthy).

<a name="attribution"></a>
## Attribution

Attribution only flows while `FlutterTimeline.debugCollectionEnabled` is true, which a measurement
session turns on. Until then the watcher records frame magnitude alone and every record's `blocks`
map is empty. Each block entry carries `micros` (inclusive of nested children), `selfMicros`
(exclusive: `micros` minus the combined duration of directly nested children), and `count`.

<a name="clock-and-interaction-link"></a>
## Clock and interaction link

Every record carries `atUs`, a monotonic microsecond timestamp from `FlutterTimeline.now`, and the
optional `interactionId` / `linkedBy` pair that correlates it to other records captured during the
same interaction. `vsyncStartUs` (from `FrameTiming.timestampInMicroseconds(FramePhase.vsyncStart)`)
rides alongside `atUs` but its clock parity with `atUs` is NOT proven: the engine documents its
timestamp only as microseconds "from some epoch" shared across every `FrameTiming` field, and a unit
test can only inject synthetic `FrameTiming` values, never a real engine-reported one. Treat
`vsyncStartUs` vs. `atUs` comparisons as needing a driven, live-engine run to validate.

<a name="registration"></a>
## Registration

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(FramePerfWatcher()); // opt-in
}
```

`!kReleaseMode` keeps the watcher in a profile build, the build whose frame timings describe a shipped app. To leave it out, omit the `registerWatcher(FramePerfWatcher())` call. `CrumbsStore.clearFramePerf()` empties only this buffer, without touching the HTTP, log and exception history.

<a name="related-documentation"></a>
## Related Documentation

- [Tool reference](../mcp/tool-reference.md#crumbs_frames): the `crumbs_frames` input schema and output shape.
- [Watchers](index.md): every other watcher and the call-site guard.
- [Buffers](../getting-started/buffers.md): the per-kind caps, `CrumbsKind.framePerf` included.
