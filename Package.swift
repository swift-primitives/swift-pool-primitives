// swift-tools-version: 6.3.1

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
        // MARK: - Namespace
        .library(
            name: "Pool Primitive",
            targets: ["Pool Primitive"]
        ),
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
        .package(url: "https://github.com/swift-primitives/swift-async-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-stack-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-array-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dimension-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ownership-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-effect-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-algebra-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Namespace
        .target(
            name: "Pool Primitive",
            dependencies: []
        ),

        // MARK: - Core
        .target(
            name: "Pool Primitives Core",
            dependencies: [
                "Pool Primitive",
                .product(name: "Async Primitives Core", package: "swift-async-primitives"),
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
                .product(name: "Effect Primitives", package: "swift-effect-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Algebra Primitives", package: "swift-algebra-primitives"),
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Pool Bounded Primitives",
            dependencies: [
                "Pool Primitives Core",
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Array Primitive", package: "swift-array-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
                .product(name: "Array Fixed Primitives", package: "swift-array-primitives"),
                .product(name: "Async Waiter Primitives", package: "swift-async-primitives"),
                .product(name: "Async Mutex Primitives", package: "swift-async-primitives"),
                .product(name: "Async Promise Primitives", package: "swift-async-primitives"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Pool Primitives",
            dependencies: [
                "Pool Primitive",
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
                .product(name: "Async Primitives", package: "swift-async-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
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
