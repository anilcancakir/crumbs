# Security Policy

## Supported Versions

Only the latest published version receives fixes.

## Reporting a Vulnerability

Report it through GitHub's private vulnerability reporting:
**[Open a private vulnerability report](https://github.com/anilcancakir/crumbs/security/advisories/new)**

The report stays confidential until a fix is ready. Include the affected version, the platform, and the steps to reproduce.

## Scope

This policy covers the `crumbs` package: `CrumbsPlugin`, the watchers and adapters, the credential redaction, the JSONL file sink, the `ext.crumbs.*` VM Service extensions, the `crumbs:*` CLI commands, the `crumbs_*` MCP tools and the `install.yaml` manifest. Issues in `dowel`, the Flutter SDK and the Dart VM Service belong to their maintainers.

crumbs is a development tool. It records HTTP traffic, logs, exceptions, queries and events from a running app and serves them over the VM Service, so anyone who can reach the VM Service of an app that has crumbs installed can read what it captured. Masking happens before a record is buffered, in two layers:

- By key, always on: the values of credential request headers (`Authorization`, `Cookie` and the like), of credential keys in a JSON or form-encoded request or response body, of credential parameters in the request URL's query (`access_token`, `api_key`, the `X-Amz-*` signature of a presigned URL and the like), and of credential keys inside the structured fields of a query (`bindings`) and a gate check (`arguments`). The name lists are extended through `CrumbsRedaction.hide*`.
- Free text, only when the host registers `CrumbsRedaction.redactor`: log messages, exception messages and stacks, event payloads, the URL, header values and bodies of an HTTP record, dump messages, query SQL and the strings inside bindings and arguments. Without a redactor, a credential written into free text (a log line, a `debugPrint`, a literal in the SQL) is buffered as written.

Model and cache records are buffered as given. The file sink writes only log, event and exception records a redactor ran over. Whatever is masked, the VM Service must never be exposed beyond the machine that runs the app. Install crumbs only behind `if (kDebugMode)` or `if (!kReleaseMode)`, and never ship a release build that registers `ext.crumbs.*`. `--dart-define=CRUMBS_DISABLE=1` makes `CrumbsPlugin.install()` skip registration in a build that must not expose the extensions. A report that needs a debug build with the VM Service reachable by the attacker describes the intended trust boundary, not a vulnerability; one that shows a credential in a buffer or in the file sink that one of the layers above should have masked, or an extension reachable in a release build, is in scope.
