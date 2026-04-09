package gateway

import (
	"context"
	"net/http"
	"strings"

	"github.com/absgrafx/nodeneo/internal/store"
)

type ctxKey int

const ctxKeyInfo ctxKey = iota

func apiKeyFromContext(ctx context.Context) (store.APIKeyInfo, bool) {
	v, ok := ctx.Value(ctxKeyInfo).(store.APIKeyInfo)
	return v, ok
}

// authMiddleware validates Bearer tokens against the store.
func (g *Gateway) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing Authorization header"})
			return
		}

		rawKey := strings.TrimPrefix(auth, "Bearer ")
		if rawKey == auth {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "expected Bearer token"})
			return
		}
		rawKey = strings.TrimSpace(rawKey)

		info, ok, err := g.store.ValidateAPIKey(rawKey)
		if err != nil {
			g.log("auth error: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal auth error"})
			return
		}
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid API key"})
			return
		}

		go func() { _ = g.store.UpdateAPIKeyLastUsed(info.ID) }()

		ctx := context.WithValue(r.Context(), ctxKeyInfo, info)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
