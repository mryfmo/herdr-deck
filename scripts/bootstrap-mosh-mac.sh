#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This helper targets macOS." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install mosh. Install it first, then rerun." >&2
  exit 1
fi

if ! command -v mosh-server >/dev/null 2>&1; then
  brew install mosh
fi

MOSH_SERVER="$(command -v mosh-server)"
HERDR="$(command -v herdr || true)"
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"

echo "mosh-server: $MOSH_SERVER"
echo "herdr:       ${HERDR:-not found}"
echo "Tailscale:   ${TAILSCALE_IP:-not connected}"
echo
echo "Set gateway/config.json mosh fields similar to:"
cat <<JSON
"mosh": {
  "enabled": true,
  "serverPath": "$MOSH_SERVER",
  "herdrPath": "${HERDR:-/opt/homebrew/bin/herdr}",
  "advertiseHost": "${TAILSCALE_IP:-macbook.example-tailnet.ts.net}",
  "bindAddress": "${TAILSCALE_IP:-100.64.0.10}",
  "portRange": "60000:61000",
  "predictionMode": "adaptive",
  "networkTimeoutSeconds": 604800,
  "takeover": true
}
JSON
echo
echo "No public router port-forward is required. Permit UDP 60000-61000 only inside your tailnet ACL/firewall."