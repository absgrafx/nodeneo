#!/bin/bash
# SQLite database + local files (conversations, RPC overrides, chat storage, logs)
rm -rf ~/Library/Application\ Support/com.nodeneo.app/nodeneo/

# Keychain items (search "com.nodeneo.app" in Keychain Access)
security delete-generic-password -s "com.nodeneo.app" 2>/dev/null; true
