// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"]),
        .executable(name: "CodexTimeScreenshotPreview", targets: ["CodexTimeScreenshotPreview"])
    ],
    dependencies: [.package(path: "../Shared/UsageSync")],
    targets: [
        .executableTarget(name: "CodexUsageMonitor", dependencies: [.product(name: "UsageSync", package: "UsageSync")], resources: [.process("Resources")]),
        .executableTarget(name: "CodexTimeScreenshotPreview"),
        .testTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitor"]
        )
    ],
    swiftLanguageModes: [.v5]
)
