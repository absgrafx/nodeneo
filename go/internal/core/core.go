package core

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"math/big"
	"sync"

	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcutil/hdkeychain"
	"github.com/ethereum/go-ethereum/accounts"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/tyler-smith/go-bip39"
)

var (
	ErrNotInitialized = errors.New("core: engine not initialized")
	ErrNoWallet       = errors.New("core: no wallet configured")
)

const DefaultDerivationPath = "m/44'/60'/0'/0/0"

type Engine struct {
	proxyBaseURL string
	privKey      *ecdsa.PrivateKey
	address      common.Address
	client       *ProxyClient
	mu           sync.RWMutex
	ready        bool
}

type Config struct {
	DataDir      string // path to app data directory
	ProxyBaseURL string // e.g. "http://localhost:8082"
}

func NewEngine(cfg Config) *Engine {
	return &Engine{
		proxyBaseURL: cfg.ProxyBaseURL,
		client:       NewProxyClient(cfg.ProxyBaseURL),
	}
}

func (e *Engine) Init(ctx context.Context) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.ready = true
	return nil
}

func (e *Engine) Close() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.ready = false
	e.privKey = nil
	e.address = common.Address{}
	return nil
}

func (e *Engine) IsReady() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.ready
}

func (e *Engine) HasWallet() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.privKey != nil
}

func (e *Engine) Address() string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.privKey == nil {
		return ""
	}
	return e.address.Hex()
}

func (e *Engine) Client() *ProxyClient {
	return e.client
}

// --- Wallet: native implementation using go-ethereum + go-bip39 ---

func (e *Engine) CreateWallet() (mnemonic string, address string, err error) {
	entropy, err := bip39.NewEntropy(128)
	if err != nil {
		return "", "", err
	}
	mnemonic, err = bip39.NewMnemonic(entropy)
	if err != nil {
		return "", "", err
	}

	addr, err := e.importFromMnemonic(mnemonic, DefaultDerivationPath)
	if err != nil {
		return "", "", err
	}
	return mnemonic, addr, nil
}

func (e *Engine) ImportWallet(mnemonic string, derivationPath string) (address string, err error) {
	if derivationPath == "" {
		derivationPath = DefaultDerivationPath
	}
	return e.importFromMnemonic(mnemonic, derivationPath)
}

func (e *Engine) ImportPrivateKey(hexKey string) (address string, err error) {
	privKey, err := crypto.HexToECDSA(hexKey)
	if err != nil {
		return "", err
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	e.privKey = privKey
	e.address = crypto.PubkeyToAddress(privKey.PublicKey)
	return e.address.Hex(), nil
}

func (e *Engine) importFromMnemonic(mnemonic string, derivationPath string) (string, error) {
	if !bip39.IsMnemonicValid(mnemonic) {
		return "", errors.New("invalid mnemonic")
	}

	seed := bip39.NewSeed(mnemonic, "")
	masterKey, err := hdkeychain.NewMaster(seed, &chaincfg.MainNetParams)
	if err != nil {
		return "", err
	}

	path, err := accounts.ParseDerivationPath(derivationPath)
	if err != nil {
		return "", err
	}

	key := masterKey
	for _, n := range path {
		key, err = key.Derive(n)
		if err != nil {
			return "", err
		}
	}

	ecKey, err := key.ECPrivKey()
	if err != nil {
		return "", err
	}
	privKey := ecKey.ToECDSA()

	e.mu.Lock()
	defer e.mu.Unlock()
	e.privKey = privKey
	e.address = crypto.PubkeyToAddress(privKey.PublicKey)
	return e.address.Hex(), nil
}

func (e *Engine) PrivateKeyHex() (string, error) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.privKey == nil {
		return "", ErrNoWallet
	}
	return common.Bytes2Hex(crypto.FromECDSA(e.privKey)), nil
}

// --- Proxy-router delegated operations ---

type WalletInfo struct {
	Address    string `json:"address"`
	MORBalance string `json:"mor_balance"`
	ETHBalance string `json:"eth_balance"`
}

func (e *Engine) GetBalance(ctx context.Context) (*WalletInfo, error) {
	if !e.IsReady() {
		return nil, ErrNotInitialized
	}
	return e.client.GetBalance(ctx)
}

type Model struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Tags      []string `json:"tags"`
	Stake     string   `json:"stake"`
	Fee       string   `json:"fee"`
	Owner     string   `json:"owner"`
	ModelType string   `json:"model_type"`
	IsDeleted bool     `json:"is_deleted"`
}

func (e *Engine) ListModels(ctx context.Context) ([]Model, error) {
	if !e.IsReady() {
		return nil, ErrNotInitialized
	}
	return e.client.GetAllModels(ctx)
}

type Bid struct {
	ID       string  `json:"id"`
	Provider string  `json:"provider"`
	ModelID  string  `json:"model_id"`
	Price    string  `json:"price_per_second"`
	Score    float64 `json:"score,omitempty"`
}

func (e *Engine) GetRatedBids(ctx context.Context, modelID string) ([]Bid, error) {
	if !e.IsReady() {
		return nil, ErrNotInitialized
	}
	return e.client.GetRatedBids(ctx, modelID)
}

type Session struct {
	ID       string `json:"id"`
	TxHash   string `json:"tx_hash,omitempty"`
	ModelID  string `json:"model_id,omitempty"`
	Provider string `json:"provider,omitempty"`
}

func (e *Engine) OpenSession(ctx context.Context, modelID string, durationSeconds int64) (*Session, error) {
	if !e.IsReady() {
		return nil, ErrNotInitialized
	}
	dur := big.NewInt(durationSeconds)
	return e.client.OpenSessionByModelId(ctx, modelID, dur)
}

func (e *Engine) CloseSession(ctx context.Context, sessionID string) error {
	if !e.IsReady() {
		return ErrNotInitialized
	}
	return e.client.CloseSession(ctx, sessionID)
}

func (e *Engine) SendPrompt(ctx context.Context, sessionID string, modelID string, prompt string) (string, error) {
	if !e.IsReady() {
		return "", ErrNotInitialized
	}
	return e.client.ChatCompletion(ctx, sessionID, modelID, prompt)
}
