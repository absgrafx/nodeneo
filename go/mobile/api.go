package mobile

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"strings"
	"sync"
	"time"

	sdk "github.com/MorpheusAIs/Morpheus-Lumerin-Node/proxy-router/mobile"
	"github.com/absgrafx/nodeneo/internal/cloudflared"
	"github.com/absgrafx/nodeneo/internal/gateway"
	"github.com/absgrafx/nodeneo/internal/logger"
	"github.com/absgrafx/nodeneo/internal/store"
	openai "github.com/sashabaranov/go-openai"
)

var (
	mu       sync.Mutex
	client   *sdk.SDK
	db       *store.Store
	initErr  error
	savedDir string // dataDir from Init, used by OpenWalletDatabase
)

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func osRename(old, new string) error {
	return os.Rename(old, new)
}

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

	// File-based rotating logger (10 MB × 5 files under dataDir/logs/).
	if err := logger.Init(dataDir, "info"); err != nil {
		return errJSON(fmt.Errorf("logger init: %w", err))
	}
	savedDir = dataDir
	logger.Info("SDK init: dataDir=%s chainID=%d", dataDir, chainID)

	activeModelsURL := "https://active.mor.org/active_models.json"

	cfg := sdk.Config{
		DataDir:         dataDir,
		EthNodeURL:      ethNodeURL,
		ChainID:         chainID,
		DiamondAddr:     diamondAddr,
		MorTokenAddr:    morTokenAddr,
		BlockscoutURL:   blockscoutURL,
		ActiveModelsURL: activeModelsURL,
		LogLevel:        "info",
		LogWriter:       logger.DirectWriter(),
	}

	var err error
	client, err = sdk.NewSDK(cfg)
	if err != nil {
		logger.Error("SDK NewSDK failed: %v", err)
		client = nil
		return errJSON(err)
	}
	logger.Info("SDK initialized (chainID=%d)", chainID)

	db, err = store.New(dataDir + "/nodeneo.db")
	if err != nil {
		logger.Error("DB open failed: %v", err)
		client.Shutdown()
		client = nil
		return errJSON(err)
	}
	logger.Info("DB opened at %s/nodeneo.db", dataDir)
	restoreSavedLogLevelLocked()

	return resultJSON(map[string]string{"status": "ok"})
}

// AppLog writes a message to nodeneo.log from the Dart/Flutter layer,
// creating a unified application log alongside the Go SDK entries.
// level: "debug", "info", "warn", "error".
func AppLog(level, message string) {
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "debug":
		logger.Debug("[FLUTTER] %s", message)
	case "warn", "warning":
		logger.Warn("[FLUTTER] %s", message)
	case "error":
		logger.Error("[FLUTTER] %s", message)
	default:
		logger.Info("[FLUTTER] %s", message)
	}
}

// Shutdown tears everything down.
func Shutdown() {
	mu.Lock()
	defer mu.Unlock()
	logger.Info("SDK shutdown")
	if db != nil {
		_ = db.Close()
		db = nil
	}
	if client != nil {
		client.Shutdown()
		client = nil
	}
	logger.Close()
}

// IsReady returns true if the SDK is initialized.
func IsReady() bool {
	mu.Lock()
	defer mu.Unlock()
	return client != nil
}

// OpenWalletDatabase closes any current DB and opens (or creates) a
// wallet-scoped database named nodeneo_{fingerprint}.db.
// If the legacy nodeneo.db exists and the scoped DB does not, the legacy
// file is renamed to the scoped path (one-time migration).
// fingerprint should be the first 8 hex chars of the wallet address (lowercase, no 0x).
func OpenWalletDatabase(fingerprint string) string {
	mu.Lock()
	defer mu.Unlock()
	if savedDir == "" {
		return errJSON(fmt.Errorf("sdk not initialized"))
	}
	fingerprint = strings.ToLower(strings.TrimSpace(fingerprint))
	if fingerprint == "" || len(fingerprint) < 4 {
		return errJSON(fmt.Errorf("invalid fingerprint"))
	}

	scopedPath := savedDir + "/nodeneo_" + fingerprint + ".db"
	legacyPath := savedDir + "/nodeneo.db"

	if db != nil {
		_ = db.Close()
		db = nil
	}

	// One-time migration: rename legacy DB → scoped if scoped doesn't exist yet.
	if !fileExists(scopedPath) && fileExists(legacyPath) {
		logger.Info("Migrating legacy DB → %s", scopedPath)
		for _, suffix := range []string{"", "-wal", "-shm"} {
			old := legacyPath + suffix
			if fileExists(old) {
				if err := osRename(old, scopedPath+suffix); err != nil {
					logger.Warn("rename %s → %s: %v", old, scopedPath+suffix, err)
				}
			}
		}
	}

	var err error
	db, err = store.New(scopedPath)
	if err != nil {
		logger.Error("DB open failed: %v", err)
		return errJSON(err)
	}
	logger.Info("Wallet DB opened: %s", scopedPath)
	restoreSavedLogLevelLocked()
	return resultJSON(map[string]string{"status": "ok", "path": scopedPath})
}

