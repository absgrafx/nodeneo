package core

// Core wraps the proxy-router's key subsystems into a single embeddable engine.
// Once Go is upgraded to 1.25+ and the proxy-router dependency is available,
// this will import and initialize the real blockchain, session, and attestation
// packages. For now, it defines the interface contracts.

import (
	"context"
	"errors"
)

var ErrNotInitialized = errors.New("core: engine not initialized")

type Engine struct {
	dataDir    string
	ethNodeURL string
	chainID    int64
	privKey    string
	ready      bool
}

type Config struct {
	DataDir    string // path to app data directory (platform-specific)
	EthNodeURL string // Arbitrum RPC endpoint
	ChainID    int64  // 42161 for Arbitrum One
}

func NewEngine(cfg Config) *Engine {
	return &Engine{
		dataDir:    cfg.DataDir,
		ethNodeURL: cfg.EthNodeURL,
		chainID:    cfg.ChainID,
	}
}

func (e *Engine) Init(ctx context.Context) error {
	// TODO: Initialize proxy-router subsystems:
	// - Blockchain client (ethNodeURL, chainID)
	// - Session manager
	// - Attestation verifier
	// - MOR-RPC transport
	e.ready = true
	return nil
}

func (e *Engine) Close() error {
	e.ready = false
	return nil
}

func (e *Engine) IsReady() bool {
	return e.ready
}

// --- Wallet ---

type WalletInfo struct {
	Address    string `json:"address"`
	MORBalance string `json:"mor_balance"`
	ETHBalance string `json:"eth_balance"`
}

func (e *Engine) CreateWallet() (mnemonic string, address string, err error) {
	if !e.ready {
		return "", "", ErrNotInitialized
	}
	// TODO: call proxy-router wallet.Create() or use go-ethereum key generation
	return "", "", errors.New("not yet implemented — needs proxy-router dependency")
}

func (e *Engine) ImportWallet(mnemonic string) (address string, err error) {
	if !e.ready {
		return "", ErrNotInitialized
	}
	// TODO: derive key from BIP-39 mnemonic, set as active wallet
	return "", errors.New("not yet implemented — needs proxy-router dependency")
}

func (e *Engine) ImportPrivateKey(hexKey string) (address string, err error) {
	if !e.ready {
		return "", ErrNotInitialized
	}
	return "", errors.New("not yet implemented — needs proxy-router dependency")
}

func (e *Engine) GetBalance(ctx context.Context, address string) (*WalletInfo, error) {
	if !e.ready {
		return nil, ErrNotInitialized
	}
	// TODO: query MOR and ETH balances from Arbitrum
	return nil, errors.New("not yet implemented — needs proxy-router dependency")
}

// --- Models ---

type Model struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Provider string   `json:"provider"`
	IsTEE    bool     `json:"is_tee"`
	Tags     []string `json:"tags"`
	Stake    string   `json:"stake"`
}

func (e *Engine) ListModels(ctx context.Context) ([]Model, error) {
	if !e.ready {
		return nil, ErrNotInitialized
	}
	// TODO: call blockchain.ListModels via proxy-router
	return nil, errors.New("not yet implemented — needs proxy-router dependency")
}

// --- Sessions ---

type Session struct {
	ID         string `json:"id"`
	ModelID    string `json:"model_id"`
	Provider   string `json:"provider"`
	IsTEE      bool   `json:"is_tee"`
	TEEVerified bool  `json:"tee_verified"`
}

func (e *Engine) OpenSession(ctx context.Context, modelID string, providerAddr string) (*Session, error) {
	if !e.ready {
		return nil, ErrNotInitialized
	}
	return nil, errors.New("not yet implemented — needs proxy-router dependency")
}

func (e *Engine) SendPrompt(ctx context.Context, sessionID string, prompt string) (<-chan string, error) {
	if !e.ready {
		return nil, ErrNotInitialized
	}
	// Returns a channel that streams response chunks
	return nil, errors.New("not yet implemented — needs proxy-router dependency")
}

func (e *Engine) CloseSession(ctx context.Context, sessionID string) error {
	if !e.ready {
		return ErrNotInitialized
	}
	return errors.New("not yet implemented — needs proxy-router dependency")
}
