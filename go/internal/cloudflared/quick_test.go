package cloudflared

import "testing"

func TestLocalHTTPOrigin(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"127.0.0.1:8069", "http://127.0.0.1:8069"},
		{"0.0.0.0:8083", "http://127.0.0.1:8083"},
	}
	for _, tc := range tests {
		got, err := LocalHTTPOrigin(tc.in)
		if err != nil {
			t.Fatalf("%q: %v", tc.in, err)
		}
		if got != tc.want {
			t.Errorf("%q: got %q want %q", tc.in, got, tc.want)
		}
	}
}

func TestTryCloudflareRegex(t *testing.T) {
	line := `|  https://abc-def-123.trycloudflare.com                                           |`
	if g := tryCloudflareURL.FindString(line); g != "https://abc-def-123.trycloudflare.com" {
		t.Fatalf("got %q", g)
	}
}
