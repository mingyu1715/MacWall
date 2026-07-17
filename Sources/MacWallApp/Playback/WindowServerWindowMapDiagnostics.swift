import CoreGraphics
import Darwin
import Foundation

@MainActor
enum WindowServerWindowMapDiagnostics {
    private static let maxEntriesToLog = 120

    static func log(label: String, wallpaperWindowNumbers: [Int]) {
        guard WallpaperPlaybackDiagnostics.isEnabled else {
            return
        }

        let wallpaperWindowSet = Set(wallpaperWindowNumbers)
        let entries = currentWindowEntries()
            .filter { isRelevant($0, wallpaperWindowNumbers: wallpaperWindowSet) }
            .prefix(maxEntriesToLog)
        let windowNumbers = entries.map(\.windowNumber)
        let slsMetadata = SkyLightWindowServerDiagnostics.shared.metadata(for: Array(windowNumbers))
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        WallpaperPlaybackDiagnostics.log(
            [
                "sample=\(label)",
                "windowMapSummary",
                "candidates=\(entries.count)",
                "desktopLevel=\(desktopLevel)",
                "desktopIconLevel=\(desktopIconLevel)",
                SkyLightWindowServerDiagnostics.shared.availabilitySummary
            ].joined(separator: " ")
        )

        for entry in entries {
            let metadata = slsMetadata[entry.windowNumber] ?? .unavailable
            WallpaperPlaybackDiagnostics.log(
                [
                    "sample=\(label)",
                    "windowMap[\(entry.orderIndex)]",
                    "relation=\(entry.relation(wallpaperWindowNumbers: wallpaperWindowSet))",
                    "windowNumber=\(entry.windowNumber)",
                    "owner=\(compact(entry.owner))",
                    "name=\(compact(entry.name))",
                    "cgLayer=\(entry.layer.map(String.init) ?? "nil")",
                    "slsLevel=\(metadata.level)",
                    "slsIteratorLevel=\(metadata.iteratorLevel)",
                    "slsTags=\(metadata.tags)",
                    "slsAttributes=\(metadata.attributes)",
                    "spaces=\(metadata.spaces)",
                    "cgOnscreen=\(entry.isOnscreen)",
                    "cgAlpha=\(entry.alpha)",
                    "cgBounds=\(compact(entry.bounds))"
                ].joined(separator: " ")
            )
        }
    }

    private static func currentWindowEntries() -> [WindowMapEntry] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windows.enumerated().compactMap { index, info in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                return nil
            }
            return WindowMapEntry(
                orderIndex: index,
                windowNumber: number,
                owner: stringValue(info[kCGWindowOwnerName as String]),
                name: stringValue(info[kCGWindowName as String]),
                layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                isOnscreen: stringValue(info[kCGWindowIsOnscreen as String]),
                alpha: stringValue(info[kCGWindowAlpha as String]),
                bounds: stringValue(info[kCGWindowBounds as String])
            )
        }
    }

    private static func isRelevant(_ entry: WindowMapEntry, wallpaperWindowNumbers: Set<Int>) -> Bool {
        let owner = entry.owner.lowercased()
        let name = entry.name.lowercased()
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let isDesktopBand = entry.layer.map {
            (desktopLevel - 5...desktopIconLevel + 5).contains($0)
        } ?? false

        return wallpaperWindowNumbers.contains(Int(entry.windowNumber))
            || owner == "dock"
            || owner == "finder"
            || owner == ProcessInfo.processInfo.processName.lowercased()
            || name.contains("desktop")
            || name.contains("wallpaper")
            || name.contains("picture")
            || isDesktopBand
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }
        return String(describing: value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func compact(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "nil"
        }
        return trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .replacingOccurrences(of: "\"", with: "'")
    }

    private struct WindowMapEntry {
        let orderIndex: Int
        let windowNumber: UInt32
        let owner: String
        let name: String
        let layer: Int?
        let isOnscreen: String
        let alpha: String
        let bounds: String

        func relation(wallpaperWindowNumbers: Set<Int>) -> String {
            var relations: [String] = []
            if wallpaperWindowNumbers.contains(Int(windowNumber)) {
                relations.append("MacWallWallpaper")
            }
            if owner == "Dock" {
                relations.append("Dock")
            }
            if owner == "Finder" {
                relations.append("Finder")
            }
            let lowercasedName = name.lowercased()
            if lowercasedName.contains("desktop") {
                relations.append("DesktopNamed")
            }
            if lowercasedName.contains("wallpaper") || lowercasedName.contains("picture") {
                relations.append("WallpaperNamed")
            }
            return relations.isEmpty ? "Candidate" : relations.joined(separator: "+")
        }
    }
}

