// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InkWandServerApp",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "InkWandServer",
            targets: ["InkWandServer"]
        ),
    ],
    dependencies: [
        .package(name: "InkWandCore", path: "../../Packages/InkWandCore"),
        .package(url: "https://github.com/LorenzoFerri/swift-cross-ui.git", revision: "5555a3473462999dca571008dd466aa29e5dd0a0"),
    ],
    targets: [
        .executableTarget(
            name: "InkWandServer",
            dependencies: [
                .product(name: "InkWandCore", package: "InkWandCore"),
                .product(name: "SwiftCrossUI", package: "swift-cross-ui", condition: .when(platforms: [.linux, .macOS])),
                .product(name: "DefaultBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux, .macOS])),
                .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
                .product(name: "AppKitBackend", package: "swift-cross-ui", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "InkWandServerTests",
            dependencies: ["InkWandServer"]
        ),
    ]
)
