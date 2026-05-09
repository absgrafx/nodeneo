## What's New in v3.5.0

Release-pipeline polish following the v3.4.0 ship. No user-visible product changes; the only thing that looks different is a cleaner version label on the macOS *About* panel.

### Releases & versioning
- **macOS About panel** on main releases reads as `Version 3.5.0 (1)` — natural-language "first release of v3.5.0" instead of the CI ordinal that `(9)` exposed on v3.4.0. Dev previews continue to show `Version 3.5.0 (N)` so a downloaded preview can be cross-referenced with its CI run at a glance.
- **Tag + GitHub Release** are now exclusively owned by the macOS workflow — eliminates the race condition that produced an asset-less release on the v3.4.0 ship.

### iOS distribution channels
- **TestFlight upload is `dev`-only.** Every push to `dev` continues to ship to TestFlight Internal. Pushes to `main` build + verify the IPA and upload it as a workflow artifact for inspection, but no longer auto-publish — App Store production upload is the next thing to wire in once App Store review approval lands.

### Documentation
- **Release-page brevity policy.** From v3.5.0 forward, the top section of `RELEASE_NOTES.md` is brief bullet points only — one sentence per bullet, grouped under 2-4 area headings. Long-form *why/how* detail lives in the per-PR commit messages and is no longer mirrored on the GitHub Release page. Goal: a release page a reader can scan in 30 seconds.

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
