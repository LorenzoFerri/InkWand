// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InkWandServerApp",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "InkWandServer",
            targets: ["InkWandServer"]
        ),
    ],
    dependencies: [
        .package(name: "InkWandCore", path: "../../Packages/InkWandCore"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/LorenzoFerri/swift-cross-ui.git", revision: "5555a3473462999dca571008dd466aa29e5dd0a0"),
    ],
    targets: [
        .executableTarget(
            name: "InkWandServer",
            dependencies: [
                .product(name: "InkWandCore", package: "InkWandCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftCrossUI", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
                .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
            ]
        ),
    ]
)
