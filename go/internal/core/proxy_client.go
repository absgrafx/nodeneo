package core

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"time"
)

// ProxyClient talks to a running proxy-router instance via its REST API.
// This keeps RedPill decoupled from proxy-router internals while still
// getting full blockchain, session, and chat functionality.
type ProxyClient struct {
	baseURL string
	http    *http.Client
}

func NewProxyClient(baseURL string) *ProxyClient {
	return &ProxyClient{
		baseURL: baseURL,
		http: &http.Client{
			Timeout: 60 * time.Second,
		},
	}
}

func (c *ProxyClient) SetBaseURL(url string) {
	c.baseURL = url
}

func (c *ProxyClient) BaseURL() string {
	return c.baseURL
}

func (c *ProxyClient) IsReachable(ctx context.Context) bool {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/healthcheck", nil)
	if err != nil {
		return false
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// --- Wallet / Balance ---

func (c *ProxyClient) GetBalance(ctx context.Context) (*WalletInfo, error) {
	var result struct {
		ETH string `json:"eth"`
		MOR string `json:"mor"`
	}
	if err := c.get(ctx, "/blockchain/balance", &result); err != nil {
		return nil, err
	}

	var addr struct {
		Address string `json:"address"`
	}
	_ = c.get(ctx, "/blockchain/address", &addr)

	return &WalletInfo{
		Address:    addr.Address,
		ETHBalance: result.ETH,
		MORBalance: result.MOR,
	}, nil
}

// --- Models ---

func (c *ProxyClient) GetAllModels(ctx context.Context) ([]Model, error) {
	var raw []json.RawMessage
	if err := c.get(ctx, "/blockchain/models", &raw); err != nil {
		return nil, err
	}

	models := make([]Model, 0, len(raw))
	for _, r := range raw {
		var m Model
		if err := json.Unmarshal(r, &m); err != nil {
			continue
		}
		models = append(models, m)
	}
	return models, nil
}

func (c *ProxyClient) GetRatedBids(ctx context.Context, modelID string) ([]Bid, error) {
	path := fmt.Sprintf("/blockchain/models/%s/bids/rated", modelID)
	var bids []Bid
	if err := c.get(ctx, path, &bids); err != nil {
		return nil, err
	}
	return bids, nil
}

// --- Sessions ---

func (c *ProxyClient) OpenSessionByModelId(ctx context.Context, modelID string, duration *big.Int) (*Session, error) {
	body := map[string]interface{}{
		"sessionDuration": duration.String(),
	}
	path := fmt.Sprintf("/blockchain/models/%s/session", modelID)
	var result Session
	if err := c.post(ctx, path, body, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func (c *ProxyClient) CloseSession(ctx context.Context, sessionID string) error {
	path := fmt.Sprintf("/blockchain/sessions/%s/close", sessionID)
	return c.post(ctx, path, nil, nil)
}

// --- Chat ---

func (c *ProxyClient) ChatCompletion(ctx context.Context, sessionID string, modelID string, prompt string) (string, error) {
	body := map[string]interface{}{
		"model": modelID,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
		"stream": false,
	}

	req, err := c.newRequest(ctx, "POST", "/v1/chat/completions", body)
	if err != nil {
		return "", err
	}
	req.Header.Set("session_id", sessionID)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("chat request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("chat error %d: %s", resp.StatusCode, string(b))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	if len(result.Choices) == 0 {
		return "", fmt.Errorf("no choices in response")
	}
	return result.Choices[0].Message.Content, nil
}

// --- HTTP helpers ---

func (c *ProxyClient) get(ctx context.Context, path string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+path, nil)
	if err != nil {
		return err
	}
	return c.doJSON(req, out)
}

func (c *ProxyClient) post(ctx context.Context, path string, body interface{}, out interface{}) error {
	req, err := c.newRequest(ctx, "POST", path, body)
	if err != nil {
		return err
	}
	return c.doJSON(req, out)
}

func (c *ProxyClient) newRequest(ctx context.Context, method string, path string, body interface{}) (*http.Request, error) {
	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		bodyReader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req, nil
}

func (c *ProxyClient) doJSON(req *http.Request, out interface{}) error {
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("proxy-router request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("proxy-router %d: %s", resp.StatusCode, string(b))
	}

	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}
