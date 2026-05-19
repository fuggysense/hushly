#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Hushly.app"
BUILD_DIR="$ROOT/dist/macos"
APP_DIR="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -parse-as-library \
  "$ROOT/desktop/macos/HushlyLite.swift" \
  -framework Cocoa \
  -framework WebKit \
  -Osize \
  -o "$MACOS_DIR/HushlyLite"

cp "$ROOT/desktop/macos/Info.plist" "$APP_DIR/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

du -sh "$APP_DIR"
echo "$APP_DIR"
