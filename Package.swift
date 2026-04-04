// swift-tools-version: 6.3

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
        // MARK: - Core
        .library(
            name: "Pool Primitives Core",
            targets: ["Pool Primitives Core"]
        ),
        // MARK: - Variants
        .library(
            name: "Pool Bounded Primitives",
            targets: ["Pool Bounded Primitives"]
        ),
        // MARK: - Umbrella
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
        .package(path: "../swift-stack-primitives"),
        .package(path: "../swift-array-primitives"),
        .package(path: "../swift-dimension-primitives"),
        .package(path: "../swift-ownership-primitives"),
        .package(path: "../swift-effect-primitives"),
        .package(path: "../swift-index-primitives"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "Pool Primitives Core",
            dependencies: [
                .product(name: "Async Primitives Core", package: "swift-async-primitives"),
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
                .product(name: "Effect Primitives", package: "swift-effect-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Pool Bounded Primitives",
            dependencies: [
                "Pool Primitives Core",
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Array Primitives Core", package: "swift-array-primitives"),
                .product(name: "Array Dynamic Primitives", package: "swift-array-primitives"),
                .product(name: "Array Fixed Primitives", package: "swift-array-primitives"),
                .product(name: "Async Waiter Primitives", package: "swift-async-primitives"),
                .product(name: "Async Mutex Primitives", package: "swift-async-primitives"),
                .product(name: "Async Promise Primitives", package: "swift-async-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Pool Primitives",
            dependencies: [
                "Pool Primitives Core",
                "Pool Bounded Primitives",
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

        // MARK: - Tests
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
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
