// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "kssh",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "kssh",
            path: "Sources/kssh"
        ),
        .testTarget(
            name: "ksshTests",
            dependencies: ["kssh"],
            path: "Tests/ksshTests"
        ),
    ]
)