@MainActor
private final class SkyLightWindowServerDiagnostics {
    static let shared = SkyLightWindowServerDiagnostics()

    private typealias SLSMainConnectionID = @convention(c) () -> Int32
    private typealias SLSCopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SLSGetWindowLevel = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias SLSWindowQueryWindows = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    private typealias SLSWindowQueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias SLSWindowIteratorGetCount = @convention(c) (CFTypeRef) -> Int32
    private typealias SLSWindowIteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    private typealias SLSWindowIteratorGetWindowID = @convention(c) (CFTypeRef) -> UInt32
    private typealias SLSWindowIteratorGetTags = @convention(c) (CFTypeRef) -> UInt64
    private typealias SLSWindowIteratorGetAttributes = @convention(c) (CFTypeRef) -> UInt64
    private typealias SLSWindowIteratorGetLevel = @convention(c) (CFTypeRef) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let mainConnectionID: SLSMainConnectionID?
    private let copySpacesForWindows: SLSCopySpacesForWindows?
    private let getWindowLevel: SLSGetWindowLevel?
    private let windowQueryWindows: SLSWindowQueryWindows?
    private let windowQueryResultCopyWindows: SLSWindowQueryResultCopyWindows?
    private let windowIteratorGetCount: SLSWindowIteratorGetCount?
    private let windowIteratorAdvance: SLSWindowIteratorAdvance?
    private let windowIteratorGetWindowID: SLSWindowIteratorGetWindowID?
    private let windowIteratorGetTags: SLSWindowIteratorGetTags?
    private let windowIteratorGetAttributes: SLSWindowIteratorGetAttributes?
    private let windowIteratorGetLevel: SLSWindowIteratorGetLevel?

    var availabilitySummary: String {
        [
            "skyLightLoaded=\(handle != nil)",
            "SLSMainConnectionID=\(mainConnectionID != nil)",
            "SLSCopySpacesForWindows=\(copySpacesForWindows != nil)",
            "SLSGetWindowLevel=\(getWindowLevel != nil)",
            "SLSWindowIteratorGetTags=\(windowIteratorGetTags != nil)"
        ].joined(separator: " ")
    }

    private init() {
        let handle = Self.openSkyLight()
        self.handle = handle
        mainConnectionID = Self.load("SLSMainConnectionID", from: handle, as: SLSMainConnectionID.self)
        copySpacesForWindows = Self.load("SLSCopySpacesForWindows", from: handle, as: SLSCopySpacesForWindows.self)
        getWindowLevel = Self.load("SLSGetWindowLevel", from: handle, as: SLSGetWindowLevel.self)
        windowQueryWindows = Self.load("SLSWindowQueryWindows", from: handle, as: SLSWindowQueryWindows.self)
        windowQueryResultCopyWindows = Self.load(
            "SLSWindowQueryResultCopyWindows",
            from: handle,
            as: SLSWindowQueryResultCopyWindows.self
        )
        windowIteratorGetCount = Self.load("SLSWindowIteratorGetCount", from: handle, as: SLSWindowIteratorGetCount.self)
        windowIteratorAdvance = Self.load("SLSWindowIteratorAdvance", from: handle, as: SLSWindowIteratorAdvance.self)
        windowIteratorGetWindowID = Self.load("SLSWindowIteratorGetWindowID", from: handle, as: SLSWindowIteratorGetWindowID.self)
        windowIteratorGetTags = Self.load("SLSWindowIteratorGetTags", from: handle, as: SLSWindowIteratorGetTags.self)
        windowIteratorGetAttributes = Self.load(
            "SLSWindowIteratorGetAttributes",
            from: handle,
            as: SLSWindowIteratorGetAttributes.self
        )
        windowIteratorGetLevel = Self.load("SLSWindowIteratorGetLevel", from: handle, as: SLSWindowIteratorGetLevel.self)
    }

