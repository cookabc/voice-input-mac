#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SHELL_DIR="$ROOT_DIR/native/VoiceInputShell"
CORE_DIR="$ROOT_DIR"

RELEASE=false
for arg in "$@"; do
  [[ "$arg" == "--release" ]] && RELEASE=true
done

if $RELEASE; then
  PROFILE=release
  CARGO_FLAGS="--release"
  SWIFT_FLAGS="-c release"
else
  PROFILE=debug
  CARGO_FLAGS=""
  SWIFT_FLAGS=""
fi

BUILD_DIR="$SHELL_DIR/.build/arm64-apple-macosx/$PROFILE"
APP_DIR="$SHELL_DIR/.stage/VoiceInputShell.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

FFMPEG_PATH="${VOICE_INPUT_FFMPEG_PATH:-$(command -v ffmpeg || true)}"
COLI_PATH="${VOICE_INPUT_COLI_PATH:-$(command -v coli || true)}"

if [[ -z "$FFMPEG_PATH" || ! -f "$FFMPEG_PATH" ]]; then
  echo "ffmpeg not found. Set VOICE_INPUT_FFMPEG_PATH or install ffmpeg." >&2
  exit 1
fi

if [[ -z "$COLI_PATH" || ! -f "$COLI_PATH" ]]; then
  echo "coli not found. Set VOICE_INPUT_COLI_PATH or install @marswave/coli." >&2
  exit 1
fi

pushd "$CORE_DIR" >/dev/null
# shellcheck disable=SC2086
cargo build $CARGO_FLAGS
popd >/dev/null

pushd "$SHELL_DIR" >/dev/null
# shellcheck disable=SC2086
swift build $SWIFT_FLAGS
popd >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$HELPERS_DIR"

cp "$BUILD_DIR/VoiceInputShell" "$MACOS_DIR/VoiceInputShell"
cp "$CORE_DIR/target/$PROFILE/libvoice_input_core.dylib" "$FRAMEWORKS_DIR/libvoice_input_core.dylib"
cp "$FFMPEG_PATH" "$HELPERS_DIR/ffmpeg"
cp "$COLI_PATH" "$HELPERS_DIR/coli"
chmod +x "$MACOS_DIR/VoiceInputShell" "$HELPERS_DIR/ffmpeg" "$HELPERS_DIR/coli"

cat >"$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VoiceInputShell</string>
  <key>CFBundleIdentifier</key>
  <string>com.advance.voiceinputshell.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>VoiceInputShell</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "Staged app bundle at: $APP_DIR"
echo "Launch with: open '$APP_DIR'"