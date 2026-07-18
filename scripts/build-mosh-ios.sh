#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Vendor/MoshBinaryPackage"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Mosh XCFramework preparation requires macOS and Xcode." >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift/Xcode command-line tools are required." >&2
  exit 1
fi

cat <<'MSG'
Resolving the pinned Blink Mosh 1.4.0+blink-18.4.5 and Protobuf 3.21.1
XCFrameworks declared in Vendor/MoshBinaryPackage/Package.swift.
MSG

swift package resolve --package-path "$PACKAGE"
swift package dump-package --package-path "$PACKAGE" >/dev/null

cat <<MSG
Mosh binary package resolved successfully.
Generate the full project with:
  $ROOT/scripts/generate-xcode-project.sh

Distribution note:
  The Mosh component is GPLv3. Review THIRD_PARTY_NOTICES.md and the project
  license before distributing a linked application binary.
MSG