// ListWalletDatabases returns JSON array of {fingerprint, path, size_bytes}
// for every nodeneo_*.db file found in the data directory.
func ListWalletDatabases() string {
	mu.Lock()
	defer mu.Unlock()
	if savedDir == "" {
		return resultJSON([]interface{}{})
	}

	entries, err := os.ReadDir(savedDir)
	if err != nil {
		return resultJSON([]interface{}{})
	}

	type dbInfo struct {
		Fingerprint string `json:"fingerprint"`
		Path        string `json:"path"`
		SizeBytes   int64  `json:"size_bytes"`
	}
	var dbs []dbInfo
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, "nodeneo_") || !strings.HasSuffix(name, ".db") {
			continue
		}
		if strings.HasSuffix(name, "-wal") || strings.HasSuffix(name, "-shm") {
			continue
		}
		fp := strings.TrimPrefix(name, "nodeneo_")
		fp = strings.TrimSuffix(fp, ".db")
		info, _ := e.Info()
		size := int64(0)
		if info != nil {
			size = info.Size()
		}
		dbs = append(dbs, dbInfo{Fingerprint: fp, Path: savedDir + "/" + name, SizeBytes: size})
	}
	return resultJSON(dbs)
}

// ExportBackup creates an encrypted .nodeneo-backup file containing all
// conversations, messages, and preferences. Passphrase is used to derive
// the AES-256-GCM key for the archive.
func ExportBackup(outputPath, passphrase, appVersion, walletPrefix string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(fmt.Errorf("sdk not initialized"))
	}
	if err := db.ExportBackup(outputPath, passphrase, appVersion, walletPrefix); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok", "path": outputPath})
}

// ImportBackup reads and decrypts a .nodeneo-backup file, destructively
// replacing all conversations, messages, and preferences in the current DB.
func ImportBackup(inputPath, passphrase string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(fmt.Errorf("sdk not initialized"))
	}
	manifest, err := db.ImportBackup(inputPath, passphrase)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(manifest)
}

// SetEncryptionKey installs AES-256-GCM encryption for message content.
// Call after Init once the wallet mnemonic is available. The key must be
// exactly 32 bytes (SHA-256 of the mnemonic). Idempotent; safe to call
// before any messages are saved — legacy plaintext is transparently handled.
func SetEncryptionKey(keyHex string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(fmt.Errorf("sdk not initialized"))
	}
	raw, err := hex.DecodeString(keyHex)
	if err != nil {
		return errJSON(fmt.Errorf("invalid hex key: %w", err))
	}
	if err := db.SetEncryptionKey(raw); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// --- Version ---

// GetProxyRouterVersion returns structured version info for the embedded
// proxy-router SDK as JSON. The "version" field is a git-describe string
// like "v6.0.1-test-12-g00562be9" — when it contains a hyphen-separated
// suffix, the SDK is a fork N commits ahead of the upstream tag.
func GetProxyRouterVersion() string {
	ver := sdk.ProxyRouterVersion()
	commit := sdk.ProxyRouterCommit()

	isFork := false
	upstreamTag := ver
	forkCommits := 0

	// git describe format: <tag>-<N>-g<hash> when ahead of a tag
	parts := strings.Split(ver, "-")
	if len(parts) >= 3 {
		last := parts[len(parts)-1]
		countStr := parts[len(parts)-2]
		if strings.HasPrefix(last, "g") {
			isFork = true
			fmt.Sscanf(countStr, "%d", &forkCommits)
			upstreamTag = strings.Join(parts[:len(parts)-2], "-")
		}
	}

	return resultJSON(map[string]interface{}{
		"version":      ver,
		"commit":       commit,
		"is_fork":      isFork,
		"upstream_tag":  upstreamTag,
		"fork_commits": forkCommits,
	})
}

