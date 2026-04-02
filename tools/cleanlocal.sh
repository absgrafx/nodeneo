#!/bin/bash
# SQLite database + local files (conversations, RPC overrides, chat storage, logs)
rm -rf ~/Library/Application\ Support/com.absgrafx.nodeneo/nodeneo/

# Keychain items (search "com.absgrafx.nodeneo" in Keychain Access)
security delete-generic-password -s "com.absgrafx.nodeneo" 2>/dev/null; true
