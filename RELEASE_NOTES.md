## What's New

### Customizable System Prompts
- Set a default persona for all chats (Preferences > System Prompt)
- Override per-conversation from the Chat Tuning panel
- Encrypted at rest, included in backup/restore

### MOR Balance Scanner ("Where's My MOR")
- On-chain scan showing MOR across three buckets: wallet, active sessions, and on-hold timelock
- Recover claimable MOR with one tap (sends `withdrawUserStakes` transaction)

### Settings Reorganization
- **Preferences** — System Prompt, Default Tuning, Session Duration, Security (app lock, biometrics)
- **Wallet** — Key Management, Where's My MOR, Active Sessions
- **Expert Mode** — Network, API, Gateway
- **Backup & Reset** — Data Backup, Danger Zone

### Expert API Authentication
- Auto-generated HTTP Basic Auth for the Developer API (Swagger)
- Credentials displayed masked with reveal/copy in Expert Mode
- Only safe routes exposed (selective registration prevents crashes)

### Security Improvements
- Erase Wallet and Factory Reset now require private key confirmation
- Simplified private key export (single dialog with warning + masked key)
- RPC URLs sanitized in error messages (hostname only, no API keys leaked)

### Data Integrity
- All preferences migrated from files to SQLite (encrypted, backed up/restored)
- Per-conversation system prompts included in backup/restore
- Replaced discontinued `flutter_markdown` with `flutter_markdown_plus`
