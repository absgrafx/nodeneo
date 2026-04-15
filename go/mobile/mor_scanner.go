package mobile

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
)

const (
	inferenceContract = "0x6aBE1d282f72B474E54527D93b979A4f64d3030a"
	morToken          = "0x7431ada8a591c955a994a21710752ef9b882b8e3"
	defaultBaseRPC    = "https://mainnet.base.org"
	baseChainID       = 8453
	scanTimeout       = 30 * time.Second
)

// sanitizeRPCURL returns only the hostname from an RPC URL for safe error messages.
func sanitizeRPCURL(raw string) string {
	u := strings.TrimSpace(raw)
	if idx := strings.Index(u, "://"); idx >= 0 {
		host := u[idx+3:]
		if slash := strings.Index(host, "/"); slash >= 0 {
			host = host[:slash]
		}
		if qmark := strings.Index(host, "?"); qmark >= 0 {
			host = host[:qmark]
		}
		return host
	}
	return "unknown-rpc"
}

// rpcURLs returns the saved RPC URLs (split on commas) or the default.
func rpcURLs() []string {
	src := savedRPC
	if src == "" {
		src = defaultBaseRPC
	}
	var urls []string
	for _, u := range strings.Split(src, ",") {
		u = strings.TrimSpace(u)
		if u != "" {
			urls = append(urls, u)
		}
	}
	if len(urls) == 0 {
		return []string{defaultBaseRPC}
	}
	return urls
}

// ethCall performs a read-only eth_call, trying each RPC URL until one succeeds.
func ethCall(to, data string) (string, error) {
	body := fmt.Sprintf(
		`{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"%s","data":"%s"},"latest"]}`,
		to, data,
	)
	var lastErr error
	for _, rpc := range rpcURLs() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		req, err := http.NewRequestWithContext(ctx, "POST", rpc, bytes.NewBufferString(body))
		if err != nil {
			cancel()
			lastErr = err
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			cancel()
			lastErr = fmt.Errorf("RPC connection failed (%s)", sanitizeRPCURL(rpc))
			continue
		}
		raw, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		cancel()
		if err != nil {
			lastErr = fmt.Errorf("RPC read failed (%s)", sanitizeRPCURL(rpc))
			continue
		}
		var rpcResp struct {
			Result string `json:"result"`
			Error  *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if err := json.Unmarshal(raw, &rpcResp); err != nil {
			lastErr = fmt.Errorf("bad RPC response (%s)", sanitizeRPCURL(rpc))
			continue
		}
		if rpcResp.Error != nil {
			lastErr = fmt.Errorf("RPC error (%s): %s", sanitizeRPCURL(rpc), rpcResp.Error.Message)
			continue
		}
		return rpcResp.Result, nil
	}
	return "", fmt.Errorf("all RPC endpoints failed: %v", lastErr)
}

// abiEncodeAddress pads an address to 32 bytes for ABI encoding.
func abiEncodeAddress(addr string) string {
	addr = strings.TrimPrefix(strings.ToLower(addr), "0x")
	return fmt.Sprintf("%064s", addr)
}

// abiEncodeUint8 pads a uint8 to 32 bytes.
func abiEncodeUint8(v uint8) string {
	return fmt.Sprintf("%064x", v)
}

// abiEncodeUint256 pads a big.Int to 32 bytes.
func abiEncodeUint256(v *big.Int) string {
	return fmt.Sprintf("%064x", v)
}

// decodeBigInt parses a hex string (with 0x prefix) into a big.Int.
func decodeBigInt(hexStr string) *big.Int {
	hexStr = strings.TrimPrefix(hexStr, "0x")
	if hexStr == "" || hexStr == "0" {
		return big.NewInt(0)
	}
	v, ok := new(big.Int).SetString(hexStr, 16)
	if !ok {
		return big.NewInt(0)
	}
	return v
}

// formatMOR converts a wei big.Int to a human-readable MOR string (4 decimal places).
func formatMOR(wei *big.Int) string {
	if wei.Sign() == 0 {
		return "0"
	}
	ether := new(big.Float).SetInt(wei)
	divisor := new(big.Float).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil))
	ether.Quo(ether, divisor)
	return ether.Text('f', 4)
}

