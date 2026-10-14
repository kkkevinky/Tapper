// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Tapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TapperLib",
            targets: ["TapperLib"]
        )
    ],
    targets: [
        .target(
            name: "TapperLib",
            dependencies: [],
            path: ".",
            exclude: [
                "AppIcon.icns",
                "AppDelegate.swift",
                "ZoomScrollFilter.swift",
                "ZoomDiagnosticWindow.swift",
                "CHANGELOG.md",
                "Info.plist",
                "LICENSE",
                "THIRD_PARTY_NOTICES.md",
                "Tapper-logo-dark.png",
                "Tapper-logo-light.png",
                "design",
                "MultitouchBridge.h",
                "MultitouchManager.swift",
                "MouseSpeedIOKitBackend.swift",
                "PointerSpeedMenuView.swift",
                "README.md",
                "README_ja.md",
                "README_zh.md",
                "SettingsWindowController.swift",
                "build-debug.sh",
                "build.sh",
                "debug-run.sh",
                "diagnose-zoom.sh",
                "install-final.sh",
                "main.swift",
                "quick-test.sh",
                "run_tests.sh",
                "test-and-install.sh",
                "AppIcon.iconset",
                "Tests",
                "build"
            ],
            sources: [
                "Constants.swift",
                "DefaultsMigration.swift",
                "EventSynthesizer.swift",
                "ZoomGestureDetector.swift",
                "ZoomEventSynthesizer.swift",
                "ZoomDiagnostics.swift",
                "ZoomCoordinator.swift",

                "MouseSpeedManager.swift",
                "MultitouchDeviceMonitor.swift",
                "MultitouchRestartManager.swift",
                "MultitouchDeviceClassifier.swift",
                "TapConfiguration.swift",
                "TapDetector.swift"
            ]
        ),
        .testTarget(
            name: "TapperTests",
            dependencies: ["TapperLib"],
            path: "Tests",
            exclude: ["ScriptWorkflowTests.py"]
        )
    ]
)
