#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache"
APP_DIR="$PROJECT_DIR/build/QRScanner.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache")"
cp "$BIN_DIR/QRScanner" "$APP_DIR/Contents/MacOS/QRScanner"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
print -r -- "$APP_DIR"
