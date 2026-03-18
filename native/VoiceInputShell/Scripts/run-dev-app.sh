#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../.stage/VoiceInputShell.app"

"$SCRIPT_DIR/stage-dev-app.sh"

pkill -f 'VoiceInputShell.app/Contents/MacOS/VoiceInputShell' >/dev/null 2>&1 || true
pkill -f 'arm64-apple-macosx/debug/VoiceInputShell' >/dev/null 2>&1 || true
sleep 0.4   # give macOS time to reclaim the process slot before relaunching

open "$APP_DIR"

echo "Launched staged app: $APP_DIR"