package core

import (
	"context"
	"strings"
	"testing"
)

func TestCreateWallet(t *testing.T) {
	eng := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng.Init(context.Background())

	mnemonic, addr, err := eng.CreateWallet()
	if err != nil {
		t.Fatalf("CreateWallet: %v", err)
	}

	words := strings.Fields(mnemonic)
	if len(words) != 12 {
		t.Fatalf("expected 12-word mnemonic, got %d words", len(words))
	}

	if !strings.HasPrefix(addr, "0x") || len(addr) != 42 {
		t.Fatalf("invalid address: %s", addr)
	}

	if eng.Address() != addr {
		t.Fatalf("Address() mismatch: got %s, want %s", eng.Address(), addr)
	}
	t.Logf("mnemonic: %s", mnemonic)
	t.Logf("address:  %s", addr)
}

func TestImportWallet(t *testing.T) {
	eng := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng.Init(context.Background())

	// Well-known test mnemonic (DO NOT use for real funds)
	mnemonic := "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
	addr, err := eng.ImportWallet(mnemonic, "")
	if err != nil {
		t.Fatalf("ImportWallet: %v", err)
	}

	// This mnemonic at m/44'/60'/0'/0/0 produces a well-known address
	expected := "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
	if !strings.EqualFold(addr, expected) {
		t.Fatalf("expected %s, got %s", expected, addr)
	}
	t.Logf("imported address: %s", addr)
}

func TestImportPrivateKey(t *testing.T) {
	eng := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng.Init(context.Background())

	// Random test key (DO NOT use for real funds)
	hexKey := "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
	addr, err := eng.ImportPrivateKey(hexKey)
	if err != nil {
		t.Fatalf("ImportPrivateKey: %v", err)
	}

	expected := "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
	if !strings.EqualFold(addr, expected) {
		t.Fatalf("expected %s, got %s", expected, addr)
	}
	t.Logf("imported address: %s", addr)
}

func TestCreateThenExportKey(t *testing.T) {
	eng := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng.Init(context.Background())

	_, addr1, err := eng.CreateWallet()
	if err != nil {
		t.Fatal(err)
	}

	hex, err := eng.PrivateKeyHex()
	if err != nil {
		t.Fatal(err)
	}

	// Re-import the exported key — should produce the same address
	eng2 := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng2.Init(context.Background())
	addr2, err := eng2.ImportPrivateKey(hex)
	if err != nil {
		t.Fatal(err)
	}

	if !strings.EqualFold(addr1, addr2) {
		t.Fatalf("round-trip failed: %s != %s", addr1, addr2)
	}
}

func TestInvalidMnemonic(t *testing.T) {
	eng := NewEngine(Config{ProxyBaseURL: "http://localhost:8082"})
	_ = eng.Init(context.Background())

	_, err := eng.ImportWallet("not a valid mnemonic", "")
	if err == nil {
		t.Fatal("expected error for invalid mnemonic")
	}
}
