# Node Neo - iOS signing, device builds, and TestFlight

End-to-end runbook from "fresh-checkout iOS dev" to "build is live in TestFlight". Three audiences, three sections:

- **Section 1 - Local device builds** - fastest tap-cycle for iteration on Phlame / your own iPhone
- **Section 2 - TestFlight first cut** - manual one-time setup of App Store Connect + API key, then the upload pipeline
- **Section 3 - Future CI** - what we will automate in `.github/workflows/build-ios.yml` once the manual path is proven

---

## 1. Local device builds (Phlame / your iPhone)

### One-time setup

1. **Apple ID in Xcode** - Xcode -> Settings -> Accounts -> add Apple ID -> select team `2S4578V7ZD` (matches `DEVELOPMENT_TEAM` in `ios/Runner.xcodeproj/project.pbxproj`).
2. **Device trust + Developer Mode** - connect via USB, tap **Trust** when prompted, then on the phone go **Settings -> Privacy & Security -> Developer Mode -> On** (reboot when iOS asks).
3. **Bundle ID is already registered** - `com.absgrafx.nodeneo` is set up under team `2S4578V7ZD`. Automatic signing handles the development profile + `Apple Development` cert (`security find-identity -p codesigning -v` confirms the cert is in your keychain).

### Daily workflow - pick the target by what you need

| You want... | Command | Mode | Notes |
|---|---|---|---|
| Tap-cycle UX on Phlame, no debugger | `make install-ios-profile` | Profile (AOT) | Sidesteps the iOS 26 `flutter run` VM Service hang. Use this for 95% of on-device work. |
| Live Dart debugging on Phlame | `make run-ios` | Debug (kernel + JIT) | Frequently broken on iOS 26 (VM Service attach hangs). When it works, you get hot reload. |
| Quick UI preview on simulator | `make run-ios-sim` | Debug | iPhone 16 Pro by default; override with `SIM_DEVICE=...`. |
| Full reset when iOS state is wedged | `make ios-clean && make install-ios-profile` | - | Wipes Pods, native_assets cache, last-arch stamp, then rebuilds. |

> **iOS 26 traps already fixed:** the implicit-engine `VSyncClient` SIGSEGV on ProMotion devices and the cross-arch `native_assets/ios/` cache pollution both have shipped workarounds in `ios/Runner/SceneDelegate.swift` and the `Makefile`. See `architecture.md` -> *Recently Shipped -> iOS build pipeline hardening* for the root-cause writeups before debugging future iOS install issues.

### Cursor-first vs Xcode

Do not open Xcode for routine builds - it often breaks the CocoaPods layout that `flutter` depends on. Reserve Xcode for:
- **Signing & Capabilities** changes (rare)
- Inspecting **Window -> Organizer** after an Archive (TestFlight upload errors land here)
- **Manage Certificates...** if Xcode needs to create the Apple Distribution cert for the first time

For everything else: `make <target>` from the Cursor terminal.

---

## 2. TestFlight first cut (one-time ASC setup, then a repeatable upload pipeline)

### Prereqs in code (already done)
- `pubspec.yaml` -> `version: 3.3.0+1` (CFBundleShortVersionString = 3.3.0, CFBundleVersion = 1)
- `ios/ExportOptions.plist` - `app-store-connect` method, automatic signing, team `2S4578V7ZD`, dSYM upload on
- `Makefile` -> `ipa-testflight` and `upload-testflight` targets
- `Info.plist` has `NSFaceIDUsageDescription` and `ITSAppUsesNonExemptEncryption=false` (skips the export-compliance question on every upload)

### One-time: create the App Store Connect app record

You need **App Manager** or **Admin** role on the team. Walkthrough:

1. Sign in at <https://appstoreconnect.apple.com/> with the same Apple ID that owns team `2S4578V7ZD`.
2. **Apps** tab -> **+** (top-left) -> **New App**. Fill in:
    - **Platform:** iOS
    - **Name:** `Node Neo` (must be unique across the App Store; if taken, append " - DeAI" or similar - this is what users see in Search)
    - **Primary Language:** English (U.S.)
    - **Bundle ID:** select `com.absgrafx.nodeneo - Node Neo` from the dropdown (auto-populated from the bundle ID we already registered for development)
    - **SKU:** `nodeneo-ios-001` (internal-only identifier, never shown to users; pick anything unique to your developer account)
    - **User Access:** Full Access
3. Click **Create**. The app record exists; processing can begin once the first build is uploaded.

