// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KikaReportsViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KikaReportsViewer", targets: ["KikaReportsViewer"])
    ],
    targets: [
        .executableTarget(
            name: "KikaReportsViewer",
            path: "Sources/KikaReportsViewer"
        )
    ]
)