// ScanWalletMOR performs read-only on-chain lookups to show where the user's MOR lives.
// Returns JSON with wallet_balance, active_stake, on_hold_available, on_hold_locked, total.
func ScanWalletMOR() string {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		return errJSON(errNotInit)
	}

	addr, err := c.GetAddress()
	if err != nil {
		return errJSON(fmt.Errorf("no wallet address: %w", err))
	}

	addrPadded := abiEncodeAddress(addr)

	// 1. MOR balance in wallet: balanceOf(address) = 0x70a08231
	balData := "0x70a08231" + addrPadded
	balResult, err := ethCall(morToken, balData)
	if err != nil {
		return errJSON(fmt.Errorf("balanceOf failed: %w", err))
	}
	walletWei := decodeBigInt(balResult)

	// 2. On-hold stakes: getUserStakesOnHold(address, uint8) = 0x967885df
	holdData := "0x967885df" + addrPadded + abiEncodeUint8(1)
	holdResult, err := ethCall(inferenceContract, holdData)
	if err != nil {
		return errJSON(fmt.Errorf("getUserStakesOnHold failed: %w", err))
	}
	// Returns (uint256 available_, uint256 hold_) — two 32-byte words
	holdHex := strings.TrimPrefix(holdResult, "0x")
	availableWei := big.NewInt(0)
	holdWei := big.NewInt(0)
	if len(holdHex) >= 128 {
		availableWei = decodeBigInt("0x" + holdHex[:64])
		holdWei = decodeBigInt("0x" + holdHex[64:128])
	}

	// 3. Active session stake: getUserSessions to get count, then getSession for each
	//    getUserSessions(address, uint256 offset, uint256 limit) = 0xeb7764bb
	//    First call with offset=0, limit=0 to get total count
	countData := "0xeb7764bb" + addrPadded + abiEncodeUint256(big.NewInt(0)) + abiEncodeUint256(big.NewInt(0))
	countResult, err := ethCall(inferenceContract, countData)
	if err != nil {
		return errJSON(fmt.Errorf("getUserSessions count failed: %w", err))
	}
	// Returns (bytes32[], uint256 total) — dynamic array + total
	countHex := strings.TrimPrefix(countResult, "0x")
	totalSessions := 0
	if len(countHex) >= 128 {
		// Skip first 32 bytes (offset to array data), read second 32 bytes (total)
		totalBig := decodeBigInt("0x" + countHex[64:128])
		totalSessions = int(totalBig.Int64())
	}

	// Scan all sessions from newest to oldest to find open (unclosed) ones.
	const batchSize = 50
	openStakeWei := big.NewInt(0)
	openCount := 0
	expiredUnclosedCount := 0
	scannedCount := 0

	remaining := totalSessions
	for remaining > 0 {
		limit := remaining
		if limit > batchSize {
			limit = batchSize
		}
		offset := remaining - limit
		if offset < 0 {
			offset = 0
		}

		sessData := "0xeb7764bb" + addrPadded + abiEncodeUint256(big.NewInt(int64(offset))) + abiEncodeUint256(big.NewInt(int64(limit)))
		sessResult, err := ethCall(inferenceContract, sessData)
		if err != nil {
			break
		}
		sessHex := strings.TrimPrefix(sessResult, "0x")
		if len(sessHex) < 192 {
			break
		}
		arrLen := decodeBigInt("0x" + sessHex[128:192])
		idCount := int(arrLen.Int64())
		for i := 0; i < idCount; i++ {
			start := 192 + i*64
			end := start + 64
			if end > len(sessHex) {
				break
			}
			sessionID := "0x" + sessHex[start:end]
			sess, serr := getSessionData(sessionID)
			if serr != nil {
				continue
			}
			scannedCount++
			if sess.closedAt.Sign() == 0 {
				openCount++
				openStakeWei.Add(openStakeWei, sess.stake)
				now := time.Now().Unix()
				if sess.endsAt.Int64() <= now {
					expiredUnclosedCount++
				}
			}
		}
		remaining -= limit
	}

	onHoldTotal := new(big.Int).Add(availableWei, holdWei)
	total := new(big.Int).Add(walletWei, new(big.Int).Add(openStakeWei, onHoldTotal))

	return resultJSON(map[string]interface{}{
		"address":                addr,
		"wallet_balance_wei":     walletWei.String(),
		"wallet_balance":         formatMOR(walletWei),
		"active_stake_wei":       openStakeWei.String(),
		"active_stake":           formatMOR(openStakeWei),
		"on_hold_available_wei":  availableWei.String(),
		"on_hold_available":      formatMOR(availableWei),
		"on_hold_locked_wei":     holdWei.String(),
		"on_hold_locked":         formatMOR(holdWei),
		"on_hold_total_wei":      onHoldTotal.String(),
		"on_hold_total":          formatMOR(onHoldTotal),
		"total_wei":              total.String(),
		"total":                  formatMOR(total),
		"open_sessions":          openCount,
		"expired_unclosed":       expiredUnclosedCount,
		"total_sessions":         totalSessions,
		"scanned":                scannedCount,
		"incomplete":             scannedCount < totalSessions,
	})
}

