# Quickstart

Take a fresh Flutter project from zero to an AI agent reading the app's logs, HTTP traffic and exceptions through the `crumbs_*` MCP tools.

Prerequisites: Dart 3.13 and Flutter 3.47 or newer, and a Flutter project (a plain `flutter create` output works). `dowel` comes with crumbs, and `crumbs:install` scaffolds its harness on the first run.

- [Install crumbs](#install-crumbs)
- [Start the app and generate traffic](#start-the-app)
- [Read the buffers from the CLI](#read-from-the-cli)
- [Read the buffers from an agent](#read-from-an-agent)
- [Related Documentation](#related-documentation)

<a name="install-crumbs"></a>
## Install crumbs

```bash
flutter pub add crumbs
dart run crumbs crumbs:install
```

The installer scaffolds the dowel harness when it is missing, registers crumbs as a dowel plugin and patches `lib/main.dart` with an `!kReleaseMode` block that installs crumbs with the exception and dump watchers. On a Magic app with a `magic_devtools` release built on crumbs it also wires `MagicCrumbsIntegration.install()` after `Magic.init()`; see [Installation](installation.md#run-the-installer) for every step.

From here on the fast launcher `./bin/dowel` runs every command; `dart run crumbs <command>` is the slower equivalent that needs no build. Confirm the plugin registered:

```bash
./bin/dowel list
```

The output lists the `crumbs:` namespace.

<a name="start-the-app"></a>
## Start the app and generate traffic

```bash
./bin/dowel start --device=chrome
```

dowel starts `flutter run`, records the VM Service URI of the session, and every `crumbs:*` command and `crumbs_*` tool dials that session.

Use the app. On a vanilla app, `package:logging` records fill the log buffer and `debugPrint` calls the dump buffer; on a Magic app, HTTP calls through the `Http` facade, model saves, cache reads and gate checks land in their buffers too. To produce records on purpose, from anywhere in the app:

```dart
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

void emitSampleRecords() {
  Logger('Quickstart').info('quickstart test log'); // a log record
  debugPrint('quickstart test dump'); // a dump record
}
```

<a name="read-from-the-cli"></a>
## Read the buffers from the CLI

```bash
./bin/dowel crumbs:tail --level=INFO
./bin/dowel crumbs:dumps
./bin/dowel crumbs:requests --limit=10
./bin/dowel crumbs:clear
```

Each read command prints the newest records, oldest first (`--limit` defaults to 50). `crumbs:clear` empties every buffer, so the next read holds only what happens after it. `crumbs:tail --follow` keeps printing new log lines until you stop it.

<a name="read-from-an-agent"></a>
## Read the buffers from an agent

Write the MCP entry and reconnect the client:

```bash
dart run crumbs mcp:install
```

In Claude Code, run `/mcp reconnect dowel`; the `crumbs_*` tools appear next to the `dowel_*` tools. A typical inspection:

```text
crumbs_clear {}
# exercise the feature
crumbs_tail {"level": "WARNING", "limit": 20}
crumbs_requests {}
crumbs_exceptions {}
```

`crumbs_tail` returns log records at or above the level, `crumbs_requests` every captured HTTP request with its status, duration and masked headers, and `crumbs_exceptions` the uncaught errors with their stack traces. Every tool reads an `ext.crumbs.*` extension in the running app; the buffers fill passively, so nothing in the app changes between reads.

<a name="related-documentation"></a>
## Related Documentation

- [Installation](installation.md): manual wiring, the Magic integration and a Dio interceptor.
- [Watchers](../watchers/index.md): which watchers are opt-in and how they chain to Sentry and Bugsnag.
- [Tool reference](../mcp/tool-reference.md): every tool's input and output shape.
- [Redaction](redaction.md), [File sink](file-sink.md) and [Cursor and filters](../mcp/cursor-and-filters.md): mask secrets, keep a timeline on disk, and follow a buffer.
