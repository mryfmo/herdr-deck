#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${HERDDECK_CONFIG:-$ROOT/gateway/config.json}"
command -v tailscale >/dev/null 2>&1 || { echo "tailscale CLI is required" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG" >&2; exit 1; }
PORT="$(CONFIG="$CONFIG" python3 - <<'PY'
import json,os
with open(os.environ['CONFIG']) as f: print(json.load(f).get('port',8787))
PY
)"
# Serve is tailnet-only. Do not replace this with `tailscale funnel`.
tailscale serve --bg "http://127.0.0.1:$PORT"
printf '\nHerdDeck is now available only inside your tailnet.\n'
tailscale serve status
