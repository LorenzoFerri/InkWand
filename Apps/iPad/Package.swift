// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InkWandIPad",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(
            name: "InkWand",
            targets: ["InkWand"]
        ),
    ],
    dependencies: [
        .package(name: "InkWandCore", path: "../../Packages/InkWandCore"),
    ],
    targets: [
        .target(
            name: "InkWand",
            dependencies: [
                .product(name: "InkWandCore", package: "InkWandCore"),
            ]
        ),
    ]
)
