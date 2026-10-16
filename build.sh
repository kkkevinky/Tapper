#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build script for Tapper app (Production)

APP_NAME="Tapper"
BUNDLE_ID="io.github.kkkevinky.tapper"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE="$BUILD_DIR/clang-module-cache"
XCRUN="/usr/bin/xcrun"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-}"

if [ "$XCODE_DEVELOPER_DIR" = "" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [ "$XCODE_DEVELOPER_DIR" != "" ]; then
    SDKROOT="$(env DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" "$XCRUN" --sdk macosx --show-sdk-path)"
    SWIFTC="$(env DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" "$XCRUN" --find swiftc)"
else
    SDKROOT="$("$XCRUN" --sdk macosx --show-sdk-path)"
    SWIFTC="$("$XCRUN" --find swiftc)"
fi

echo "=========================================="
echo "Building Tapper (Universal Binary)"
echo "=========================================="

# Clean previous build
rm -rf "$APP_PATH"
mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_CACHE"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

compile_arch() {
    local arch="$1"
    local label="$2"
    local output="$BUILD_DIR/${APP_NAME}_${arch}"

    echo "📦 Compiling for $label ($arch)..."
    "$SWIFTC" -O -o "$output" \
    -sdk "$SDKROOT" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    -target "${arch}-apple-macos13.0" \
    -import-objc-header MultitouchBridge.h \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -framework IOKit \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Constants.swift \
    DefaultsMigration.swift \
    MultitouchDeviceClassifier.swift \
    TapConfiguration.swift \
    TapDetector.swift \
    TwoFingerTap.swift \
    TouchTuning.swift \
    SpaceSwipe.swift \
    EventSynthesizer.swift \
    ZoomGestureDetector.swift \
    ZoomEventSynthesizer.swift \
    ZoomDiagnostics.swift \
    ZoomCoordinator.swift \
    ZoomScrollFilter.swift \
    ZoomDiagnosticWindow.swift \
    MouseSpeedManager.swift \
    MouseSpeedIOKitBackend.swift \
    PointerSpeedMenuView.swift \
    MultitouchDeviceMonitor.swift \
    MultitouchManager.swift \
    MultitouchRestartManager.swift \
    SettingsWindowController.swift \
    AppDelegate.swift \
    main.swift
}

compile_arch "arm64" "Apple Silicon"
compile_arch "x86_64" "Intel"

# Create universal binary
echo "🔗 Creating universal binary..."
lipo -create \
    "$BUILD_DIR/${APP_NAME}_arm64" \
    "$BUILD_DIR/${APP_NAME}_x86_64" \
    -output "$APP_PATH/Contents/MacOS/$APP_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Failed to create universal binary!"
    exit 1
fi

# Clean up temporary files
rm "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"

# Copy Info.plist
cp Info.plist "$APP_PATH/Contents/"

# Copy app icon
cp AppIcon.icns "$APP_PATH/Contents/Resources/"

# Ad-hoc sign the app bundle so macOS Accessibility permissions persist
echo ""
echo "🔐 Codesigning app bundle..."
codesign --force --deep --sign - "$APP_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Codesigning failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ UNIVERSAL BINARY BUILD COMPLETE!"
echo "=========================================="
echo ""
echo "App location: $APP_PATH"
echo "Architectures: arm64 (Apple Silicon) + x86_64 (Intel)"
echo ""
echo "Features:"
echo "  • Tap to click, double-click and tap-to-drag"
echo "  • Two-finger tap to right-click"
echo "  • Two-finger Space switching, also with the palm resting on the mouse"
echo "  • Pointer speed slider and tap sensitivity settings"
echo "  • Independent two-finger zoom (experimental, off by default)"
echo "  • Launch at Login"
echo ""
echo "To run the app:"
echo "  open $APP_PATH"
echo ""
echo "To install the app:"
echo "  bash install-final.sh"
echo ""
