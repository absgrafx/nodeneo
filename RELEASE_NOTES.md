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
