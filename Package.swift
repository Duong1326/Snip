// swift-tools-version: 6.2
// Requires Swift 6 toolchain and macOS 26 (Tahoe) for Liquid Glass APIs.

import PackageDescription

let package = Package(
    name: "snip",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "snip",
            path: "Sources/snip"
        ),
    ]
)
