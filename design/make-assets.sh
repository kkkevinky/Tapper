#!/bin/bash
# Regenerates the README logo and the app icon from design/*.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

swift design/logo.swift .
swift design/icon.swift AppIcon.iconset
iconutil -c icns AppIcon.iconset -o AppIcon.icns
echo "Updated Tapper-logo-light.png, Tapper-logo-dark.png, AppIcon.iconset and AppIcon.icns"
