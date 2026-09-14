#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/usr/local/lib/codex-call"
BIN_DIR="/usr/local/bin"
HELPER_APP="$INSTALL_DIR/CodexCallHelper.app/Contents/MacOS/codex-call-helper"
PLIST="$HOME/Library/LaunchAgents/com.codexcall.router.plist"

echo "== Building =="
"$ROOT/native/driver/build.sh"
"$ROOT/native/helper/build.sh"

echo
echo "== Installing helper =="
sudo mkdir -p "$INSTALL_DIR" "$BIN_DIR"
sudo rm -rf "$INSTALL_DIR/CodexCallHelper.app"
sudo cp -R "$ROOT/native/helper/build/CodexCallHelper.app" "$INSTALL_DIR/"
sudo cp "$ROOT/native/helper/build/codex-call-helper" "$BIN_DIR/codex-call-helper"

echo
echo "== Installing virtual audio driver =="
sudo "$ROOT/native/driver/install.sh"

echo
echo "== Configuring routing =="
"$BIN_DIR/codex-call-helper" setup

echo
echo "== Installing router agent =="
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__HELPER__|$HELPER_APP|" \
  "$ROOT/scripts/launchd/com.codexcall.router.plist.template" > "$PLIST"
launchctl bootout "gui/$(id -u)/com.codexcall.router" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" || launchctl load "$PLIST"

echo
echo "== Diagnostics =="
sleep 2
"$BIN_DIR/codex-call-helper" doctor || true

echo
echo "Install complete. The first run may prompt for microphone access for Codex Call Helper."
