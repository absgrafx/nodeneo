## What's New in v3.0.0

### Pre-Session Confirmation Flow
- Tapping a model now opens a **"Start chat?"** modal before any stake is posted: model name, MAX Privacy (TEE) badge, duration dropdown, and the exact MOR that will be staked for the chosen duration
- Duration presets surface the **live hourly stake** calibrated from the home list so the number in the modal matches the number on the tile (no more drift between list price and actual stake)
- Default session length is **10 minutes** (was 1 hour) — cheaper to try a model, easier to discard
- Cancel returns to the home screen with no chain interaction; confirm opens the chat with the chosen duration

### In-Place Model Affordability
- Unaffordable models are greyed out **in place** (no re-sorting). The list stays visually stable as balances update
- Header counter now reads `X of Y affordable` and respects the Privacy / Show All filters
- "Show All" reveals unaffordable models (still greyed); off by default, so only what you can actually chat with is shown
- Affordability refreshes on wallet balance change, session open/close, return from Send MOR, and a 60s idle tick

### TEE Attestation on iPhone
- Fixed `mkdir .sigstore: operation not permitted` — the Sigstore TUF cache now lives under the iOS-writable `dataDir` via `sdk.SetSigstoreCacheDir`
- TEE models verified end-to-end on device (CPU attestation + cosign golden-value check)
- Quick-attestation cache now persists across relaunches for sub-second reconnects to known-good providers

### Wallet Card Redesign
- Collapsed card: address on a single line, right-aligned MOR / ETH numbers with compact `(+staked)` suffix in purple that visually recedes below the liquid balances
- Expanded card: **"Where's My MOR?"** pill deep-links to the on-chain scanner with auto-scan, "Stake for inference" / "Pays on-chain gas" helper text now spans the full chip width, staked MOR shown in purple beneath the liquid balance
- Balance numbers use `FittedBox(scaleDown)` so 5-decimal values stay honest on narrow iPhone widths instead of ellipsizing
- Live RPC connectivity pill + "Send Max" button on the MOR send sheet

### Chain Correction: Base (not Arbitrum)
- Scrubbed every user-facing "Arbitrum" reference in UI strings, tooltips, and code comments to correctly read **Base**
- `chain_config.dart` default RPCs, chainID (8453), and Blockscout links verified

### Provider Endpoint Redaction
- New `lib/utils/error_redaction.dart` strips `http(s)://`, `host:port`, and bare IPv4 addresses from error messages before they hit the chat UI
- Users see a neutral `<provider endpoint>` placeholder; full detail still lands in the app log for debugging
- Protects provider infrastructure from being shouted on screen-share / bug reports

### "Fund Your Wallet" Overlay Scoped
- Overlay now appears **only** when both MOR and ETH are 0 — no more covering active chats or re-appearing after a successful top-up
- Continue Chatting strip sits above Privacy / Show All toggles with proper vertical padding

### RPC Failover Resilience
- Expanded the fork's `shouldRetryRPCError` to cover all common public-RPC rate-limit signals (JSON-RPC `-32005`, "usage limit", "rate limit exceeded", "over quota", "too many requests", "plan limit", etc.)
- Wallet balance fetch now preserves the last-known-good number on transient errors instead of flashing `0.00000`
- Result: public round-robin of 6 Base RPCs rides through per-node daily caps transparently; no more 45-second cold-start stall

### Flutter 3.41.7 Upgrade
- Local toolchain bumped from 3.41.5 → 3.41.7 after a debugger-attach edge case left iOS releases suspended on splash
- macOS CI Flutter version pinned to 3.41.7 to match

### Fork Refresh (Morpheus-Lumerin-Node)
- `proxy-router/mobile` pseudo-version bumped to the current `absgrafx/Morpheus-Lumerin-Node` fork tip
- Pulls in Sigstore cache configurability, the expanded RPC retry list, and the upstream `v7.0.0` merge (TEE v2, session maintenance loop)

---

## What's New in v2.7.0

### iOS Support (iPhone)
- Node Neo now runs on iPhone — full onboarding, wallet, chat, and settings
- Go SDK compiled as static library for iOS (device + simulator)
- Platform-aware feature gating: Developer API and AI Gateway hidden on mobile (desktop-only features requiring persistent servers)
- Touch-optimized: pull-to-refresh, safe area handling, compact layouts
- App icon regenerated as full-bleed for clean iOS superellipse clipping
- Simulator workflow: `make run-ios-sim` for fast iteration without a physical device

### Thinking / Reasoning Model Support
- Two-zone streaming display: chain-of-thought reasoning renders in a purple "Thinking..." zone above the answer
- Live spinner during thinking with scrolling reasoning text
- Collapses to "Thought for Xs" after completion — tap to expand and review full reasoning
- Supports both `reasoning_content` field (Venice, DeepSeek, OpenAI o-series) and `<think>` tag fallback (vLLM, ollama)
- Reasoning tokens excluded from conversation history (per best practice — not fed back as context)

### Stop / Cancel Generation
- Send button transforms to amber stop icon during streaming
- Tap to cancel: partial response is kept with "Generation stopped" indicator
- Cancellation propagates through the full stack (Dart → FFI → Go → proxy-router context cancellation)

### MOR Scanner Fix
- Fixed off-by-one ABI decoding error in `getSession` — active session stakes were always showing 0
- Removed 20-session scan cap: all sessions now scanned in batches
- Scan runs on background isolate (non-blocking UI with spinner)
- Lazy scan on card expand instead of screen load
- Auto-scan when "Where's My MOR" card is expanded (no extra tap)

### Home Screen UX
- Collapsible wallet card: compact row with address + MOR/ETH balances (collapsed by default)
- Slimmed privacy toggle: single-line "Full Privacy Models" with TEE explainer link
- Pull-to-refresh on all platforms (replaces manual refresh button on mobile)
- Hidden overlay scrollbar for cleaner appearance

### Factory Reset Improvements
- Factory reset now uses "DELETE ALL" phrase confirmation instead of private key
- Works when private key is lost (the whole point of a factory reset)
- Consistent confirmation flow from both Settings and lock screen entry points

### Additional Fixes
- Backup export works on iOS (handles `bytes` parameter requirement)
- Lock screen recovery sheet defaults to Private Key tab (matches onboarding)
- Onboarding backup screen spacing tightened for small screens
- App bar tagline overflow handling
- Deployment target aligned to iOS 16.0 across all build configurations
- Info.plist: ATS local networking, export encryption compliance
