enum MacWallNativeWallpaperTimingClockMode: String, Sendable {
    case controlTimebase = "control-timebase"
    case synchronizer
}

enum MacWallNativeWallpaperTimingProfile: String, Sendable {
    case normal
    case reduced
}

enum MacWallNativeWallpaperTimingConfiguration {
    static let clockMode: MacWallNativeWallpaperTimingClockMode = .synchronizer
    static let profile: MacWallNativeWallpaperTimingProfile = .normal
}
