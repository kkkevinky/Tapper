#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Debug build script for Tapper app

APP_NAME="Tapper_Debug"
BUNDLE_ID="io.github.kkkevinky.tapper.debug"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE="$BUILD_DIR/clang-module-cache"
XCRUN="/usr/bin/xcrun"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-}"
ARCH="${ARCH:-$(uname -m)}"
BASE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

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

if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

echo "=========================================="
echo "Building Tapper (Debug Mode)"
echo "=========================================="

# Clean previous debug build
rm -rf "$APP_PATH"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$MODULE_CACHE"

# Compile with debug symbols for current architecture only
echo "📦 Compiling debug version..."
"$SWIFTC" -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
    -sdk "$SDKROOT" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    -g \
    -Onone \
    -D DEBUG \
    -target "${ARCH}-apple-macos13.0" \
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

if [ $? -ne 0 ]; then
    echo "❌ Debug compilation failed!"
    exit 1
fi

# Create debug Info.plist from the shared app plist to avoid duplicate metadata.
cp Info.plist "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Tapper Debug" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BASE_VERSION}-debug" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$APP_PATH/Contents/Info.plist"

# Copy app icon
cp AppIcon.icns "$APP_PATH/Contents/Resources/"

# Sign the app
echo "🔐 Codesigning debug app..."
codesign --force --deep --sign - "$APP_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Codesigning failed!"
    exit 1
fi

echo ""
echo "✅ Debug build complete!"
echo ""
echo "App location: $APP_PATH"
echo ""
echo "To run with console output:"
echo "  $APP_PATH/Contents/MacOS/$APP_NAME"
echo ""
echo "To run as app:"
echo "  open $APP_PATH"
echo ""
