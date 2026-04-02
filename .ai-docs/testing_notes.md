# Node Neo — Local testing & wallet reset

Hot-wallet demo on **Base mainnet**. This doc covers persistence, moving funds, **chat / sessions**, and **nuke-and-pave** when you want a clean slate.

---

## Smoke tests (after a build)

| Check | What to do | Pass criteria |
| ----- | ---------- | ------------- |
| **Chat E2E** | Home → tap an LLM (e.g. TEE) → wait for session → send a short prompt | Assistant reply appears; no Go panic |
| **Close on-chain** | **Continue chatting** card **✕**, or drawer row **✕** on an open thread, or **Network / RPC → Open on-chain sessions** | Same confirm + tx sheet; after success, home/history show **Session closed** (SQLite `session_id` cleared + reconcile on refresh) |
| **Streaming flag** | In chat, toggle **Streaming reply** off/on, send two prompts | Both complete; preference survives app restart (`chat_streaming_preference.txt`) |
| **RPC override** | ⋮ → Network / RPC → save custom URL → restart | Init uses override; clear restores defaults |
| **TEE negative test** | Pick a known-bad Secure model (e.g. fake TEE) → open chat | Session open **fails**; red **“Secure (TEE) verification failed”**; expandable technical shows register mismatch (not a silent success) |
| **Stake panel** | Open chat to a model (before/after error) | Green block shows **Estimated MOR moved** vs **wallet MOR** (not only price×time) |
| **Active session clock** | Home → **Continue chatting** with open session | Subtitle shows **~N min left**; after wall-clock `ends_at`, row drops after refresh/timer reconcile |
| **Second topic same model** | Open GLM-5 chat A, then tap GLM-5 again for new thread | New conversation; **same** `session_id` if still valid; **✕** on one thread does **not** chain-close if another thread shares session |

**Planned UX checks (backlog)** — token symbols (ETH / Base / MOR), drawer width + swipe vs overflow menu, Markdown code in replies, clipboard in/out.

---

## Wallet persistence (normal use)

- The **BIP-39 mnemonic** is stored in the OS **secure store**:
    - **macOS:** Keychain (via `flutter_secure_storage`). If Keychain returns **-34018** (missing entitlement / unsigned debug), the app falls back to **`Application Support/nodeneo/.mnemonic_vault`** inside the app container — still sandboxed, but not hardware-backed like Keychain. After a successful Keychain write, the fallback file is removed.
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

Use this when you want to be sure **no Node Neo secrets** remain, or the app still “remembers” a wallet after erase.

### A. Keychain Access (GUI)

1. Open **Keychain Access** (Spotlight: “Keychain Access”).
2. Search for **`nodeneo`**, **`flutter_secure_storage`**, or your app name.
3. Delete entries tied to **Node Neo** / **com.absgrafx.nodeneo** (inspect “Kind” / account if unsure).

### B. App sandbox data (SQLite, chats, preferences)

Sandboxed macOS app data lives under the **container** (paths can vary slightly by install):

```text
~/Library/Containers/com.absgrafx.nodeneo/Data/Library/Application Support/
```

Look for a **`nodeneo`** folder (contains `nodeneo.db`, chat files, etc.). **Quit the app**, then delete that folder to wipe local DBs.  
This does **not** remove Keychain items by itself — do **A** or in-app **Erase** for secrets.

### C. Full container nuke (last resort)

Quit Node Neo, then remove the entire container (you will lose **all** app-local state):

```bash
rm -rf ~/Library/Containers/com.absgrafx.nodeneo
```

Re-open the app from Xcode / `flutter run` / Finder — it’s a fresh install from the OS’s perspective.

---

## Rebuild native library after Go changes

Any new `//export` from Go requires rebuilding the `.dylib` before `flutter run`:

```bash
cd nodeneo && make go-macos && flutter run -d macos
```

---

## Base RPC (rate limits)

Default URLs live in **`lib/config/chain_config.dart`** (`defaultBaseMainnetRpcUrls`). The embedded SDK **round-robins** and **backoffs** on `429`, **`403` / Cloudflare HTML**, missing **`eth_call`**, etc.

**Optional custom RPC:** **⋮ → Network / RPC** (or **Edit custom RPC** if init fails). Saves to **`Application Support/.../nodeneo/eth_rpc_override.txt`** (plain text, not secret). **Clear — use built-in public RPCs** removes that file. Saving triggers **SDK shutdown + re-init**; the wallet is re-imported from the vault automatically.

**Before save:** each URL is probed with JSON-RPC **`eth_chainId`**; it must match **Base mainnet (8453)**. Use **Test URLs (no save)** to validate without switching the running app off the current RPC. If chat still fails on defaults, **Retry** after a short wait; home **Refresh** re-queries balances.

---

## App lock & biometrics

