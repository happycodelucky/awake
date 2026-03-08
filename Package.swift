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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "AwakeMenuBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AwakeMenuBar"
        )
    ]
)
