import Darwin
import Foundation

@MainActor
enum WindowServerWindowTagExperiment {
    static let appliesStickyTagToWallpaperWindows = false
}

@MainActor
final class WindowServerWindowTagController {
    static let shared = WindowServerWindowTagController()

    private typealias SLSMainConnectionID = @convention(c) () -> Int32
    private typealias SLSSetWindowTags = @convention(c) (
        Int32,
        UInt32,
        UnsafePointer<UInt64>,
        Int32
    ) -> Int32
    private typealias SLSClearWindowTags = @convention(c) (
        Int32,
        UInt32,
        UnsafePointer<UInt64>,
        Int32
    ) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let mainConnectionID: SLSMainConnectionID?
    private let setWindowTags: SLSSetWindowTags?
    private let clearWindowTags: SLSClearWindowTags?

    private init() {
        let handle = Self.openSkyLight()
        self.handle = handle
        mainConnectionID = Self.load("SLSMainConnectionID", from: handle, as: SLSMainConnectionID.self)
        setWindowTags = Self.load("SLSSetWindowTags", from: handle, as: SLSSetWindowTags.self)
        clearWindowTags = Self.load("SLSClearWindowTags", from: handle, as: SLSClearWindowTags.self)
    }

    @discardableResult
    func applyStickyTag(to windowNumber: Int) -> Bool {
        guard WindowServerWindowTagExperiment.appliesStickyTagToWallpaperWindows else {
            return false
        }
        return mutateStickyTag(
            windowNumber: windowNumber,
            operationName: "SLSSetWindowTags",
            operation: setWindowTags
        )
    }

    func clearStickyTag(from windowNumber: Int) {
        guard WindowServerWindowTagExperiment.appliesStickyTagToWallpaperWindows else {
            return
        }
        _ = mutateStickyTag(
            windowNumber: windowNumber,
            operationName: "SLSClearWindowTags",
            operation: clearWindowTags
        )
    }

    private func mutateStickyTag(
        windowNumber: Int,
        operationName: String,
        operation: ((Int32, UInt32, UnsafePointer<UInt64>, Int32) -> Int32)?
    ) -> Bool {
        guard windowNumber > 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowTag operation=\(operationName) windowNumber=\(windowNumber) result=skipped-invalid-window"
            )
            return false
        }
        guard let connectionID = mainConnectionID?(), let operation else {
            WallpaperPlaybackDiagnostics.log(
                "windowTag operation=\(operationName) windowNumber=\(windowNumber) result=unavailable"
            )
            return false
        }

        let tagWords: [UInt64] = [UInt64(1 << 11), 0]
        let error = tagWords.withUnsafeBufferPointer { pointer in
            operation(connectionID, UInt32(windowNumber), pointer.baseAddress!, Int32(tagWords.count))
        }
        guard error == 0 else {
            WallpaperPlaybackDiagnostics.log(
                "windowTag operation=\(operationName) windowNumber=\(windowNumber) result=error:\(error)"
            )
            return false
        }
        WallpaperPlaybackDiagnostics.log(
            "windowTag operation=\(operationName) windowNumber=\(windowNumber) result=ok tagWords=\(tagWords)"
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