**⋮ → Security** — optional app password + Face ID / Touch ID (when enabled). Uses **`AutofillGroup`** with a fixed read-only **Password manager ID** (`Node Neo` + **`AutofillHints.username`**) plus password fields so **1Password / iCloud Keychain** can match the item (not wallet-specific). **Unlock** calls `finishAutofillContext(shouldSave: false)` so you are not prompted to “save” on every unlock. After **background (paused)**, the app locks again if app lock is on.

**Continue chatting** — Lists conversations with a stored **`session_id`** (on-chain still open per local DB, reconciled with chain on **`GetConversations`**). **✕** starts the same close flow as the full sessions screen. Tap the row to **resume** SQLite + on-chain session.

**After app restart:** The embedded SDK used to lose the in-memory **provider URL / pubkey** map while the **on-chain session** was still valid → `provider not found`. The proxy-router **re-pings the provider** and re-registers that row before `SendPrompt`. Rebuild **dylib** after pulling Morpheus `proxy-router` + nodeneo Go changes.

**Chat “memory”:** SQLite stores turns per **conversation id**; each `SendPrompt` sends the **last ~80 prior messages** from SQLite plus the new user line as an OpenAI-style `messages[]` payload (not just the latest utterance). Separate conversations = separate threads; switching models starts a different conversation row. Very long threads are truncated from the oldest side to control tokens.

**History drawer:** Title **Chats & Sessions**. Tap row → **transcript** → **Continue chatting** (passes open `session_id` when set). **🗑** / menu **Delete conversation** → **`DeleteConversation`**: attempts **on-chain close** when `session_id` is set, then removes SQLite rows; **`close_warning`** in JSON if close failed (local delete still happens). **`ClaimEmptyDraftForModel`** reuses empty-per-model draft so re-opening a model before the first message does not spawn duplicate threads.

**User-facing copy:** **Secure** / **SECURE** / **MAX Security** in UI where we used to say TEE; model list **tags** stay as returned from the API (may still show `TEE`). Provider addresses hidden on model tiles.

**App lock:** Near-invisible username field for autofill pairing; password fields use `visiblePassword` + `AutofillHints` + no autocorrect/suggestions.

**Session open errors:** Plain-language MOR vs ETH gas hints (`session_open_errors.dart`). **Estimated MOR stake** from top bid × duration (`session_cost_estimate.dart`). **Default session length** persisted (`session_duration_store.txt`) — **Network** screen + chat error **Retry** UI (optional “save as default”).

- **macOS:** If Keychain returns **-34018** (missing entitlement / unsigned debug), app-lock secrets fall back to **`Application Support/nodeneo/.app_lock_vault.json`** (JSON map of the same logical keys as Keychain). After a successful Keychain write, the corresponding file keys are removed. **Treat like the mnemonic fallback:** fine for local dev; for distribution builds, use proper **Keychain** entitlements / signing so storage is hardware-backed.

See **`.ai-docs/app_security_plan.md`**.

---

## iPhone device builds

Apple signing and TestFlight: **`.ai-docs/ios_device_signing.md`**. Note: **Go `libnodeneo` is currently wired for macOS**; iOS needs a native library build/embed step before FFI works on device.

---

## Open sessions list (empty)

Go’s `json.Marshal` of a **nil** slice encodes as JSON **`null`**, not `[]`. The Dart bridge now maps `null` → empty list, and the SDK returns a non-nil empty slice so JSON is `[]`. Rebuild the dylib after SDK changes.

---

## Chat / `SendPrompt` (embedded SDK)

Streaming completions can include **usage-only** SSE chunks (no `choices`). The proxy-router used to panic in `ChunkStreaming.String()` on those; that is fixed in `Morpheus-Lumerin-Node` (`genericchatstorage/completion.go`). **Rebuild the macOS dylib** (`make go-macos` or your usual target) after pulling that change.

**Streaming vs one-shot:** Chat has a **Streaming reply** switch (default on). It is stored in **`Application Support/.../nodeneo/chat_streaming_preference.txt`** (`1` / `0`). When on, Flutter calls **`SendPromptStream`** with a native chunk callback so the assistant bubble grows as deltas arrive; when off, **`SendPrompt`** is used with `stream: false` and the reply appears when the FFI call returns. Rebuild **`libnodeneo`** after Go changes (`make go-macos`).

---

## Chat history (SQLite)

- Each new chat screen calls **`CreateConversation`** then **`SendPrompt`** (which saves **user** then **assistant** messages).
- Data lives in **`nodeneo.db`** under Application Support (see hard reset paths above).
- **There is no conversation list in the UI yet** — history is for upcoming **P2** (see `plan.md` → Next up). To inspect locally, use a SQLite browser on `nodeneo.db` or add temporary debug UI.

---

## CocoaPods

If macOS build complains about CocoaPods, install via Homebrew (`brew install cocoapods`) and run `flutter pub get` / open the macOS workspace once so pods sync.
