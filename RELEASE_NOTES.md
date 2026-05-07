## What's New in v3.4.0

The App Store legitimacy + CI/CD release. The app now points users out to a real public Privacy / Terms / Support surface on `nodeneo.ai`, and a new `.github/workflows/build-ios.yml` ships every `dev` merge straight to TestFlight (Internal Group) and every `main` merge to TestFlight + a tagged GitHub Release. App Store submission for review remains a deliberate manual click in App Store Connect — every other gate is now automated.

### App Store legitimacy surface (nodeneo.ai + in-app links)

Apple's submission flow expects a public Privacy Policy URL, a public Support URL, and (for any app touching financial-adjacent flows) a public Terms of Service URL. Pointing those at GitHub anchors is a poor consumer signal. Three new pages on `nodeneo.ai` close the gap:

- **`privacy.html`** — App-Store-grade privacy policy. Leads with "Node Neo collects nothing" and walks through what stays on device, the two third parties (public Base RPC + Morpheus inference providers) the app necessarily talks to, the OS permissions declared (with the iOS Photos / Camera / Mic explanation for the `file_picker` quirk), GDPR / CCPA rights, and contact at `support@nodeneo.ai`.
- **`terms.html`** — Terms of Service / EULA. MIT for source, narrower personal-use license for the signed binaries, hard self-custody disclaimer ("we cannot recover lost keys, no one can"), warranty disclaimer + liability cap (USD $100), South Dakota governing law (any SD court), individual disputes only.
- **`support.html`** — Email + GitHub-issues CTAs at the top, then 5 sections of collapsible FAQ (Getting started / Wallet & funds / Chat & models / Privacy & data / Troubleshooting). Every common error message we surface in the app has a matching FAQ entry.

The app threads users out to those pages from three surfaces:

- **Settings drawer** — new *Help & Resources* group below *Version & Logs* with rows for *Why Node Neo? · New to crypto? · Quick start · Support · Privacy Policy · Terms of Service*. The trailing chevron is replaced by an `open_in_new` glyph on these rows so the user knows the tap leaves the app.
- **About screen** — new *Legal & Resources* card with *Privacy Policy · Terms of Service · Support · Source code*. App Store reviewers actively look for these surfaces inside Settings → About as a sanity check on the App Store Connect URLs.
- **Onboarding screen** — subtle *New to crypto? See the walkthrough →* `TextButton` directly under the "Import Wallet" button, plus an inline *By creating or importing a wallet you agree to our Terms and Privacy Policy.* line at the bottom of the form with both phrases as tappable links.

A new `lib/constants/external_links.dart` is the single source of truth for every external URL the app opens — one class to read for any reviewer or privacy auditor who wants to see every hostname the binary will ever launch. The footer on every public `nodeneo.ai` page was rewired in lockstep: the right-column section renamed `External` → `Legal`, `Support` redirected from github-issues to `support.html`, `Privacy` redirected from the github anchor to `privacy.html`, and a new `Terms` row added.

### iOS CI to TestFlight (`.github/workflows/build-ios.yml`)

Mirrors the structure of `build-macos.yml`: a `generate-tag` job that produces the same SemVer tags either platform reads, and a `build-ios` job that runs the same proven local pipeline you use today (`make go-ios` + `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist` + `xcrun altool --upload-app`).

- **Push to `dev`** — IPA built, verified for Go FFI symbol export (the same `_verify-ipa-symbols` Mach-O `nm` check the Makefile runs locally), uploaded to TestFlight. Internal Group testers see the build immediately after processing (~10–30 min). No git tag, no GitHub Release.
- **Push to `main`** — same pipeline, plus a SemVer git tag and a GitHub Release with notes only (the IPA itself is uploaded to TestFlight, not attached to the GH Release — App Store distribution doesn't allow sideload).
- **App Store submission for review** is intentionally **not** automated. The "Submit for Review" click in App Store Connect requires complete metadata (screenshots, age rating, review notes, what's-new copy); a rejection costs days. Once a build lands in TestFlight from `main`, promote it manually via App Store Connect.

Apple Distribution `.p12` cert is base64-decoded into an ephemeral keychain on the runner; ASC API key is staged at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` so both archive-time signing AND the `altool` upload use the same credential. Required GitHub Secrets and the `.p12` export walkthrough are documented in `.ai-docs/ios_device_signing.md` Section 3 (which used to be a "future plan" placeholder; now it's the runbook).

### macOS workflow polish

While in the workflows file: the long-standing cosmetic bug where the in-app *About → Proxy-router* row showed a bare 12-char commit hash instead of `v7.0.0-N-g<hash>` is fixed (`build-macos.yml` and `build-ios.yml` both drop `--single-branch` and explicitly fetch `main` so `git describe --tags` can reach release tags as ancestors of dev-pinned commits).

### iOS Impact / Compatibility

- All in-app changes are platform-neutral; the `Help & Resources` drawer section, the About screen `Legal & Resources` card, and the onboarding `Terms / Privacy` acknowledgement all render on iOS, macOS, and (when they ship) iPad / Android.
- No new dependencies. Re-uses `url_launcher` (already in `pubspec.yaml`) and the existing `LaunchMode.externalApplication` pattern from `home_screen.dart` and `wallet_screen.dart`.
- Gateway (desktop-only feature, gated by `PlatformCaps.supportsGateway`) is unchanged in this release.

---

## Previous Releases

Full notes for each prior release are pinned to its tag page on GitHub.

| Version | Date | Headline |
|---------|------|----------|
| [v3.3.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.3.0) | 2026-05-03 | iOS TestFlight readiness — biometrics-first app lock, private-key-only wallets, network reachability gate + offline screens, FirstLaunchGuard for iOS app-delete, iOS 26 ProMotion engine workaround, cross-arch native_assets cache fix |
| [v3.2.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.2.0) | 2026-04-30 | Cursor / Zed-class AI Gateway — full OpenAI Chat Completions parity (`tools`, `tool_choice`, `reasoning_content`, `MultiContent`); `/v1/embeddings` + `/v1/completions`; capability flags; three-layer endpoint redaction |
| [v3.1.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.1.0) | 2026-04-24 | Chat reliability patch — reasoning-only stream completions no longer surface as a false error ([#66](https://github.com/absgrafx/nodeneo/pull/66)) |
| [v3.0.0](https://github.com/absgrafx/nodeneo/releases/tag/v3.0.0) | 2026-04-24 | Full TEE compliance with proxy-router v7.0.0 on macOS + iPhone, pre-session confirmation flow, in-place affordability, wallet card redesign, provider-endpoint redaction, RPC failover, Flutter 3.41.7 |
| [v2.7.0](https://github.com/absgrafx/nodeneo/releases/tag/v2.7.0) | 2026-04 | iOS (iPhone) first light, two-zone thinking/reasoning model support, stop/cancel generation, MOR scanner fix, collapsible wallet card, factory reset via "DELETE ALL" |
| [Older](https://github.com/absgrafx/nodeneo/releases) | — | Full release archive |
