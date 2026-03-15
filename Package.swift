// NOTE: This Package.swift is vestigial. The active build system is Awake.xcodeproj,
// generated from project.yml via XcodeGen. This file is retained as a reference.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "Awake",
            targets: ["Awake"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Awake",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Awake"
        )
    ]
)
