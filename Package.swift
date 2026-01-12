// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-pool-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Pool Primitives",
            targets: ["Pool Primitives"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-async-primitives.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-primitives/swift-container-primitives.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-primitives/swift-dimension-primitives.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-primitives/swift-test-primitives.git", from: "0.0.1"),
        .package(url: "https://github.com/swift-foundations/swift-testing-extras.git", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "Pool Primitives",
            dependencies: [
                .product(name: "Async Primitives", package: "swift-async-primitives"),
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Container Primitives", package: "swift-container-primitives"),
                .product(name: "Dimension Primitives", package: "swift-dimension-primitives"),
            ]
        ),
        .testTarget(
            name: "Pool Primitives Tests",
            dependencies: [
                "Pool Primitives",
                .product(name: "Test Primitives", package: "swift-test-primitives"),
                .product(name: "Testing Extras", package: "swift-testing-extras"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let settings: [SwiftSetting] = [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + settings
}
