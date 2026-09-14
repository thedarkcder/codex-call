#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This installer must run as root: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"

for name in CodexVirtualRX CodexVirtualTX CodexVirtualClock; do
  if [ ! -d "$BUILD_DIR/$name.driver" ]; then
    echo "Missing $BUILD_DIR/$name.driver; run build.sh first." >&2
    exit 1
  fi
done

mkdir -p "$HAL_DIR"
rm -rf "$HAL_DIR/CodexVirtualRX.driver" "$HAL_DIR/CodexVirtualTX.driver" "$HAL_DIR/CodexVirtualClock.driver"
cp -R "$BUILD_DIR/CodexVirtualRX.driver" "$HAL_DIR/"
cp -R "$BUILD_DIR/CodexVirtualTX.driver" "$HAL_DIR/"
cp -R "$BUILD_DIR/CodexVirtualClock.driver" "$HAL_DIR/"
chown -R root:wheel "$HAL_DIR/CodexVirtualRX.driver" "$HAL_DIR/CodexVirtualTX.driver" "$HAL_DIR/CodexVirtualClock.driver"

echo "Restarting coreaudiod..."
launchctl kickstart -k system/com.apple.audio.coreaudiod || killall coreaudiod || true
sleep 3

echo "Installed:"
ls -1 "$HAL_DIR" | grep CodexVirtual || true
