package gateway

import (
	"context"
	"fmt"
	"strings"
	"time"
)

type sessionResult struct {
	SessionID string
	ModelID   string
	ModelName string
}

// resolveSession mirrors the Flutter ChatScreen._openSessionAndPersist logic:
// 1. Resolve model name → blockchain ID
// 2. Search unclosed sessions for a match
// 3. Open a new session if none found
func (g *Gateway) resolveSession(ctx context.Context, modelNameOrID string) (sessionResult, error) {
	modelID, err := g.sdk.ResolveModelID(ctx, modelNameOrID)
	if err != nil {
		return sessionResult{}, fmt.Errorf("resolve model %q: %w", modelNameOrID, err)
	}

	// Find canonical name for display
	modelName := modelNameOrID
	models, _ := g.sdk.GetAllModels(ctx)
	for _, m := range models {
		if strings.EqualFold(m.ID, modelID) {
			modelName = m.Name
			break
		}
	}

	sessID, err := g.findExistingSession(ctx, modelID)
	if err == nil && sessID != "" {
		return sessionResult{SessionID: sessID, ModelID: modelID, ModelName: modelName}, nil
	}

	sessID, err = g.sdk.OpenSession(ctx, modelID, g.sessionDuration, false)
	if err != nil {
		return sessionResult{}, fmt.Errorf("open session for model %q: %w", modelNameOrID, err)
	}

	return sessionResult{SessionID: sessID, ModelID: modelID, ModelName: modelName}, nil
}

// findExistingSession scans unclosed on-chain sessions for one matching the model.
// Same logic as mobile.ReusableSessionForModel.
func (g *Gateway) findExistingSession(ctx context.Context, modelID string) (string, error) {
	sessions, err := g.sdk.GetUnclosedUserSessions(ctx)
	if err != nil {
		return "", err
	}

	normalizedModel := normalizeHex(modelID)
	now := time.Now().Unix()

	for _, s := range sessions {
		if normalizeHex(s.ModelAgentID) != normalizedModel {
			continue
		}
		if endsAt := parseEndsAt(s.EndsAt); endsAt > 0 && endsAt <= now {
			continue
		}
		return s.ID, nil
	}
	return "", fmt.Errorf("no open session for model %s", modelID)
}

func normalizeHex(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = strings.TrimPrefix(s, "0x")
	return s
}

func parseEndsAt(s string) int64 {
	if s == "" {
		return 0
	}
	// Try unix timestamp first
	var ts int64
	if _, err := fmt.Sscanf(s, "%d", &ts); err == nil && ts > 0 {
		return ts
	}
	// Try RFC3339
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t.Unix()
	}
	return 0
}

// modelInfo returns (modelID, modelName) for a given name-or-ID.
func (g *Gateway) modelInfo(ctx context.Context, nameOrID string) (id, name string) {
	resolved, err := g.sdk.ResolveModelID(ctx, nameOrID)
	if err != nil {
		return nameOrID, nameOrID
	}
	models, _ := g.sdk.GetAllModels(ctx)
	for _, m := range models {
		if strings.EqualFold(m.ID, resolved) {
			return resolved, m.Name
		}
	}
	return resolved, nameOrID
}

