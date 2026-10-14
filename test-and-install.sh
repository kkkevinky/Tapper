#!/bin/bash
# Build current source, test the exact bundle, then optionally install it.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
APP_PATH="$SCRIPT_DIR/build/Tapper.app"
INSTALL_PATH="/Applications/Tapper.app"
MODE="${1:-interactive}"
case "$MODE" in
    interactive|--build-only|--test-only|--install-only) ;;
    *) echo "Usage: bash test-and-install.sh [--build-only|--test-only|--install-only]"; exit 2 ;;
esac

stop_instances() {
    local name attempt
    for name in Tapper Tapper_Debug MagicTapper MagicTapper_Debug; do
        if pgrep -x "$name" >/dev/null; then
            echo "正在退出 $name..."
            killall "$name"
            for ((attempt=0; attempt<20; attempt++)); do
                if ! pgrep -x "$name" >/dev/null; then break; fi
                sleep 0.1
            done
            if pgrep -x "$name" >/dev/null; then
                echo "无法退出 ${name}，请从菜单退出后重试。"
                exit 1
            fi
        fi
    done
}

confirm() {
    local answer
    read -r -p "$1 (y/N): " answer || return 1
    [[ "$answer" == y || "$answer" == Y ]]
}

# Never trust an existing bundle: build scripts include every current source.
# A compile/signature failure exits before stopping or replacing the installed app.
echo "正在从当前源码构建最新版本..."
bash "$SCRIPT_DIR/build.sh"
codesign --verify --deep --strict "$APP_PATH"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DIGEST=$(shasum -a 256 "$APP_PATH/Contents/MacOS/Tapper" | awk '{print $1}')
echo "版本: $VERSION"
echo "本次构建: $APP_PATH"
echo "二进制 SHA-256: $DIGEST"
if [[ "$MODE" == --build-only ]]; then exit 0; fi

if [[ "$MODE" != --install-only ]]; then
    stop_instances
    # Force the specified bundle, rather than activating another registered copy.
    open -n "$APP_PATH"
    echo "已启动本次构建。请检查菜单栏、轻点、右键、双击拖拽和普通滚动。"
    echo "缩放测试：开启 Two-Finger Zoom，在 Chrome 和 PDF 中检查放大、缩小及额外滚动。"
    echo "再关闭 Tap to Click，确认缩放仍可独立使用。"
    if [[ "$MODE" == --test-only ]]; then exit 0; fi
    if ! confirm "测试完成后，是否安装到 /Applications"; then
        echo "未安装；原有安装版本保留，测试版继续运行。"
        exit 0
    fi
fi

# Stage and verify a complete copy before touching the existing installation.
STAGING=$(mktemp -d "/Applications/.Tapper-install.XXXXXX")
BACKUP_PATH=""
cleanup() {
    local status=$?
    if [[ $status -ne 0 && -n "$BACKUP_PATH" && ! -e "$INSTALL_PATH" ]]; then
        mv "$BACKUP_PATH" "$INSTALL_PATH" || echo "恢复失败，旧版仍保留在: $BACKUP_PATH" >&2
    fi
    rm -rf "$STAGING"
    return "$status"
}
trap cleanup EXIT
ditto "$APP_PATH" "$STAGING/Tapper.app"
codesign --verify --deep --strict "$STAGING/Tapper.app"
cmp "$APP_PATH/Contents/MacOS/Tapper" "$STAGING/Tapper.app/Contents/MacOS/Tapper"
stop_instances
if [[ -e "$INSTALL_PATH" || -L "$INSTALL_PATH" ]]; then
    BACKUP_PATH="/Applications/Tapper_backup_$(date +%Y%m%d_%H%M%S)_$$.app"
    mv "$INSTALL_PATH" "$BACKUP_PATH"
fi
mv "$STAGING/Tapper.app" "$INSTALL_PATH"
echo "已安装本次构建: $INSTALL_PATH"
if [[ -n "$BACKUP_PATH" ]]; then echo "旧版备份: $BACKUP_PATH"; fi
if confirm "是否立即启动已安装版本"; then
    open -n "$INSTALL_PATH"
fi
