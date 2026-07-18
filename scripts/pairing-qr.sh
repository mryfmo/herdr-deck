#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${HERDDECK_CONFIG:-$ROOT/gateway/config.json}"
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
command -v tailscale >/dev/null 2>&1 || { echo "tailscale CLI is required" >&2; exit 1; }

TOKEN_FILE="$(CONFIG="$CONFIG" python3 - <<'PYJSON'
import json, os
with open(os.environ['CONFIG']) as f: c=json.load(f)
print(os.path.expandvars(c.get('tokenFile','${HOME}/.config/herddeck/token')))
PYJSON
)"
[[ -s "$TOKEN_FILE" ]] || { echo "Missing token at $TOKEN_FILE" >&2; exit 1; }
DNS_NAME="$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
NAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
PAIR_URL="$(ENDPOINT="https://$DNS_NAME" TOKEN="$TOKEN" NAME="$NAME" python3 - <<'PY'
import os,urllib.parse
query=urllib.parse.urlencode({'endpoint':os.environ['ENDPOINT'],'token':os.environ['TOKEN'],'name':os.environ['NAME']})
print('herddeck://pair?'+query)
PY
)"

printf 'Pairing endpoint: https://%s\n' "$DNS_NAME"
printf 'This QR contains the Gateway bearer token. Display it privately and do not save or share it.\n\n'
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ANSIUTF8 "$PAIR_URL"
else
  printf '%s\n' "$PAIR_URL"
  printf '\nInstall qrencode for a terminal QR: brew install qrencode\n'
fi
