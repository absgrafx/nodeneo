# Node Neo — App security (hot wallet)

## Goals

1. **App lock** — Password separate from the BIP-39 seed; required after cold start and when returning from background (paused).
2. **Biometrics** — Optional Face ID / Touch ID / fingerprint to unlock (platform-dependent).
3. **Password managers** — Same **[AutofillGroup](https://api.flutter.dev/flutter/widgets/AutofillGroup-class.html)** with a **fixed synthetic username** (**`AutofillHints.username`**, value `Node Neo` — not the wallet) **plus** **`AutofillHints.password`** / **`AutofillHints.newPassword`**. Many systems (especially **macOS / iOS**) only offer save/fill when they see a **username + password** pair; native apps often use a **hidden or read-only** synthetic username for app-only passwords. Node Neo shows it as a small read-only **“Password manager ID”** row so vault entries stay stable when the wallet changes.

## What is implemented (MVP)

- **⋮ → Security** → turn on lock, change password, optional biometrics, turn off (password required).
- **SHA-256(salt:password)** stored in **flutter_secure_storage** (not the mnemonic).
- **AppLockGate** wraps the home experience after onboarding when a wallet exists.
- **Lifecycle:** `AppLifecycleState.paused` → lock if app lock is enabled.

## Hardening backlog

- **Rate-limit** failed password attempts; optional lockout timer.
- **Biometric enrollment change** — detect and prompt re-auth.
- **Screenshot / overlay** privacy on lock screen (iOS secure text field flags where applicable).
- **Auto-lock timeout** (e.g. 5 min in foreground) in addition to background.
- **macOS** — Touch ID support varies; password path always works.

## Wallet vs app password

| Secret | Role |
|--------|------|
| **Mnemonic** | On-chain funds; in Keychain / secure store; **never** the same as app lock password. |
| **App password** | UI gate only; if lost, user still has seed — but must re-import / erase app data carefully. |

Communicate in UI: app password **does not replace** backing up the seed phrase.
