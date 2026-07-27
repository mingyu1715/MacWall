import Darwin
import ExtensionFoundation
import Foundation
import os

let macWallNativeWallpaperLogger = Logger(
    subsystem: "com.mingyu1715.macwall.native-wallpaper-extension",
    category: "Runtime"
)

@main
final class MacWallNativeWallpaperExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        macWallNativeWallpaperLogger.info(
            "MacWall native wallpaper extension process started"
        )
        loadWallpaperExtensionKit()
    }

    deinit {
        let removed = MacWallRemoteWallpaperContextStore.shared.removeAll(
            reason: "extension-deinit"
        )
        macWallNativeWallpaperLogger.info(
            "MacWall native wallpaper extension deinit removedContexts=\(removed)"
        )
    }

    var configuration: some AppExtensionConfiguration {
        MacWallWallpaperExtensionConfiguration()
    }

    private func loadWallpaperExtensionKit() {
        let frameworkPath =
            "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        if dlopen(frameworkPath, RTLD_LAZY) != nil {
            macWallNativeWallpaperLogger.info("WallpaperExtensionKit loaded")
        } else if let error = dlerror() {
            macWallNativeWallpaperLogger.error(
                "WallpaperExtensionKit load failed: \(String(cString: error), privacy: .public)"
            )
        } else {
            macWallNativeWallpaperLogger.error(
                "WallpaperExtensionKit load failed without dlerror"
            )
        }
    }
}
