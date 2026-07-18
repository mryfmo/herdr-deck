#!/usr/bin/env bash

# @file gateway/scripts/agmsg-api.sh
# @brief Read AGMSG teams, members, and messages as JSON Lines.
# @description
#   Reads team configuration and the message database without modifying either.
# @arg $1 action Must be `get`.
# @arg $2 resource Must be `teams`.
# @option --limit <count> Maximum messages to return.
# @option --agent <name> Include messages sent from or to this agent.
# @option --before-id <id> Include messages with a smaller numeric ID.
# @example
#   AGMSG_ROOT="$HOME/.agents/skills/agmsg" agmsg-api.sh get teams
# @example
#   AGMSG_ROOT="$HOME/.agents/skills/agmsg" agmsg-api.sh get teams my-team messages --limit 50

set -euo pipefail

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

ROOT="${AGMSG_ROOT:?AGMSG_ROOT is required}"
[[ "${1:-}" == "get" && "${2:-}" == "teams" ]] || die "Usage: agmsg-api.sh get teams [<team> members|messages]"

if [[ "$#" -eq 2 ]]; then
  python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
names = []
for config_path in root.glob("teams/*/config.json"):
    config = json.loads(config_path.read_text())
    names.append(config.get("name") or config_path.parent.name)
for name in sorted(names):
    print(json.dumps(name, separators=(",", ":")))
PY
  exit
fi

TEAM="${3:-}"
RESOURCE="${4:-}"
[[ "$TEAM" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "Invalid team name"

if [[ "$RESOURCE" == "members" && "$#" -eq 4 ]]; then
  CONFIG="$ROOT/teams/$TEAM/config.json"
  [[ -f "$CONFIG" ]] || die "Team not found: $TEAM"
  python3 - "$CONFIG" <<'PY'
import json
import pathlib
import sys

config = json.loads(pathlib.Path(sys.argv[1]).read_text())
for name, agent in sorted(config.get("agents", {}).items()):
    registrations = agent.get("registrations")
    registration = registrations[-1] if registrations else agent
    print(json.dumps({
        "name": name,
        "type": registration.get("type"),
        "project": registration.get("project"),
    }, separators=(",", ":")))
PY
  exit
fi

[[ "$RESOURCE" == "messages" ]] || die "Usage: agmsg-api.sh get teams <team> members|messages"
shift 4
LIMIT=50
AGENT=""
BEFORE_ID=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --limit)
      [[ "$#" -ge 2 ]] || die "--limit requires a value"
      LIMIT="$2"
      shift 2
      ;;
    --agent)
      [[ "$#" -ge 2 ]] || die "--agent requires a value"
      AGENT="$2"
      shift 2
      ;;
    --before-id)
      [[ "$#" -ge 2 ]] || die "--before-id requires a value"
      BEFORE_ID="$2"
      shift 2
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "Invalid --limit"
[[ -z "$AGENT" || "$AGENT" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "Invalid --agent"
[[ -z "$BEFORE_ID" || "$BEFORE_ID" =~ ^[1-9][0-9]*$ ]] || die "Invalid --before-id"

DB="${AGMSG_STORAGE_PATH:-$ROOT/db}/messages.db"
[[ -f "$DB" ]] || die "AGMSG database not found: $DB"
DB_URI="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri() + "?mode=ro")' "$DB")"
WHERE="team = '$TEAM'"
[[ -z "$AGENT" ]] || WHERE="$WHERE AND (to_agent = '$AGENT' OR from_agent = '$AGENT')"
[[ -z "$BEFORE_ID" ]] || WHERE="$WHERE AND id < $BEFORE_ID"

sqlite3 -readonly -json "$DB_URI" "
  SELECT 'message' AS type, id, team, from_agent AS 'from', to_agent AS 'to',
         body, created_at AS at
  FROM (
    SELECT id, team, from_agent, to_agent, body, created_at
    FROM messages
    WHERE $WHERE
    ORDER BY id DESC
    LIMIT $LIMIT
  )
  ORDER BY id ASC;
" | python3 -c '
import json
import sys

text = sys.stdin.read().strip()
for row in json.loads(text or "[]"):
    print(json.dumps(row, separators=(",", ":")))
'
