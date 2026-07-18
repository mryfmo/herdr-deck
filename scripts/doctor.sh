#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${HERDDECK_CONFIG:-$ROOT/gateway/config.json}"
FAIL=0

ok() { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAIL=1; }
check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then ok "$1: $($1 --version 2>/dev/null | head -1 || command -v "$1")"; else fail "$1 is missing"; fi
}

printf 'HerdDeck doctor\n\nRuntime\n'
[[ "$(uname -s)" == "Darwin" ]] && ok "macOS" || warn "Gateway is designed for a Mac Herdr host"
check_cmd node
check_cmd python3
check_cmd herdr
check_cmd tailscale
check_cmd claude
check_cmd codex

printf '\nConfiguration\n'
if [[ -f "$CONFIG" ]]; then
  ok "$CONFIG"
  if (cd "$ROOT" && CONFIG="$CONFIG" node --input-type=module - <<'NODE' >/dev/null 2>&1
import { loadConfig } from './gateway/src/config.mjs';
await loadConfig(process.env.CONFIG);
NODE
  )
  then
    ok "Gateway configuration validates"
  else
    fail "Gateway configuration is invalid"
    printf '      Run for details: cd %q && HERDDECK_CONFIG=%q node gateway/src/index.mjs\n' "$ROOT" "$CONFIG"
  fi
else
  fail "Missing $CONFIG (copy gateway/config.example.json)"
fi

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf 0)"
  [[ "$NODE_MAJOR" -ge 22 ]] && ok "Node.js major version is supported" || fail "Node.js 22 or later is required"
fi

if [[ -f "$CONFIG" ]]; then
  while IFS=$'\t' read -r label path; do
    if [[ -z "$path" ]]; then fail "$label missing from configuration"; continue; fi
    if [[ -e "$path" ]]; then ok "$label: $path"; else fail "$label missing: $path"; fi
  done < <(CONFIG="$CONFIG" python3 - <<'PY'
import json,os
with open(os.environ['CONFIG']) as f:c=json.load(f)
for key,label in [('herdrSocket','Herdr socket'),('tokenFile','Token'),('agmsgRoot','AGMSG root')]:
 value=c.get(key)
 print(label+'\t'+(os.path.expandvars(value) if isinstance(value,str) else ''))
PY
)
fi

printf '\nMosh terminal path\n'
if [[ -f "$CONFIG" ]]; then
  while IFS=$'\t' read -r key value; do
    case "$key" in
      enabled)
        MOSH_ENABLED="$value"
        if [[ "$value" == "true" ]]; then ok "Mosh is enabled in Gateway configuration"; else warn "Mosh is disabled; cellular Terminal will use HTTPS"; fi
        ;;
      server) MOSH_SERVER_PATH="$value" ;;
      herdr) MOSH_HERDR_PATH="$value" ;;
      advertise) MOSH_ADVERTISE_HOST="$value" ;;
      bind) MOSH_BIND_ADDRESS="$value" ;;
      ports) MOSH_PORT_RANGE="$value" ;;
    esac
  done < <(CONFIG="$CONFIG" python3 - <<'PYMOSH'
import json
import os

with open(os.environ['CONFIG']) as handle:
    config = json.load(handle)
mosh = config.get('mosh') or {}
print('enabled\t' + ('true' if mosh.get('enabled') else 'false'))
print('server\t' + os.path.expandvars(str(mosh.get('serverPath', 'mosh-server'))))
print('herdr\t' + os.path.expandvars(str(mosh.get('herdrPath', 'herdr'))))
print('advertise\t' + str(mosh.get('advertiseHost', '')))
print('bind\t' + str(mosh.get('bindAddress', '')))
print('ports\t' + str(mosh.get('portRange', '60000:61000')))
PYMOSH
  )

  if [[ "${MOSH_ENABLED:-false}" == "true" ]]; then
    if [[ -x "${MOSH_SERVER_PATH:-}" ]] || command -v "${MOSH_SERVER_PATH:-mosh-server}" >/dev/null 2>&1; then
      ok "mosh-server executable"
    else
      fail "Mosh is enabled but mosh-server is unavailable: ${MOSH_SERVER_PATH:-unset}"
    fi
    if [[ -x "${MOSH_HERDR_PATH:-}" ]] || command -v "${MOSH_HERDR_PATH:-herdr}" >/dev/null 2>&1; then
      ok "Herdr executable for Mosh attach"
    else
      fail "Mosh is enabled but Herdr is unavailable: ${MOSH_HERDR_PATH:-unset}"
    fi
    [[ -n "${MOSH_ADVERTISE_HOST:-}" ]] && ok "Advertise host: $MOSH_ADVERTISE_HOST" || fail "mosh.advertiseHost is empty"
    [[ -n "${MOSH_BIND_ADDRESS:-}" ]] && ok "UDP bind address: $MOSH_BIND_ADDRESS" || warn "mosh.bindAddress is empty; mosh-server will choose an interface"
    if [[ "${MOSH_PORT_RANGE:-}" =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]]; then
      ok "UDP port range: $MOSH_PORT_RANGE"
    else
      fail "Invalid Mosh UDP port range: ${MOSH_PORT_RANGE:-unset}"
    fi
    if command -v tailscale >/dev/null 2>&1; then
      TS_IPS="$(tailscale ip -4 2>/dev/null || true)"
      if [[ -n "$TS_IPS" ]]; then
        ok "Tailscale IPv4 is available for Mosh UDP"
        if [[ -n "${MOSH_BIND_ADDRESS:-}" ]] && ! grep -Fxq "$MOSH_BIND_ADDRESS" <<<"$TS_IPS"; then
          warn "mosh.bindAddress is not one of this Mac's current Tailscale IPv4 addresses"
        fi
      else
        warn "No Tailscale IPv4 address is currently available"
      fi
    fi
  fi
