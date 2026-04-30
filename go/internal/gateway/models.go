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
//
// The capability flags (supports_tools, supports_vision, supports_reasoning)
// are best-effort hints derived from the model name and tags. They mirror
// fields some clients (LangChain templates, Open WebUI, OpenRouter consumers)
// look for to auto-configure features. Zed and Cursor read capabilities from
// their own settings.json, so the flags are advisory there.
//
// The flags are always serialised — `false` is emitted explicitly rather than
// elided — so consumers can distinguish "this gateway does not advertise the
// capability" (field missing) from "this model does not support it" (field
// present and false).
type openAIModelEntry struct {
	ID                string   `json:"id"`
	Object            string   `json:"object"`
	Created           int64    `json:"created"`
	OwnedBy           string   `json:"owned_by"`
	BlockchainID      string   `json:"blockchainID,omitempty"`
	Tags              []string `json:"tags,omitempty"`
	ModelType         string   `json:"modelType,omitempty"`
	SupportsTools     bool     `json:"supports_tools"`
	SupportsVision    bool     `json:"supports_vision"`
	SupportsReasoning bool     `json:"supports_reasoning"`
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
		entries = append(entries, newModelEntry(m.Name, m.ID, m.ModelType, m.Tags, m.CreatedAt))
	}
	return entries, nil
}

func (g *Gateway) activeModelsToOpenAI(models []activeModel) []openAIModelEntry {
	entries := make([]openAIModelEntry, 0, len(models))
	for _, m := range models {
		entries = append(entries, newModelEntry(m.Name, m.ID, m.ModelType, m.Tags, m.CreatedAt))
	}
	return entries
}

// findModelByName returns the model entry matching the given name (case-insensitive).
func (g *Gateway) findModelByName(name string) (openAIModelEntry, bool) {
	if cached, ok := g.getCachedModels(); ok {
		lower := strings.ToLower(name)
		for _, m := range cached {
			if strings.ToLower(m.Name) == lower {
				return newModelEntry(m.Name, m.ID, m.ModelType, m.Tags, m.CreatedAt), true
			}
		}
	}
	return openAIModelEntry{}, false
}

// newModelEntry builds an openAIModelEntry, including best-effort capability
// flags inferred from the model name + tags. Centralising this keeps the
// per-source converters (active.mor.org, SDK fallback, by-name lookup) in sync.
func newModelEntry(name, id, modelType string, tags []string, createdAt int64) openAIModelEntry {
	return openAIModelEntry{
		ID:                name,
		Object:            "model",
		Created:           createdAt,
		OwnedBy:           "morpheus",
		BlockchainID:      id,
		Tags:              tags,
		ModelType:         modelType,
		SupportsTools:     supportsTools(name, tags),
		SupportsVision:    supportsVision(name, tags),
		SupportsReasoning: supportsReasoning(name, tags),
	}
}

// Capability inference is intentionally conservative — we'd rather under-report
// a capability than have an IDE attempt a feature against a model that doesn't
// support it. Patterns reflect the families known to ship native tool-call /
// vision / chain-of-thought parsers in the major inference servers (vLLM,
// SGLang, llama.cpp, TGI) as of 2026.

var (
	toolCapableSubstrings = []string{
		"glm-4.5", "glm-4.6", "glm-4.7", "glm-4.8", "glm-4.9", "glm-5",
		"llama-3.1", "llama-3.2", "llama-3.3", "llama-4",
		"qwen2.5", "qwen-2.5", "qwen3", "qwen-3",
		"mistral-nemo", "mistral-large", "mixtral-8x22",
		"deepseek-v3", "deepseek-r1", "deepseek-coder-v2",
		"hermes-3", "hermes-4",
		"command-r", "command-a",
		"granite-3", "granite-4",
		"phi-4", "phi-3.5",
		"firefunction",
	}
	visionCapableSubstrings = []string{
		"vision", "-vl", "vl-", "llava", "internvl", "qwen-vl", "qwen2-vl", "qwen2.5-vl",
		"pixtral", "molmo", "minicpm-v", "florence", "cogvlm", "kimi-vl",
		"gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gemini",
	}
	reasoningCapableSubstrings = []string{
		"o1", "o3", "o4", "deepseek-r1", "qwen-qwq", "qwq",
		"glm-z1", "glm-5", // GLM-5.x ships with reasoning_content streaming on by default
		"gemini-2.0-flash-thinking", "marco-o1", "skywork-o1",
	}
)

func supportsTools(name string, tags []string) bool {
	if hasTag(tags, "tools", "function_calling", "function-calling", "functions") {
		return true
	}
	return matchAny(name, toolCapableSubstrings)
}

func supportsVision(name string, tags []string) bool {
	if hasTag(tags, "vision", "multimodal", "vlm") {
		return true
	}
	return matchAny(name, visionCapableSubstrings)
}

func supportsReasoning(name string, tags []string) bool {
	if hasTag(tags, "reasoning", "thinking", "cot") {
		return true
	}
	return matchAny(name, reasoningCapableSubstrings)
}

func hasTag(tags []string, candidates ...string) bool {
	for _, t := range tags {
		lt := strings.ToLower(strings.TrimSpace(t))
		for _, c := range candidates {
			if lt == c {
				return true
			}
		}
	}
	return false
}

func matchAny(name string, substrings []string) bool {
	lower := strings.ToLower(name)
	for _, s := range substrings {
		if strings.Contains(lower, s) {
			return true
		}
	}
	return false
}
