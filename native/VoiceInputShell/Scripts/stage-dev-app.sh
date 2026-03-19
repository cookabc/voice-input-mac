#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SHELL_DIR="$ROOT_DIR/native/VoiceInputShell"

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

BUILD_DIR="$SHELL_DIR/.build/arm64-apple-macosx/$PROFILE"
APP_DIR="$SHELL_DIR/.stage/VoiceInputShell.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

COLI_PATH="${VOICE_INPUT_COLI_PATH:-$(command -v coli || true)}"

if [[ -z "$COLI_PATH" || ! -f "$COLI_PATH" ]]; then
  echo "coli not found. Set VOICE_INPUT_COLI_PATH or install @marswave/coli." >&2
  exit 1
fi

pushd "$SHELL_DIR" >/dev/null
# shellcheck disable=SC2086
swift build $SWIFT_FLAGS
popd >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$HELPERS_DIR"

cp "$BUILD_DIR/VoiceInputShell" "$MACOS_DIR/VoiceInputShell"
cp "$COLI_PATH" "$HELPERS_DIR/coli"
chmod +x "$MACOS_DIR/VoiceInputShell" "$HELPERS_DIR/coli"

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
  <key>NSMicrophoneUsageDescription</key>
  <string>Voice Input needs microphone access to record audio for transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Voice Input uses on-device speech recognition to show a live preview while you dictate.</string>
</dict>
</plist>
PLIST

echo "Staged app bundle at: $APP_DIR"
echo "Launch with: open '$APP_DIR'"