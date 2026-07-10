// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InkWandCore",
    platforms: [
        .iOS("17.0"),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "InkWandCore",
            targets: ["InkWandCore"]
        ),
    ],
    targets: [
        .target(
            name: "InkWandCryptoC",
            publicHeadersPath: "include",
            cSettings: [
                .define("INKWAND_USE_OPENSSL", .when(platforms: [.linux])),
            ],
            linkerSettings: [
                .linkedLibrary("crypto", .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "InkWandCore",
            dependencies: [
                .target(name: "InkWandCryptoC", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "InkWandCoreTests",
            dependencies: ["InkWandCore"]
        ),
    ]
)
