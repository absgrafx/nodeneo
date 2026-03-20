# RedPill — Local testing & wallet reset

Hot-wallet demo on **Base mainnet**. This doc covers persistence, moving funds, **chat / sessions**, and **nuke-and-pave** when you want a clean slate.

---

## Smoke tests (after a build)

| Check | What to do | Pass criteria |
| ----- | ---------- | ------------- |
| **Chat E2E** | Home → tap an LLM (e.g. TEE) → wait for session → send a short prompt | Assistant reply appears; no Go panic |
| **On-chain sessions** | ⋮ → **Open on-chain sessions** (or drawer / Network → RPC → same) | **Close** shows a sheet with **full tx hash**, **Copy**, and **View on Blockscout**; list refreshes after |
| **Streaming flag** | In chat, toggle **Streaming reply** off/on, send two prompts | Both complete; preference survives app restart (`chat_streaming_preference.txt`) |
| **RPC override** | ⋮ → Network / RPC → save custom URL → restart | Init uses override; clear restores defaults |

---

## Wallet persistence (normal use)

- The **BIP-39 mnemonic** is stored in the OS **secure store**:
    - **macOS:** Keychain (via `flutter_secure_storage`). If Keychain returns **-34018** (missing entitlement / unsigned debug), the app falls back to **`Application Support/redpill/.mnemonic_vault`** inside the app container — still sandboxed, but not hardware-backed like Keychain. After a successful Keychain write, the fallback file is removed.
    - **iOS / Android:** Keychain / Keystore as configured by the plugin
- The **Go SDK** only holds keys **in memory**. On each cold start, the app **re-imports** the saved mnemonic so you keep the **same address** and balances.
- **Export private key:** **Wallet** (toolbar icon on home) → **Export private key** — use this to import the same account into **MetaMask** (or another wallet). Base mainnet, same derivation path as the app (`m/44'/60'/0'/0/0`).

---

## Sending funds (demo)

**Wallet** screen → **Send**:

- **ETH** — native Base ETH (leave some for gas).
- **MOR** — ERC-20 on Base; contract shown on screen (`0x7431…b8e3` mainnet).
- Amounts are **human decimals** (e.g. `0.01`); both assets use **18 decimals** under the hood.
- Submitted txs wait for **confirmation** in Go (can take ~15–60s+). On failure, the error SnackBar is usually an RPC / gas / balance message.

Block explorer: `https://base.blockscout.com/tx/<tx_hash>`

---

## Soft reset — “Erase wallet” in the app

1. Open **Wallet** → **Erase wallet from this device**.
2. Confirm. This **clears the Keychain mnemonic** (and the macOS **file fallback**, if used) and calls **Go `Shutdown`**, then **re-inits** the SDK.
3. You should land on **onboarding** with a **new** wallet flow.  
   On-chain funds on the **old** address are unchanged; recover that address only with the **seed phrase** or **exported private key** you saved earlier.

---

## Hard reset — remove Keychain footprint (macOS)

Use this when you want to be sure **no RedPill secrets** remain, or the app still “remembers” a wallet after erase.

### A. Keychain Access (GUI)

1. Open **Keychain Access** (Spotlight: “Keychain Access”).
2. Search for **`redpill`**, **`flutter_secure_storage`**, or your app name.
3. Delete entries tied to **RedPill** / **com.morpheusais.redpill** (inspect “Kind” / account if unsure).

### B. App sandbox data (SQLite, chats, preferences)

Sandboxed macOS app data lives under the **container** (paths can vary slightly by install):

```text
~/Library/Containers/com.morpheusais.redpill/Data/Library/Application Support/
```

Look for a **`redpill`** folder (contains `redpill.db`, chat files, etc.). **Quit the app**, then delete that folder to wipe local DBs.  
This does **not** remove Keychain items by itself — do **A** or in-app **Erase** for secrets.

### C. Full container nuke (last resort)

Quit RedPill, then remove the entire container (you will lose **all** app-local state):

```bash
rm -rf ~/Library/Containers/com.morpheusais.redpill
```

Re-open the app from Xcode / `flutter run` / Finder — it’s a fresh install from the OS’s perspective.

---

## Rebuild native library after Go changes

Any new `//export` from Go requires rebuilding the `.dylib` before `flutter run`:

```bash
cd redpill && make go-macos && flutter run -d macos
```

---

## Base RPC (rate limits)

Default URLs live in **`lib/config/chain_config.dart`** (`defaultBaseMainnetRpcUrls`). The embedded SDK **round-robins** and **backoffs** on `429`, **`403` / Cloudflare HTML**, missing **`eth_call`**, etc.

**Optional custom RPC:** **⋮ → Network / RPC** (or **Edit custom RPC** if init fails). Saves to **`Application Support/.../redpill/eth_rpc_override.txt`** (plain text, not secret). **Clear — use built-in public RPCs** removes that file. Saving triggers **SDK shutdown + re-init**; the wallet is re-imported from the vault automatically.

If chat open still fails on defaults, **Retry** after a short wait; home **Refresh** re-queries balances.

---

## Chat / `SendPrompt` (embedded SDK)

Streaming completions can include **usage-only** SSE chunks (no `choices`). The proxy-router used to panic in `ChunkStreaming.String()` on those; that is fixed in `Morpheus-Lumerin-Node` (`genericchatstorage/completion.go`). **Rebuild the macOS dylib** (`make go-macos` or your usual target) after pulling that change.

**Streaming vs one-shot:** Chat has a **Streaming reply** switch (default on). It is stored in **`Application Support/.../redpill/chat_streaming_preference.txt`** (`1` / `0`) and is passed into Go as `SendPrompt(..., stream)`. That controls the OpenAI `stream` flag to the provider; the UI still shows the full reply when the FFI call returns.

---

## Chat history (SQLite)

- Each new chat screen calls **`CreateConversation`** then **`SendPrompt`** (which saves **user** then **assistant** messages).
- Data lives in **`redpill.db`** under Application Support (see hard reset paths above).
- **There is no conversation list in the UI yet** — history is for upcoming **P2** (see `redpill_plan.md` → Next up). To inspect locally, use a SQLite browser on `redpill.db` or add temporary debug UI.

---

## CocoaPods

If macOS build complains about CocoaPods, install via Homebrew (`brew install cocoapods`) and run `flutter pub get` / open the macOS workspace once so pods sync.
