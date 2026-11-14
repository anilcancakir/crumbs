# Redaction

How crumbs keeps secrets out of the buffers it serves to AI agents and writes to disk: credential name lists that mask by key, and a host-supplied text redactor for free text.

- [Credential lists](#credential-lists)
- [The text redactor](#the-text-redactor)
- [JSON-safe event payloads](#json-safe-event-payloads)
- [Related Documentation](#related-documentation)

<a name="credential-lists"></a>
## Credential lists

The store masks credential values by key before it buffers a record, always, with no host setup:

- `CrumbsStore.recordHttp`: the request headers `authorization`, `proxy-authorization`, `cookie`,
  `set-cookie` and `x-api-key`; credential keys in a JSON or form-encoded request or response body
  (`password`, `token`, `access_token`, ...; the response list is the request list plus a few names only
  a response carries, such as `plain_text_token` and `recovery_codes`); and the value of a credential-named query parameter of the URL (`access_token`,
  `api_key`, the `X-Amz-*` signature of a presigned URL, ...). The rest of the URL stays as captured.
- `CrumbsStore.recordQuery` and `recordGate`: the same request-parameter names, matched against the keys
  of the Map elements of a query's `bindings` and a gate check's `arguments`. A positional binding (the
  usual SQL shape) has no key, so only a [text redactor](#the-text-redactor) can mask it, and it sees the
  bare value.

A masked value reads `********`. Names match case-insensitively and at any depth. An empty value (null,
`false`, `''`, `[]`, `{}`) stays visible.

Free text has no keys to match: a log message, a `debugPrint` dump, the SQL of a query and a credential
written into any of them are buffered as written until the host sets a [text redactor](#the-text-redactor).
Model attributes and cache records are buffered as given.

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

When it is set, the store runs it at insert over every text field of a log, event, exception, HTTP, dump,
query and gate record, before the record enters its queue or its stream:

| Record | Text the redactor sees |
|:---|:---|
| `LogRecordEntry` | level, message, logger name, error, stack trace |
| `ExceptionRecord` | exception type, message, stack trace, isolate |
| `EventRecord` | event type, interaction fields, and every String value and every map key inside the payload's nested Maps and Lists |
| `HttpRequestRecord` | URL, method, header values, request and response body, request id, interaction fields (after the credential key masking above) |
| `DumpRecord` | the message |
| `QueryRecord` | the SQL, and every String inside the bindings (not the connection name) |
| `GateRecord` | the user id, and every String inside the arguments (not the ability) |

A subtree nested past 64 levels is masked whole.

### Contract

- The redactor must be pure and total: it takes one String and returns the masked String.
- A redactor that throws drops the record. The record is neither buffered nor emitted on its stream,
  because a record that could not be masked is never let through unmasked.
- A record buffered while no redactor is registered is stored as is. Setting a redactor later does not
  rewrite what is already in the buffers.
- `CrumbsRedaction.resetForTesting()` unregisters the redactor and restores the credential lists.

### The `redacted` flag

The log, event, exception and HTTP records carry a read-only `redacted` getter, serialised in `toJson`; the
dump, query and gate records are masked too but carry no flag, and nothing persists them. It
is true only for a record the store's redaction pass produced with a redactor registered. The
constructors take no `redacted` argument, and `HttpRequestRecord.copyWith` returns an unredacted copy, so
no caller can build a record that a persisting consumer would take for masked. `CrumbsFileSink` relies
on this: it writes only records whose `redacted` is true (see [File sink](file-sink.md)).

### Per-record entry points

`redactLogRecord`, `redactExceptionRecord`, `redactEventRecord`, `redactHttpRecord`, `redactDumpRecord`,
`redactQueryRecord` and `redactGateRecord` apply the masking its record gets (by key, by the redactor, or both) to one record. The store
calls them; a caller outside the store rarely needs to. Each returns null for a dropped record, so
`redactHttpRecord` returns `HttpRequestRecord?` and a caller adds a null check.

<a name="json-safe-event-payloads"></a>
## JSON-safe event payloads

`recordEvent` stores any payload value that `jsonEncode` cannot write (a `DateTime`, a `Duration`, `NaN`
or an infinity, any object) as its `toString()`, and a non-String map key likewise, so one bad payload
cannot fail a whole `ext.crumbs.events` response. A value whose `toString()` throws is stored as
`<unprintable Type>`, so recording never throws into the app. `recordQuery` and `recordGate` treat
bindings and arguments the same way. A payload that is already safe keeps its identity. This runs with or
without a redactor.

<a name="related-documentation"></a>
## Related Documentation

- [File sink](file-sink.md): the timeline on disk that writes only redacted records.
- [Watchers](../watchers/index.md#credential-redaction): the default credential lists and how an HTTP adapter masks a body.
- [Tool reference](../mcp/tool-reference.md#crumbs_requests): how a masked HTTP record reads over MCP.
