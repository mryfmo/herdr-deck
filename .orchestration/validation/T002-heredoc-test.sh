#!/bin/bash
set -euo pipefail
CONFIG=dummy

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
