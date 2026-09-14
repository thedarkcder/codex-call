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
if [ -n "$CODESIGN_IDENTITY" ]; then
  echo "Signing identity: $CODESIGN_IDENTITY"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$BUILD_DIR"

swiftc -O \
  -target arm64-apple-macosx14.2 \
  -o "$BUILD_DIR/codex-call-helper" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework Foundation \
  -framework AVFoundation \
  -framework AppKit

APP="$BUILD_DIR/CodexCallHelper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

if [ -n "$CODESIGN_IDENTITY" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$SCRIPT_DIR/CodexCallHelper.entitlements" "$BUILD_DIR/codex-call-helper"
fi

cp "$BUILD_DIR/codex-call-helper" "$APP/Contents/MacOS/codex-call-helper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>codex-call-helper</string>
	<key>CFBundleIdentifier</key>
	<string>com.codexcall.helper</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Codex Call Helper</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.9</string>
	<key>CFBundleVersion</key>
	<string>9</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Codex Call routes your microphone audio into Codex for phone calls.</string>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Codex Call captures the call app's audio so Codex can hear the person on the phone.</string>
</dict>
</plist>
PLIST

if [ -n "$CODESIGN_IDENTITY" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$SCRIPT_DIR/CodexCallHelper.entitlements" "$APP"
  codesign --verify --verbose=2 "$APP"
  codesign -d --entitlements - "$APP" 2>/dev/null | rg -q "audio-input" \
    && echo "audio-input entitlement: present"
else
  echo "warning: CODESIGN_IDENTITY not set; helper app is unsigned" >&2
fi

echo "built $BUILD_DIR/codex-call-helper"
echo "built $APP"
