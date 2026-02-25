// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-pool-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "Pool Primitives",
            targets: ["Pool Primitives"]
        ),
        .library(
            name: "Pool Primitives Test Support",
            targets: ["Pool Primitives Test Support"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-async-primitives"),
        .package(path: "../swift-buffer-primitives"),
        .package(path: "../swift-stack-primitives"),
        .package(path: "../swift-array-primitives"),
        .package(path: "../swift-dimension-primitives"),
        .package(path: "../swift-ownership-primitives"),
        .package(path: "../swift-effect-primitives"),
        .package(path: "../swift-index-primitives"),
        .package(path: "../swift-collection-primitives"),

        // SDG(wraps): pool resources wrap managed lifetimes
        // .package(path: "../swift-lifetime-primitives"),
    ],
    targets: [
        .target(
            name: "Pool Primitives",
            dependencies: [
                .product(name: "Async Primitives", package: "swift-async-primitives"),
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Effect Primitives", package: "swift-effect-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Collection Primitives", package: "swift-collection-primitives"),
            ]
        ),
        .target(
            name: "Pool Primitives Test Support",
            dependencies: [
                "Pool Primitives",
                .product(name: "Index Primitives Test Support", package: "swift-index-primitives"),
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Pool Primitives Tests",
            dependencies: [
                "Pool Primitives",
                "Pool Primitives Test Support",
            ],
            path: "Tests/Pool Primitives Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
