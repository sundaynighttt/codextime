// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"])
    ],
    targets: [
        .executableTarget(name: "CodexUsageMonitor"),
        .testTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitor"]
        )
    ],
    swiftLanguageModes: [.v5]
)
