import AppKit
import Foundation

struct DesktopWallpaperSnapshot: Equatable {
    let screenID: String
    let wallpaperURL: URL?
}

struct OriginalDesktopWallpaperRecord: Codable, Equatable {
    var originalWallpaperURL: URL?
    var appAppliedFallbackURL: URL?
    var isManagedWallpaperSession: Bool
}

struct OriginalDesktopWallpaperCaptureToken: Equatable {
    let capturedScreenIDs: Set<String>
}

@MainActor
protocol OriginalDesktopWallpaperManaging: AnyObject {
    @discardableResult
    func captureOriginalWallpaperIfNeeded(beforeApplyingFallback fallbackURL: URL) -> OriginalDesktopWallpaperCaptureToken
    func recordAppAppliedFallback(_ fallbackURL: URL)
    func discardUnappliedFallbackCapture(_ token: OriginalDesktopWallpaperCaptureToken)
    func restoreOriginalWallpaperIfCurrentMatchesManagedFallback()
}

@MainActor
final class OriginalDesktopWallpaperStore: OriginalDesktopWallpaperManaging {
    typealias CurrentWallpapers = @MainActor () -> [DesktopWallpaperSnapshot]
    typealias RestoreWallpaper = @MainActor (URL, String) throws -> Void

    private let userDefaults: UserDefaults
    private let currentWallpapers: CurrentWallpapers
    private let restoreWallpaper: RestoreWallpaper
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "OriginalDesktopWallpaperStore.records.v1",
        currentWallpapers: @escaping CurrentWallpapers = OriginalDesktopWallpaperStore.currentDesktopWallpapers,
        restoreWallpaper: @escaping RestoreWallpaper = OriginalDesktopWallpaperStore.restoreDesktopWallpaper
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.currentWallpapers = currentWallpapers
        self.restoreWallpaper = restoreWallpaper
    }

    var records: [String: OriginalDesktopWallpaperRecord] {
        loadRecords()
    }

    @discardableResult
    func captureOriginalWallpaperIfNeeded(beforeApplyingFallback fallbackURL: URL) -> OriginalDesktopWallpaperCaptureToken {
        var records = loadRecords()
        var capturedScreenIDs: Set<String> = []
        for snapshot in currentWallpapers() {
            if records[snapshot.screenID]?.isManagedWallpaperSession == true {
                continue
            }
            if urlsMatch(snapshot.wallpaperURL, fallbackURL) {
                continue
            }
            records[snapshot.screenID] = OriginalDesktopWallpaperRecord(
                originalWallpaperURL: snapshot.wallpaperURL,
                appAppliedFallbackURL: nil,
                isManagedWallpaperSession: true
            )
            capturedScreenIDs.insert(snapshot.screenID)
        }
        saveRecords(records)
        return OriginalDesktopWallpaperCaptureToken(capturedScreenIDs: capturedScreenIDs)
    }

    func recordAppAppliedFallback(_ fallbackURL: URL) {
        var records = loadRecords()
        for snapshot in currentWallpapers() {
            guard var record = records[snapshot.screenID],
                  record.isManagedWallpaperSession else {
                continue
            }
            record.appAppliedFallbackURL = fallbackURL
            records[snapshot.screenID] = record
        }
        saveRecords(records)
    }

    func discardUnappliedFallbackCapture(_ token: OriginalDesktopWallpaperCaptureToken) {
        guard !token.capturedScreenIDs.isEmpty else {
            return
        }
        var records = loadRecords()
        for screenID in token.capturedScreenIDs {
            guard records[screenID]?.appAppliedFallbackURL == nil else {
                continue
            }
            records.removeValue(forKey: screenID)
        }
        saveRecords(records)
    }

    func restoreOriginalWallpaperIfCurrentMatchesManagedFallback() {
        var records = loadRecords()
        for snapshot in currentWallpapers() {
            guard let record = records[snapshot.screenID],
                  record.isManagedWallpaperSession,
                  let appAppliedFallbackURL = record.appAppliedFallbackURL,
                  let originalWallpaperURL = record.originalWallpaperURL,
                  urlsMatch(snapshot.wallpaperURL, appAppliedFallbackURL) else {
                continue
            }
            do {
                try restoreWallpaper(originalWallpaperURL, snapshot.screenID)
                records.removeValue(forKey: snapshot.screenID)
            } catch {
                continue
            }
        }
        saveRecords(records)
    }

    private func loadRecords() -> [String: OriginalDesktopWallpaperRecord] {
        guard let data = userDefaults.data(forKey: key) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: OriginalDesktopWallpaperRecord].self, from: data)) ?? [:]
    }

    private func saveRecords(_ records: [String: OriginalDesktopWallpaperRecord]) {
        guard !records.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(records) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func urlsMatch(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        return Self.normalizedURLKey(lhs) == Self.normalizedURLKey(rhs)
    }

    private func urlsMatch(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else {
            return false
        }
        return Self.normalizedURLKey(lhs) == Self.normalizedURLKey(rhs)
    }

    private static func currentDesktopWallpapers() -> [DesktopWallpaperSnapshot] {
        NSScreen.screens.map { screen in
            DesktopWallpaperSnapshot(
                screenID: screenID(for: screen),
                wallpaperURL: NSWorkspace.shared.desktopImageURL(for: screen)
            )
        }
    }

    private static func restoreDesktopWallpaper(_ url: URL, screenID: String) throws {
        guard let screen = NSScreen.screens.first(where: { Self.screenID(for: $0) == screenID }) else {
            return
        }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let displayID = screen.deviceDescription[key] as? NSNumber {
            return displayID.stringValue
        }
        return screen.localizedName
    }

    private static func normalizedURLKey(_ url: URL) -> String {
        if url.isFileURL {
            return url.standardizedFileURL.path
        }
        return url.absoluteString
    }
}
