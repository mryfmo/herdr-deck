#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPEC="project.yml"
PROJECT_NAME="HerdDeck"
case "${1:-}" in
  ""|--with-mosh)
    ;;
  --lite)
    SPEC="project-lite.yml"
    PROJECT_NAME="HerdDeckLite"
    ;;
  *)
    echo "Usage: $0 [--with-mosh|--lite]" >&2
    exit 2
    ;;
esac

if ! command -v xcodegen >/dev/null 2>&1; then
  cat >&2 <<'MSG'
XcodeGen is required to materialize the Xcode project.
Install it on the Mac with:
  brew install xcodegen
Then rerun:
  ./scripts/generate-xcode-project.sh
MSG
  exit 1
fi

xcodegen generate --spec "$SPEC"
printf 'Generated %s/%s.xcodeproj from %s\n' "$ROOT" "$PROJECT_NAME" "$SPEC"
if [ "$SPEC" = "project.yml" ]; then
  echo "Xcode will resolve the pinned official Mosh and Protobuf XCFrameworks through Swift Package Manager."
  echo "This build links GPLv3 Mosh; review THIRD_PARTY_NOTICES.md before distribution."
fi
