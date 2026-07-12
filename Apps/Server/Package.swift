// swift-tools-version: 6.0

import PackageDescription

var dependencies: [Package.Dependency] = [
    .package(name: "InkWandCore", path: "../../Packages/InkWandCore"),
    .package(url: "https://github.com/LorenzoFerri/swift-cross-ui.git", revision: "5555a3473462999dca571008dd466aa29e5dd0a0"),
]

var targetDependencies: [Target.Dependency] = [
    .product(name: "InkWandCore", package: "InkWandCore"),
    .product(name: "SwiftCrossUI", package: "swift-cross-ui", condition: .when(platforms: [.linux, .macOS])),
    .product(name: "DefaultBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux, .macOS])),
    .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
    .product(name: "AppKitBackend", package: "swift-cross-ui", condition: .when(platforms: [.macOS])),
]

#if compiler(>=6.0)
    dependencies.append(
        .package(
            url: "https://github.com/moreSwift/swift-bundler",
            revision: "496c0638dc2c6750c7873832a08c36c74631aed4"
        )
    )
    targetDependencies.append(
        .product(
            name: "SwiftBundlerRuntime",
            package: "swift-bundler",
            condition: .when(platforms: [.linux, .macOS])
        )
    )
#endif

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
    dependencies: dependencies,
    targets: [
        .executableTarget(
            name: "InkWandServer",
            dependencies: targetDependencies
        ),
        .testTarget(
            name: "InkWandServerTests",
            dependencies: ["InkWandServer"]
        ),
    ]
)