// --- Logging ---

// GetLogDir returns the absolute path to the log directory.
func GetLogDir() string {
	return logger.LogDir()
}

// SetLogLevel changes the log level at runtime for all emitters:
// the wrapper's rotating file logger (Flutter + wrapper messages) AND the
// SDK's internal zap logger (blockchain/proxy-router messages).
// The preference is persisted so it survives app restarts.
func SetLogLevel(level string) string {
	logger.SetLevel(level)
	if client != nil {
		if err := client.SetLogLevel(level); err != nil {
			logger.Warn("SDK SetLogLevel(%s) failed: %v", level, err)
		}
	}
	mu.Lock()
	d := db
	mu.Unlock()
	if d != nil {
		_ = d.SetPreference("log_level", logger.GetLevel())
	}
	logger.Info("Log level changed to %s (wrapper + SDK)", logger.GetLevel())
	return resultJSON(map[string]string{"status": "ok", "level": logger.GetLevel()})
}

// restoreSavedLogLevelLocked applies the persisted log level preference.
// Must be called while mu is already held (from Init or OpenWalletDatabase).
func restoreSavedLogLevelLocked() {
	if db == nil {
		return
	}
	saved, err := db.GetPreference("log_level")
	if err != nil || saved == "" {
		return
	}
	logger.SetLevel(saved)
	if client != nil {
		_ = client.SetLogLevel(saved)
	}
	logger.Info("Restored saved log level: %s", saved)
}

// GetLogLevel returns the current log level.
func GetLogLevel() string {
	return logger.GetLevel()
}

// SetSessionMaintenanceInterval changes how often the SDK checks for expired sessions
// and auto-closes them (reclaiming locked MOR). intervalSeconds of 0 disables auto-close.
// Default is 900 (15 minutes). Provider-initiated closes already refund MOR on-chain
// immediately, so this only catches naturally-expired sessions.
func SetSessionMaintenanceInterval(intervalSeconds int64) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	client.SetMaintenanceInterval(time.Duration(intervalSeconds) * time.Second)
	return resultJSON(map[string]string{"status": "ok", "interval_seconds": fmt.Sprintf("%d", intervalSeconds)})
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

// VerifyRecoveryMnemonic returns {"ok":true} if the phrase matches the loaded wallet (read-only).
func VerifyRecoveryMnemonic(mnemonic string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	ok, err := client.VerifyMnemonicMatchesCurrent(mnemonic)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]bool{"ok": ok})
}

// VerifyRecoveryPrivateKey returns {"ok":true} if the hex key matches the loaded wallet (read-only).
func VerifyRecoveryPrivateKey(hexKey string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	ok, err := client.VerifyPrivateKeyMatchesCurrent(hexKey)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]bool{"ok": ok})
}

// SendETH sends native ETH (amountWei as decimal string, unit wei). Waits for confirmation.
func SendETH(toAddress, amountWei string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	tx, err := client.SendETH(context.Background(), toAddress, amountWei)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"tx_hash": tx})
}

// SendMOR sends MOR tokens (18 decimals, amountWei as decimal string). Waits for confirmation.
func SendMOR(toAddress, amountWei string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	tx, err := client.SendMOR(context.Background(), toAddress, amountWei)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"tx_hash": tx})
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

