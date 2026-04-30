package gateway

import "regexp"

// Provider-identifying address redaction for outbound error messages.
//
// Morpheus routes requests to whichever provider wins the rated bid; their
// raw endpoint URL (often an IPv4 + port like
// `http://216.81.245.17:18788/embeddings`) leaks into upstream error
// messages whenever a provider misbehaves. Surfacing that address to
// external API clients (Cursor, Zed, generic curl scripts) gives them
// nothing actionable and exposes provider infrastructure to anyone who can
// read the response.
//
// This file is the server-side mirror of `lib/utils/error_redaction.dart`
// in the Flutter UI; both should be kept in lockstep so error text reads
// the same regardless of where it's rendered. Order of replacement
// matters: full URLs are stripped first so the host:port and bare-IP
// passes can't eat fragments of an already-cleaned URL.
//
// The patterns are deliberately conservative — RE2 has no lookbehind, so
// "near-miss" matches in free-form text are filtered with capturing
// groups + ReplaceAllStringFunc rather than zero-width assertions.

const (
	providerPlaceholder = "<provider endpoint>"
	shortPlaceholder    = "<provider>"
)

var (
	// Matches any full http/https URL whose host is an IPv4 address, an
	// IPv6 [...] literal, or an FQDN. Optional port and path. Stops at
	// whitespace, closing quotes/brackets, or trailing punctuation so we
	// don't eat the surrounding sentence.
	httpURLPattern = regexp.MustCompile(
		`(?i)https?://(?:\[[^\]\s]+\]|[A-Za-z0-9._\-]+)(?::\d+)?(?:/[^\s"\)\],;]*)?`,
	)

	// Bare host:port pairs that survived the URL pass — log fragments like
	// `dial tcp provider.example.com:36318`. Captures the boundary chars
	// so we can re-emit them (RE2 lacks lookbehind/lookahead).
	hostPortPattern = regexp.MustCompile(
		`([^A-Za-z0-9./@\-]|^)((?:[A-Za-z0-9\-]+\.)+[A-Za-z0-9\-]+:\d{2,5})([^A-Za-z0-9]|$)`,
	)

	// Bare IPv4 addresses that survived both prior passes.
	bareIPPattern = regexp.MustCompile(
		`([^\d.]|^)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})([^\d.]|$)`,
	)
)

// redactProviderEndpoints returns msg with any provider-identifying
// addresses replaced by neutral placeholders. Safe to call on any string —
// it leaves non-matching text untouched.
func redactProviderEndpoints(msg string) string {
	if msg == "" {
		return msg
	}
	out := httpURLPattern.ReplaceAllString(msg, providerPlaceholder)
	out = hostPortPattern.ReplaceAllStringFunc(out, func(m string) string {
		groups := hostPortPattern.FindStringSubmatch(m)
		if len(groups) < 4 {
			return m
		}
		return groups[1] + shortPlaceholder + groups[3]
	})
	out = bareIPPattern.ReplaceAllStringFunc(out, func(m string) string {
		groups := bareIPPattern.FindStringSubmatch(m)
		if len(groups) < 4 {
			return m
		}
		return groups[1] + shortPlaceholder + groups[3]
	})
	return out
}
