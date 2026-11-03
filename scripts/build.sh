#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache"
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PROJECT_DIR/.build/cache")"
APP_DIR="$PROJECT_DIR/build/QRScanner.app"
SIGN_IDENTITY="${QRSCANNER_SIGN_IDENTITY:--}"
# Signing a staging bundle must not mutate a running application's on-disk identity.
mkdir -p "$PROJECT_DIR/build"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/build/stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_APP="$STAGE_DIR/QRScanner.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/QRScanner" "$STAGED_APP/Contents/MacOS/QRScanner"
cp scripts/Info.plist "$STAGED_APP/Contents/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# Same executable + metadata + code requirement means there is nothing to deploy.
# Preserve both the installed bundle and its existing TCC identity in this case.
if [[ -d "$APP_DIR" ]] && \
   cmp -s "$STAGED_APP/Contents/MacOS/QRScanner" "$APP_DIR/Contents/MacOS/QRScanner" && \
   cmp -s "$STAGED_APP/Contents/Info.plist" "$APP_DIR/Contents/Info.plist" && \
   codesign --verify --strict "$APP_DIR" 2>/dev/null; then
    print -r -- "构建内容未变，保留现有应用：$APP_DIR"
    exit 0
fi
# pgrep returns 1 for no process; other errors must not allow replacement.
RUNNING_STATUS=0
pgrep -x QRScanner >/dev/null || RUNNING_STATUS=$?
if (( RUNNING_STATUS == 0 )); then
    print -u2 'QRScanner 正在运行。请从菜单栏右键菜单退出应用，再运行 Launch.command 更新。'
    print -u2 '为避免屏幕录制授权与运行进程不一致，本次未替换应用。'
    exit 1
elif (( RUNNING_STATUS != 1 )); then
    print -u2 '无法检查 QRScanner 是否运行，本次未替换应用。'
    exit 1
fi
# Keep the previous build until the replacement is ready, then move within one filesystem.
if [[ -d "$APP_DIR" ]]; then
    mv "$APP_DIR" "$STAGE_DIR/previous.app"
fi
if ! mv "$STAGED_APP" "$APP_DIR"; then
    if [[ -d "$STAGE_DIR/previous.app" ]]; then mv "$STAGE_DIR/previous.app" "$APP_DIR"; fi
    exit 1
fi
if [[ "$SIGN_IDENTITY" == '-' ]]; then
    print -r -- '本次使用 ad-hoc 签名：代码更新后可能需要退出应用、移除旧录屏权限条目并重新授权。'
    print -r -- '可设置 QRSCANNER_SIGN_IDENTITY 使用已安装的 Apple Development / Developer ID 证书。'
fi
print -r -- "$APP_DIR"
