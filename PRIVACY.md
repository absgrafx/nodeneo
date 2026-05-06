# Node Neo Privacy Policy

**Effective date:** May 1, 2026  
**Last updated:** May 1, 2026  
**Publisher:** absgrafx ([github.com/absgrafx](https://github.com/absgrafx))  
**App:** Node Neo (`com.absgrafx.nodeneo`) — iOS, macOS, Android

> **In one sentence:** Node Neo runs entirely on your device. We — the publisher — operate no servers, collect no analytics, and have no account system. Your wallet keys, chat history, and preferences never leave your device unless you explicitly send a chat message to a third-party AI provider.

---

## 1. What Node Neo is

Node Neo is a mobile-first client for the **Morpheus** decentralized AI inference network. You hold a self-custodial wallet on your device, which authenticates per-session payments to independent AI model providers. Think of it as a chat client that talks to many small inference providers instead of one large company.

Node Neo is **not** a backend service. There is no absgrafx-operated server that processes your prompts, stores your chats, or holds your wallet keys. We do not have a database with your data in it because we do not have a database, full stop.

---

## 2. Information we collect

**absgrafx, the publisher of Node Neo, collects no personal information.** We do not operate a backend, have no analytics, and do not log your usage of the app.

That said, **using the app necessarily involves communicating with third parties** (a blockchain RPC endpoint, a public model registry, and the AI provider you choose to chat with). What you send to those parties is described in *Section 4 — Third parties* below.

---

## 3. Information stored on your device

Node Neo stores the following on your device, in protected storage. None of this is transmitted to absgrafx or to any other party except where you explicitly direct it:

| Data | Where it's stored | Purpose |
|------|------------------|---------|
| Wallet private key | iOS Keychain / Android Keystore / macOS Keychain (via `flutter_secure_storage`, hardware-backed where available) | Sign blockchain transactions and AI session payments |
| Wallet address | SQLite database in app sandbox | Display balances; correlate sessions |
| Chat conversations and messages | SQLite database in app sandbox | Show your history; resume conversations |
| App preferences (theme, default session length, custom RPC, etc.) | SQLite database in app sandbox | Restore your settings between launches |
| App-lock password hash (if you enable an app password) | iOS Keychain / Android Keystore (hashed with SHA-256 + per-install salt; not the raw password) | Verify the password you type to unlock the app |
| Cached AI model catalog | App sandbox file (`active_models.json`) | Avoid re-downloading the model catalog on every launch (5-minute cache, validated against an on-chain hash) |
| Wallet backup files (`.nnbak`) you choose to export | Wherever you save them (Files, iCloud Drive, etc.) | Restore your wallet on a different device |

You can:
- **Erase your wallet** in *Wallet → Erase wallet from this device*. This clears the wallet private key, app-lock credentials, and the local SQLite data, then re-launches the app in onboarding.
- **Delete the app entirely.** On iOS / macOS we proactively wipe orphaned Keychain entries on the next install (because iOS Keychain entries normally survive uninstall — Node Neo opts out of this default).

---

## 4. Third parties Node Neo connects to

Using Node Neo necessarily involves the following network connections. **We — absgrafx — are not a party to any of them. We do not see, log, or relay any of this traffic.**

### 4.1 Base mainnet RPC endpoint

To read your balance and submit on-chain transactions, Node Neo connects to a Base (Layer 2 Ethereum) RPC endpoint. By default this is a public Base RPC service; you can override it under *Settings → Network → Custom RPC*.

The RPC operator can see, for any request you make:
- Your IP address
- Your wallet address
- Which smart-contract methods you're calling
- Transactions you submit

This is true of every wallet on every blockchain. To minimize linkage:
- Use a privacy-respecting RPC (your own node, a paid RPC with no logging, etc.)
- Use a VPN to mask your IP

### 4.2 Morpheus active-models registry — `https://active.mor.org/active_models.json`

Node Neo periodically fetches the catalog of available models from Morpheus' public registry. This is a static JSON file; no authentication, no per-user data, no cookies. The registry operator may log standard HTTP request metadata (your IP, user-agent, timestamp).

### 4.3 AI model providers (per chat session)

When you start a chat, Node Neo opens an on-chain session with an independent **provider** chosen for the model you selected. The provider's URL is published on-chain via the Morpheus SessionRouter. From that point until the session closes:

- **Your prompts and the provider's responses flow directly between your device and that provider.** Node Neo does not relay, log, or proxy them.
- The provider sees your wallet address (used as session identity), your IP address, and the full content of your prompts.
- Some providers operate inside **Trusted Execution Environments (TEEs)** — these are flagged with the "MAX Privacy" badge in the app's model picker, and your prompts are encrypted such that even the provider operator cannot read them in clear text. **If end-to-end privacy matters for a particular conversation, only use models marked MAX Privacy.**
- Non-TEE providers can read, log, and retain your prompts according to their own policies, which absgrafx does not control or audit.

You acknowledge that the AI provider you select is the data controller for your prompts and responses, and that absgrafx has no contractual or technical relationship with that provider.

### 4.4 Apple App Store, App Store Connect, and TestFlight

If you obtained Node Neo from the App Store or TestFlight, Apple processes:
- Your purchase / install record (we receive only an aggregate install count via App Analytics, **never** individual user identity)
- TestFlight crash reports and basic interaction metadata, per Apple's standard Apple Developer Program agreement
- Any feedback you submit through TestFlight

Apple's handling of this data is governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). We receive only the aggregated, de-identified portion that App Store Connect surfaces to all developers.

### 4.5 No other third parties

Node Neo does **not** integrate with:
- Third-party analytics SDKs (no Firebase, Mixpanel, Amplitude, Segment, etc.)
- Third-party crash reporters (no Sentry, Crashlytics, Bugsnag, etc.)
- Advertising networks or tracking SDKs
- Social login or single-sign-on providers
- Push notification services

---

## 5. What we do not collect (App Store Privacy Disclosure mapping)

For clarity, here is how Node Neo's behavior maps to Apple's App Store Privacy categories. **All categories below are "Data Not Collected"** by absgrafx as the developer:

| Apple Category | Collected by absgrafx? | Notes |
|---|---|---|
| Contact Info (name, email, phone, address) | **No** | We have no account system. |
| Health & Fitness | **No** | |
| Financial Info | **No** | Your wallet private key is on-device only. We do not see balances, transactions, or session payments. |
| Location | **No** | Node Neo does not request location access. |
| Sensitive Info | **No** | |
| Contacts | **No** | |
| User Content (chat messages) | **Not by absgrafx.** Transmitted to your selected AI provider as described in §4.3. | Chat content is **stored on your device only**. When you send a prompt, it goes directly to the provider you chose; we do not see it. |
| Browsing History | **No** | |
| Search History | **No** | |
| Identifiers (IDFA, device ID) | **No** | We do not request, generate, or transmit any user-identifying token. |
| Purchases | **No** | |
| Usage Data | **No** | No analytics. |
| Diagnostics | **No** | No crash-reporting SDK. (Apple may collect TestFlight crash data per §4.4 — that flows to Apple, not to us.) |
| Other Data | **No** | Wallet address is on-device; not transmitted to absgrafx. |

---

## 6. iOS permissions you may see

Node Neo declares the following iOS permission usage strings in `Info.plist`. Most of them are required because of a third-party dependency (`file_picker`) and **only fire if you take a specific action**:

| Permission | When it's actually used |
|---|---|
| `NSFaceIDUsageDescription` (Face ID / Touch ID) | Only if you enable biometric app lock under *Preferences → App Lock*. |
| `NSPhotoLibraryUsageDescription` | Only if you tap "Restore from backup" and choose to pick a backup file from Photos. We never read your photo library otherwise. |
| `NSPhotoLibraryAddUsageDescription` | Only if you tap "Save backup" and choose Photos as the destination. |
| `NSCameraUsageDescription` | Reserved by the file picker SDK. Node Neo never takes a photo or records video on its own. |
| `NSMicrophoneUsageDescription` | Reserved by the file picker SDK. Node Neo never records audio. |

If iOS prompts you for any of these and you decline, Node Neo continues to function normally — only the specific feature that triggered the prompt becomes unavailable.

---

## 7. Children's privacy

Node Neo is **not directed at children under 17**. The app is rated **17+** in the App Store because:
- It connects to AI models whose responses are not curated by absgrafx and may produce mature, inaccurate, or harmful content
- It is a self-custodial cryptocurrency wallet (in the sense of holding a private key for blockchain identity), and we believe minors should not be making unsupervised on-chain financial decisions

We do not knowingly collect any personal information from children. If you are a parent or guardian and believe your child has installed Node Neo, the app's local data can be removed entirely by deleting the app from the device.

---

## 8. International users

Node Neo runs on your device wherever you are. Because we operate no backend, **there is no cross-border data transfer involving absgrafx as the data controller.**

Any cross-border transfer that occurs is between your device and:
- The Base RPC endpoint you've configured (default: public Base RPC, operator's location varies)
- `active.mor.org` (US-based)
- Whichever AI provider you select for a chat session (location varies; check the provider entry in the model picker)

**EU / UK / EEA users:** Because absgrafx processes no personal data of yours, the GDPR data-subject rights (access, rectification, erasure, portability, restriction, objection) do not have a server-side counterpart at absgrafx — there is nothing on our side to access or delete. You can exercise the equivalent on-device by erasing your wallet or deleting the app.

**California (CCPA / CPRA) residents:** Same as above. We are not a "business" that "sells" or "shares" personal information for the purposes of CCPA, because we collect no personal information.

---

## 9. Your choices

| You want to... | Do this |
|---|---|
| Stop using Node Neo | Delete the app. On iOS, our `FirstLaunchGuard` mechanism will wipe Keychain entries the next time the app is installed, so a fresh install starts clean. |
| Erase the wallet but keep the app | *Wallet → Erase wallet from this device*. |
| Back up the wallet for use elsewhere | *Wallet → Export private key*, or *Settings → Backup & Reset → Export backup* (`.nnbak` file). Store the result somewhere only you control. |
| Use a more private RPC endpoint | *Settings → Network → Custom RPC*. Point at your own Base node, a paid no-log RPC, or a Tor / VPN-fronted endpoint. |
| Use a more private AI model | Select any model marked **MAX Privacy** in the model picker (TEE-protected provider). |
| Question something in this policy | See §11 — Contact. |

---

## 10. Security

- **Wallet private key:** stored in iOS Keychain / macOS Keychain / Android Keystore via `flutter_secure_storage`, leveraging hardware-backed secure enclaves where the device supports them. Never written to disk in plain text and never transmitted off-device by Node Neo.
- **App-lock password:** never stored. We store a SHA-256 hash with a per-install random salt, used only for local verification. Even we could not recover your password from what is stored.
- **Backup files (`.nnbak`):** encrypted with a passphrase you provide at export time. Without that passphrase, the file is opaque ciphertext.
- **Code:** Node Neo is open source — every claim in this policy is auditable at <https://github.com/absgrafx/nodeneo>.

No system is perfectly secure. If you suspect Node Neo has a security vulnerability, please report it via the contact channels below — responsibly disclosed reports will be acknowledged within 72 hours.

---

## 11. Changes to this policy

If we change this policy in a way that affects how Node Neo handles data, we will:

1. Update the "Last updated" date at the top of this document
2. Note the change in the next release's `RELEASE_NOTES.md` and the in-app *About* screen
3. For materially adverse changes (none currently planned because there is no data flow to expand), publish notice in the app at least 30 days before the change takes effect

The current and historical versions of this policy live in this repository's git history.

---

## 12. Contact

| For | Reach us at |
|---|---|
| Bug reports, feature requests, support | <https://github.com/absgrafx/nodeneo/issues> |
| Anything else (privacy questions, security disclosures, general) | `nodeneo@absgrafx.com` |

absgrafx is an independent publisher operating Node Neo as a free, open-source DeAI client. The contact address above is a single shared inbox; please put a clear subject line (e.g. *"Security disclosure"*, *"Privacy question"*) so we can prioritize correctly. We do not run an organization-scale support desk; please be patient and detailed in your reports.
