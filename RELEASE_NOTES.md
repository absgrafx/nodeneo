## What's New in v3.4.0

The App Store legitimacy + CI/CD release. The app now points users out to a real public Privacy / Terms / Support surface on `nodeneo.ai`, a new `.github/workflows/build-ios.yml` ships every `dev` merge straight to TestFlight (Internal Group) and every `main` merge to TestFlight + a tagged GitHub Release, the iOS App Privacy nutrition label is now legitimately "Data Not Collected" (only `NSFaceIDUsageDescription` declared), and the in-app helper-link surface has been reorganized so each external page lives in its single most contextually appropriate home. App Store submission for review remains a deliberate manual click in App Store Connect — every other gate is now automated.

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

Apple Distribution `.p12` cert is base64-decoded into an ephemeral keychain on the runner; ASC API key is staged at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` so both archive-time signing AND the `altool` upload use the same credential.

### macOS workflow polish

While in the workflows file: the long-standing cosmetic bug where the in-app *About → Proxy-router* row showed a bare 12-char commit hash instead of `v7.0.0-N-g<hash>` is fixed (`build-macos.yml` and `build-ios.yml` both drop `--single-branch` and explicitly fetch `main` so `git describe --tags` can reach release tags as ancestors of dev-pinned commits).

### iOS App Privacy nutrition label cleanup (`file_picker` → `file_selector`)

The old `file_picker` package transitively pulled in photo / video / audio CocoaPods (`DKImagePickerController`, `DKPhotoGallery`, `SDWebImage`, `SwiftyGif`) even though the app's only document-picker call site is the `.nnbak` save / load on the Backup & Reset screen. Apple's binary scanner observed those linked frameworks and forced four purpose strings into `Info.plist` — `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` — which then surfaced as data-collection rows on the App Privacy nutrition label even though Dart never invokes Photos / Camera / Mic. For a privacy-first app, that's the kind of half-true label that erodes trust.

Replaced with the official `flutter.dev` `file_selector` package, which uses `UIDocumentPickerViewController` exclusively on iOS (no Photos / Camera / Mic linkage). All three non-FaceID purpose strings have been removed; `NSFaceIDUsageDescription` (authentication, not data collection) is the only declaration that remains. The App Privacy section can now legitimately answer "Data Not Collected" for every category. `BackupResetScreen` was rewired to the new API: `getSaveLocation` for export, `openFile` for import, plus the iOS-specific "write to temp file → read bytes → `XFile.fromData(...).saveTo(scopedPath)`" dance because the document picker returns a writeable scoped path rather than a destination directory.

### Helper-link reorganization

The previous v3.4.0 work landed a `Help & Resources` group in the settings drawer with seven external-link rows. On smaller screens the drawer body (a non-scrolling `Column`) overflowed; on larger screens the rows duplicated content that has more contextually correct homes elsewhere in the app. The reorganization pushes each link to its single best home and rewrites the drawer body as a scrollable `ListView` so future additions can't regress this.

- **Settings drawer** trimmed to the five in-app navigation rows: *Preferences · Wallet · Expert Mode · Backup & Reset · About & Help*. The `Version & Logs` row was renamed `About & Help` (subtitle `App info · Resources · Logs`) — anchors on existing Apple-platform muscle memory and signals all three card types behind it.
- **About screen** is now three cards, each with one purpose. The **About card** absorbs `Why Node Neo?` + `Architecture deep dive` + `Privacy Policy` + `Terms of Service` below the version block (separated by a divider) — Privacy + Terms are legal *commitments*, not utilities, so they belong with "who runs this app and what we promise" rather than in a generic resources bucket. The **Resources card** (renamed from `Legal & Resources`) is a tight three-row utility card: *Support · Report a bug · Source code*. The **Logs card** is unchanged.
- **Wallet screen** gained a compact "New to crypto? See the walkthrough" link below the Active Sessions card — same affordance the onboarding screen uses, so anyone landing on Wallet without crypto vocabulary has one tap to the 25-minute primer.
- **Home front page** gained a small "Quick start guide" link below the `START A NEW CHAT by selecting a model` hint — discoverable for the user staring at the model list, ignored by an oriented user.
- **`lib/constants/external_links.dart`** doc comments updated to reflect the new homes for each link.

### Public website (`nodeneo.ai`) — support CTA flip

`nodeneo.ai/support.html` previously led with "Email support@nodeneo.ai" as the primary action. Flipped: **GitHub Issues** is now the primary CTA (public, searchable, every answer helps the next user with the same problem); email is the secondary fallback for cases that genuinely need a private channel (lost-wallet questions, payment-processor issues, security disclosures). Meta description and supporting copy updated to match. The `support.html` favicon and footer references are unchanged.

### iOS Impact / Compatibility

- All in-app changes are platform-neutral; the trimmed settings drawer, the consolidated About / Resources cards, the onboarding `Terms / Privacy` acknowledgement, and the new contextual deep-links on Wallet / Home all render on iOS, macOS, and (when they ship) iPad / Android.
- One dependency swap: `file_picker: ^11.0.2` → `file_selector: ^1.1.0`. The replacement is an official `flutter.dev` package; on iOS it's a thin wrapper around `UIDocumentPickerViewController` and adds zero new permissions. macOS uses the native `NSSavePanel` / `NSOpenPanel` (no entitlement changes). The `BackupResetScreen` rewire is the only call site.
- Re-uses `url_launcher` (already in `pubspec.yaml`) and the existing `LaunchMode.externalApplication` pattern for every external link.
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
