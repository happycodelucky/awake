// NOTE: This Package.swift is vestigial. The active build system is Awake.xcodeproj,
// generated from project.yml via XcodeGen. This file is retained as a reference.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AwakeMenuBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AwakeUI",
            targets: ["AwakeUI"]
        ),
        .executable(
            name: "AwakeMenuBar",
            targets: ["AwakeMenuBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
    ],
    targets: [
        .target(
            name: "AwakeUI",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AwakeUI"
        ),
        .executableTarget(
            name: "AwakeMenuBar",
            dependencies: [
                "AwakeUI"
            ],
            path: "Sources/AwakeMenuBarApp"
        )
    ]
)