fi

printf '\nProtocol\n'
if command -v herdr >/dev/null 2>&1 && herdr api schema --json >/dev/null 2>&1; then ok "Herdr bundled API schema is readable"; else fail "herdr api schema --json failed"; fi
if command -v claude >/dev/null 2>&1; then
  claude --help 2>&1 | grep -q -- '--model' && ok "Claude Code exposes model selection" || warn "Claude --help did not list --model; run claude update"
  claude --help 2>&1 | grep -q -- '--effort' && ok "Claude Code exposes effort selection" || warn "Claude --help did not list --effort; current docs note that not every flag is listed"
fi
if command -v codex >/dev/null 2>&1; then
  codex --help 2>&1 | grep -q -- '--model' && ok "Codex exposes --model" || warn "Codex --help did not list --model"
  if codex debug models --bundled 2>/dev/null | grep -q 'gpt-5.6-sol'; then
    ok "Codex bundled catalog includes gpt-5.6-sol"
  else
    warn "Could not confirm gpt-5.6-sol in the bundled Codex catalog; update Codex (current catalog requires client 0.144.0+)"
  fi
fi

if command -v herdr >/dev/null 2>&1; then
  herdr integration status >/dev/null 2>&1 && ok "Herdr integration status is readable" || warn "Herdr integration status failed"
fi

printf '\nAGMSG\n'
if [[ -f "$CONFIG" ]]; then
  AGMSG_ROOT="$(CONFIG="$CONFIG" python3 - <<'PYAGMSG'
import json,os
with open(os.environ['CONFIG']) as f:c=json.load(f)
value=c.get('agmsgRoot')
print(os.path.expandvars(value) if isinstance(value,str) else '')
PYAGMSG
)"
  if [[ -n "$AGMSG_ROOT" ]]; then
    for script in api.sh send.sh join.sh delivery.sh; do
      [[ -x "$AGMSG_ROOT/scripts/$script" ]] && ok "$script" || fail "Missing executable $AGMSG_ROOT/scripts/$script"
    done
  else
    fail "AGMSG root missing from configuration"
  fi
fi

printf '\nGateway\n'
if [[ -f "$CONFIG" ]]; then
  PORT="$(CONFIG="$CONFIG" python3 - <<'PYPORT'
import json,os
with open(os.environ['CONFIG']) as f:c=json.load(f)
print(c.get('port',8787))
PYPORT
)"
  TOKEN_FILE="$(CONFIG="$CONFIG" python3 - <<'PYTOKEN'
import json,os
with open(os.environ['CONFIG']) as f:c=json.load(f)
value=c.get('tokenFile')
print(os.path.expandvars(value) if isinstance(value,str) else '')
PYTOKEN
)"
  if [[ -n "$TOKEN_FILE" && -s "$TOKEN_FILE" ]] && {
    { printf 'Authorization: Bearer '; tr -d '\r\n' < "$TOKEN_FILE"; printf '\n'; } |
      curl -fsS -H @- "http://127.0.0.1:$PORT/v1/health" >/dev/null 2>&1
  }; then
    ok "Gateway health endpoint"
  else
    warn "Gateway is not running or health check failed"
  fi
fi

printf '\nTailscale Serve\n'
if command -v tailscale >/dev/null 2>&1; then
  tailscale serve status >/dev/null 2>&1 && ok "Serve configuration readable" || warn "No Tailscale Serve configuration"
fi

printf '\n'
if [[ "$FAIL" -eq 0 ]]; then printf 'No blocking setup problem was found.\n'; else printf 'One or more blocking problems were found.\n'; fi
exit "$FAIL"
