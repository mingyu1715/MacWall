import AppKit

@MainActor
protocol DesktopWallpaperRestoreWarningPresenting: AnyObject {
    func showUnsupportedOriginalWallpaperWarning(message: String)
}

@MainActor
final class DesktopWallpaperRestoreWarningPresenter: DesktopWallpaperRestoreWarningPresenting {
    func showUnsupportedOriginalWallpaperWarning(message: String) {
        let alert = NSAlert()
        alert.messageText = "Original wallpaper cannot be restored automatically"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