// EstimateOpenSessionStake returns JSON matching proxy-router OpenSessionStakeEstimate
// (actual MOR pull for the top-scored bid, supply/budget formula, allowance note).
func EstimateOpenSessionStake(modelID string, durationSeconds int64, directPayment bool) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	s, err := client.EstimateOpenSessionStakeJSON(context.Background(), modelID, durationSeconds, directPayment)
	if err != nil {
		return errJSON(err)
	}
	return s
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
	// Local UI uses SQLite session_id for "On-chain open"; clear it when the chain close succeeds.
	if db != nil {
		_ = db.ClearConversationSessionBySessionID(sessionID)
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

// GetUnclosedUserSessions returns JSON array of open sessions (ClosedAt == 0) for this wallet.
func GetUnclosedUserSessions() string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	js, err := client.GetUnclosedUserSessionsJSON(context.Background())
	if err != nil {
		return errJSON(err)
	}
	return js
}

// --- Chat (direct MOR-RPC via SDK — streaming) ---

// maxChatHistoryMessages caps how many prior SQLite turns we attach (user+assistant); avoids huge prompts.
const maxChatHistoryMessages = 80

func openAIMessagesFromSQLiteHistory(msgs []store.Message, newUserPrompt string) []openai.ChatCompletionMessage {
	n := len(msgs)
	start := 0
	if n > maxChatHistoryMessages {
		start = n - maxChatHistoryMessages
	}
	out := make([]openai.ChatCompletionMessage, 0, n-start+1)
	for _, m := range msgs[start:] {
		role := m.Role
		if role != "user" && role != "assistant" {
			continue
		}
		or := openai.ChatMessageRoleUser
		if role == "assistant" {
			or = openai.ChatMessageRoleAssistant
		}
		out = append(out, openai.ChatCompletionMessage{Role: or, Content: m.Content})
	}
	out = append(out, openai.ChatCompletionMessage{Role: openai.ChatMessageRoleUser, Content: newUserPrompt})
	return out
}

// SendPrompt sends a chat prompt through an open session and persists
// the exchange locally. Returns the full response.
// Prior messages for [conversationID] are loaded from SQLite and sent as OpenAI-style history so the model
// sees full context after app restarts (provider session is separate from chat memory).
// stream: when true, request OpenAI-style streaming (SSE) from the provider; when false, non-streaming completion.
func SendPrompt(sessionID string, conversationID string, prompt string, stream bool) string {
	return sendPromptWithOptionalChunk(sessionID, conversationID, prompt, stream, nil)
}

// SendPromptWithStreamCallback is like [SendPrompt] but invokes [chunk] for each provider delta
// (and again with isLast=true on the final chunk). When [chunk] returns an error, streaming aborts.
// [chunk] may be nil (same behavior as [SendPrompt]).
func SendPromptWithStreamCallback(sessionID string, conversationID string, prompt string, stream bool, chunk func(text string, isLast bool) error) string {
	return sendPromptWithOptionalChunk(sessionID, conversationID, prompt, stream, chunk)
}

// SendPromptWithStreamCallbackAsync is the non-blocking variant of [SendPromptWithStreamCallback].
// It launches the prompt in a goroutine and returns immediately. Streaming deltas arrive through
// [chunk]; the final result JSON is delivered through [done]. This allows the FFI caller's event
// loop to process delta callbacks in real-time instead of batching them after completion.
func SendPromptWithStreamCallbackAsync(sessionID, conversationID, prompt string, stream bool, chunk func(text string, isLast bool) error, done func(resultJSON string)) {
	go func() {
		result := sendPromptWithOptionalChunk(sessionID, conversationID, prompt, stream, chunk)
		done(result)
	}()
}

func sendPromptWithOptionalChunk(sessionID string, conversationID string, prompt string, stream bool, chunk func(text string, isLast bool) error) string {
	mu.Lock()
	c := client
	d := db
	mu.Unlock()

	if c == nil {
		return errJSON(errNotInit)
	}

	var omsgs []openai.ChatCompletionMessage
	if d != nil {
		prev, err := d.GetMessages(conversationID)
		if err != nil {
			return errJSON(err)
		}
		omsgs = openAIMessagesFromSQLiteHistory(prev, prompt)
	} else {
		omsgs = []openai.ChatCompletionMessage{{Role: openai.ChatMessageRoleUser, Content: prompt}}
	}

	var fullResponse string
	err := c.SendPromptWithMessages(context.Background(), sessionID, omsgs, stream, func(text string, isLast bool) error {
		fullResponse += text
		if chunk != nil {
			return chunk(text, isLast)
		}
		return nil
	})
	if err != nil {
		return errJSON(err)
	}

	if d != nil {
		_ = d.SaveMessage(conversationID, "user", prompt)
		_ = d.SaveMessage(conversationID, "assistant", fullResponse)
	}

	return resultJSON(map[string]string{"response": fullResponse})
}

