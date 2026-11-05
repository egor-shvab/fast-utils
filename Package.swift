// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Swift Build (default in SwiftPM 6.4) sometimes omits the Swift Testing macro plugin path
// for test targets when building with Command Line Tools only, failing with
// "plugin for module 'TestingMacros' not found". Pass it explicitly. See CLAUDE.md.
let testingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPluginPath)
    ? [.unsafeFlags(["-plugin-path", testingPluginPath])]
    : []

// Feature modules depend only on Core, never on each other (see TZ.md §12).
let package = Package(
    name: "FastUtils",
    defaultLocalization: "ru",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FastUtils", targets: ["FastUtilsApp"]),
    ],
    targets: [
        .executableTarget(
            name: "FastUtilsApp",
            dependencies: ["Core", "FeatureOCR", "FeatureTranslate", "FeatureClipboard"]
        ),
        .target(name: "Core"),
        .target(name: "FeatureOCR", dependencies: ["Core"]),
        .target(name: "FeatureTranslate", dependencies: ["Core"]),
        .target(name: "FeatureClipboard", dependencies: ["Core"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"], swiftSettings: testSettings),
        .testTarget(name: "FeatureOCRTests", dependencies: ["FeatureOCR"], swiftSettings: testSettings),
        .testTarget(name: "FeatureTranslateTests", dependencies: ["FeatureTranslate"], swiftSettings: testSettings),
        .testTarget(name: "FeatureClipboardTests", dependencies: ["FeatureClipboard"], swiftSettings: testSettings),
    ]
)
