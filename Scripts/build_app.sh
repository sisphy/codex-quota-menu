#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ChatGPTQuotaMenu"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  swift build --disable-sandbox \
  --cache-path /private/tmp/swiftpm-cache \
  --config-path /private/tmp/swiftpm-config \
  --security-path /private/tmp/swiftpm-security \
  --manifest-cache local

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
  find "$APP_DIR/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle" -maxdepth 1 -type f ! -name "Info.plist" ! -name "casio-skin*.png" -delete
  cp "$RESOURCE_BUNDLE"/casio-skin*.png "$APP_DIR/Contents/MacOS/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ChatGPTQuotaMenu</string>
  <key>CFBundleIdentifier</key>
  <string>local.chatgpt.quota.menu</string>
  <key>CFBundleName</key>
  <string>ChatGPTQuotaMenu</string>
  <key>CFBundleDisplayName</key>
  <string>ChatGPT 额度</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
  </dict>
</dict>
</plist>
PLIST

echo "$APP_DIR"
