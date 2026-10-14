#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "1) 正常运行  2) 调试运行"
read -r -p "请选择 (1/2): " choice
if [[ "$choice" == 2 ]]; then
    exec bash "$SCRIPT_DIR/debug-run.sh"
fi
exec bash "$SCRIPT_DIR/test-and-install.sh" --test-only