    func metadata(for windowNumbers: [UInt32]) -> [UInt32: SLSWindowMetadata] {
        guard !windowNumbers.isEmpty,
              let connectionID = mainConnectionID?() else {
            return [:]
        }

        var metadata = Dictionary(
            uniqueKeysWithValues: windowNumbers.map { ($0, SLSWindowMetadata.unavailable) }
        )
        for windowNumber in windowNumbers {
            metadata[windowNumber]?.level = level(windowNumber: windowNumber, connectionID: connectionID)
            metadata[windowNumber]?.spaces = spaces(windowNumber: windowNumber, connectionID: connectionID)
        }

        for (windowNumber, iteratorMetadata) in iteratorMetadata(
            windowNumbers: windowNumbers,
            connectionID: connectionID
        ) {
            metadata[windowNumber]?.tags = iteratorMetadata.tags
            metadata[windowNumber]?.attributes = iteratorMetadata.attributes
            metadata[windowNumber]?.iteratorLevel = iteratorMetadata.iteratorLevel
        }
        return metadata
    }

    private func level(windowNumber: UInt32, connectionID: Int32) -> String {
        guard let getWindowLevel else {
            return "unavailable"
        }
        var level: Int32 = 0
        let error = getWindowLevel(connectionID, windowNumber, &level)
        guard error == 0 else {
            return "error:\(error)"
        }
        return String(level)
    }

    private func spaces(windowNumber: UInt32, connectionID: Int32) -> String {
        guard let copySpacesForWindows else {
            return "unavailable"
        }
        let windows = [NSNumber(value: windowNumber)] as CFArray
        guard let unmanagedSpaces = copySpacesForWindows(connectionID, 0x7, windows) else {
            return "nil"
        }
        let spaces = unmanagedSpaces.takeRetainedValue() as NSArray
        let values = spaces.compactMap { ($0 as? NSNumber)?.stringValue }
        return values.isEmpty ? "[]" : "[\(values.joined(separator: ","))]"
    }

    private func iteratorMetadata(
        windowNumbers: [UInt32],
        connectionID: Int32
    ) -> [UInt32: SLSIteratorWindowMetadata] {
        guard let windowQueryWindows,
              let windowQueryResultCopyWindows,
              let windowIteratorGetCount,
              let windowIteratorAdvance,
              let windowIteratorGetWindowID,
              let windowIteratorGetTags,
              let windowIteratorGetAttributes,
              let windowIteratorGetLevel else {
            return [:]
        }

        let windows = windowNumbers.map { NSNumber(value: $0) } as CFArray
        guard let unmanagedQuery = windowQueryWindows(
            connectionID,
            windows,
            Int32(windowNumbers.count)
        ) else {
            return [:]
        }
        let query = unmanagedQuery.takeRetainedValue()
        guard let unmanagedIterator = windowQueryResultCopyWindows(query) else {
            return [:]
        }
        let iterator = unmanagedIterator.takeRetainedValue()
        let count = max(0, Int(windowIteratorGetCount(iterator)))
        var metadata: [UInt32: SLSIteratorWindowMetadata] = [:]

        for _ in 0..<count {
            guard windowIteratorAdvance(iterator) else {
                break
            }
            let windowNumber = windowIteratorGetWindowID(iterator)
            metadata[windowNumber] = SLSIteratorWindowMetadata(
                tags: Self.hex(windowIteratorGetTags(iterator)),
                attributes: Self.hex(windowIteratorGetAttributes(iterator)),
                iteratorLevel: String(windowIteratorGetLevel(iterator))
            )
        }
        return metadata
    }

    private static func openSkyLight() -> UnsafeMutableRawPointer? {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreGraphics.framework/CoreGraphics"
        ]
        for path in paths {
            if let handle = dlopen(path, RTLD_NOW) {
                return handle
            }
        }
        return nil
    }

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as _: T.Type) -> T? {
        guard let handle,
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "0x%016llx", value)
    }
}

struct SLSWindowMetadata {
    var level: String
    var iteratorLevel: String
    var tags: String
    var attributes: String
    var spaces: String

    static let unavailable = SLSWindowMetadata(
        level: "unavailable",
        iteratorLevel: "unavailable",
        tags: "unavailable",
        attributes: "unavailable",
        spaces: "unavailable"
    )
}

private struct SLSIteratorWindowMetadata {
    let tags: String
    let attributes: String
    let iteratorLevel: String
}
