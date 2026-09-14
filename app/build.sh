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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  -target arm64-apple-macosx14.2 \
  -o "$APP/Contents/MacOS/CodexCall" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -framework AppKit -framework AVFoundation -framework Foundation

cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/native/helper/build/CodexCallHelper.app" "$APP/Contents/Resources/"
cp -R "$ROOT/plugins/codex-call" "$APP/Contents/Resources/plugin"
rm -rf "$APP/Contents/Resources/plugin/server/test"

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