You will later fill in App Information, screenshots, descriptions, age rating, etc. - **none of that is required to upload a TestFlight build**, only to submit for App Store review. We can stage it incrementally.

### One-time: create the App Store Connect API key

The API key replaces username/password auth for `iTMSTransporter` / `altool`. **You can download the key file exactly once - back it up immediately.**

1. App Store Connect -> **Users and Access** -> **Integrations** tab (top of page) -> **App Store Connect API** subsection.
2. Click **+** to create a new key:
    - **Name:** `Node Neo CI Upload` (descriptive - you will see it in the audit log)
    - **Access:** `App Manager` (sufficient for TestFlight uploads; `Admin` works too but more privilege than needed)
3. Click **Generate**. The page now shows:
    - **Key ID** - 10-char alphanumeric, like `ABCDE12345`. Copy this.
    - **Issuer ID** - UUID, like `69a6de80-1234-5678-9abc-def012345678`. Copy this from the top of the page.
    - A blue **Download API Key** link - click it ONCE. You get a file named `AuthKey_<KEYID>.p8`.
4. **Save the `.p8` file outside the repo.** Recommended: `~/.config/asc/AuthKey_<KEYID>.p8` with `chmod 600`. Our `.gitignore` blocks `*.p8` from accidentally landing in the repo, but it is still safer to keep the file in `~/.config/`.

> The `.p8` is a private signing key. Anyone with it can upload binaries to your developer account. Treat it like an SSH private key.

### One-time: confirm Apple Distribution cert (Xcode auto-creates it)

The first time we Archive in App Store distribution mode, Xcode (or the `xcodebuild` build process invoked by `flutter build ipa`) needs to either find or create an `Apple Distribution: <account name> (2S4578V7ZD)` certificate. Today `security find-identity` shows only `Apple Development` and `Developer ID Application`. Two ways to seed the Distribution cert:

**Option A (simplest): let `flutter build ipa` do it.**
The first run with `--release --export-options-plist=ios/ExportOptions.plist` triggers automatic-signing certificate creation. If the keychain does not have an Apple Distribution cert, `xcodebuild` makes one and adds it. You will see "Provisioning profile ... created" lines in the output.

**Option B: pre-create from Xcode.**
Open `ios/Runner.xcworkspace` -> Runner target -> Signing & Capabilities -> All. With Automatic signing on, change the *Configuration* dropdown at the top from Debug to Release and confirm "Provisioning Profile: Xcode Managed Profile" appears with no red error. If it errors, click **Manage Certificates...** under Xcode -> Settings -> Accounts -> team -> click **+** -> **Apple Distribution**.

### Repeatable: build the IPA

```bash
cd /Volumes/moon/repo/personal_mor/nodeneo
make ipa-testflight
```

What this does:
1. `_ios-stamp-device` - refreshes the cross-arch native_assets cache for device builds.
2. `make go-ios` - rebuilds `libnodeneo.a` for iOS arm64.
3. `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist` - Xcode Archive in release mode, then `xcodebuild -exportArchive` packages a signed `.ipa` per `ExportOptions.plist`.
4. Drops `build/ios/ipa/Node Neo.ipa` (or similarly named).

If signing fails (red error in output), the most common fixes:
- **"No Accounts"** -> Xcode -> Settings -> Accounts -> add Apple ID
- **"No 'Apple Distribution' signing identity matching team ... found"** -> either Option B above, or accept the Apple Distribution cert prompt that pops up
- **"requires a provisioning profile with the App Sandbox capability"** - N/A for iOS, would only fire if you accidentally ran macOS distribution

### Repeatable: upload to App Store Connect

```bash
make upload-testflight \
  ASC_API_KEY_ID=ABCDE12345 \
  ASC_API_ISSUER_ID=69a6de80-1234-5678-9abc-def012345678 \
  ASC_API_KEY_PATH=$HOME/.config/asc/AuthKey_ABCDE12345.p8
```

(Set those three env vars in your shell rc once and the command shrinks to `make upload-testflight`.)

What this does:
1. Validates the three env vars and key file exist.
2. Copies the `.p8` into `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` - the path `altool` looks at by convention (idempotent; safe to re-run).
3. Picks the most recent `build/ios/ipa/*.ipa`.
4. Runs `xcrun altool --upload-app --type ios --file ... --apiKey ... --apiIssuer ...`.

