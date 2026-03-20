# RedPill — Run on a physical iPhone (Apple Developer)

Stepwise checklist. You already have a **paid Apple Developer Program** account.

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
4. Change **Bundle Identifier** if needed (e.g. `com.yourorg.redpill`). It must be unique in the Apple Developer portal.

Enable **Automatically manage signing** so Xcode creates a **development** provisioning profile for your device.

---

## 3. Trust the Mac and enable Developer Mode (device)

1. Connect the iPhone with USB (or use wireless debugging after pairing).
2. On the phone: **Trust** this computer if asked.
3. **iOS 16+:** **Settings → Privacy & Security → Developer Mode** → On → reboot if required.

---

## 4. Build & run from Xcode (first success)

1. In Xcode’s toolbar, pick your **iPhone** as the run destination (not a simulator).
2. **Product → Run** (▶).  
   - First run may ask to **enable development** on the device; accept on the phone.
3. If signing errors appear, read the red message: missing capability, wrong team, or bundle ID conflict — fix in **Signing & Capabilities**.

---

## 5. Build from Flutter CLI

```bash
cd redpill
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

## 7. Native Go library on iOS (important for RedPill)

Today’s **Makefile** target **`go-macos`** builds **`libredpill.dylib`** for **macOS** and the Xcode **Copy Go Library** phase copies it into the Mac app.

**iOS** does not load a macOS dylib. You need an **iOS slice** of the same c-shared library (e.g. **`.framework`** / **`.xcarchive`** embedding) or a separate **gomobile** / **cgo** pipeline that targets `GOOS=ios` / `arm64`. This is a **follow-up engineering task**: wire the Go `cshared` build into the **Runner** Xcode project for **iphoneos**, similar to the macOS copy phase.

Until that is done, **Flutter UI** can run on a device, but **dart:ffi calls into `libredpill` will fail** unless the iOS binary is embedded.

**Track as:** “iOS Go c-shared / xcframework + Runner embed” before treating iPhone as a full RedPill target.

---

## 8. Capabilities you may need later

- **Keychain** — `flutter_secure_storage` uses the Keychain; standard app signing is usually enough.
- **Face ID** — `NSFaceIDUsageDescription` is already in **`ios/Runner/Info.plist`** for app lock.
- **App Groups** — only if you add extensions or share data with other apps.

---

## Quick troubleshooting

| Symptom | What to check |
|--------|----------------|
| “Signing for Runner requires a development team” | Pick a **Team** in Signing & Capabilities. |
| “Failed to register bundle identifier” | Bundle ID already taken — change it or use the portal app id. |
| Device grayed out | Cable, **Trust**, **Developer Mode**, or iOS version too old for your Xcode. |
| App installs but crashes on launch (FFI) | **Go native library not built/linked for iOS** (see §7). |
