#!/bin/bash
set -euo pipefail
export COPYFILE_DISABLE=1

detect_installer_identity() {
  security find-identity -v -p basic 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' \
    | head -1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/app/Info.plist")"
BUILD_DIR="$SCRIPT_DIR/build"
PAYLOAD="$BUILD_DIR/payload"
COMPONENT_PKG="$BUILD_DIR/CodexCall-component.pkg"
OUTPUT_DIR="$ROOT/dist"
OUTPUT_PKG="$OUTPUT_DIR/CodexCall-$VERSION.pkg"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-$(detect_installer_identity)}"

"$ROOT/app/build.sh"

rm -rf "$BUILD_DIR"
mkdir -p \
  "$PAYLOAD/Applications" \
  "$PAYLOAD/Library/Audio/Plug-Ins/HAL" \
  "$PAYLOAD/usr/local/bin" \
  "$PAYLOAD/usr/local/lib/codex-call" \
  "$OUTPUT_DIR"

ditto --norsrc "$ROOT/app/build/Codex Call.app" "$PAYLOAD/Applications/Codex Call.app"
ditto --norsrc "$ROOT/native/driver/build/CodexVirtualRX.driver" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/CodexVirtualRX.driver"
ditto --norsrc "$ROOT/native/driver/build/CodexVirtualTX.driver" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/CodexVirtualTX.driver"
ditto --norsrc "$ROOT/native/driver/build/CodexVirtualClock.driver" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/CodexVirtualClock.driver"
ditto --norsrc "$ROOT/native/helper/build/CodexCallHelper.app" "$PAYLOAD/usr/local/lib/codex-call/CodexCallHelper.app"
install -m 755 "$ROOT/native/helper/build/codex-call-helper" "$PAYLOAD/usr/local/bin/codex-call-helper"

codesign --verify --deep --strict "$PAYLOAD/Applications/Codex Call.app"
codesign --verify --strict "$PAYLOAD/usr/local/lib/codex-call/CodexCallHelper.app"

pkgbuild \
  --root "$PAYLOAD" \
  --scripts "$SCRIPT_DIR/scripts" \
  --identifier com.codexcall.pkg \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$COMPONENT_PKG"

rm -f "$OUTPUT_PKG"
if [ -n "$INSTALLER_SIGN_IDENTITY" ]; then
  echo "Installer signing identity: $INSTALLER_SIGN_IDENTITY"
  productbuild --package "$COMPONENT_PKG" --sign "$INSTALLER_SIGN_IDENTITY" "$OUTPUT_PKG"
  pkgutil --check-signature "$OUTPUT_PKG"
elif [ "${REQUIRE_SIGNING:-0}" = "1" ]; then
  echo "error: a Developer ID Installer identity is required" >&2
  exit 1
else
  echo "warning: no Developer ID Installer identity; producing a local unsigned package" >&2
  productbuild --package "$COMPONENT_PKG" "$OUTPUT_PKG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$OUTPUT_PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUTPUT_PKG"
  xcrun stapler validate "$OUTPUT_PKG"
fi

shasum -a 256 "$OUTPUT_PKG" > "$OUTPUT_PKG.sha256"
echo "Built: $OUTPUT_PKG"
