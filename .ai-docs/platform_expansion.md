# Platform Expansion Plan

Comprehensive plan for publishing Node Neo across platforms from a single codebase: iOS App Store (iPhone + iPad), Android (Google Play), and future desktop expansion (Windows, Linux).

*Last updated: 2026-04-14*

---

## Strategy

One Flutter codebase, one Go SDK codebase, platform-specific build artifacts. The UI and business logic are shared; only the Go binary format and platform runner differ per target. Feature availability is controlled at the **sub-option level** via runtime platform checks -- no conditional compilation directives, no separate repos, no build flavors.

### Platform Priority Order

| # | Platform | Distribution | Status |
|---|----------|-------------|--------|
| 1 | **macOS** (arm64) | Signed/notarized DMG via GitHub Releases | Done -- refining |
| 2 | **iOS** (iPhone + iPad) | App Store + TestFlight | **Next** |
| 3 | **Android** (arm64, x86_64) | Google Play + sideload APK | Planned |
| 4 | **Linux** (x86_64, arm64) | AppImage / .deb | Future |
| 5 | **Windows** (x86_64) | MSIX or Inno Setup | Future |

### Delivery Tiers

**All platforms** share the core consumer experience: onboarding, wallet, chat, model browser, session management, settings, backup/restore, and blockchain connection configuration.

**Desktop platforms** (macOS, Linux, Windows) additionally expose server-side developer tooling: Developer API (Swagger), AI Gateway, API keys, MCP server integration.

**Mobile platforms** (iOS, Android) include Blockchain Connection (RPC config) but exclude features that require long-running local HTTP servers, which are impractical on mobile due to background execution limits and App Store/Play Store policy.

---

## Platform Feature Matrix

Granular breakdown of what ships on each platform. The gating happens at the **individual feature / accordion section** level, not at the "Expert Mode" screen level.

### Core Features (All Platforms)

| Feature | iPhone | iPad | macOS | Android | Linux | Windows |
|---------|--------|------|-------|---------|-------|---------|
| Onboarding (create/import wallet) | Yes | Yes | Yes | Yes | Yes | Yes |
| Home (balances, model list, chat entry) | Yes | Yes | Yes | Yes | Yes | Yes |
| Chat (streaming, tuning, metadata) | Yes | Yes | Yes | Yes | Yes | Yes |
| Wallet (keys, backup, erase, reset) | Yes | Yes | Yes | Yes | Yes | Yes |
| Sessions (duration, system prompt, on-chain list) | Yes | Yes | Yes | Yes | Yes | Yes |
| Send MOR / Send ETH | Yes | Yes | Yes | Yes | Yes | Yes |
| MAX Privacy (TEE toggle) | Yes | Yes | Yes | Yes | Yes | Yes |
| Conversation history (drawer) | Yes | Yes | Yes | Yes | Yes | Yes |
| Version and Logs | Yes | Yes | Yes | Yes | Yes | Yes |
| Backup and Reset | Yes | Yes | Yes | Yes | Yes | Yes |

### Expert Mode Sub-Options (Granular Gating)

| Expert Mode Section | iPhone | iPad | macOS | Android | Linux | Windows | Rationale |
|---------------------|--------|------|-------|---------|-------|---------|-----------|
| **Blockchain Connection** (RPC config) | Yes | Yes | Yes | Yes | Yes | Yes | Users on any platform may need custom RPC endpoints |
| **Developer API** (Swagger REST server) | No | No | Yes | No | Yes | Yes | Local HTTP server for devs -- impractical on mobile |
| **AI Gateway** (OpenAI-compat server) | No | No | Yes | No | Yes | Yes | Serves external tools -- requires persistent HTTP server |
| **API Keys** (generate, revoke, list) | No | No | Yes | No | Yes | Yes | Tied to Gateway -- no gateway means no keys needed |
| **MCP Server** integration info | No | No | Yes | No | Yes | Yes | stdio process for desktop AI agents |

### Settings Drawer Adaptation

On **desktop**, the Settings drawer shows Expert Mode as today: "Network / API / Gateway".

On **mobile**, Expert Mode still appears but with reduced scope. Options: keep "Expert Mode" label with just Blockchain Connection, or rename the drawer entry to "Network" on mobile. UX decision to finalize during implementation.

---

## Feature Gating: Sub-Option Granularity

### Implementation: PlatformCaps

