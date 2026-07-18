#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/gateway/config.json"

[[ "$(uname -s)" == "Darwin" ]] || { echo "Run this script on the Mac that hosts Herdr." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Install Node.js 22 or later." >&2; exit 1; }
NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
[[ "$NODE_MAJOR" -ge 22 ]] || { echo "Node.js 22+ is required (found $(node --version))." >&2; exit 1; }

if [[ ! -f "$CONFIG" ]]; then
  cp "$ROOT/gateway/config.example.json" "$CONFIG"
  printf 'Created %s\n' "$CONFIG"
fi
"$ROOT/scripts/generate-token.sh"

cat <<MSG

Before launch, verify these values in:
  $CONFIG

1. projectRoots contains every repository parent directory you intend to control.
2. herdrSocket points to the active Herdr session socket.
3. agmsgRoot points to the installed agmsg skill directory.
4. profile model names match \`claude\` and \`codex\` on this Mac.
5. To use Mosh on cellular, run scripts/bootstrap-mosh-mac.sh and enable the mosh block.

The defaults deliberately keep Codex in workspace-write sandbox mode and never add dangerous approval bypass flags.
MSG

"$ROOT/scripts/doctor.sh" || true
printf '\nTo continue:\n'
printf '  %s/scripts/install-launch-agent.sh\n' "$ROOT"
printf '  %s/scripts/tailscale-serve.sh\n' "$ROOT"
printf '  %s/scripts/pairing-qr.sh\n' "$ROOT"
printf '\nOptional cellular Terminal path:\n'
printf '  %s/scripts/bootstrap-mosh-mac.sh\n' "$ROOT"
