#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/usr/local/lib/codex-call"
BIN_DIR="/usr/local/bin"
PLIST="$HOME/Library/LaunchAgents/com.codexcall.router.plist"

echo "== Stopping router agent =="
launchctl bootout "gui/$(id -u)/com.codexcall.router" 2>/dev/null || true
rm -f "$PLIST"

echo
echo "== Restoring default audio devices =="
if [ -x "$BIN_DIR/codex-call-helper" ]; then
  "$BIN_DIR/codex-call-helper" restore || true
fi

echo
echo "== Removing virtual audio driver =="
sudo "$ROOT/native/driver/uninstall.sh"

echo
echo "== Removing helper =="
sudo rm -rf "$INSTALL_DIR"
sudo rm -f "$BIN_DIR/codex-call-helper"

echo
echo "Uninstall complete."
