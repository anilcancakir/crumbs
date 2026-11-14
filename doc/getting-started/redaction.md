# Redaction

How crumbs keeps secrets out of the buffers it serves to AI agents and writes to disk: credential lists for HTTP records, and a host-supplied text redactor for every record that carries free text.

- [Credential lists (HTTP)](#credential-lists)
- [The text redactor](#the-text-redactor)
- [JSON-safe event payloads](#json-safe-event-payloads)
- [Related Documentation](#related-documentation)

<a name="credential-lists"></a>
## Credential lists (HTTP)

`CrumbsStore.recordHttp` masks credential values before it buffers a record. The request headers
`authorization`, `proxy-authorization`, `cookie`, `set-cookie` and `x-api-key`, and credential keys in a
JSON or form-encoded body (`password`, `token`, `access_token`, ...), read `********`. Names match
case-insensitively and at any depth. An empty value (null, `false`, `''`, `[]`, `{}`) stays visible.

Extend the lists with `CrumbsRedaction.hideRequestHeaders`, `hideRequestParameters` and
`hideResponseParameters`. Additions merge with the defaults and never replace them. An adapter that holds a
body as a Dart `Map` runs it through `CrumbsRedaction.redactParameters(data, keys)` or
`redactBody(body, keys)` before it stringifies or truncates it, because the store cannot mask a body it
cannot parse. The full default lists are on the [Watchers](../watchers/index.md#credential-redaction) page.

<a name="the-text-redactor"></a>
## The text redactor

`CrumbsRedaction.redactor` is a host hook, `String Function(String)?`, that is null until you set it:

```dart
CrumbsRedaction.redactor = (String text) =>
    text.replaceAll(RegExp(r'\b\d{13,19}\b'), '[card]');
```

When it is set, the store runs it at insert over every text field of a log, event, exception and HTTP
record, before the record enters its queue or its stream:

| Record | Text the redactor sees |
|---|---|
| `LogRecordEntry` | level, message, logger name, error, stack trace |
| `ExceptionRecord` | exception type, message, stack trace, isolate |
| `EventRecord` | event type, interaction fields, and every String value and every map key inside the payload's nested Maps and Lists |
| `HttpRequestRecord` | URL, method, header values, request and response body, request id, interaction fields (after the credential key masking above) |

A subtree nested past 64 levels is masked whole.

### Contract

- The redactor must be pure and total: it takes one String and returns the masked String.
- A redactor that throws drops the record. The record is neither buffered nor emitted on its stream,
  because a record that could not be masked is never let through unmasked.
- A record buffered while no redactor is registered is stored as is. Setting a redactor later does not
  rewrite what is already in the buffers.
- `CrumbsRedaction.resetForTesting()` unregisters the redactor and restores the credential lists.

### The `redacted` flag

The log, event, exception and HTTP records carry a read-only `redacted` getter, serialized in `toJson`. It
is true only for a record the store's redaction pass produced with a redactor registered. The
constructors take no `redacted` argument, and `HttpRequestRecord.copyWith` returns an unredacted copy, so
no caller can build a record that a persisting consumer would take for masked. `CrumbsFileSink` relies
on this: it writes only records whose `redacted` is true (see [File sink](file-sink.md)).

### Per-record entry points

`redactLogRecord`, `redactExceptionRecord`, `redactEventRecord` and `redactHttpRecord` apply the redactor to
one record. The store calls them; a caller outside the store rarely needs to. Each returns null for a
dropped record, so `redactHttpRecord` returns `HttpRequestRecord?` and a caller adds a null check.

<a name="json-safe-event-payloads"></a>
## JSON-safe event payloads

`recordEvent` stores any payload value that `jsonEncode` cannot write (a `DateTime`, a `Duration`, any
object) as its `toString()`, and a non-String map key likewise, so one bad payload cannot fail a whole
`ext.crumbs.events` response. A payload that is already safe keeps its identity. This runs with or
without a redactor.

<a name="related-documentation"></a>
## Related Documentation

- [File sink](file-sink.md): the timeline on disk that writes only redacted records.
- [Watchers](../watchers/index.md#credential-redaction): the default credential lists and how an HTTP adapter masks a body.
- [Tool reference](../mcp/tool-reference.md#crumbs_requests): how a masked HTTP record reads over MCP.