type sessionData struct {
	stake    *big.Int
	endsAt   *big.Int
	closedAt *big.Int
}

// getSession(bytes32 sessionId_) = 0x79f6f637 (from ABI)
// Actually the selector for getSession varies. Let me use the proper one.
// From the contract bindings: getSession(bytes32) returns tuple
// Selector: function signature hash
func getSessionData(sessionID string) (*sessionData, error) {
	sid := strings.TrimPrefix(sessionID, "0x")
	if len(sid) < 64 {
		sid = fmt.Sprintf("%064s", sid)
	}
	// getSession(bytes32) selector = 0xd9ef1c5b (from SessionRouter ABI binding 0xd9ef1c5b)
	// Actually let me compute it: keccak256("getSession(bytes32)")
	// The bindings show: function getSession(bytes32 sessionId_) view returns(tuple(...))
	data := "0x" + selectorGetSession + sid
	result, err := ethCall(inferenceContract, data)
	if err != nil {
		return nil, err
	}
	resultHex := strings.TrimPrefix(result, "0x")
	// The return is ABI-encoded as a dynamic tuple (contains `bytes`).
	// Word 0 is the offset to the tuple head (0x20), so actual fields
	// start at word 1. Raw word indices in resultHex:
	//   [0] offset (0x20)
	//   [1] user (address)
	//   [2] bidId (bytes32)
	//   [3] stake (uint256)
	//   [4] offset to closeoutReceipt (dynamic bytes)
	//   [5] closeoutType (uint256)
	//   [6] providerWithdrawnAmount (uint256)
	//   [7] openedAt (uint128)
	//   [8] endsAt (uint128)
	//   [9] closedAt (uint128)
	//   [10] isActive (bool)
	//   [11] isDirectPaymentFromUser (bool)
	if len(resultHex) < 64*10 {
		return nil, fmt.Errorf("getSession response too short")
	}
	stake := decodeBigInt("0x" + resultHex[3*64:4*64])
	endsAt := decodeBigInt("0x" + resultHex[8*64:9*64])
	closedAt := decodeBigInt("0x" + resultHex[9*64:10*64])
	return &sessionData{stake: stake, endsAt: endsAt, closedAt: closedAt}, nil
}

// Compute the function selector for getSession(bytes32)
var selectorGetSession = func() string {
	hash := crypto.Keccak256([]byte("getSession(bytes32)"))
	return hex.EncodeToString(hash[:4])
}()

// WithdrawUserStakes sends an on-chain transaction to recover claimable on-hold MOR.
// iterations controls how many on-hold rows to process (20 is typical).
func WithdrawUserStakes(iterations int) string {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		return errJSON(errNotInit)
	}

	addr, err := c.GetAddress()
	if err != nil {
		return errJSON(fmt.Errorf("no wallet address: %w", err))
	}

	pkHex, err := c.ExportPrivateKey()
	if err != nil {
		return errJSON(fmt.Errorf("cannot access private key: %w", err))
	}

	pkHex = strings.TrimPrefix(pkHex, "0x")
	privateKey, err := crypto.HexToECDSA(pkHex)
	if err != nil {
		return errJSON(fmt.Errorf("invalid private key: %w", err))
	}

	if iterations <= 0 || iterations > 255 {
		iterations = 20
	}

	// Build calldata: withdrawUserStakes(address, uint8) = 0xa98a7c6b
	calldata := "0xa98a7c6b" + abiEncodeAddress(addr) + abiEncodeUint8(uint8(iterations))
	calldataBytes, err := hex.DecodeString(strings.TrimPrefix(calldata, "0x"))
	if err != nil {
		return errJSON(fmt.Errorf("encode calldata: %w", err))
	}

	txHash, err := sendTransaction(privateKey, common.HexToAddress(inferenceContract), calldataBytes)
	if err != nil {
		return errJSON(fmt.Errorf("withdraw transaction failed: %w", err))
	}

	return resultJSON(map[string]string{
		"status":  "ok",
		"tx_hash": txHash,
	})
}

