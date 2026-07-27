// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacWall",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacWallCore", targets: ["MacWallCore"]),
        .library(name: "MacWallApp", targets: ["MacWallApp"]),
        .library(
            name: "MacWallNativeRuntimeSupport",
            targets: ["MacWallNativeRuntimeSupport"]
        ),
        .executable(name: "MacWall", targets: ["MacWallExecutable"]),
        .executable(name: "macwallctl", targets: ["macwallctl"])
    ],
    targets: [
        .target(name: "MacWallCore"),
        .target(name: "MacWallNativeRuntimeSupport"),
        .target(
            name: "MacWallApp",
            dependencies: ["MacWallCore", "MacWallNativeRuntimeSupport"]
        ),
        .executableTarget(
            name: "MacWallExecutable",
            dependencies: ["MacWallApp"]
        ),
        .executableTarget(
            name: "macwallctl",
            dependencies: ["MacWallCore"]
        ),
        .testTarget(
            name: "MacWallCoreTests",
            dependencies: ["MacWallCore"]
        ),
        .testTarget(
            name: "MacWallAppTests",
            dependencies: ["MacWallApp"]
        ),
        .testTarget(
            name: "MacWallNativeRuntimeSupportTests",
            dependencies: ["MacWallNativeRuntimeSupport"]
        )
    ]
)
