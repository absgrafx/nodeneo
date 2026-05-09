## What's New in v3.5.0

Maintenance release — no new features or behavior changes.

The macOS *About Node Neo* panel now reads as a clean `Version 3.5.0` instead of `Version 3.4.0 (9)`-style text that was exposing an internal CI build counter.

### Engineering footnotes
- Build counter resets to ~1 with each release (was carrying the cumulative GitHub Actions counter across release trains).
- Release tag and GitHub Release page are owned exclusively by the macOS workflow.
- TestFlight uploads gated to `dev`; `main` IPAs build as workflow artifacts only until App Store production approval lands.

---

## Previous Releases

Full notes for each prior release are pinned to its tag page on GitHub.

| Version | Date | Headline |
|---------|------|----------|
| [v3.4.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.4.0) | 2026-05-08 | App Store legitimacy + CI/CD release — public Privacy / Terms / Support pages on `nodeneo.ai`, `build-ios.yml` shipping every `dev` push to TestFlight Internal, “Data Not Collected” iOS App Privacy label, three-pass `file_selector` rewire of Backup & Reset (macOS NSSavePanel / iOS Share-sheet / iOS UTI fix), Resources & Legal helper-link reorganization, fully signed + notarized dev DMGs with iOS-aligned build numbers |
| [v3.3.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.3.0) | 2026-05-03 | iOS TestFlight readiness — biometrics-first app lock, private-key-only wallets, network reachability gate + offline screens, FirstLaunchGuard for iOS app-delete, iOS 26 ProMotion engine workaround, cross-arch native_assets cache fix |
| [v3.2.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.2.0) | 2026-04-30 | Cursor / Zed-class AI Gateway — full OpenAI Chat Completions parity (`tools`, `tool_choice`, `reasoning_content`, `MultiContent`); `/v1/embeddings` + `/v1/completions`; capability flags; three-layer endpoint redaction |
| [v3.1.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.1.0) | 2026-04-24 | Chat reliability patch — reasoning-only stream completions no longer surface as a false error ([#66](https://github.com/absgrafx/nodeneo/pull/66)) |
| [v3.0.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.0.0) | 2026-04-24 | Full TEE compliance with proxy-router v7.0.0 on macOS + iPhone, pre-session confirmation flow, in-place affordability, wallet card redesign, provider-endpoint redaction, RPC failover, Flutter 3.41.7 |
| [v2.7.0](https://github.com/absgrafx/nodeneo/releases/tag/v2.7.0) | 2026-04 | iOS (iPhone) first light, two-zone thinking/reasoning model support, stop/cancel generation, MOR scanner fix, collapsible wallet card, factory reset via "DELETE ALL" |
| [Older](https://github.com/absgrafx/nodeneo/releases) | — | Full release archive |
