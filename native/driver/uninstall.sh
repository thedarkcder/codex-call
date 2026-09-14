#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This uninstaller must run as root: sudo $0" >&2
  exit 1
fi

HAL_DIR="/Library/Audio/Plug-Ins/HAL"

rm -rf "$HAL_DIR/CodexVirtualRX.driver" "$HAL_DIR/CodexVirtualTX.driver" "$HAL_DIR/CodexVirtualClock.driver"

echo "Restarting coreaudiod..."
launchctl kickstart -k system/com.apple.audio.coreaudiod || killall coreaudiod || true
sleep 2

echo "Removed Codex Virtual RX/TX drivers."