// TuningOptions maps the JSON blob from the UI/FFI layer to SDK ChatParams.
type TuningOptions struct {
	Temperature      *float32 `json:"temperature,omitempty"`
	TopP             *float32 `json:"top_p,omitempty"`
	MaxTokens        *int     `json:"max_tokens,omitempty"`
	FrequencyPenalty *float32 `json:"frequency_penalty,omitempty"`
	PresencePenalty  *float32 `json:"presence_penalty,omitempty"`
}

func (t *TuningOptions) toChatParams() *sdk.ChatParams {
	if t == nil {
		return nil
	}
	return &sdk.ChatParams{
		Temperature:      t.Temperature,
		TopP:             t.TopP,
		MaxTokens:        t.MaxTokens,
		FrequencyPenalty: t.FrequencyPenalty,
		PresencePenalty:  t.PresencePenalty,
	}
}

// SendPromptWithOptions sends a prompt with optional tuning parameters.
// [optionsJSON] is a JSON blob with temperature, top_p, max_tokens, etc.
// Empty string or "{}" uses SDK defaults.
func SendPromptWithOptions(sessionID, conversationID, prompt, optionsJSON string, stream bool, chunk func(text string, isLast bool) error) string {
	return sendPromptWithOptions(sessionID, conversationID, prompt, optionsJSON, stream, chunk)
}

// SendPromptWithOptionsAsync is the non-blocking variant of [SendPromptWithOptions].
func SendPromptWithOptionsAsync(sessionID, conversationID, prompt, optionsJSON string, stream bool, chunk func(text string, isLast bool) error, done func(resultJSON string)) {
	go func() {
		result := sendPromptWithOptions(sessionID, conversationID, prompt, optionsJSON, stream, chunk)
		done(result)
	}()
}

func sendPromptWithOptions(sessionID, conversationID, prompt, optionsJSON string, stream bool, chunk func(text string, isLast bool) error) string {
	// Grab references under the lock, then release before the (potentially long) SDK call.
	mu.Lock()
	c := client
	d := db
	mu.Unlock()

	if c == nil {
		return errJSON(errNotInit)
	}

	var opts *TuningOptions
	if optionsJSON != "" && optionsJSON != "{}" {
		opts = &TuningOptions{}
		if err := json.Unmarshal([]byte(optionsJSON), opts); err != nil {
			return errJSON(fmt.Errorf("invalid options JSON: %w", err))
		}
	}

	var omsgs []openai.ChatCompletionMessage
	if d != nil {
		prev, err := d.GetMessages(conversationID)
		if err != nil {
			return errJSON(err)
		}
		omsgs = openAIMessagesFromSQLiteHistory(prev, prompt)
	} else {
		omsgs = []openai.ChatCompletionMessage{{Role: openai.ChatMessageRoleUser, Content: prompt}}
	}

	logger.Debug("INFERENCE request: session=%s conv=%s stream=%v msgs=%d", sessionID, conversationID, stream, len(omsgs))
	if opts != nil {
		logger.Debug("INFERENCE tuning: temp=%.2f top_p=%.2f max_tokens=%d freq=%.2f pres=%.2f",
			opts.Temperature, opts.TopP, opts.MaxTokens, opts.FrequencyPenalty, opts.PresencePenalty)
	}

	startTime := time.Now()
	var fullResponse string

	rawChunkJSON, err := c.SendPromptWithMessagesAndParams(context.Background(), sessionID, omsgs, stream, opts.toChatParams(), func(text string, isLast bool) error {
		fullResponse += text
		if chunk != nil {
			return chunk(text, isLast)
		}
		return nil
	})
	if err != nil {
		logger.Error("INFERENCE failed after %dms: %v", time.Since(startTime).Milliseconds(), err)
		return errJSON(err)
	}

	latencyMs := time.Since(startTime).Milliseconds()
	respLen := len(fullResponse)
	logger.Debug("INFERENCE response: %dms, %d chars, raw_meta=%d bytes", latencyMs, respLen, len(rawChunkJSON))
	if respLen == 0 {
		logger.Warn("INFERENCE empty response from provider (session=%s, %dms)", sessionID, latencyMs)
	}

	// Build result: start with any raw provider metadata the SDK captured,
	// then overlay our own fields so they're always present.
	result := map[string]interface{}{}
	if len(rawChunkJSON) > 0 {
		var raw map[string]interface{}
		if json.Unmarshal(rawChunkJSON, &raw) == nil {
			result["provider_response"] = raw
		}
	}
	result["response"] = fullResponse
	result["latency_ms"] = latencyMs

	if d != nil {
		_ = d.SaveMessage(conversationID, "user", prompt)
		metaJSON, _ := json.Marshal(result)
		_ = d.SaveMessageWithMetadata(conversationID, "assistant", fullResponse, string(metaJSON))
	}

	return resultJSON(result)
}

