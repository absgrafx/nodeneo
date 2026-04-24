/// Redact provider-identifying addresses from user-facing error text.
///
/// Morpheus routes requests to whichever provider wins the rated bid, and
/// their endpoint URL (often a raw IPv4 + port, e.g.
/// `http://74.48.78.46:36318/v1/chat/completions`) leaks into the Go
/// bridge's error messages when a provider misbehaves. Surfacing that
/// address in the UI gives end users nothing actionable and exposes the
/// provider's infrastructure to anyone reading over their shoulder.
///
/// This module replaces those addresses with a neutral placeholder while
/// leaving the rest of the error intact so the underlying failure mode
/// (timeout / EOF / HTTP status) is still legible.
library;

/// Default placeholder substituted for any redacted address.
const String _providerPlaceholder = '<provider endpoint>';
const String _shortPlaceholder = '<provider>';

/// Matches any full `http://…` / `https://…` URL regardless of whether the
/// host is an IPv4 address, an IPv6 `[…]` literal, or an FQDN like
/// `provider.example.com`. Optional port, optional path, stops at
/// whitespace, closing quotes/brackets, or a trailing comma/semicolon so
/// we don't eat the surrounding sentence.
final RegExp _httpUrlPattern = RegExp(
  r'https?://'
  r'(?:\[[^\]\s]+\]|[A-Za-z0-9._\-]+)' // [ipv6] OR ipv4/fqdn host
  r'(?::\d+)?' // optional :port
  r'(?:/[^\s"\)\],;]*)?', // optional /path
  caseSensitive: false,
);

/// Matches a `host:port` pair that's *not* part of a URL we already
/// redacted — covers log-style fragments like `connecting to
/// provider.example.com:36318`. Host may be FQDN or IPv4; we refuse to
/// match short bare words by requiring at least one dot in the host.
final RegExp _hostPortPattern = RegExp(
  r'(?<![A-Za-z0-9./@\-])'
  r'(?:[A-Za-z0-9\-]+\.)+[A-Za-z0-9\-]+'
  r':\d{2,5}'
  r'(?![A-Za-z0-9])',
);

/// Bare IPv4 addresses that survived the URL + host:port passes.
/// (We intentionally do not redact bare FQDNs — too many false positives
/// in free-form error text; anything worth hiding nearly always shows up
/// inside a URL or host:port.)
final RegExp _bareIpPattern = RegExp(
  r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])',
);

/// Returns [raw] with any provider endpoints (full URLs, `host:port`
/// pairs, bare IPv4 addresses) replaced by neutral placeholders. Safe to
/// call on any string — it leaves non-matching text untouched.
///
/// Order is important: full URLs are stripped first so the subsequent
/// host-level rules can't eat pieces of a URL that were already cleaned.
String redactProviderEndpoints(String raw) {
  if (raw.isEmpty) return raw;
  var out = raw;
  out = out.replaceAll(_httpUrlPattern, _providerPlaceholder);
  out = out.replaceAll(_hostPortPattern, _shortPlaceholder);
  out = out.replaceAll(_bareIpPattern, _shortPlaceholder);
  return out;
}
