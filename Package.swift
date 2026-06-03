// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WorkshopWallpaperBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorkshopWallpaperCore", targets: ["WorkshopWallpaperCore"]),
        .executable(name: "WorkshopWallpaperBridge", targets: ["WorkshopWallpaperBridgeExecutable"]),
        .executable(name: "wwbctl", targets: ["wwbctl"])
    ],
    targets: [
        .target(name: "WorkshopWallpaperCore"),
        .target(
            name: "WorkshopWallpaperBridgeApp",
            dependencies: ["WorkshopWallpaperCore"]
        ),
        .executableTarget(
            name: "WorkshopWallpaperBridgeExecutable",
            dependencies: ["WorkshopWallpaperBridgeApp"]
        ),
        .executableTarget(
            name: "wwbctl",
            dependencies: ["WorkshopWallpaperCore"]
        ),
        .testTarget(
            name: "WorkshopWallpaperCoreTests",
            dependencies: ["WorkshopWallpaperCore"]
        ),
        .testTarget(
            name: "WorkshopWallpaperBridgeAppTests",
            dependencies: ["WorkshopWallpaperBridgeApp"]
        )
    ]
)
