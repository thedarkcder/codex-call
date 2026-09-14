#!/bin/bash
set -euo pipefail

BLACKHOLE_REPO="${BLACKHOLE_REPO:-https://github.com/ExistentialAudio/BlackHole.git}"
BLACKHOLE_COMMIT="${BLACKHOLE_COMMIT:-ffcb74433fbcf8c8ca5c736677c1a4864384dc09}"

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
CACHE_DIR="$SCRIPT_DIR/.cache"
SRC_DIR="$CACHE_DIR/BlackHole"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$CACHE_DIR" "$BUILD_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  git clone "$BLACKHOLE_REPO" "$SRC_DIR"
fi
git -C "$SRC_DIR" fetch --depth 1 origin "$BLACKHOLE_COMMIT" 2>/dev/null || true
git -C "$SRC_DIR" checkout --quiet "$BLACKHOLE_COMMIT"

SOURCE="$SRC_DIR/BlackHole/BlackHole.c"
if [ ! -f "$SOURCE" ]; then
  echo "BlackHole source not found at $SOURCE" >&2
  exit 1
fi

build_variant() {
  local variant="$1"
  local name="$2"
  local bundle_id="$3"
  shift 3
  local bundle="$BUILD_DIR/${name// /}.driver"
  local executable="${name// /}"

  rm -rf "$bundle"
  mkdir -p "$bundle/Contents/MacOS"

  clang -w -bundle -arch arm64 -mmacosx-version-min=12.3 -O2 \
    -o "$bundle/Contents/MacOS/$executable" "$SOURCE" \
    -DkDriver_Name="\"$name\"" \
    -DkPlugIn_BundleID="\"$bundle_id\"" \
    -DkDevice_Name="\"$name\"" \
    -DkDevice2_Name="\"$name Mirror\"" \
    -DkHas_Driver_Name_Format=false \
    -DkNumber_Of_Channels=2 \
    "$@" \
    -framework Accelerate -framework CoreAudio -framework CoreFoundation

  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>$executable</string>
	<key>CFBundleIconFile</key>
	<string></string>
	<key>CFBundleIdentifier</key>
	<string>$bundle_id</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFPlugInFactories</key>
	<dict>
		<key>e395c745-4eea-4d94-bb92-46224221047c</key>
		<string>BlackHole_Create</string>
	</dict>
	<key>CFPlugInTypes</key>
	<dict>
		<key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
		<array>
			<string>e395c745-4eea-4d94-bb92-46224221047c</string>
		</array>
	</dict>
</dict>
</plist>
PLIST

  if [ -n "$CODESIGN_IDENTITY" ]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$bundle"
    codesign --verify --verbose=2 "$bundle"
  else
    echo "warning: CODESIGN_IDENTITY not set; driver is unsigned" >&2
  fi

  echo "built $bundle"
}

build_variant rx "Codex Virtual RX" "com.codexcall.driver.rx"
build_variant tx "Codex Virtual TX" "com.codexcall.driver.tx"
build_variant clock "Codex Virtual Clock" "com.codexcall.driver.clock" \
  -DkDevice_HasInput=false -DkCanBeDefaultDevice=false -DkCanBeDefaultSystemDevice=false

echo
echo "Driver bundles written to $BUILD_DIR"
ls -1 "$BUILD_DIR"
