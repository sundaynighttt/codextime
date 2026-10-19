// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageSync",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "UsageSync", targets: ["UsageSync"])],
    targets: [
        .target(name: "UsageSync"),
        .testTarget(name: "UsageSyncTests", dependencies: ["UsageSync"])
    ],
    swiftLanguageVersions: [.v5]
)
