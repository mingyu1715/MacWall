enum MacWallNativeWallpaperVideoSourceMode: String, Sendable {
    case asset
    case generated
}

enum MacWallNativeWallpaperVideoSourceModeConfiguration {
    static let mode: MacWallNativeWallpaperVideoSourceMode = .asset
}
