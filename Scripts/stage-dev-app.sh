#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

RELEASE=false
for arg in "$@"; do
  [[ "$arg" == "--release" ]] && RELEASE=true
done

if $RELEASE; then
  PROFILE=release
  SWIFT_FLAGS="-c release"
else
  PROFILE=debug
  SWIFT_FLAGS=""
fi

BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$PROFILE"
APP_DIR="$ROOT_DIR/.stage/Murmur.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

COLI_PATH="${VOICE_INPUT_COLI_PATH:-$(command -v coli || true)}"

if [[ -z "$COLI_PATH" || ! -f "$COLI_PATH" ]]; then
  echo "coli not found. Set VOICE_INPUT_COLI_PATH or install @marswave/coli." >&2
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null
# shellcheck disable=SC2086
swift build $SWIFT_FLAGS
popd >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR"

cp "$BUILD_DIR/Murmur" "$MACOS_DIR/Murmur"

# Resolve coli's real path (through symlinks) to find the package root.
COLI_REAL="$(realpath "$COLI_PATH")"
# cli.js lives at <pkg>/distribution/cli.js; two dirname calls reach the package root.
COLI_PKG_DIR="$(dirname "$(dirname "$COLI_REAL")")"

# Copy node binary from the same bin directory as coli (handles nvm, homebrew, etc.)
NODE_BIN="$(dirname "$COLI_PATH")/node"
[[ ! -f "$NODE_BIN" ]] && NODE_BIN="$(command -v node)"

cp -R "$COLI_PKG_DIR" "$HELPERS_DIR/coli_pkg"
cp "$NODE_BIN" "$HELPERS_DIR/node"

# Wrapper script that invokes coli in its own package context (so node_modules resolve).
cat > "$HELPERS_DIR/coli" <<'COLI_SH'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/node" "$DIR/coli_pkg/distribution/cli.js" "$@"
COLI_SH

chmod +x "$MACOS_DIR/Murmur" "$HELPERS_DIR/coli" "$HELPERS_DIR/node"

cat >"$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Murmur</string>
  <key>CFBundleIdentifier</key>
  <string>com.advance.murmur.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Murmur</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Murmur needs microphone access to record audio for transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Murmur uses on-device speech recognition to show a live preview while you dictate.</string>
</dict>
</plist>
PLIST

echo "Staged app bundle at: $APP_DIR"
echo "Launch with: open '$APP_DIR'"