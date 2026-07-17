import CoreGraphics
import Darwin
import Foundation

@MainActor
enum WindowServerWindowLevelExperiment {
    static let appliesDockHostAdjacentLevelToWallpaperWindows = true

    static var targetLevel: Int32 {
        Int32(CGWindowLevelForKey(.desktopWindow) + 2)
    }
}

@MainActor
final class WindowServerWindowLevelController {
    static let shared = WindowServerWindowLevelController()

    private typealias SLSMainConnectionID = @convention(c) () -> Int32
    private typealias SLSSetWindowLevel = @convention(c) (Int32, UInt32, Int32) -> Int32
    private typealias SLSGetWindowLevel = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let mainConnectionID: SLSMainConnectionID?
    private let setWindowLevel: SLSSetWindowLevel?
    private let getWindowLevel: SLSGetWindowLevel?
    private let setWindowLevelSymbolName: String?

    private init() {
        let handle = Self.openSkyLight()
        self.handle = handle
        mainConnectionID = Self.load("SLSMainConnectionID", from: handle, as: SLSMainConnectionID.self)
        getWindowLevel = Self.load("SLSGetWindowLevel", from: handle, as: SLSGetWindowLevel.self)

        if let setWindowLevel = Self.load("SLSSetWindowLevel", from: handle, as: SLSSetWindowLevel.self) {
            self.setWindowLevel = setWindowLevel
            setWindowLevelSymbolName = "SLSSetWindowLevel"
        } else if let setWindowLevel = Self.load("CGSSetWindowLevel", from: handle, as: SLSSetWindowLevel.self) {
            self.setWindowLevel = setWindowLevel
            setWindowLevelSymbolName = "CGSSetWindowLevel"
        } else {
            setWindowLevel = nil
            setWindowLevelSymbolName = nil
        }
    }

    @discardableResult
    func applyDockHostAdjacentLevel(to windowNumber: Int, originalLevel: Int32) -> Int32? {
        guard WindowServerWindowLevelExperiment.appliesDockHostAdjacentLevelToWallpaperWindows else {
            return nil
        }
        let targetLevel = WindowServerWindowLevelExperiment.targetLevel
        guard setLevel(targetLevel, to: windowNumber, operation: "applyDockHostAdjacentLevel") else {
            return nil
        }
        WallpaperPlaybackDiagnostics.log(
            "windowLevel operation=applyDockHostAdjacentLevel windowNumber=\(windowNumber) originalLevel=\(originalLevel) targetLevel=\(targetLevel) result=ok"
        )
        verifyLevel(windowNumber: windowNumber, label: "immediate-after-apply")
        return originalLevel
    }

    func restoreOriginalLevel(_ originalLevel: Int32, to windowNumber: Int) {
        guard WindowServerWindowLevelExperiment.appliesDockHostAdjacentLevelToWallpaperWindows else {
            return
        }
        _ = setLevel(originalLevel, to: windowNumber, operation: "restoreOriginalLevel")
        verifyLevel(windowNumber: windowNumber, label: "immediate-after-restore")
    }

    func verifyAppliedLevelLater(windowNumber: Int, delayMilliseconds: UInt64) {
        guard WindowServerWindowLevelExperiment.appliesDockHostAdjacentLevelToWallpaperWindows else {
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
            await MainActor.run {
                self?.verifyLevel(
                    windowNumber: windowNumber,
                    label: "\(delayMilliseconds)ms-after-apply"
                )
            }
        }
    }

    private func verifyLevel(windowNumber: Int, label: String) {
        guard windowNumber > 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevelVerify label=\(label) windowNumber=\(windowNumber) result=skipped-invalid-window"
            )
            return
        }
        guard let connectionID = mainConnectionID?(),
              let getWindowLevel else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevelVerify label=\(label) windowNumber=\(windowNumber) result=unavailable"
            )
            return
        }
        var observedLevel: Int32 = 0
        let error = getWindowLevel(connectionID, UInt32(windowNumber), &observedLevel)
        guard error == 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevelVerify label=\(label) windowNumber=\(windowNumber) result=error:\(error)"
            )
            return
        }
        WallpaperPlaybackDiagnostics.log(
            "windowLevelVerify label=\(label) windowNumber=\(windowNumber) observedLevel=\(observedLevel) targetLevel=\(WindowServerWindowLevelExperiment.targetLevel) result=ok"
        )
    }

    private func setLevel(_ level: Int32, to windowNumber: Int, operation: String) -> Bool {
        guard windowNumber > 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevel operation=\(operation) windowNumber=\(windowNumber) targetLevel=\(level) result=skipped-invalid-window"
            )
            return false
        }
        guard let connectionID = mainConnectionID?(),
              let setWindowLevel,
              let setWindowLevelSymbolName else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevel operation=\(operation) windowNumber=\(windowNumber) targetLevel=\(level) result=unavailable"
            )
            return false
        }

        let error = setWindowLevel(connectionID, UInt32(windowNumber), level)
        guard error == 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowLevel operation=\(operation) symbol=\(setWindowLevelSymbolName) windowNumber=\(windowNumber) targetLevel=\(level) result=error:\(error)"
            )
            return false
        }
        WallpaperPlaybackDiagnostics.log(
            "windowLevel operation=\(operation) symbol=\(setWindowLevelSymbolName) windowNumber=\(windowNumber) targetLevel=\(level) result=ok"
        )
        return true
    }

    private static func openSkyLight() -> UnsafeMutableRawPointer? {
        if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) {
            return handle
        }
        return dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
    }

    private static func load<T>(
        _ symbol: String,
        from handle: UnsafeMutableRawPointer?,
        as type: T.Type
    ) -> T? {
        guard let handle,
              let pointer = dlsym(handle, symbol) else {
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
