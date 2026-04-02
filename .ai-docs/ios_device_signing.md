# Node Neo — Run on a physical iPhone (Apple Developer)

Stepwise checklist. You already have a **paid Apple Developer Program** account.

---

## 0. Preview & run from Xcode (simulator or device)

**Open the Flutter iOS workspace (required for CocoaPods):**

```bash
cd nodeneo
open ios/Runner.xcworkspace
```

**Pick a destination** in Xcode's toolbar (e.g. **iPhone 16** simulator or your **plugged-in iPhone**).

**Run:**

- **Product → Run** (▶), **or**
- From the repo root, same result: `flutter run` (Xcode builds under the hood when you use Flutter CLI).

**Flutter-only workflow (no Xcode UI):**

```bash
flutter devices
flutter run -d <device_id_or_name>
```

### Cursor-first (recommended)

You do **not** need two IDEs for daily runs.

1. **One-time / occasional:** Use **Xcode** only for **Signing & Capabilities**, adding **capabilities** (e.g. Face ID), or **Archive** for TestFlight. Save the project; commit what changed under `ios/` (see **Git** below).
2. **Every build:** In Cursor's terminal from repo root:

   ```bash
   cd nodeneo
   flutter run -d Phlame    # or: flutter run -d 00008140-000E10601E29801C
   ```

   Flutter invokes **xcodebuild** with the correct **`.xcworkspace`** and CocoaPods layout. Prefer this over clicking **Run** on `Runner.xcodeproj` (that path often breaks pods).

3. If Xcode or a stale build shows **`Module 'flutter_native_splash' not found`** (or any plugin module):

   ```bash
   flutter pub get
   cd ios && pod install --repo-update && cd ..
   flutter run -d <device>
   ```

   Still broken: `flutter clean`, then the same `pub get` → `pod install` → `flutter run`.

### Git (two IDEs)

- **`ios/Pods/`** is **gitignored** — each machine runs `pod install` after clone / `pub get`.
- **Do commit** `ios/Podfile`, **`ios/Podfile.lock`**, and Xcode project changes you intend to keep.
- Opening Xcode does not create mystery noise if you only touch signing; avoid editing **generated** Flutter files under `ios/Flutter/` unless you know why.

**Note:** The **simulator** is enough to preview **UI** quickly. A **real device** still needs **signing** (§2–4) and, for this app, an **iOS build of the Go `libnodeneo` native library** before FFI works (§7).

---

## 1. Apple ID in Xcode

1. Open **Xcode** → **Settings…** (or **Preferences**) → **Accounts**.
2. Add your **Apple ID** → select your **Team** (personal or company).
3. Download manual profiles if prompted.

---

## 2. Bundle identifier (must be unique)

1. In the repo, open **`ios/Runner.xcworkspace`** (not `.xcodeproj` alone).
2. Select **Runner** target → **Signing & Capabilities**.
3. Set **Team** to your developer team.
4. Change **Bundle Identifier** if needed (repo default: `com.absgrafx.nodeneo`, reverse-DNS for **absgrafx.com**). It must be unique in the Apple Developer portal.

Enable **Automatically manage signing** so Xcode creates a **development** provisioning profile for your device.

---

## 3. Trust the Mac and enable Developer Mode (device)

1. Connect the iPhone with USB (or use wireless debugging after pairing).
2. On the phone: **Trust** this computer if asked.
3. **iOS 16+:** **Settings → Privacy & Security → Developer Mode** → On → reboot if required.

---

## 4. Build & run from Xcode (first success)

1. In Xcode's toolbar, pick your **iPhone** as the run destination (not a simulator).
2. **Product → Run** (▶).  
   - First run may ask to **enable development** on the device; accept on the phone.
3. If signing errors appear, read the red message: missing capability, wrong team, or bundle ID conflict — fix in **Signing & Capabilities**.

---

## 5. Build from Flutter CLI

```bash
cd nodeneo
flutter devices                    # confirm the phone appears
flutter run -d <device_id>         # or pick from list
```

For a **release-style** device build without going through Xcode UI every time:

```bash
flutter build ios
```

Then open **`ios/Runner.xcworkspace`**, select **Any iOS Device (arm64)** or your phone, **Product → Archive** for distribution (TestFlight / Ad Hoc).

---

## 6. TestFlight (optional, for testers)

1. **Archive** in Xcode → **Distribute App** → **App Store Connect** → **Upload**.
2. In [App Store Connect](https://appstoreconnect.apple.com/), create the app record (bundle ID must match), wait for processing, then add **Internal/External testing** in TestFlight.

---

## 7. Native Go library on iOS — DONE

### How it works

| Platform | Build mode | Output | Loaded by |
|----------|-----------|--------|-----------|
| **macOS** | `c-shared` | `libnodeneo.dylib` (Frameworks/) | `DynamicLibrary.open()` |
| **iOS** | `c-archive` | `libnodeneo.a` (static lib) | `DynamicLibrary.process()` — symbols linked into Runner binary |

iOS does **not** load `.dylib`; instead Go is compiled as a **static archive** (`-buildmode=c-archive`, `GOOS=ios GOARCH=arm64`) and the Xcode linker pulls it into the **Runner** executable.

### Build the iOS Go library

```bash
cd nodeneo
make go-ios          # → build/go/ios/libnodeneo.a  (~65 MB, arm64)
```

Requires **Go 1.26+** (via `/opt/homebrew/bin/go`) and the **iphoneos** SDK (Xcode).

### How it is linked

The Runner target's **`project.pbxproj`** (Debug / Release / Profile) has:

- `LIBRARY_SEARCH_PATHS` → `$(SRCROOT)/../build/go/ios`
- `OTHER_LDFLAGS` → `-lnodeneo -lresolv -framework Security -framework CoreFoundation`

No build phase script is needed; the linker finds `libnodeneo.a` in the search path by convention (`-lnodeneo` → `libnodeneo.a`).

### Full device deploy (Cursor terminal)

```bash
make go-ios                    # build native lib (skip if already built)
flutter run -d Phlame          # or: flutter run -d <device_id>
```

Or all-in-one: **`make run-ios`** (builds Go, then `flutter run`).

**Important:** `flutter clean` removes the `build/` dir including `libnodeneo.a`. After a clean, run **`make go-ios`** before `flutter run`.

---

## 8. Capabilities you may need later

- **Keychain** — `flutter_secure_storage` uses the Keychain; standard app signing is usually enough.
- **Face ID** — `NSFaceIDUsageDescription` is already in **`ios/Runner/Info.plist`** for app lock.
- **App Groups** — only if you add extensions or share data with other apps.

---

## Quick troubleshooting

| Symptom | What to check |
|--------|----------------|
| "Signing for Runner requires a development team" | Pick a **Team** in Signing & Capabilities. |
| "Failed to register bundle identifier" | Bundle ID already taken — change it or use the portal app id. |
| Device grayed out | Cable, **Trust**, **Developer Mode**, or iOS version too old for your Xcode. |
| App installs but crashes on launch (FFI) | Run **`make go-ios`** first, then `flutter run` (see §7). |
| `Library 'nodeneo' not found` (linker error) | `flutter clean` wiped `build/`. Run **`make go-ios`** and build again. |
