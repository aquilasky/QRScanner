#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"
BUILD_ARGS=(-c release --arch arm64 --arch x86_64 --disable-sandbox
    --scratch-path "$PROJECT_DIR/.build/distribution" --cache-path "$PROJECT_DIR/.build/cache")
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
mkdir -p "$PROJECT_DIR/dist"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
PAYLOAD_DIR="$STAGE_DIR/payload"
APP_DIR="$PAYLOAD_DIR/QRScanner.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/QRScanner" "$APP_DIR/Contents/MacOS/QRScanner"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign "${QRSCANNER_SIGN_IDENTITY:--}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ARCHS="$(lipo "$APP_DIR/Contents/MacOS/QRScanner" -archs)"
if [[ "$ARCHS" != 'x86_64 arm64' && "$ARCHS" != 'arm64 x86_64' ]]; then
    print -u2 "Expected arm64 + x86_64, got: $ARCHS"
    exit 1
fi
ln -s /Applications "$PAYLOAD_DIR/Applications"
cp scripts/INSTALL.txt "$PAYLOAD_DIR/安装说明.txt"
DMG_NAME="QRScanner-${VERSION}-universal.dmg"
# Build to a temporary path; preserve an existing release artifact if creation fails.
hdiutil create -volname "QRScanner $VERSION" -srcfolder "$PAYLOAD_DIR" -format UDZO "$STAGE_DIR/package.dmg"
hdiutil verify "$STAGE_DIR/package.dmg"
mv "$STAGE_DIR/package.dmg" "$PROJECT_DIR/dist/$DMG_NAME"
(cd "$PROJECT_DIR/dist" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
print -r -- "$PROJECT_DIR/dist/$DMG_NAME"