// --- Conversations (local SQLite) ---

// CreateConversation inserts a conversation row so messages can reference it (FK).
func CreateConversation(id, modelID, modelName, provider string, isTEE bool) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.CreateConversation(id, modelID, modelName, provider, isTEE); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// SetConversationSession persists the open MOR-RPC session id for local resume (home screen / drawer).
func SetConversationSession(conversationID, sessionID string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.SetConversationSession(conversationID, sessionID); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// SetConversationTitle updates the thread title shown in local history.
func SetConversationTitle(conversationID, title string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.SetConversationTitle(conversationID, title); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// SetConversationPinned pins or unpins a thread in local history.
func SetConversationPinned(conversationID string, pinned bool) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.SetConversationPinned(conversationID, pinned); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// SetConversationTuning stores tuning params (JSON blob) for a conversation.
func SetConversationTuning(conversationID, tuningJSON string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.SetConversationTuning(conversationID, tuningJSON); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
}

// GetConversationTuning returns the stored tuning params JSON blob for a conversation.
func GetConversationTuning(conversationID string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	raw, err := db.GetConversationTuning(conversationID)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]interface{}{"tuning_params": raw})
}

// ClaimEmptyDraftForModel returns the newest message-less conversation for this model, deletes
// other empty duplicates for that model, and refreshes model_name / is_tee. Empty JSON ids mean
// the UI should create a brand-new conversation (no draft to reuse).
func ClaimEmptyDraftForModel(modelID, modelName, provider string, isTEE bool) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	c, ok, err := db.LatestEmptyConversationForModel(modelID)
	if err != nil {
		return errJSON(err)
	}
	if !ok {
		return resultJSON(map[string]string{"conversation_id": "", "session_id": ""})
	}
	if err := db.DeleteOtherEmptyConversationsForModel(modelID, c.ID); err != nil {
		return errJSON(err)
	}
	if err := db.UpdateConversationModelMeta(c.ID, modelName, provider, isTEE); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"conversation_id": c.ID, "session_id": c.SessionID})
}

// DeleteConversation removes local messages and the conversation row. If a session_id is stored,
// attempts to close that session on-chain first (same as the Close Session flow). Local rows are
// always removed; if on-chain close fails, close_warning explains why.
func DeleteConversation(conversationID string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	sid, err := db.GetConversationSessionID(conversationID)
	if err != nil {
		return errJSON(err)
	}
	var closeWarning string
	if sid != "" && client != nil {
		nShare, nerr := db.CountConversationsWithSessionID(sid)
		if nerr != nil {
			nShare = 1
		}
		// Only submit on-chain close when this is the last local thread using the session.
		if nShare <= 1 {
			_, cerr := client.CloseSession(context.Background(), sid)
			if cerr != nil {
				closeWarning = cerr.Error()
			} else {
				_ = db.ClearConversationSessionBySessionID(sid)
			}
		}
	}
	if err := db.DeleteConversation(conversationID); err != nil {
		return errJSON(err)
	}
	if closeWarning != "" {
		return resultJSON(map[string]string{"status": "ok", "close_warning": closeWarning})
	}
	return resultJSON(map[string]string{"status": "ok"})
}

func normalizeChainSessionKey(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	s = strings.TrimPrefix(s, "0x")
	return s
}

