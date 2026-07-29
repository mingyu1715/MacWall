import AppKit
import Foundation

@MainActor
protocol WallpaperSettingsOpening: AnyObject {
    @discardableResult
    func openWallpaperSettings() -> Bool
}

@MainActor
final class WallpaperSettingsController: WallpaperSettingsOpening {
    @discardableResult
    func openWallpaperSettings() -> Bool {
        let workspace = NSWorkspace.shared
        let pane = URL(
            string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        )
        if let pane, workspace.open(pane) {
            return true
        }
        return workspace.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}
