// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HTTMELY",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HTTMELY", targets: ["HTTMELY"])
    ],
    targets: [
        .executableTarget(
            name: "HTTMELY",
            path: "Sources/HTTMELY"
        )
    ]
)
