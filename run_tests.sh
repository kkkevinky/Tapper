#!/bin/bash

# Test runner script for Tapper

echo "=== Tapper Test Suite ==="
echo ""

# Run tests using Swift Package Manager
echo "🧪 Running tests with Swift Package Manager..."

# XCTest is only bundled with full Xcode, not the standalone Command Line Tools.
# If `xcode-select` points at CLT, force DEVELOPER_DIR at the Xcode app so the
# test target can import XCTest.
if [ "$XCODE_DEVELOPER_DIR" != "" ]; then
    export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
elif [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift test

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 All tests passed!"
    exit 0
else
    echo ""
    echo "💔 Some tests failed"
    exit 1
fi
