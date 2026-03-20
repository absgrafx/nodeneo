package mobile

import (
	"context"
	"encoding/json"
	"sync"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	"github.com/absgrafx/redpill/internal/store"
)

var (
	mu      sync.Mutex
	client  *sdk.SDK
	db      *store.Store
	initErr error
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

// Init initializes the embedded proxy-router SDK and local storage.
// All blockchain operations go directly through the SDK — no external
// proxy-router process needed.
func Init(dataDir, ethNodeURL string, chainID int64, diamondAddr, morTokenAddr, blockscoutURL string) string {
	mu.Lock()
	defer mu.Unlock()

	if client != nil {
		return resultJSON(map[string]string{"status": "already_initialized"})
	}

	activeModelsURL := "https://active.dev.mor.org/active_models.json"

	cfg := sdk.Config{
		DataDir:         dataDir,
		EthNodeURL:      ethNodeURL,
		ChainID:         chainID,
		DiamondAddr:     diamondAddr,
		MorTokenAddr:    morTokenAddr,
		BlockscoutURL:   blockscoutURL,
		ActiveModelsURL: activeModelsURL,
		LogLevel:        "info",
	}

	var err error
	client, err = sdk.NewSDK(cfg)
	if err != nil {
		client = nil
		return errJSON(err)
	}

	db, err = store.New(dataDir + "/redpill.db")
	if err != nil {
		client.Shutdown()
		client = nil
		return errJSON(err)
	}

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
	if client != nil {
		client.Shutdown()
		client = nil
	}
}

// IsReady returns true if the SDK is initialized.
func IsReady() bool {
	mu.Lock()
	defer mu.Unlock()
	return client != nil
}

// --- Wallet (native via SDK — embedded proxy-router wallet) ---

// CreateWallet generates a new BIP-39 wallet. Returns JSON:
// {"mnemonic":"...", "address":"0x..."}
func CreateWallet() string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	mnemonic, address, err := client.CreateWallet()
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{
		"mnemonic": mnemonic,
		"address":  address,
	})
}

// ImportWalletMnemonic imports a wallet from a BIP-39 mnemonic.
func ImportWalletMnemonic(mnemonic string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	address, err := client.ImportMnemonic(mnemonic)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"address": address})
}

// ImportWalletPrivateKey imports a wallet from a hex-encoded private key.
func ImportWalletPrivateKey(hexKey string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	address, err := client.ImportPrivateKey(hexKey)
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
	if client == nil {
		return errJSON(errNotInit)
	}
	hex, err := client.ExportPrivateKey()
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"private_key": hex})
}

// GetWalletSummary returns address + ETH/MOR balances.
func GetWalletSummary() string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}

	addr, _ := client.GetAddress()
	bal, err := client.GetBalance(context.Background())
	if err != nil {
		return resultJSON(map[string]string{
			"address":     addr,
			"eth_balance": "0",
			"mor_balance": "0",
			"error":       err.Error(),
		})
	}
	return resultJSON(map[string]string{
		"address":     addr,
		"eth_balance": bal.ETH,
		"mor_balance": bal.MOR,
	})
}

// --- Models (direct blockchain via SDK) ---

// GetActiveModels returns all registered models as a JSON array.
// If teeOnly is true, only TEE-tagged models are returned (MAX Privacy).
func GetActiveModels(teeOnly bool) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	models, err := client.GetAllModels(context.Background())
	if err != nil {
		return errJSON(err)
	}
	if teeOnly {
		models = filterTEE(models)
	}
	return resultJSON(models)
}

// GetRatedBids returns rated bids for a model, sorted by score.
func GetRatedBids(modelID string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	bids, err := client.GetRatedBids(context.Background(), modelID)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(bids)
}

// --- Sessions (direct blockchain via SDK) ---

// OpenSession opens a session for a model. durationSeconds is the session length.
func OpenSession(modelID string, durationSeconds int64, directPayment bool) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	sessionID, err := client.OpenSession(context.Background(), modelID, durationSeconds, directPayment)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"session_id": sessionID})
}

// CloseSession closes an active session.
func CloseSession(sessionID string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	txHash, err := client.CloseSession(context.Background(), sessionID)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "closed", "tx_hash": txHash})
}

// GetSession retrieves session details by ID.
func GetSession(sessionID string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	s, err := client.GetSessionJSON(context.Background(), sessionID)
	if err != nil {
		return errJSON(err)
	}
	return s
}

// --- Chat (direct MOR-RPC via SDK — streaming) ---

// SendPrompt sends a chat prompt through an open session and persists
// the exchange locally. Returns the full response.
func SendPrompt(sessionID string, conversationID string, prompt string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}

	if db != nil {
		_ = db.SaveMessage(conversationID, "user", prompt)
	}

	var fullResponse string
	err := client.SendPrompt(context.Background(), sessionID, prompt, func(text string, isLast bool) error {
		fullResponse += text
		return nil
	})
	if err != nil {
		return errJSON(err)
	}

	if db != nil {
		_ = db.SaveMessage(conversationID, "assistant", fullResponse)
	}

	return resultJSON(map[string]string{"response": fullResponse})
}

// --- Conversations (local SQLite) ---

// GetConversations lists all saved conversations.
func GetConversations() string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
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
		return errJSON(errNotInit)
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
		return errJSON(errNotInit)
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
		return errJSON(errNotInit)
	}
	val, err := db.GetPreference(key)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"value": val})
}

// --- Helpers ---

var errNotInit = &initError{}

type initError struct{}

func (e *initError) Error() string { return "not initialized — call Init() first" }

func filterTEE(models []sdk.Model) []sdk.Model {
	out := make([]sdk.Model, 0)
	for _, m := range models {
		for _, tag := range m.Tags {
			if tag == "tee" || tag == "TEE" {
				out = append(out, m)
				break
			}
		}
	}
	return out
}