A single Dart class with static getters that Expert Mode and other screens query at runtime. Located at `lib/services/platform_caps.dart`:

```dart
import 'dart:io' show Platform;

class PlatformCaps {
  PlatformCaps._();

  static bool get isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  // Expert Mode sub-sections
  static bool get supportsBlockchainConfig => true;
  static bool get supportsDeveloperApi => isDesktop;
  static bool get supportsGateway => isDesktop;
  static bool get supportsApiKeys => supportsGateway;
  static bool get supportsMcp => isDesktop;
}
```

### Usage in Expert Screen

The `ExpertScreen.build()` conditionally includes sections based on PlatformCaps:

- Blockchain Connection: always shown
- Developer API section: wrapped in `if (PlatformCaps.supportsDeveloperApi)`
- AI Gateway section: wrapped in `if (PlatformCaps.supportsGateway)`

The Go SDK state variables and methods for Developer API / Gateway remain in the screen class but are never exercised on mobile since the UI controls are hidden.

### Usage in Settings Drawer

The drawer item adapts its title and subtitle based on `PlatformCaps.isDesktop`.

### Go SDK: No Changes Needed

The Go SDK ships all capabilities on all platforms. Functions like `StartExpertAPI`, `StartGateway`, and API key management remain in `api.go` but are never called on mobile because the Dart UI does not expose the controls. This keeps the Go layer platform-agnostic with no conditional compilation.

---

## Phase 1: iOS App Store (iPhone + iPad)

### 1.1 Go SDK: xcframework Build (Gating Risk -- Do First)

The macOS build produces `libnodeneo.dylib` via `go build -buildmode=c-shared`. iOS does not allow third-party dynamic libraries. The Go code must be compiled as a static library and packaged into an xcframework.

**Steps:**

1. Install/verify gomobile: `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`
2. Build via `go build -buildmode=c-archive` targeting ios/arm64, then wrap with `xcodebuild -create-xcframework`
3. Embed the xcframework in the Xcode project (ios/Runner/) -- Frameworks, Libraries, and Embedded Content
4. Update `bridge.dart` FFI loading: on iOS use `DynamicLibrary.process()` (static link) instead of `.open('libnodeneo.dylib')`
5. Verify all FFI exports resolve -- build and run on iOS Simulator (arm64)
6. Test on a physical iPhone via Xcode with a dev provisioning profile

**Makefile targets to add:** `go-ios`, `flutter-ios`, `run-ios`

**Key decisions:**

- `gomobile bind` vs manual c-archive + xcframework: gomobile bind creates an ObjC wrapper; c-archive preserves the existing `//export` C surface 1:1. Evaluate which maps better to the current FFI bridge.
- The xcframework should include ios-arm64 (device) and optionally ios-arm64-simulator (Apple Silicon Simulator).

### 1.2 iOS Deployment Target

**Bump from iOS 13.0 to iOS 16.0.**

Files to update:

- `ios/Podfile` -- `platform :ios, '16.0'`
- `ios/Runner.xcodeproj/project.pbxproj` -- IPHONEOS_DEPLOYMENT_TARGET = 16.0 for all configurations
- Verify all CocoaPods dependencies support iOS 16+

iOS 16.0 covers approximately 95% of active iPhones (iPhone 8 forward). iOS 17 would cut iPhone 8 and X; iOS 18 is too recent.

### 1.3 Info.plist Additions

Already present: `NSFaceIDUsageDescription`, `LSRequiresIPhoneOS`, orientation support.

Additional entries needed:

| Key | Value | Why |
|-----|-------|-----|
| `NSAppTransportSecurity` | Evaluate localhost exception | ATS compliance |
| `ITSAppUsesNonExemptEncryption` | `false` (standard APIs) | Export compliance |
| `UIBackgroundModes` | Evaluate for session auto-close | Background execution (may defer to v2) |

### 1.4 UI Adaptations for iOS

| Area | Action |
|------|--------|
| Safe area insets | Verify on notch/Dynamic Island devices |
| Keyboard handling | Chat input must scroll above iOS keyboard |
| Small screen layout | Test on iPhone SE (375pt width) |
| Touch targets | Audit for 44pt minimum per Apple HIG |
| Status bar | Verify contrast on dark background |
| Text scaling | Respect iOS Dynamic Type |

### 1.5 App Store Connect Setup