// sendTransaction builds, signs, and broadcasts an EIP-1559 transaction on Base.
func sendTransaction(key *ecdsa.PrivateKey, to common.Address, data []byte) (string, error) {
	from := crypto.PubkeyToAddress(key.PublicKey)

	// Get nonce
	nonceHex, err := rpcCall("eth_getTransactionCount", fmt.Sprintf(`["%s","pending"]`, from.Hex()))
	if err != nil {
		return "", fmt.Errorf("get nonce: %w", err)
	}
	nonce := decodeBigInt(nonceHex).Uint64()

	// Estimate gas
	toHex := to.Hex()
	dataHex := "0x" + hex.EncodeToString(data)
	gasHex, err := rpcCall("eth_estimateGas", fmt.Sprintf(`[{"from":"%s","to":"%s","data":"%s"}]`, from.Hex(), toHex, dataHex))
	if err != nil {
		return "", fmt.Errorf("estimate gas: %w", err)
	}
	gasLimit := decodeBigInt(gasHex).Uint64()
	if gasLimit < 100000 {
		gasLimit = 100000
	}
	gasLimit = gasLimit * 130 / 100 // 30% buffer

	// Get base fee from latest block
	blockJSON, err := rpcCall("eth_getBlockByNumber", `["latest",false]`)
	if err != nil {
		return "", fmt.Errorf("get block: %w", err)
	}
	var blockData struct {
		BaseFeePerGas string `json:"baseFeePerGas"`
	}
	if err := json.Unmarshal([]byte(blockJSON), &blockData); err != nil {
		return "", fmt.Errorf("parse block: %w", err)
	}
	baseFee := decodeBigInt(blockData.BaseFeePerGas)
	maxPriorityFee := big.NewInt(100000000) // 0.1 gwei tip
	maxFee := new(big.Int).Add(new(big.Int).Mul(baseFee, big.NewInt(2)), maxPriorityFee)

	chainID := big.NewInt(baseChainID)
	tx := types.NewTx(&types.DynamicFeeTx{
		ChainID:   chainID,
		Nonce:     nonce,
		GasTipCap: maxPriorityFee,
		GasFeeCap: maxFee,
		Gas:       gasLimit,
		To:        &to,
		Value:     big.NewInt(0),
		Data:      data,
	})

	signer := types.NewLondonSigner(chainID)
	signedTx, err := types.SignTx(tx, signer, key)
	if err != nil {
		return "", fmt.Errorf("sign tx: %w", err)
	}

	rawBytes, err := signedTx.MarshalBinary()
	if err != nil {
		return "", fmt.Errorf("encode tx: %w", err)
	}
	rawHex := "0x" + hex.EncodeToString(rawBytes)

	txHashHex, err := rpcCall("eth_sendRawTransaction", fmt.Sprintf(`["%s"]`, rawHex))
	if err != nil {
		return "", fmt.Errorf("send tx: %w", err)
	}

	return txHashHex, nil
}

// rpcCall makes a JSON-RPC call, trying each URL until one succeeds.
func rpcCall(method, paramsJSON string) (string, error) {
	body := fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"method":"%s","params":%s}`, method, paramsJSON)
	var lastErr error
	for _, rpc := range rpcURLs() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		req, err := http.NewRequestWithContext(ctx, "POST", rpc, bytes.NewBufferString(body))
		if err != nil {
			cancel()
			lastErr = err
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			cancel()
			lastErr = fmt.Errorf("RPC connection failed (%s)", sanitizeRPCURL(rpc))
			continue
		}
		raw, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		cancel()
		if err != nil {
			lastErr = fmt.Errorf("RPC read failed (%s)", sanitizeRPCURL(rpc))
			continue
		}
		var rpcResp struct {
			Result json.RawMessage `json:"result"`
			Error  *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if err := json.Unmarshal(raw, &rpcResp); err != nil {
			lastErr = fmt.Errorf("bad RPC response (%s)", sanitizeRPCURL(rpc))
			continue
		}
		if rpcResp.Error != nil {
			lastErr = fmt.Errorf("RPC error (%s): %s", sanitizeRPCURL(rpc), rpcResp.Error.Message)
			continue
		}
		var s string
		if err := json.Unmarshal(rpcResp.Result, &s); err == nil {
			return s, nil
		}
		return string(rpcResp.Result), nil
	}
	return "", fmt.Errorf("all RPC endpoints failed: %v", lastErr)
}
