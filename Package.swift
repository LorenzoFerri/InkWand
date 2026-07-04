// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InkWand",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "InkWand",
            targets: ["InkWand"]
        ),
        .executable(
            name: "InkWandServer",
            targets: ["InkWandServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "InkWand",
            dependencies: ["InkWandCore"]
        ),
        .target(
            name: "InkWandCore"
        ),
        .executableTarget(
            name: "InkWandServer",
            dependencies: [
                "InkWandCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "InkWandCoreTests",
            dependencies: ["InkWandCore"]
        ),
    ]
)