1. Verify App ID `com.absgrafx.nodeneo` is configured for iOS in Apple Developer portal
2. Enable capabilities: Keychain Sharing, possibly Background Modes
3. Create iOS Development and Distribution provisioning profiles
4. Create iOS app record in App Store Connect (separate from macOS)
5. Use Xcode automatic signing with existing team cert

### 1.6 TestFlight (Before Submission)

1. Build archive: `flutter build ipa --release`
2. Upload via Xcode Organizer or Transporter
3. Automated review (minutes) -- private API usage, entitlements, binary size
4. Internal testing: up to 25 testers, no App Store review
5. Test on physical devices: iPhone SE, iPhone 15/16, iPad
6. External TestFlight (optional): up to 10,000 testers

### 1.7 iOS Task Checklist

- [ ] Go xcframework builds for iOS arm64
- [ ] FFI bridge loads framework on iOS (bridge.dart update)
- [ ] `flutter build ios` succeeds with xcframework linked
- [ ] App runs on iOS Simulator
- [ ] App runs on physical iPhone (dev provisioning profile)
- [ ] Bump deployment target to iOS 16.0 (Podfile + pbxproj)
- [ ] Add PlatformCaps class
- [ ] Expert screen: only Blockchain Connection on iOS
- [ ] Settings drawer: adapt label/subtitle on mobile
- [ ] UI audit: safe areas, keyboard, small screens, touch targets
- [ ] Info.plist: ATS, encryption compliance, background modes
- [ ] App Store Connect: app record, provisioning profiles
- [ ] Privacy policy URL (publicly accessible)
- [ ] App Store screenshots (6.7 inch, 6.1 inch, iPad 12.9 inch)
- [ ] Privacy nutrition labels declared
- [ ] Review notes drafted
- [ ] TestFlight internal build uploaded and tested
- [ ] App Store submission

---

## Phase 2: Android (Google Play)

### 2.1 Go SDK: .so Build

1. Cross-compile for arm64 and x86_64 using `go build -buildmode=c-shared`
2. Place .so files in `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/`
3. Update `bridge.dart` FFI loading: `DynamicLibrary.open('libnodeneo.so')`
4. Verify on emulator + physical device

Android allows .so dynamic libraries natively -- simpler than the iOS xcframework path. Needs Android NDK for CGO cross-compilation.

### 2.2 Android-Specific Adaptations

- Keystore: `flutter_secure_storage` uses Android Keystore by default
- Permissions: network in AndroidManifest.xml (likely from Flutter template)
- Back gesture: Flutter handles Android back by default
- Material You: consider dynamic color on Android 12+
- Minimum API: 24 (Android 7.0) -- Flutter 3.x minimum

### 2.3 Google Play Submission

1. Google Play Developer account ($25 one-time)
2. Build: `flutter build appbundle --release` (.aab required)
3. App signing: Play App Signing
4. Store listing: screenshots, description, privacy policy
5. Content rating questionnaire
6. Internal testing -> Closed testing -> Production

Google Play is less restrictive than Apple for crypto/wallet apps. Still needs privacy policy and Data Safety section.

### 2.4 Feature Gating

Same PlatformCaps -- `Platform.isAndroid` means isMobile is true. Desktop-only features hidden. Blockchain Connection available.

---

## Phase 3: Windows and Linux

### 3.1 Go SDK

| Platform | Artifact | Build |
|----------|----------|-------|
| Linux x86_64 | libnodeneo.so | `GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -buildmode=c-shared` |
| Linux arm64 | libnodeneo.so | Cross-compile or ARM CI runner |
| Windows x86_64 | nodeneo.dll | `GOOS=windows GOARCH=amd64 CGO_ENABLED=1` (MinGW) |

### 3.2 Platform Notes

**Linux:** `flutter_secure_storage` uses libsecret (GNOME Keyring). Distribution via AppImage / .deb. Desktop file + icon registration. No notarization.

**Windows:** `flutter_secure_storage` uses Windows Credential Manager. Distribution via MSIX or Inno Setup. EV cert for SmartScreen optional initially. MinGW for Go CGO.

### 3.3 Feature Gating

Both are desktop -- `PlatformCaps.isDesktop` is true. Full Expert Mode with all sub-sections.

---

## Go SDK Build Matrix

