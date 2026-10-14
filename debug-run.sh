#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build before stopping any running instance; never reuse an old debug bundle.
bash "$SCRIPT_DIR/build-debug.sh"

echo "=========================================="
echo "Tapper 调试运行器"
echo "=========================================="
echo ""
echo "此脚本将在终端中运行应用，显示所有调试输出"
echo ""
echo "调试信息说明："
echo "  📱 = 触摸事件检测"
echo "  🖱️ = 点击已识别"
echo "  ⚠️ = 点击未触发（显示原因）"
echo "  🎯 = 拖拽事件"
echo "  💥 = 鼠标事件合成"
echo ""
echo "按 Ctrl+C 停止应用"
echo ""
echo "=========================================="
echo ""

# Stop both variants, and refuse to overlap with a process that won't exit.
for name in Tapper Tapper_Debug MagicTapper MagicTapper_Debug; do
    if pgrep -x "$name" >/dev/null; then
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

echo "🚀 启动调试版本..."
echo ""

# 运行调试版本
exec "$SCRIPT_DIR/build/Tapper_Debug.app/Contents/MacOS/Tapper_Debug"
