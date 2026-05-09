## What's New in v3.5.0

Release-pipeline polish following the v3.4.0 ship. No user-visible product changes; the visible deltas are cosmetic — the macOS *About* panel and the dev preview build counter both render the way the user mental model expects.

### Releases & versioning
- **macOS About panel on main releases reads as a bare `Version 3.5.0`** — no `(N)` parens at all. AppDelegate now overrides the standard About menu and clears AppKit's parens segment whenever `CFBundleVersion == CFBundleShortVersionString` (which the macOS workflow arranges only on `main`). Dev previews continue to show `Version 3.5.0 (N)` so a downloaded preview can be matched with its TestFlight build.
- **Build counter resets per release train.** `CFBundleVersion` is now `git rev-list --count <last-vX.Y.Z-tag>..HEAD` — the count of dev commits since the most recent release — instead of `GITHUB_RUN_NUMBER` (which never resets, and was causing v3.5.0 dev builds to start at `+11` because that was the cumulative iOS workflow counter from the v3.4.0 train). After every main release the counter resets to ~1 automatically.
- **macOS and iOS no longer cross-reference each other** to align build numbers. Both workflows compute the same git counter against the same `head_sha` independently, so DMG / IPA / TestFlight all agree by construction. The `gh api` polling loop that used to look up the iOS workflow's run number from the macOS workflow is gone.
- **Tag + GitHub Release** are owned exclusively by the macOS workflow (it has the only downloadable asset). Eliminates the race condition that produced an asset-less release on the v3.4.0 ship.

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
