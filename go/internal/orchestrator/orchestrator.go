package orchestrator

import (
	"context"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/absgrafx/redpill/internal/core"
	"github.com/absgrafx/redpill/internal/store"
)

const modelCacheTTL = 60 * time.Second

// Orchestrator provides consumer-friendly operations on top of the raw
// proxy-router engine. Consolidates multi-step workflows (like the API
// Gateway does) without multi-user/billing overhead.
type Orchestrator struct {
	engine *core.Engine
	store  *store.Store

	mu          sync.RWMutex
	modelCache  []core.Model
	modelExpiry time.Time
}

func New(engine *core.Engine, store *store.Store) *Orchestrator {
	return &Orchestrator{
		engine: engine,
		store:  store,
	}
}

// ActiveModels returns currently active (non-deleted) models, cached
// for modelCacheTTL. LLM models are sorted first, then alphabetically.
// If teeOnly is true, only models with a "tee" tag are returned.
func (o *Orchestrator) ActiveModels(ctx context.Context, teeOnly bool) ([]core.Model, error) {
	o.mu.RLock()
	if time.Now().Before(o.modelExpiry) && len(o.modelCache) > 0 {
		cached := o.modelCache
		o.mu.RUnlock()
		return filterModels(cached, teeOnly), nil
	}
	o.mu.RUnlock()

	all, err := o.engine.ListModels(ctx)
	if err != nil {
		return nil, err
	}

	active := make([]core.Model, 0, len(all))
	for _, m := range all {
		if !m.IsDeleted {
			active = append(active, m)
		}
	}

	sort.Slice(active, func(i, j int) bool {
		iTEE := hasTEETag(active[i].Tags)
		jTEE := hasTEETag(active[j].Tags)
		if iTEE != jTEE {
			return iTEE
		}
		if active[i].ModelType != active[j].ModelType {
			return active[i].ModelType == "LLM"
		}
		return active[i].Name < active[j].Name
	})

	o.mu.Lock()
	o.modelCache = active
	o.modelExpiry = time.Now().Add(modelCacheTTL)
	o.mu.Unlock()

	return filterModels(active, teeOnly), nil
}

func filterModels(models []core.Model, teeOnly bool) []core.Model {
	if !teeOnly {
		return models
	}
	out := make([]core.Model, 0)
	for _, m := range models {
		if hasTEETag(m.Tags) {
			out = append(out, m)
		}
	}
	return out
}

func hasTEETag(tags []string) bool {
	for _, t := range tags {
		lower := strings.ToLower(t)
		if lower == "tee" || strings.Contains(lower, "tee") {
			return true
		}
	}
	return false
}

type WalletSummary struct {
	Address        string `json:"address"`
	MORBalance     string `json:"mor_balance"`
	ETHBalance     string `json:"eth_balance"`
	ActiveSessions int    `json:"active_sessions"`
}

func (o *Orchestrator) GetWalletSummary(ctx context.Context) (*WalletSummary, error) {
	info, err := o.engine.GetBalance(ctx)
	if err != nil {
		return &WalletSummary{Address: o.engine.Address()}, nil
	}

	return &WalletSummary{
		Address:    info.Address,
		MORBalance: info.MORBalance,
		ETHBalance: info.ETHBalance,
	}, nil
}

// QuickSession opens a session for a model in one call — the proxy-router
// handles bid selection, MOR approval, and provider handshake.
func (o *Orchestrator) QuickSession(ctx context.Context, modelID string, durationSeconds int64) (*core.Session, error) {
	return o.engine.OpenSession(ctx, modelID, durationSeconds)
}

// ChatStream sends a prompt and persists the exchange to local storage.
// Returns the full response (streaming will be added in a later phase).
func (o *Orchestrator) ChatStream(ctx context.Context, sessionID string, modelID string, conversationID string, prompt string) (string, error) {
	_ = o.store.SaveMessage(conversationID, "user", prompt)

	response, err := o.engine.SendPrompt(ctx, sessionID, modelID, prompt)
	if err != nil {
		return "", err
	}

	_ = o.store.SaveMessage(conversationID, "assistant", response)
	return response, nil
}

// ProxyReachable checks if the proxy-router HTTP service is available.
func (o *Orchestrator) ProxyReachable(ctx context.Context) bool {
	return o.engine.Client().IsReachable(ctx)
}