Output finishes with `No errors uploading <file>.` on success. On failure, `altool` prints structured JSON-ish error blocks; the most common cause is **ITMS-90683 missing purpose string in Info.plist** (binary scan caught a privacy-sensitive API reference) — fix the plist, bump CFBundleVersion, rebuild.

> **Note on `iTMSTransporter`:** Apple removed `xcrun iTMSTransporter` from the Xcode 26 command-line tools. The replacements are either the standalone **Transporter Mac App Store app** (GUI + nested CLI under `/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter`) or **`xcrun altool --upload-app`**, which is what our Makefile uses. `altool` ships with Xcode CLT, accepts the same App Store Connect API key auth, and works in headless CI containers. Apple has signaled `altool` will eventually be deprecated in favor of direct App Store Connect API calls (or `notarytool` for notarization), but for IPA uploads it is the canonical CLI option as of Xcode 26.

### After upload

1. **App Store Connect -> your app -> TestFlight** tab. The build appears under "iOS Builds" with status "Processing" - typically 10-30 min. You will get an email when processing completes.
2. **Add yourself as Internal Tester:**
    - Click **Internal Testing** in the left sidebar -> **+** next to "Internal Group" -> create a group (e.g. "Core Team") -> add your Apple ID.
    - Once the build finishes processing, the group sees a "3.3.0 (1)" build (matching the version we set in `pubspec.yaml`).
3. **Install on Phlame** via the **TestFlight** app from the App Store. The app will appear there once you accept the email invitation.
4. **First run on TestFlight build:** verify (a) the legacy mnemonic auto-migration works if your previous on-device wallet was mnemonic-imported, (b) Face ID prompt looks right, (c) airplane-mode behavior matches the dev build.

### External testers (later, requires Beta App Review)

Internal testers (max 100, all on your team) can install with no review. **External testers** need a one-time Beta App Review per major version (~24h gate, then up to 10,000 testers per build). To enable:

1. TestFlight -> **External Groups** -> **+** -> create a group, add tester emails (or generate a public link).
2. Select a build and click **Submit for Beta App Review**. Provide:
    - Test contact info (your email + phone)
    - "What to test" notes
    - "App description" and "Beta App Description"
3. Apple reviews; on approval, all current and future builds in this version stream are auto-approved (no per-build review).

---

## 3. CI for App Store / TestFlight (`.github/workflows/build-ios.yml`)

Shipped on `feat/website-links-and-ios-ci`. Mirrors `build-macos.yml`'s SemVer + branch-strategy:

| Branch event | Pipeline | Destination |
|---|---|---|
| Push to `dev` | `make go-ios` + `flutter build ipa` + `altool upload` | TestFlight (Internal Group, no review) |
| Push to `main` | Same as dev + git tag + GitHub Release (notes only — no IPA asset) | TestFlight + ready for ASC submission via UI |

