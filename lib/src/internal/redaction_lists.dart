/// Library-internal hidden-name lists behind [CrumbsRedaction].
///
/// Kept here (like `http_adapter_registry.dart`) so [CrumbsStore.resetForTesting]
/// can restore them from library code without calling a `@visibleForTesting`
/// member. Not exported from the public barrel. Every entry is lowercased.
library;

// Laravel's defaults (`authorization`, `php-auth-pw`) widened to the headers
// a Flutter client actually sends a credential in: proxy auth, cookies (a
// session is a credential) and the common API-key header. `php-auth-pw` is a
// PHP server variable, never a client header.
const Set<String> defaultHiddenRequestHeaders = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
};

// Laravel hides `password` and `password_confirmation`; the rest are the
// names a Fortify-style password change, two-factor challenge
// (`two_factor_token`, `recovery_code`), OAuth or social login
// (`authorization_code`, `id_token`), an API key and a signed or presigned
// URL (`signature`, `sig`, the `x-amz-*` credentials) send a credential
// under. The same set masks the request URL's query, where a callback or a
// presigned link carries them. Kept to names that are credentials in
// practice, so a debugging agent still sees the ordinary fields of a
// request. A one-time `code` is left visible: the name is too generic to
// hide.
const Set<String> defaultHiddenRequestParameters = <String>{
  'password',
  'password_confirmation',
  'current_password',
  'new_password',
  'token',
  'access_token',
  'refresh_token',
  'secret',
  'client_secret',
  'authorization_code',
  'id_token',
  'two_factor_token',
  'recovery_code',
  'api_key',
  'apikey',
  'signature',
  'sig',
  'x-amz-signature',
  'x-amz-credential',
  'x-amz-security-token',
};

// Laravel hides nothing in a response by default, but a response carries the
// credentials a request sends (a profile or an API-key creation answers with
// `password`, `api_key`, `signature`), so it starts from every request name.
// On top of those, a Sanctum login answers with `plain_text_token` (the
// NewAccessToken shape), and a two-factor setup with `recovery_codes` plus the
// TOTP secret three times (`secret`, and inside `qr_url` and `qr_svg`). A
// bare list of codes under `data` has no key to match and is not covered.
const Set<String> defaultHiddenResponseParameters = <String>{
  ...defaultHiddenRequestParameters,
  'plain_text_token',
  'recovery_codes',
  'qr_url',
  'qr_svg',
};

final Set<String> hiddenRequestHeaders = <String>{
  ...defaultHiddenRequestHeaders,
};

final Set<String> hiddenRequestParameters = <String>{
  ...defaultHiddenRequestParameters,
};

final Set<String> hiddenResponseParameters = <String>{
  ...defaultHiddenResponseParameters,
};

/// Restore the three lists to their defaults.
void resetRedactionLists() {
  hiddenRequestHeaders
    ..clear()
    ..addAll(defaultHiddenRequestHeaders);
  hiddenRequestParameters
    ..clear()
    ..addAll(defaultHiddenRequestParameters);
  hiddenResponseParameters
    ..clear()
    ..addAll(defaultHiddenResponseParameters);
}
