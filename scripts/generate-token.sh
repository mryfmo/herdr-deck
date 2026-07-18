#!/bin/bash
set -euo pipefail

TOKEN_FILE="${HERDDECK_TOKEN_FILE:-$HOME/.config/herddeck/token}"
TOKEN_DIR="$(dirname "$TOKEN_FILE")"
if [[ ! -d "$TOKEN_DIR" ]]; then
  mkdir -p "$TOKEN_DIR"
  chmod 700 "$TOKEN_DIR"
fi
if [[ -s "$TOKEN_FILE" ]]; then
  chmod 600 "$TOKEN_FILE"
  printf 'Existing token: %s\n' "$TOKEN_FILE"
  exit 0
fi
umask 077
python3 - <<'PY' > "$TOKEN_FILE"
import secrets
print(secrets.token_urlsafe(32))
PY
chmod 600 "$TOKEN_FILE"
printf 'Created token: %s\n' "$TOKEN_FILE"
