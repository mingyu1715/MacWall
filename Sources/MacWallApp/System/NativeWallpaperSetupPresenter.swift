import AppKit

@MainActor
protocol NativeWallpaperSetupPresenting: AnyObject {
    func presentNativeWallpaperSetup() -> NativeWallpaperSetupChoice
}

@MainActor
final class NativeWallpaperSetupPresenter: NativeWallpaperSetupPresenting {
    func presentNativeWallpaperSetup() -> NativeWallpaperSetupChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Native Wallpaper 설정이 필요합니다"
        alert.informativeText = """
        macOS 26의 Native Wallpaper 방식은 시스템 설정에서 MacWall을 배경화면으로 한 번 선택해야 합니다. Native 방식은 전체 화면과 Space 전환이 자연스럽습니다.

        기존 방식은 바로 재생할 수 있지만 전환 중 macOS 배경화면이 잠깐 보일 수 있습니다.
        """
        alert.addButton(withTitle: "배경화면 설정 열기")
        alert.addButton(withTitle: "기존 방식으로 재생")
        alert.addButton(withTitle: "취소")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .openSettings
        case .alertSecondButtonReturn:
            return .useLegacyOnce
        default:
            return .cancel
        }
    }
}
