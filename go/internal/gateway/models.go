package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	activeModelsURL      = "https://active.mor.org/active_models.json"
	modelsCacheTTL       = 5 * time.Minute
	modelsFetchTimeout   = 10 * time.Second
)

// activeModel mirrors the JSON structure from active.mor.org/active_models.json.
type activeModel struct {
	ID        string   `json:"Id"`
	Name      string   `json:"Name"`
	Tags      []string `json:"Tags"`
	ModelType string   `json:"ModelType"`
	CreatedAt int64    `json:"CreatedAt"`
	Fee       float64  `json:"Fee"`
	Stake     float64  `json:"Stake"`
	Owner     string   `json:"Owner"`
	IsDeleted bool     `json:"IsDeleted"`
}

// openAIModelEntry is the per-model response in /v1/models, matching the
// Marketplace API format (OpenAI envelope with Morpheus-specific fields).
type openAIModelEntry struct {
	ID           string   `json:"id"`
	Object       string   `json:"object"`
	Created      int64    `json:"created"`
	OwnedBy      string   `json:"owned_by"`
	BlockchainID string   `json:"blockchainID,omitempty"`
	Tags         []string `json:"tags,omitempty"`
	ModelType    string   `json:"modelType,omitempty"`
}

type modelsListResponse struct {
	Object string             `json:"object"`
	Data   []openAIModelEntry `json:"data"`
}

// modelsCache is an in-memory cache for the active models list,
// matching the Marketplace API's DirectModelService pattern.
type modelsCache struct {
	mu        sync.RWMutex
	models    []activeModel
	cachedAt  time.Time
	etag      string
}

func (g *Gateway) getCachedModels() ([]activeModel, bool) {
	g.modelCache.mu.RLock()
	defer g.modelCache.mu.RUnlock()
	if g.modelCache.models != nil && time.Since(g.modelCache.cachedAt) < modelsCacheTTL {
		return g.modelCache.models, true
	}
	return nil, false
}

func (g *Gateway) setCachedModels(models []activeModel, etag string) {
	g.modelCache.mu.Lock()
	defer g.modelCache.mu.Unlock()
	g.modelCache.models = models
	g.modelCache.cachedAt = time.Now()
	g.modelCache.etag = etag
}

// fetchActiveModels fetches the model list from active.mor.org with caching.
// Falls back to the SDK's GetAllModels if the HTTP fetch fails.
func (g *Gateway) fetchActiveModels(ctx context.Context) ([]openAIModelEntry, error) {
	if cached, ok := g.getCachedModels(); ok {
		return g.activeModelsToOpenAI(cached), nil
	}

	models, err := g.fetchActiveModelsHTTP(ctx)
	if err != nil {
		g.log("active.mor.org fetch failed (%v), falling back to SDK", err)
		return g.fetchModelsFromSDK(ctx)
	}

	return g.activeModelsToOpenAI(models), nil
}

// fetchActiveModelsHTTP does the direct HTTP GET to active.mor.org/active_models.json.
func (g *Gateway) fetchActiveModelsHTTP(ctx context.Context) ([]activeModel, error) {
	ctx, cancel := context.WithTimeout(ctx, modelsFetchTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, activeModelsURL, nil)
	if err != nil {
		return nil, err
	}

	g.modelCache.mu.RLock()
	etag := g.modelCache.etag
	g.modelCache.mu.RUnlock()
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch active models: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		g.modelCache.mu.Lock()
		g.modelCache.cachedAt = time.Now()
		g.modelCache.mu.Unlock()
		if cached, ok := g.getCachedModels(); ok {
			return cached, nil
		}
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("active models HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var envelope struct {
		Models []activeModel `json:"models"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return nil, fmt.Errorf("parse active models: %w", err)
	}

	// Filter deleted models
	active := make([]activeModel, 0, len(envelope.Models))
	for _, m := range envelope.Models {
		if !m.IsDeleted && m.Name != "" {
			active = append(active, m)
		}
	}

	newEtag := resp.Header.Get("ETag")
	g.setCachedModels(active, newEtag)
	g.log("refreshed %d active models from active.mor.org", len(active))

	return active, nil
}

// fetchModelsFromSDK falls back to the embedded SDK's model list.
func (g *Gateway) fetchModelsFromSDK(ctx context.Context) ([]openAIModelEntry, error) {
	models, err := g.sdk.GetAllModels(ctx)
	if err != nil {
		return nil, err
	}

	entries := make([]openAIModelEntry, 0, len(models))
	for _, m := range models {
		entries = append(entries, openAIModelEntry{
			ID:           m.Name,
			Object:       "model",
			Created:      m.CreatedAt,
			OwnedBy:      "morpheus",
			BlockchainID: m.ID,
			Tags:         m.Tags,
			ModelType:    m.ModelType,
		})
	}
	return entries, nil
}

func (g *Gateway) activeModelsToOpenAI(models []activeModel) []openAIModelEntry {
	entries := make([]openAIModelEntry, 0, len(models))
	for _, m := range models {
		entries = append(entries, openAIModelEntry{
			ID:           m.Name,
			Object:       "model",
			Created:      m.CreatedAt,
			OwnedBy:      "morpheus",
			BlockchainID: m.ID,
			Tags:         m.Tags,
			ModelType:    m.ModelType,
		})
	}
	return entries
}

// findModelByName returns the model entry matching the given name (case-insensitive).
func (g *Gateway) findModelByName(name string) (openAIModelEntry, bool) {
	if cached, ok := g.getCachedModels(); ok {
		lower := strings.ToLower(name)
		for _, m := range cached {
			if strings.ToLower(m.Name) == lower {
				return openAIModelEntry{
					ID:           m.Name,
					Object:       "model",
					Created:      m.CreatedAt,
					OwnedBy:      "morpheus",
					BlockchainID: m.ID,
					Tags:         m.Tags,
					ModelType:    m.ModelType,
				}, true
			}
		}
	}
	return openAIModelEntry{}, false
}
