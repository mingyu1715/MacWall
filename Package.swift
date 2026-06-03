// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacWall",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacWallCore", targets: ["MacWallCore"]),
        .executable(name: "MacWall", targets: ["MacWallExecutable"]),
        .executable(name: "macwallctl", targets: ["macwallctl"])
    ],
    targets: [
        .target(name: "MacWallCore"),
        .target(
            name: "MacWallApp",
            dependencies: ["MacWallCore"]
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
        )
    ]
)
