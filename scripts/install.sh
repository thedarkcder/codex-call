#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/app/Info.plist")"

"$ROOT/installer/build-pkg.sh"
open "$ROOT/dist/CodexCall-$VERSION.pkg"

echo "Installer opened. macOS Installer owns the authorization and installation flow."
