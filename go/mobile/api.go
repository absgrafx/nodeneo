// Package mobile provides the gomobile-exported API surface.
// All functions use basic types (string, int, bool, []byte) for cross-platform
// FFI compatibility. Complex return values are JSON-encoded strings.
package mobile

import (
	"context"
	"encoding/json"
	"sync"

	"github.com/AlanHortwormo/redpill/internal/core"
	"github.com/AlanHortwormo/redpill/internal/orchestrator"
	"github.com/AlanHortwormo/redpill/internal/store"
)

var (
	mu   sync.Mutex
	eng  *core.Engine
	orch *orchestrator.Orchestrator
	db   *store.Store
)

// Init initializes the RedPill engine. Must be called once at app startup.
// dataDir: platform-specific writable directory for DB and config.
// ethNodeURL: Arbitrum RPC endpoint (e.g. "https://arb1.arbitrum.io/rpc").
// Returns empty string on success, error message on failure.
func Init(dataDir string, ethNodeURL string) string {
	mu.Lock()
	defer mu.Unlock()

	var err error
	db, err = store.New(dataDir + "/redpill.db")
	if err != nil {
		return "store init failed: " + err.Error()
	}

	eng = core.NewEngine(core.Config{
		DataDir:    dataDir,
		EthNodeURL: ethNodeURL,
		ChainID:    42161, // Arbitrum One
	})

	if err := eng.Init(context.Background()); err != nil {
		return "engine init failed: " + err.Error()
	}

	orch = orchestrator.New(eng, db)
	return ""
}

// Shutdown cleanly shuts down the engine and closes the database.
func Shutdown() string {
	mu.Lock()
	defer mu.Unlock()

	if eng != nil {
		eng.Close()
	}
	if db != nil {
		db.Close()
	}
	return ""
}

// IsReady returns true if the engine is initialized.
func IsReady() bool {
	mu.Lock()
	defer mu.Unlock()
	return eng != nil && eng.IsReady()
}

// --- Wallet ---

// CreateWallet generates a new BIP-39 wallet.
// Returns JSON: {"mnemonic":"...", "address":"0x..."}
func CreateWallet() string {
	mu.Lock()
	defer mu.Unlock()

	mnemonic, address, err := eng.CreateWallet()
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(map[string]string{"mnemonic": mnemonic, "address": address})
}

// ImportWalletMnemonic imports a wallet from a BIP-39 mnemonic phrase.
// Returns JSON: {"address":"0x..."}
func ImportWalletMnemonic(mnemonic string) string {
	mu.Lock()
	defer mu.Unlock()

	address, err := eng.ImportWallet(mnemonic)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(map[string]string{"address": address})
}

// ImportWalletPrivateKey imports a wallet from a hex-encoded private key.
// Returns JSON: {"address":"0x..."}
func ImportWalletPrivateKey(hexKey string) string {
	mu.Lock()
	defer mu.Unlock()

	address, err := eng.ImportPrivateKey(hexKey)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(map[string]string{"address": address})
}

// GetWalletSummary returns balances and session count for the given address.
// Returns JSON: {"address":"...", "mor_balance":"...", "eth_balance":"...", "active_sessions":0}
func GetWalletSummary(address string) string {
	summary, err := orch.GetWalletSummary(context.Background(), address)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(summary)
}

// --- Models ---

// GetActiveModels returns the list of active models, TEE-first.
// Returns JSON array of model objects.
func GetActiveModels() string {
	models, err := orch.ActiveModels(context.Background())
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(models)
}

// --- Sessions ---

// QuickOpenSession finds the best provider and opens a session for the given model.
// Returns JSON session object.
func QuickOpenSession(modelID string) string {
	session, err := orch.QuickSession(context.Background(), modelID)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(session)
}

// SendPrompt sends a prompt to the active session.
// For now, returns the full response (non-streaming).
// TODO: implement streaming via callback interface.
func SendPrompt(sessionID string, conversationID string, prompt string) string {
	chunks, err := orch.ChatStream(context.Background(), sessionID, conversationID, prompt)
	if err != nil {
		return jsonError(err)
	}

	var full string
	for chunk := range chunks {
		full += chunk
	}
	return jsonOK(map[string]string{"response": full})
}

// --- Conversations ---

// GetConversations returns recent conversation list.
// Returns JSON array.
func GetConversations(limit int) string {
	convos, err := db.ListConversations(limit)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(convos)
}

// GetMessages returns all messages in a conversation.
// Returns JSON array.
func GetMessages(conversationID string) string {
	msgs, err := db.GetMessages(conversationID)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(msgs)
}

// --- Preferences ---

func SetPreference(key, value string) string {
	if err := db.SetPreference(key, value); err != nil {
		return jsonError(err)
	}
	return jsonOK("ok")
}

func GetPreference(key string) string {
	val, err := db.GetPreference(key)
	if err != nil {
		return jsonError(err)
	}
	return jsonOK(map[string]string{"value": val})
}

// --- JSON helpers ---

type apiResponse struct {
	OK    bool        `json:"ok"`
	Data  interface{} `json:"data,omitempty"`
	Error string      `json:"error,omitempty"`
}

func jsonOK(data interface{}) string {
	b, _ := json.Marshal(apiResponse{OK: true, Data: data})
	return string(b)
}

func jsonError(err error) string {
	b, _ := json.Marshal(apiResponse{OK: false, Error: err.Error()})
	return string(b)
}
