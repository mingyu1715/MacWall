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
        .target(name: "MacWallSceneFormats"),
        .target(
            name: "MacWallSceneAudit",
            dependencies: ["MacWallSceneFormats"]
        ),
        .target(
            name: "MacWallSceneTestSupport",
            dependencies: ["MacWallSceneFormats"],
            path: "Tests/MacWallSceneTestSupport"
        ),
        .target(
            name: "MacWallCore",
            dependencies: ["MacWallSceneFormats"]
        ),
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
            dependencies: [
                "MacWallCore",
                "MacWallSceneAudit"
            ]
        ),
        .testTarget(
            name: "MacWallCoreTests",
            dependencies: [
                "MacWallCore",
                "MacWallSceneTestSupport"
            ]
        ),
        .testTarget(
            name: "MacWallAppTests",
            dependencies: ["MacWallApp"]
        ),
        .testTarget(
            name: "MacWallNativeRuntimeSupportTests",
            dependencies: ["MacWallNativeRuntimeSupport"]
        ),
        .testTarget(
            name: "MacWallSceneFormatsTests",
            dependencies: [
                "MacWallSceneFormats",
                "MacWallSceneTestSupport"
            ]
        ),
        .testTarget(
            name: "MacWallSceneAuditTests",
            dependencies: [
                "MacWallSceneAudit",
                "MacWallSceneFormats",
                "MacWallSceneTestSupport"
            ]
        )
    ]
)
