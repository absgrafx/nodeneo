#!/bin/bash
# SQLite database + local files (conversations, RPC overrides, vault fallback files)
rm -rf ~/Library/Application\ Support/com.absgrafx.redpill/redpill/

# Keychain items (wallet mnemonic, app lock PIN)
# Either delete manually in Keychain Access (search "com.absgrafx.redpill")
# or run:
security delete-generic-password -s "com.absgrafx.redpill" 2>/dev/null; true