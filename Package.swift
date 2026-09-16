// swift-tools-version: 5.9
// Yêu cầu Swift 5.9+ để hỗ trợ macOS 13 target và SwiftUI hiện đại
// AppKit, SwiftUI, UniformTypeIdentifiers được tự động link trên macOS — không cần khai báo thủ công

import PackageDescription

let package = Package(
    name: "snip",
    // Tối thiểu macOS 13 (Ventura) — yêu cầu từ spec
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "snip",
            path: "Sources/snip"
        ),
    ]
)
