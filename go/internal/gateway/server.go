package gateway

import (
	"context"
	"fmt"
	"net/http"
	"sync"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	"github.com/absgrafx/nodeneo/internal/store"
)

// Gateway is an OpenAI-compatible HTTP API server that sits on top of
// the proxy-router SDK, providing automatic model resolution and session
// management for external consumers like Cursor.
type Gateway struct {
	sdk             *sdk.SDK
	store           *store.Store
	log             func(format string, args ...interface{})
	sessionDuration int64 // seconds

	server *http.Server
	addr   string
	mu     sync.Mutex

	// Maps external X-Chat-Id → internal conversation ID for multi-turn reuse.
	chatIDMap map[string]string
	convMu    sync.Mutex

	modelCache modelsCache
}

func New(s *sdk.SDK, st *store.Store, logFn func(string, ...interface{}), sessionDurationSec int64) *Gateway {
	if sessionDurationSec <= 0 {
		sessionDurationSec = 3600
	}
	return &Gateway{
		sdk:             s,
		store:           st,
		log:             logFn,
		sessionDuration: sessionDurationSec,
		chatIDMap:       make(map[string]string),
	}
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
	mux.Handle("/v1/models", authed(http.HandlerFunc(g.handleModels)))
	mux.HandleFunc("/health", g.handleHealth)

	handler := g.requestLogger(g.corsMiddleware(mux))

	g.server = &http.Server{
		Addr:         address,
		Handler:      handler,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 5 * time.Minute, // streaming responses can be long
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

// requestLogger logs every inbound request for debugging.
func (g *Gateway) requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		g.log("%s %s → %d (%s)", r.Method, r.URL.Path, sw.status, time.Since(start).Round(time.Millisecond))
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
