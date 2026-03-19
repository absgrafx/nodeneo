package orchestrator

import (
	"context"
	"sort"
	"sync"
	"time"

	"github.com/AlanHortwormo/redpill/internal/core"
	"github.com/AlanHortwormo/redpill/internal/store"
)

// Orchestrator provides consumer-friendly operations on top of the raw
// proxy-router engine. It consolidates multi-step workflows (like the API
// Gateway does) without the multi-user/billing overhead.
type Orchestrator struct {
	engine *core.Engine
	store  *store.Store

	mu          sync.RWMutex
	modelCache  []core.Model
	modelExpiry time.Time
}

const modelCacheTTL = 60 * time.Second

func New(engine *core.Engine, store *store.Store) *Orchestrator {
	return &Orchestrator{
		engine: engine,
		store:  store,
	}
}

// ActiveModels returns currently active models with available bids,
// enriched with TEE status. Results are cached for modelCacheTTL.
// TEE-attested models are sorted first.
func (o *Orchestrator) ActiveModels(ctx context.Context) ([]core.Model, error) {
	o.mu.RLock()
	if time.Now().Before(o.modelExpiry) && len(o.modelCache) > 0 {
		cached := o.modelCache
		o.mu.RUnlock()
		return cached, nil
	}
	o.mu.RUnlock()

	all, err := o.engine.ListModels(ctx)
	if err != nil {
		return nil, err
	}

	active := make([]core.Model, 0, len(all))
	for _, m := range all {
		// TODO: filter by active status, available bids
		active = append(active, m)
	}

	sort.Slice(active, func(i, j int) bool {
		if active[i].IsTEE != active[j].IsTEE {
			return active[i].IsTEE
		}
		return active[i].Name < active[j].Name
	})

	o.mu.Lock()
	o.modelCache = active
	o.modelExpiry = time.Now().Add(modelCacheTTL)
	o.mu.Unlock()

	return active, nil
}

// WalletSummary returns a consolidated view of the user's wallet.
type WalletSummary struct {
	Address        string `json:"address"`
	MORBalance     string `json:"mor_balance"`
	ETHBalance     string `json:"eth_balance"`
	ActiveSessions int    `json:"active_sessions"`
}

func (o *Orchestrator) GetWalletSummary(ctx context.Context, address string) (*WalletSummary, error) {
	info, err := o.engine.GetBalance(ctx, address)
	if err != nil {
		return nil, err
	}

	return &WalletSummary{
		Address:    info.Address,
		MORBalance: info.MORBalance,
		ETHBalance: info.ETHBalance,
	}, nil
}

// QuickSession finds the best provider for a model, handles MOR approval
// if needed, and initiates a session — all in one call.
func (o *Orchestrator) QuickSession(ctx context.Context, modelID string) (*core.Session, error) {
	models, err := o.ActiveModels(ctx)
	if err != nil {
		return nil, err
	}

	var bestProvider string
	for _, m := range models {
		if m.ID == modelID {
			bestProvider = m.Provider
			if m.IsTEE {
				break // prefer TEE provider
			}
		}
	}

	if bestProvider == "" {
		return nil, core.ErrNotInitialized // TODO: proper error
	}

	// TODO: check MOR allowance, auto-approve if needed

	return o.engine.OpenSession(ctx, modelID, bestProvider)
}

// ChatStream sends a prompt and returns streaming response chunks.
// It also persists the exchange to local storage.
func (o *Orchestrator) ChatStream(ctx context.Context, sessionID string, conversationID string, prompt string) (<-chan string, error) {
	chunks, err := o.engine.SendPrompt(ctx, sessionID, prompt)
	if err != nil {
		return nil, err
	}

	// Save user message
	_ = o.store.SaveMessage(conversationID, "user", prompt)

	// Wrap the channel to accumulate and persist the full response
	out := make(chan string, 64)
	go func() {
		defer close(out)
		var full string
		for chunk := range chunks {
			full += chunk
			out <- chunk
		}
		_ = o.store.SaveMessage(conversationID, "assistant", full)
	}()

	return out, nil
}
