package gateway

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestRedactProviderEndpoints pins the redaction surface that's mirrored on
// the Flutter UI side (lib/utils/error_redaction.dart). Adding new shapes
// here without updating the Dart side (or vice versa) creates inconsistent
// error rendering between the chat UI and external API clients, so the test
// table is the contract.
func TestRedactProviderEndpoints(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "full http URL with IPv4 + port + path is replaced",
			in:   `Post "http://216.81.245.17:18788/embeddings": dial tcp 216.81.245.17:18788: connect: connection refused`,
			want: `Post "<provider endpoint>": dial tcp <provider>: connect: connection refused`,
		},
		{
			name: "https with FQDN host",
			in:   "could not connect to https://provider.mor.org:3333/v1 again",
			want: "could not connect to <provider endpoint> again",
		},
		{
			name: "bare host:port leaks too",
			in:   "dial tcp provider.example.com:36318: i/o timeout",
			want: "dial tcp <provider>: i/o timeout",
		},
		{
			name: "bare IPv4 (no port) leaks too",
			in:   "no route to host 74.48.78.46 — try again",
			want: "no route to host <provider> — try again",
		},
		{
			name: "non-matching text is untouched",
			in:   "missing Authorization header",
			want: "missing Authorization header",
		},
		{
			name: "version numbers and timestamps are NOT mistaken for IPs",
			in:   "v1.2.3 released at 12:34:56",
			want: "v1.2.3 released at 12:34:56",
		},
		{
			name: "empty input",
			in:   "",
			want: "",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := redactProviderEndpoints(tc.in)
			if got != tc.want {
				t.Errorf("\n  in:   %q\n  got:  %q\n  want: %q", tc.in, got, tc.want)
			}
		})
	}
}

// TestOpenAIErrorRedactsProviderInfo wires the redaction through the error
// envelope path that EVERY handler uses. This is the regression guard for
// the bug your curl test caught — provider IP leaking through 502 bodies.
func TestOpenAIErrorRedactsProviderInfo(t *testing.T) {
	st := testStore(t)
	gw := New(nil, st, func(string, ...interface{}) {}, 3600)

	rr := httptest.NewRecorder()
	rr.Header().Set("X-Request-Id", "req-test-redact")
	leaky := `provider request failed: failed to send request: Post "http://216.81.245.17:18788/embeddings": dial tcp 216.81.245.17:18788: connect: connection refused`
	writeOpenAIError(rr, http.StatusBadGateway, "provider_error", leaky)

	// JSON-decode the body — Go's default encoder HTML-escapes the angle
	// brackets in the placeholder, so a raw substring check on the wire
	// bytes won't see "<provider>" verbatim. Decoding gives the original
	// message content back.
	var parsed openAIErrorBody
	if err := json.NewDecoder(rr.Body).Decode(&parsed); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	msg := parsed.Error.Message

	for _, leaked := range []string{"216.81.245.17", "18788"} {
		if strings.Contains(msg, leaked) {
			t.Errorf("error message must not contain raw provider info %q\nmessage: %s", leaked, msg)
		}
	}
	if !strings.Contains(msg, "<provider endpoint>") && !strings.Contains(msg, "<provider>") {
		t.Errorf("expected at least one redaction placeholder in message: %s", msg)
	}
	if !strings.Contains(msg, "connection refused") {
		t.Errorf("redaction should preserve the underlying failure mode (connection refused): %s", msg)
	}
	if parsed.Error.RequestID != "req-test-redact" {
		t.Errorf("X-Request-Id should still surface: got %q", parsed.Error.RequestID)
	}

	// Reference the gateway so the linter doesn't complain about unused vars.
	_ = gw
}
