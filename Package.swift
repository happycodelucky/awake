// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AwakeMenuBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "AwakeMenuBar",
            targets: ["AwakeMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AwakeMenuBar",
            path: "Sources/AwakeMenuBar"
        )
    ]
)
