#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
if ! "$PROJECT_DIR/scripts/build.sh"; then
    print 'QRScanner 构建失败，请检查上方错误。按回车关闭。'
    read -r
    exit 1
fi
open "$PROJECT_DIR/build/QRScanner.app"
