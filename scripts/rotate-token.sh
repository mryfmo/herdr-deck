#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${HERDDECK_CONFIG:-$ROOT/gateway/config.json}"
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }

TOKEN_FILE="$(CONFIG="$CONFIG" python3 - <<'PY'
import json, os
with open(os.environ['CONFIG']) as f: c=json.load(f)
print(os.path.expandvars(c['tokenFile']))
PY
)"

TOKEN_DIR="$(dirname "$TOKEN_FILE")"
if [[ ! -d "$TOKEN_DIR" ]]; then
  mkdir -p "$TOKEN_DIR"
  chmod 700 "$TOKEN_DIR"
fi
TMP="$TOKEN_FILE.$$.tmp"
trap 'rm -f "$TMP"' EXIT
umask 077
python3 - <<'PY' > "$TMP"
import secrets
print(secrets.token_urlsafe(32))
PY
chmod 600 "$TMP"
mv "$TMP" "$TOKEN_FILE"
trap - EXIT

if [[ "$(uname -s)" == "Darwin" ]] && launchctl print "gui/$UID/com.herddeck.gateway" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$UID/com.herddeck.gateway"
  printf 'Rotated token and restarted the HerdDeck Gateway.\n'
else
  printf 'Rotated token. Restart the HerdDeck Gateway before reconnecting.\n'
fi
printf 'All paired devices must pair again. Run:\n  %s/scripts/pairing-qr.sh\n' "$ROOT"
