package gateway

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"sync"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	"github.com/absgrafx/nodeneo/internal/store"
)

type ctxKeyRequestID struct{}

// requestIDFromContext returns the X-Request-Id assigned to the current
// request, or "" if not present.
func requestIDFromContext(ctx context.Context) string {
	if v, ok := ctx.Value(ctxKeyRequestID{}).(string); ok {
		return v
	}
	return ""
}

func newRequestID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("req-%d", time.Now().UnixNano())
	}
	return "req-" + hex.EncodeToString(b[:])
}

// Gateway is an OpenAI-compatible HTTP API server that sits on top of
// the proxy-router SDK, providing automatic model resolution and session
// management for external consumers like Cursor.
type Gateway struct {
	sdk *sdk.SDK
	store *store.Store
	log   func(format string, args ...interface{})

	// fallbackSessionDuration is used when the store has no user preference.
	// Per-request resolution of the actual duration goes through
	// resolveSessionDuration() so changes to the user's preference take effect
	// for the next session open without a gateway restart.
	fallbackSessionDuration int64

	server *http.Server
	addr   string
	mu     sync.Mutex

	// Maps external X-Chat-Id → internal conversation ID for multi-turn reuse.
	chatIDMap map[string]string
	convMu    sync.Mutex

	modelCache modelsCache
}

// sessionDurationPrefKey is the SQLite preferences row that the Flutter UI
// reads/writes via SessionDurationStore (lib/services/session_duration_store.dart).
// The gateway uses the same key so changing Settings → Preferences → Default
// session length affects API-driven sessions too.
const sessionDurationPrefKey = "session_duration_seconds"

// minSessionDurationSeconds matches the floor enforced by the Flutter UI
// (SessionDurationStore.minSeconds) — anything shorter is rejected by the
// session-open contract anyway.
const minSessionDurationSeconds = 600

func New(s *sdk.SDK, st *store.Store, logFn func(string, ...interface{}), sessionDurationSec int64) *Gateway {
	if sessionDurationSec <= 0 {
		sessionDurationSec = 3600
	}
	return &Gateway{
		sdk:                     s,
		store:                   st,
		log:                     logFn,
		fallbackSessionDuration: sessionDurationSec,
		chatIDMap:               make(map[string]string),
	}
}

// resolveSessionDuration returns the session length to stake when the gateway
// opens a new on-chain session, in seconds. It reads the same preferences row
// the UI writes to (`session_duration_seconds`) so users get one knob for both
// surfaces. Falls back to the constructor-provided default if the preference
// is missing, malformed, or below the network minimum.
func (g *Gateway) resolveSessionDuration() int64 {
	if g.store != nil {
		if raw, err := g.store.GetPreference(sessionDurationPrefKey); err == nil && raw != "" {
			var sec int64
			if _, err := fmt.Sscanf(raw, "%d", &sec); err == nil && sec >= minSessionDurationSeconds {
				return sec
			}
		}
	}
	if g.fallbackSessionDuration >= minSessionDurationSeconds {
		return g.fallbackSessionDuration
	}
	return minSessionDurationSeconds
}

// Start launches the gateway HTTP server on the given address (e.g. "127.0.0.1:8083").
func (g *Gateway) Start(address string) error {
	g.mu.Lock()
	defer g.mu.Unlock()

	if g.server != nil {
		return fmt.Errorf("gateway already running on %s", g.addr)
	}

	mux := http.NewServeMux()

	authed := g.authMiddleware

	mux.Handle("/v1/chat/completions", authed(http.HandlerFunc(g.handleChatCompletions)))
	mux.Handle("/v1/completions", authed(http.HandlerFunc(g.handleCompletions)))
	mux.Handle("/v1/embeddings", authed(http.HandlerFunc(g.handleEmbeddings)))
	mux.Handle("/v1/models", authed(http.HandlerFunc(g.handleModels)))
	mux.HandleFunc("/health", g.handleHealth)

	handler := g.requestIDMiddleware(g.requestLogger(g.corsMiddleware(mux)))

	g.server = &http.Server{
		Addr:    address,
		Handler: handler,
		// Agent-mode IDE clients (Cursor, Zed, Claude Desktop) commonly POST
		// large bodies — full file contents, repo context, multi-megabyte tool
		// schemas, and accumulated tool-call histories. ReadHeaderTimeout
		// guards against slowloris on the headers; ReadTimeout/WriteTimeout
		// match each other so a long, valid request can stream both ways.
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       5 * time.Minute,
		WriteTimeout:      5 * time.Minute,
	}
	g.addr = address

	errCh := make(chan error, 1)
	go func() {
		g.log("Gateway listening on %s", address)
		if err := g.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			g.log("Gateway error: %v", err)
			errCh <- err
		}
	}()

	// Brief wait to catch immediate bind errors
	select {
	case err := <-errCh:
		g.server = nil
		g.addr = ""
		return err
	case <-time.After(100 * time.Millisecond):
		return nil
	}
}

// Stop shuts down the gateway HTTP server.
func (g *Gateway) Stop() error {
	g.mu.Lock()
	defer g.mu.Unlock()

	if g.server == nil {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	err := g.server.Shutdown(ctx)

	g.server = nil
	g.addr = ""
	g.log("Gateway stopped")
	return err
}

// Addr returns the listen address, or "" if not running.
func (g *Gateway) Addr() string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.addr
}

// Running reports whether the server is active.
func (g *Gateway) Running() bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.server != nil
}

// requestIDMiddleware ensures every request has an X-Request-Id, using the
// caller-supplied value when present and minting a new one otherwise. The id
// is echoed back on the response so SDK consumers (and Sentry/Datadog-style
// loggers) can correlate logs across machines, and stashed on the request
// context so handlers can include it in their own log lines.
func (g *Gateway) requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if id == "" {
			id = newRequestID()
		}
		w.Header().Set("X-Request-Id", id)
		ctx := context.WithValue(r.Context(), ctxKeyRequestID{}, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// requestLogger logs every inbound request for debugging.
func (g *Gateway) requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		reqID := requestIDFromContext(r.Context())
		if reqID != "" {
			g.log("[%s] %s %s → %d (%s)", reqID, r.Method, r.URL.Path, sw.status, time.Since(start).Round(time.Millisecond))
		} else {
			g.log("%s %s → %d (%s)", r.Method, r.URL.Path, sw.status, time.Since(start).Round(time.Millisecond))
		}
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (w *statusWriter) WriteHeader(code int) {
	if !w.wrote {
		w.status = code
		w.wrote = true
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// corsMiddleware adds permissive CORS headers for local/LAN use.
func (g *Gateway) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Chat-Id, X-Request-Id")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
