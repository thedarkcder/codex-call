#!/bin/bash
set -euo pipefail

detect_identity() {
  local id
  id=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
  if [ -z "$id" ]; then
    id=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
  fi
  printf '%s' "$id"
}

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-$(detect_identity)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP="$BUILD_DIR/Codex Call.app"

echo "== Building helper =="
"$ROOT/native/helper/build.sh"

echo "== Building driver =="
"$ROOT/native/driver/build.sh"

echo "== Building app =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/driver"

swiftc -O \
  -o "$APP/Contents/MacOS/CodexCall" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -framework AppKit -framework AVFoundation -framework Foundation

cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/native/helper/build/codex-call-helper" "$APP/Contents/Resources/codex-call-helper"
chmod 755 "$APP/Contents/Resources/codex-call-helper"
cp -R "$ROOT/native/driver/build/CodexVirtualRX.driver" "$APP/Contents/Resources/driver/"
cp -R "$ROOT/native/driver/build/CodexVirtualTX.driver" "$APP/Contents/Resources/driver/"
cp -R "$ROOT/plugins/codex-call" "$APP/Contents/Resources/plugin"

if [ -n "$CODESIGN_IDENTITY" ]; then
  echo "Signing identity: $CODESIGN_IDENTITY"
  codesign --force --deep --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$SCRIPT_DIR/CodexCall.entitlements" "$APP"
  codesign --verify --verbose=2 "$APP"
else
  echo "warning: no signing identity; app is unsigned" >&2
fi

echo
echo "Built: $APP"
