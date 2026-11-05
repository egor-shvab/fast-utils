// swift-tools-version: 6.0
import PackageDescription

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

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "FeatureOCRTests", dependencies: ["FeatureOCR"]),
        .testTarget(name: "FeatureTranslateTests", dependencies: ["FeatureTranslate"]),
        .testTarget(name: "FeatureClipboardTests", dependencies: ["FeatureClipboard"]),
    ]
)