| Platform | Go Build Mode | Output | FFI Loading |
|----------|--------------|--------|-------------|
| macOS arm64 | c-shared | libnodeneo.dylib | `DynamicLibrary.open()` |
| iOS arm64 | c-archive / xcframework | Nodeneo.xcframework | `DynamicLibrary.process()` |
| Android arm64/x86_64 | c-shared | libnodeneo.so | `DynamicLibrary.open()` |
| Linux x86_64/arm64 | c-shared | libnodeneo.so | `DynamicLibrary.open()` |
| Windows x86_64 | c-shared | nodeneo.dll | `DynamicLibrary.open()` |

The `bridge.dart` FFI initialization already branches on platform to load the correct library. This extends naturally to new platforms.

---

## App Store Metadata and Review Strategy

### App Identity

| Field | Value |
|-------|-------|
| App name | Node Neo |
| Subtitle | Decentralized AI Chat |
| Bundle ID | com.absgrafx.nodeneo |
| Category (primary) | **Productivity** |
| Category (secondary) | Utilities |
| Age rating | 4+ or 12+ |

### App Description (Draft)

Node Neo is a private AI chat client for the Morpheus decentralized AI network. Pick a model, start a conversation, and chat -- all without running infrastructure or trusting a central server.

Private by design. No analytics, no telemetry, no data collection. Your conversations are encrypted on-device. Your prompts go directly to AI providers on the Morpheus network -- no middleman.

How it works: Node Neo uses MOR tokens to access AI inference providers on the Morpheus network (Base blockchain). Users bring their own tokens and manage them in a non-custodial wallet. The app does not sell, exchange, or trade tokens.

Features include chat with multiple AI models, MAX Privacy mode for hardware-attested inference, non-custodial wallet, AES-256-GCM encrypted conversation history, per-conversation tuning parameters, real-time streaming responses, and encrypted backup/restore.

### Privacy Policy Requirements

Must be a publicly accessible URL. Key points:

- No data collection, analytics, telemetry, or crash reporting
- Private keys in device secure enclave (iOS Keychain)
- Conversations encrypted at rest, stored locally only
- Network traffic direct to blockchain RPCs and AI providers -- no developer servers
- No accounts, registration, or email collection
- Wallet address on public blockchain for transactions

### Privacy Nutrition Labels

Expected declaration: **Data Not Collected** -- the simplest possible label. Node Neo collects no data that leaves the device.

### Review Notes (Draft)

**What this app does:** Decentralized AI chat client -- similar to ChatGPT or Grok -- connecting to the Morpheus AI network.

**Wallet and tokens:** Non-custodial wallet for MOR tokens (access tokens for AI inference, like API credits). On-device only. Tokens acquired externally.

**This app does NOT:** facilitate trading/exchange, offer in-app purchases, act as custodian, or collect user data.

**To test:** Requires MOR and ETH on Base. Contact support for test wallet funding or walkthrough.

**Export compliance:** Standard iOS crypto APIs for AES-256-GCM. No proprietary algorithms.

### Screenshots Required

| Device | Dimensions |
|--------|-----------|
| iPhone 6.7 inch | 1290 x 2796 |
| iPhone 6.5 inch | 1242 x 2688 |
| iPad Pro 12.9 inch | 2048 x 2732 |

Suggested set: home screen, chat conversation, MAX Privacy toggle, model list, settings.

---

## Open Questions

| # | Question | Impact | Decide By |
|---|----------|--------|-----------|
| 1 | gomobile bind vs manual c-archive + xcframework? | Build complexity, FFI compat | Before Phase 1 Go work |
| 2 | Privacy policy hosting -- GitHub Pages or landing page? | App Store blocker | Before TestFlight |
| 3 | Support email/URL -- dedicated or GitHub Issues? | App Store submission | Before TestFlight |
| 4 | Rename drawer to "Network" on mobile or keep "Expert Mode"? | UX consistency | During PlatformCaps impl |
| 5 | Background execution -- BGTaskScheduler for auto-close or foreground-only v1? | Architecture | During iOS adaptation |
| 6 | iPad: Split View / Slide Over day one or basic layout first? | Scope | Before submission |
| 7 | Test token faucet for reviewers -- how to fund review wallet? | Rejection risk | Before submission |
| 8 | Google Play Developer account -- existing or create? | Phase 2 timeline | Before Phase 2 |
| 9 | Minimum Android API -- 24 or higher? | Device coverage | Before Phase 2 |

---

*Single source of truth for platform expansion. Update as decisions are made and phases complete.*
