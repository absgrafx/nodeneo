package mobile

import (
	"context"
	"encoding/json"
	"sync"

	"github.com/absgrafx/redpill/internal/core"
	"github.com/absgrafx/redpill/internal/orchestrator"
	"github.com/absgrafx/redpill/internal/store"
)

var (
	mu   sync.Mutex
	eng  *core.Engine
	orch *orchestrator.Orchestrator
	db   *store.Store
)

func resultJSON(v interface{}) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func errJSON(err error) string {
	b, _ := json.Marshal(map[string]string{"error": err.Error()})
	return string(b)
}

// --- Lifecycle ---

// Init starts the engine. proxyBaseURL is the running proxy-router
// (e.g. "http://localhost:8082"). dataDir is where the local SQLite
// database will be stored.
func Init(dataDir string, proxyBaseURL string) string {
	mu.Lock()
	defer mu.Unlock()

	if eng != nil {
		return resultJSON(map[string]string{"status": "already_initialized"})
	}

	cfg := core.Config{
		DataDir:      dataDir,
		ProxyBaseURL: proxyBaseURL,
	}
	eng = core.NewEngine(cfg)
	if err := eng.Init(context.Background()); err != nil {
		eng = nil
		return errJSON(err)
	}

	var err error
	db, err = store.New(dataDir + "/redpill.db")
	if err != nil {
		eng = nil
		return errJSON(err)
	}

	orch = orchestrator.New(eng, db)
	return resultJSON(map[string]string{"status": "ok"})
}

// Shutdown tears everything down.
func Shutdown() {
	mu.Lock()
	defer mu.Unlock()
	if db != nil {
		_ = db.Close()
		db = nil
	}
	if eng != nil {
		_ = eng.Close()
		eng = nil
	}
	orch = nil
}

// IsReady returns true if the engine is initialized.
func IsReady() bool {
	mu.Lock()
	defer mu.Unlock()
	return eng != nil && eng.IsReady()
}

// IsProxyReachable checks if the proxy-router HTTP service responds.
func IsProxyReachable() bool {
	mu.Lock()
	defer mu.Unlock()
	if orch == nil {
		return false
	}
	return orch.ProxyReachable(context.Background())
}

// --- Wallet (native — no proxy-router needed) ---

// CreateWallet generates a new BIP-39 wallet. Returns JSON:
// {"mnemonic":"...", "address":"0x..."}
func CreateWallet() string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	mnemonic, address, err := eng.CreateWallet()
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{
		"mnemonic": mnemonic,
		"address":  address,
	})
}

// ImportWalletMnemonic imports a wallet from a BIP-39 mnemonic.
// derivationPath can be empty to use the default (m/44'/60'/0'/0/0).
func ImportWalletMnemonic(mnemonic string, derivationPath string) string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	address, err := eng.ImportWallet(mnemonic, derivationPath)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"address": address})
}

// ImportWalletPrivateKey imports a wallet from a hex-encoded private key.
func ImportWalletPrivateKey(hexKey string) string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	address, err := eng.ImportPrivateKey(hexKey)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"address": address})
}

// ExportPrivateKey returns the hex-encoded private key of the current wallet.
// The caller (UI) should gate this behind biometric re-auth before displaying.
func ExportPrivateKey() string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	hex, err := eng.PrivateKeyHex()
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"private_key": hex})
}

// GetWalletSummary returns address, ETH balance, and MOR balance.
func GetWalletSummary() string {
	mu.Lock()
	defer mu.Unlock()
	if orch == nil {
		return errJSON(core.ErrNotInitialized)
	}
	summary, err := orch.GetWalletSummary(context.Background())
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(summary)
}

// --- Models (via proxy-router HTTP) ---

// GetActiveModels returns active models as JSON array, cached 60s.
// If teeOnly is true, only models with TEE in their tags are returned
// (MAX Privacy mode).
func GetActiveModels(teeOnly bool) string {
	mu.Lock()
	defer mu.Unlock()
	if orch == nil {
		return errJSON(core.ErrNotInitialized)
	}
	models, err := orch.ActiveModels(context.Background(), teeOnly)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(models)
}

// GetRatedBids returns rated bids for a model, sorted by score.
func GetRatedBids(modelID string) string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	bids, err := eng.GetRatedBids(context.Background(), modelID)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(bids)
}

// --- Sessions (via proxy-router HTTP) ---

// QuickOpenSession opens a session for a model in one shot.
func QuickOpenSession(modelID string, durationSeconds int) string {
	mu.Lock()
	defer mu.Unlock()
	if orch == nil {
		return errJSON(core.ErrNotInitialized)
	}
	session, err := orch.QuickSession(context.Background(), modelID, int64(durationSeconds))
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(session)
}

// CloseSession closes an active session.
func CloseSession(sessionID string) string {
	mu.Lock()
	defer mu.Unlock()
	if eng == nil {
		return errJSON(core.ErrNotInitialized)
	}
	if err := eng.CloseSession(context.Background(), sessionID); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "closed"})
}

// --- Chat (via proxy-router HTTP) ---

// SendPrompt sends a chat prompt through an open session.
// Returns the full assistant response (non-streaming for now).
func SendPrompt(sessionID string, modelID string, conversationID string, prompt string) string {
	mu.Lock()
	defer mu.Unlock()
	if orch == nil {
		return errJSON(core.ErrNotInitialized)
	}
	response, err := orch.ChatStream(context.Background(), sessionID, modelID, conversationID, prompt)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"response": response})
}

// --- Conversations (local SQLite) ---

// GetConversations lists all saved conversations.
func GetConversations() string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(core.ErrNotInitialized)
	}
	convos, err := db.ListConversations(100)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(convos)
}

// GetMessages returns messages for a conversation.
func GetMessages(conversationID string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(core.ErrNotInitialized)
	}
	msgs, err := db.GetMessages(conversationID)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(msgs)
}

// --- Preferences (local SQLite) ---

func SetPreference(key string, value string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(core.ErrNotInitialized)
	}
	if err := db.SetPreference(key, value); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

func GetPreference(key string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(core.ErrNotInitialized)
	}
	val, err := db.GetPreference(key)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"value": val})
}
