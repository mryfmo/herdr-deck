#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${HERDDECK_CONFIG:-$ROOT/gateway/config.json}"
NODE="$(command -v node || true)"
PLIST="$HOME/Library/LaunchAgents/com.herddeck.gateway.plist"
LOG_DIR="$HOME/Library/Logs/HerdDeck"

[[ "$(uname -s)" == "Darwin" ]] || { echo "launchd installation requires macOS" >&2; exit 1; }
[[ -n "$NODE" ]] || { echo "node 22+ is required" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG; copy gateway/config.example.json first" >&2; exit 1; }
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

ROOT="$ROOT" CONFIG="$CONFIG" NODE="$NODE" PLIST="$PLIST" LOG_DIR="$LOG_DIR" python3 - <<'PY'
import os, plistlib
root=os.environ['ROOT']; config=os.environ['CONFIG']; node=os.environ['NODE']
plist_path=os.environ['PLIST']; log=os.environ['LOG_DIR']
path=os.environ.get('PATH','/usr/bin:/bin:/usr/sbin:/sbin')
extra='/opt/homebrew/bin:/usr/local/bin'
value={
 'Label':'com.herddeck.gateway',
 'ProgramArguments':[node, os.path.join(root,'gateway','src','index.mjs')],
 'WorkingDirectory':os.path.join(root,'gateway'),
 'EnvironmentVariables':{
   'HERDDECK_CONFIG':config,
   'PATH':f'{extra}:{path}',
   'HOME':os.path.expanduser('~'),
 },
 'RunAtLoad':True,
 'KeepAlive':True,
 'ThrottleInterval':5,
 'ProcessType':'Background',
 'StandardOutPath':os.path.join(log,'gateway.log'),
 'StandardErrorPath':os.path.join(log,'gateway-error.log'),
}
with open(plist_path,'wb') as f:
    plistlib.dump(value,f,fmt=plistlib.FMT_XML,sort_keys=False)
os.chmod(plist_path,0o600)
PY

launchctl bootout "gui/$UID/com.herddeck.gateway" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/com.herddeck.gateway"
launchctl kickstart -k "gui/$UID/com.herddeck.gateway"
printf 'Installed and started %s\n' "$PLIST"
printf 'Logs: %s\n' "$LOG_DIR"
