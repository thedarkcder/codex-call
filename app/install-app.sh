#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Info.plist")"

"$ROOT/installer/build-pkg.sh"
open "$ROOT/dist/CodexCall-$VERSION.pkg"
