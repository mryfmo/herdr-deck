#!/bin/bash
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.herddeck.gateway.plist"
launchctl bootout "gui/$UID/com.herddeck.gateway" >/dev/null 2>&1 || true
rm -f "$PLIST"
printf 'Removed HerdDeck LaunchAgent. Configuration, token, and logs were left intact.\n'
