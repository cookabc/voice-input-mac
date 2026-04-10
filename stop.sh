#!/bin/bash
# stop.sh — Kill running Murmur instance

APP_NAME="Murmur"

pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null \
  && echo "✓ ${APP_NAME} stopped" \
  || echo "${APP_NAME} not running"
