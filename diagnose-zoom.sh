#!/bin/bash
# Opt-in local trace; no synthetic probes are sent by this script.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p build
TRACE_PATH="$SCRIPT_DIR/build/zoom-diagnostics-$(date +%Y%m%d-%H%M%S)-$$.log"
echo "将构建并运行诊断版，日志仅保存在本机：$TRACE_PATH"
echo "启动后开启 Two-Finger Zoom，在 Chrome 同一普通网页中："
echo "1. 用 Magic Mouse 连续完成三次放大、缩小，每次完全抬起手指。"
echo "2. 换触摸板完成三次捏合缩放（不要同时操作两种设备）。"
echo "3. 返回终端按 Ctrl+C 停止，把日志路径告诉我。"
TAPPER_ZOOM_DIAGNOSTICS=1 bash "$SCRIPT_DIR/debug-run.sh" 2>&1 | tee "$TRACE_PATH"