func parseEndsAtUnix(endsAt string) int64 {
	endsAt = strings.TrimSpace(endsAt)
	if endsAt == "" || endsAt == "0" {
		return 0
	}
	v, ok := new(big.Int).SetString(endsAt, 10)
	if !ok || v == nil {
		return 0
	}
	if !v.IsInt64() {
		return 0
	}
	return v.Int64()
}

// chainSessionSnapshot is built from on-chain unclosed sessions (ClosedAt==0) minus wall-clock expired.
type chainSessionSnapshot struct {
	UsableKeys map[string]bool
	EndsAt     map[string]int64
}

// loadChainSessionSnapshot fetches open sessions and marks past ends_at as unusable for local UI.
func loadChainSessionSnapshot() (*chainSessionSnapshot, bool) {
	if client == nil {
		return &chainSessionSnapshot{UsableKeys: map[string]bool{}, EndsAt: map[string]int64{}}, true
	}
	list, err := client.GetUnclosedUserSessions(context.Background())
	if err != nil {
		return nil, false
	}
	now := time.Now().Unix()
	snap := &chainSessionSnapshot{
		UsableKeys: make(map[string]bool),
		EndsAt:     make(map[string]int64),
	}
	for _, ses := range list {
		k := normalizeChainSessionKey(ses.ID)
		if k == "" {
			continue
		}
		end := parseEndsAtUnix(ses.EndsAt)
		if end > 0 && now >= end {
			continue
		}
		snap.UsableKeys[k] = true
		if end > 0 {
			snap.EndsAt[k] = end
		}
	}
	return snap, true
}

// ReusableSessionForModel returns an active, non-expired on-chain session id for this model, if any.
func ReusableSessionForModel(modelID string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	want := strings.ToLower(strings.TrimSpace(modelID))
	if want == "" {
		return resultJSON(map[string]string{"session_id": ""})
	}
	list, err := client.GetUnclosedUserSessions(context.Background())
	if err != nil {
		return errJSON(err)
	}
	now := time.Now().Unix()
	for _, ses := range list {
		if strings.ToLower(strings.TrimSpace(ses.ModelAgentID)) != want {
			continue
		}
		end := parseEndsAtUnix(ses.EndsAt)
		if end > 0 && now >= end {
			continue
		}
		id := strings.TrimSpace(ses.ID)
		if id == "" {
			continue
		}
		return resultJSON(map[string]string{"session_id": id})
	}
	return resultJSON(map[string]string{"session_id": ""})
}

// GetConversations lists all saved conversations.
func GetConversations() string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	snap, ok := loadChainSessionSnapshot()
	if ok {
		_ = db.ReconcileConversationSessions(snap.UsableKeys)
	}
	convos, err := db.ListConversations(100)
	if err != nil {
		return errJSON(err)
	}
	if ok {
		for i := range convos {
			if convos[i].SessionID == "" {
				continue
			}
			k := normalizeChainSessionKey(convos[i].SessionID)
			if end, has := snap.EndsAt[k]; has && end > 0 {
				convos[i].SessionEndsAt = end
			}
		}
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

// --- Expert Mode (native proxy-router swagger API) ---

// StartExpertAPI starts the native proxy-router HTTP server (swagger UI + full REST API).
// address is "host:port", e.g. "127.0.0.1:8082" for local-only or "0.0.0.0:8082" for network.
// publicURL sets the Swagger host for CORS (e.g. "http://192.168.1.42:8082").
func StartExpertAPI(address, publicURL string) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	if err := client.StartHTTPServer(address, publicURL); err != nil {
		return errJSON(err)
	}
	logger.Info("Expert API (swagger) started on %s (public: %s)", address, publicURL)
	return resultJSON(map[string]string{"status": "ok", "address": address, "public_url": publicURL})
}

// StopExpertAPI stops the native proxy-router HTTP server.
func StopExpertAPI() string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	client.StopHTTPServer()
	logger.Info("Expert API stopped")
	return resultJSON(map[string]string{"status": "ok"})
}

// ExpertAPIStatus returns whether the API server is running and on which address.
func ExpertAPIStatus() string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	addr := client.HTTPServerAddr()
	running := addr != ""
	return resultJSON(map[string]interface{}{"running": running, "address": addr})
}

