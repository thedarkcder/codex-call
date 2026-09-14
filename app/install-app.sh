#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/build.sh"

DEST="/Applications/Codex Call.app"
if [ -w /Applications ]; then
  rm -rf "$DEST"
  cp -R "$SCRIPT_DIR/build/Codex Call.app" "$DEST"
else
  DEST="$HOME/Applications/Codex Call.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$SCRIPT_DIR/build/Codex Call.app" "$DEST"
fi

xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo
echo "Installed: $DEST"
echo "Open it from Finder (double-click), or run: open \"$DEST\""