App Store submission for review is intentionally **not** automated. The "Submit for Review" click requires complete metadata (screenshots, age rating, review notes, what's-new copy), and an Apple rejection is expensive enough that gating it behind a human eyeball click is the right call. Once the build lands in TestFlight from main, promote it via App Store Connect → My Apps → "Prepare for Submission" → Add Build → Submit.

### Required GitHub Secrets (one-time setup)

Set these in **Settings → Secrets and variables → Actions** on `absgrafx/nodeneo`. The workflow won't run until all six are present.

| Secret | Source | How to populate |
|---|---|---|
| `APPLE_ASC_API_KEY_ID` | The 10-char key id from `.appstore` | Visible at App Store Connect → Users and Access → Integrations → Team Keys |
| `APPLE_ASC_API_ISSUER_ID` | The UUID issuer id from `.appstore` | Already known: `69a6de70-32af-47e3-e053-5b8c7c11a4d1` |
| `APPLE_ASC_API_KEY_P8` | base64-encoded contents of `~/.config/asc/AuthKey_<KEYID>.p8` | `base64 -i ~/.config/asc/AuthKey_<KEYID>.p8 \| pbcopy` |
| `APPLE_DIST_CERT_P12_BASE64` | The Apple Distribution cert exported as `.p12` from your keychain, base64-encoded | See *Exporting the Distribution cert* below |
| `APPLE_DIST_CERT_PASSWORD` | Password you typed when exporting the `.p12` | Pick a strong random one; only the secret needs it |
| `KEYCHAIN_PASSWORD` | Anything random — used to unlock the temp keychain on the runner | `uuidgen \| pbcopy` |

`APPLE_TEAM_ID` is **not** a secret — it's already in `ios/ExportOptions.plist` (`2S4578V7ZD`) and the Xcode project. The workflow reads it from there.

### Exporting the Distribution cert as `.p12`

Once locally — the same process the macOS workflow uses for its Developer ID cert.

1. **Confirm the cert exists** in your keychain: `security find-identity -p codesigning -v` should list an `Apple Distribution: <account name> (2S4578V7ZD)` row. If it doesn't, run `make ipa-testflight` once locally — the first invocation triggers Xcode's automatic-signing path which creates and registers the cert.
2. **Export it**: open Keychain Access → `My Certificates` (or `login` keychain) → expand the `Apple Distribution: <account name> (2S4578V7ZD)` entry to confirm it has both the cert AND the matching private key (you should see two child rows). Right-click the cert row → **Export** → set the format to **Personal Information Exchange (.p12)** → choose a password (this is `APPLE_DIST_CERT_PASSWORD`) → save somewhere outside the repo (e.g. `~/.config/asc/dist.p12`).
3. **Base64-encode** for the GitHub Secret: `base64 -i ~/.config/asc/dist.p12 | pbcopy`. Paste into the `APPLE_DIST_CERT_P12_BASE64` secret on GitHub. Verify with `pbpaste | base64 -d | openssl pkcs12 -info -noout -password pass:<password>` to confirm the cert + key roundtripped.

### One-time: confirm the App Store Connect app record exists

The workflow will fail upload with `ITMS-90238` if no app record exists for `com.absgrafx.nodeneo`. Walkthrough is in Section 2 (`Create the App Store Connect app record`) above — do this once before the first CI run.

### Sanity-check the workflow before the first push

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-ios.yml'))"

# Inspect the workflow run page after the first push
gh workflow view "iOS Build & TestFlight"
gh run list --workflow build-ios.yml --limit 5
```

The first CI run typically fails on a missing secret or an outdated Distribution cert — both surface as a clear error in the workflow log. Re-run after fixing.

### Local fallback when CI is broken

The workflow **uses the same `make ipa-testflight` + `make upload-testflight` chain you already run locally** (see Section 2). If CI is wedged, you can always cut a TestFlight build from your laptop without unblocking CI first. The local path was the path that proved the upload pipeline before CI was wired up; it stays as the backstop.

---

## Quick troubleshooting

| Symptom | Fix |
|---|---|
| `make ipa-testflight` -> "Signing for Runner requires a development team" | Open Xcode, sign into your Apple ID, select team `2S4578V7ZD`. |
| `make ipa-testflight` -> "No Apple Distribution cert" | See Section 2 -> "Confirm Apple Distribution cert". |
| `make upload-testflight` -> "ITMS-90161: Invalid Provisioning Profile" | The IPA was signed with a Development profile, not Distribution. Re-run `make ipa-testflight` after fixing signing. |
| `make upload-testflight` -> "ITMS-90189: Redundant Binary Upload" | CFBundleVersion (`+N` in pubspec.yaml) has not been bumped since the last upload. Increment and re-run. |
| `make upload-testflight` -> "ITMS-90683: Missing purpose string in Info.plist" | A privacy-sensitive API is referenced by your binary (often via a Pod transitive dep) without a matching `NS*UsageDescription` key. Add the key (and a meaningful, scoped purpose string) to `ios/Runner/Info.plist`, bump CFBundleVersion, rebuild. Apple bounces these one at a time, so add all expected siblings (`NSPhotoLibrary*`, `NSCamera`, `NSMicrophone` for `file_picker`-class deps) in one shot. |
| `make upload-testflight` -> "iTMSTransporter is now part of Transporter. Please install Transporter from the Mac App Store" | You are on Xcode 26+ and an older Makefile that still calls `xcrun iTMSTransporter`. Either install Transporter from the Mac App Store, or — preferred — switch to `xcrun altool --upload-app` (already wired in the current Makefile). |
| `make upload-testflight` -> "altool: command not found" | Xcode CLT not installed or not selected. Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, then `xcrun --find altool` should print a path. |
| TestFlight processing stuck >2 hours | Check the build's "Test Information" tab in ASC - sometimes a new privacy disclosure or export-compliance question is required and surfaces only after upload. |
| TestFlight install on device -> "Unable to install" | Phlame's iOS version may be older than the TestFlight build's deployment target. We target iOS 16+. |
| Cannot add an external tester | They need to install the **TestFlight** app first, then accept the email invite from within it. |