// --- Gateway (OpenAI-compatible API for external consumers like Cursor) ---

var gw *gateway.Gateway
var cfTunnel *cloudflared.QuickTunnel

// StartGateway starts the OpenAI-compatible gateway HTTP server.
// address is "host:port", e.g. "127.0.0.1:8083" or "0.0.0.0:8083".
// If cloudflaredQuickTunnel is true, also runs `cloudflared tunnel --url http://127.0.0.1:port`
// and returns the public https://*.trycloudflare.com URL in JSON (requires cloudflared on PATH).
func StartGateway(address string, cloudflaredQuickTunnel bool) string {
	mu.Lock()
	defer mu.Unlock()
	if client == nil {
		return errJSON(errNotInit)
	}
	if db == nil {
		return errJSON(fmt.Errorf("database not initialized"))
	}
	if gw != nil && gw.Running() {
		return errJSON(fmt.Errorf("gateway already running on %s", gw.Addr()))
	}

	dur, _ := db.GetPreference("gateway_session_duration")
	durationSec := int64(3600)
	if dur != "" {
		fmt.Sscanf(dur, "%d", &durationSec)
	}

	gw = gateway.New(client, db, func(format string, args ...interface{}) {
		logger.Info("[GATEWAY] "+format, args...)
	}, durationSec)

	if err := gw.Start(address); err != nil {
		return errJSON(err)
	}

	if cloudflaredQuickTunnel {
		origin, err := cloudflared.LocalHTTPOrigin(address)
		if err != nil {
			_ = gw.Stop()
			gw = nil
			return errJSON(err)
		}
		t, err := cloudflared.StartQuickTunnel(context.Background(), origin)
		if err != nil {
			_ = gw.Stop()
			gw = nil
			return errJSON(err)
		}
		cfTunnel = t
		logger.Info("Cloudflare quick tunnel: %s → %s", t.URL, origin)
	}

	logger.Info("Gateway started on %s", address)
	out := map[string]interface{}{"status": "ok", "address": address}
	if cfTunnel != nil {
		out["cloudflared_url"] = cfTunnel.URL
	}
	return resultJSON(out)
}

// StopGateway stops the gateway HTTP server.
func StopGateway() string {
	mu.Lock()
	defer mu.Unlock()
	if gw == nil {
		return resultJSON(map[string]string{"status": "ok"})
	}
	if cfTunnel != nil {
		_ = cfTunnel.Stop()
		cfTunnel = nil
	}
	if err := gw.Stop(); err != nil {
		return errJSON(err)
	}
	gw = nil
	logger.Info("Gateway stopped")
	return resultJSON(map[string]string{"status": "ok"})
}

// GatewayStatus returns whether the gateway is running and on which address.
func GatewayStatus() string {
	mu.Lock()
	defer mu.Unlock()
	if gw == nil {
		return resultJSON(map[string]interface{}{"running": false, "address": ""})
	}
	m := map[string]interface{}{"running": gw.Running(), "address": gw.Addr()}
	if cfTunnel != nil {
		m["cloudflared_url"] = cfTunnel.URL
	}
	return resultJSON(m)
}

// --- API Key management ---

// GenerateAPIKey creates a new API key for gateway access.
// Returns the full key (shown once to the user) and metadata.
func GenerateAPIKey(name string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	fullKey, info, err := db.GenerateAPIKey(name)
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]interface{}{
		"id":     info.ID,
		"key":    fullKey,
		"prefix": info.Prefix,
		"name":   info.Name,
	})
}

// ListAPIKeys returns all active API keys (never exposes secrets).
func ListAPIKeys() string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	keys, err := db.ListAPIKeys()
	if err != nil {
		return errJSON(err)
	}
	return resultJSON(keys)
}

// RevokeAPIKey deletes an API key, immediately blocking access.
func RevokeAPIKey(id string) string {
	mu.Lock()
	defer mu.Unlock()
	if db == nil {
		return errJSON(errNotInit)
	}
	if err := db.RevokeAPIKey(id); err != nil {
		return errJSON(err)
	}
	return resultJSON(map[string]string{"status": "ok"})
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
