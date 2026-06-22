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
        // MARK: - Namespace + foundational
        .library(
            name: "Pool Primitive",
            targets: ["Pool Primitive"]
        ),

        // MARK: - Identity & configuration vocabulary
        .library(
            name: "Pool Scope Primitives",
            targets: ["Pool Scope Primitives"]
        ),
        .library(
            name: "Pool ID Primitives",
            targets: ["Pool ID Primitives"]
        ),
        .library(
            name: "Pool Error Primitives",
            targets: ["Pool Error Primitives"]
        ),
        .library(
            name: "Pool Capacity Primitives",
            targets: ["Pool Capacity Primitives"]
        ),

        // MARK: - Lifecycle & metrics
        .library(
            name: "Pool Lifecycle Primitives",
            targets: ["Pool Lifecycle Primitives"]
        ),
        .library(
            name: "Pool Metrics Primitives",
            targets: ["Pool Metrics Primitives"]
        ),

        // MARK: - Effects
        .library(
            name: "Pool Acquire Primitives",
            targets: ["Pool Acquire Primitives"]
        ),
        .library(
            name: "Pool Release Primitives",
            targets: ["Pool Release Primitives"]
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
        .package(url: "https://github.com/swift-primitives/swift-fixed-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-column-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-linear-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-shared-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-storage-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-heap-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-allocation-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-tagged-collection-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dimension-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ownership-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-effect-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Namespace + foundational
        .target(
            name: "Pool Primitive",
            dependencies: []
        ),

        // MARK: - Identity & configuration vocabulary
        // Genuine depth-4 chain Capacity→Error→ID→Scope (each embeds/throws the
        // next); [MOD-007] depth≤3 is ADVISORY (2026-06-17 / GR4) — maximize-split
        // favors width over fused depth here, not number-chasing.
        .target(
            name: "Pool Scope Primitives",
            dependencies: [
                "Pool Primitive",
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
                .product(name: "Async Primitives", package: "swift-async-primitives"),
            ]
        ),
        .target(
            name: "Pool ID Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
            ]
        ),
        .target(
            name: "Pool Error Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                "Pool ID Primitives",
            ]
        ),
        .target(
            name: "Pool Capacity Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Error Primitives",
            ]
        ),

        // MARK: - Lifecycle & metrics
        .target(
            name: "Pool Lifecycle Primitives",
            dependencies: [
                "Pool Primitive",
                .product(name: "Async Primitives", package: "swift-async-primitives"),
            ]
        ),
        .target(
            name: "Pool Metrics Primitives",
            dependencies: [
                "Pool Primitive",
            ]
        ),

        // MARK: - Effects
        .target(
            name: "Pool Acquire Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                "Pool Error Primitives",
                .product(name: "Effect Primitives", package: "swift-effect-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
            ]
        ),
        .target(
            name: "Pool Release Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                "Pool ID Primitives",
                .product(name: "Effect Primitives", package: "swift-effect-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Pool Bounded Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                "Pool ID Primitives",
                "Pool Error Primitives",
                "Pool Capacity Primitives",
                "Pool Lifecycle Primitives",
                "Pool Metrics Primitives",
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Buffer Linear Bounded Primitive", package: "swift-buffer-linear-primitives"),
                .product(name: "Buffer Linear Primitive", package: "swift-buffer-linear-primitives"),
                .product(name: "Shared Primitive", package: "swift-shared-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Array Primitive", package: "swift-array-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
                .product(name: "Fixed Primitives", package: "swift-fixed-primitives"),
                .product(name: "Tagged Collection Primitives", package: "swift-tagged-collection-primitives"),
                .product(name: "Async Primitives", package: "swift-async-primitives"),
                .product(name: "Async Waiter Primitives", package: "swift-async-primitives"),
                .product(name: "Async Mutex Primitives", package: "swift-async-primitives"),
                .product(name: "Async Promise Primitives", package: "swift-async-primitives"),
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Pool Primitives",
            dependencies: [
                "Pool Primitive",
                "Pool Scope Primitives",
                "Pool ID Primitives",
                "Pool Error Primitives",
                "Pool Capacity Primitives",
                "Pool Lifecycle Primitives",
                "Pool Metrics Primitives",
                "Pool Acquire Primitives",
                "Pool Release Primitives",
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
                .product(name: "Fixed Primitives", package: "swift-fixed-primitives"),
                .product(name: "Tagged Collection Primitives", package: "swift-tagged-collection-primitives"),
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
