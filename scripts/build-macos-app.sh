#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Hushly.app"
BUILD_DIR="$ROOT/dist/macos"
APP_DIR="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SPARKLE_VERSION="2.9.2"
SPARKLE_CACHE="$ROOT/.cache/sparkle"
SPARKLE_ARCHIVE="$SPARKLE_CACHE/Sparkle-$SPARKLE_VERSION.tar.xz"
SPARKLE_FRAMEWORK="$SPARKLE_CACHE/Sparkle.framework"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$SPARKLE_CACHE"
  if [[ ! -f "$SPARKLE_ARCHIVE" ]]; then
    curl -L --fail --silent --show-error "$SPARKLE_URL" -o "$SPARKLE_ARCHIVE"
  fi
  tar -xf "$SPARKLE_ARCHIVE" -C "$SPARKLE_CACHE"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

swiftc \
  -parse-as-library \
  -F "$SPARKLE_CACHE" \
  "$ROOT/desktop/macos/HushlyLite.swift" \
  -framework Cocoa \
  -framework ApplicationServices \
  -framework AVFoundation \
  -framework AudioToolbox \
  -framework Sparkle \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  -Osize \
  -o "$MACOS_DIR/HushlyLite"

cp "$ROOT/desktop/macos/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/desktop/macos/Assets/tablet-glow.png" "$RESOURCES_DIR/tablet-glow.png"
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

du -sh "$APP_DIR"
echo "$APP_DIR"
