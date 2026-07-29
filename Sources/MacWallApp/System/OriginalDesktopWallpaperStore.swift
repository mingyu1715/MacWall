import AppKit
import CoreGraphics
import Foundation

struct DesktopWallpaperSnapshot: Equatable {
    let screenID: String
    let displayUUID: String?
    let spaceUUID: String?
    let provider: String?
    let wallpaperURL: URL?

    init(
        screenID: String,
        displayUUID: String? = nil,
        spaceUUID: String? = nil,
        provider: String? = nil,
        wallpaperURL: URL?
    ) {
        self.screenID = screenID
        self.displayUUID = displayUUID
        self.spaceUUID = spaceUUID
        self.provider = provider
        self.wallpaperURL = wallpaperURL
    }

    var originalKind: DesktopWallpaperOriginalKind {
        guard let provider else {
            return wallpaperURL == nil ? .unknown : .staticImage
        }
        if provider == "com.apple.wallpaper.choice.image" {
            return wallpaperURL == nil ? .unknown : .staticImage
        }
        return .appleManagedUnsupported
    }
}

enum DesktopWallpaperOriginalKind: String, Codable, Equatable {
    case staticImage
    case appleManagedUnsupported
    case unknown
}

struct DesktopWallpaperRestoreSupport: Equatable {
    let warningMessage: String?

    var isRestorable: Bool {
        warningMessage == nil
    }

    static let restorable = DesktopWallpaperRestoreSupport(warningMessage: nil)

    static func unsupported(_ message: String) -> DesktopWallpaperRestoreSupport {
        DesktopWallpaperRestoreSupport(warningMessage: message)
    }
}

struct OriginalDesktopWallpaperRecord: Codable, Equatable {
    var screenID: String
    var displayUUID: String?
    var spaceUUID: String?
    var originalKind: DesktopWallpaperOriginalKind
    var provider: String?
    var originalWallpaperURL: URL?
    var cachedOriginalWallpaperURL: URL?
    var appAppliedFallbackURL: URL?
    var isManagedWallpaperSession: Bool
    var capturedAt: Date?
    var fallbackAppliedAt: Date?
}

struct OriginalDesktopWallpaperCaptureToken: Equatable {
    let capturedScreenIDs: Set<String>
    var warningMessage: String? = nil
}

@MainActor
protocol OriginalDesktopWallpaperManaging: AnyObject {
    var restoreOnStopEnabled: Bool { get set }
    func currentRestoreSupport() -> DesktopWallpaperRestoreSupport
    @discardableResult
    func captureOriginalWallpaperIfNeeded(beforeApplyingFallback fallbackURL: URL) -> OriginalDesktopWallpaperCaptureToken
    func recordAppAppliedFallback(_ fallbackURL: URL)
    func discardUnappliedFallbackCapture(_ token: OriginalDesktopWallpaperCaptureToken)
    func synchronizeRestoreSessionWithCurrentWallpaper()
    func restoreOriginalWallpaperIfCurrentMatchesManagedFallback()
    func abandonManagedWallpaperSession()
}

@MainActor
final class OriginalDesktopWallpaperStore: OriginalDesktopWallpaperManaging {
    typealias CurrentWallpapers = @MainActor () -> [DesktopWallpaperSnapshot]
    typealias RestoreWallpaper = @MainActor (URL, String) throws -> Void

    private let currentWallpapers: CurrentWallpapers
    private let restoreWallpaper: RestoreWallpaper
    private let storageDirectory: URL
    private let fileManager: FileManager

    var restoreOnStopEnabled = false

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "OriginalDesktopWallpaperStore.records.v1",
        storageDirectory: URL? = nil,
        fileManager: FileManager = .default,
        currentWallpapers: @escaping CurrentWallpapers = OriginalDesktopWallpaperStore.currentDesktopWallpapers,
        restoreWallpaper: @escaping RestoreWallpaper = OriginalDesktopWallpaperStore.restoreDesktopWallpaper
    ) {
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory()
        self.fileManager = fileManager
        self.currentWallpapers = currentWallpapers
        self.restoreWallpaper = restoreWallpaper
        userDefaults.removeObject(forKey: key)
    }

    var records: [String: OriginalDesktopWallpaperRecord] {
        loadRecords()
    }

    func currentRestoreSupport() -> DesktopWallpaperRestoreSupport {
        let snapshots = currentWallpapers()
        guard !snapshots.isEmpty else {
            return .unsupported("Current macOS wallpaper could not be inspected, so Stop cannot restore it automatically.")
        }
        guard let unsupported = snapshots.first(where: { $0.originalKind != .staticImage }) else {
            return .restorable
        }
        let providerDescription = unsupported.provider.map { " (\($0))" } ?? ""
        return .unsupported(
            "Current macOS dynamic or built-in wallpaper\(providerDescription) cannot be restored automatically. "
                + "Stop will skip original wallpaper restore for this session."
        )
    }

    @discardableResult
    func captureOriginalWallpaperIfNeeded(beforeApplyingFallback fallbackURL: URL) -> OriginalDesktopWallpaperCaptureToken {
        guard restoreOnStopEnabled else {
            return OriginalDesktopWallpaperCaptureToken(capturedScreenIDs: [])
        }
        var records = loadRecords()
        var capturedScreenIDs: Set<String> = []
        var warningMessage: String?
        for snapshot in currentWallpapers() {
            if records[snapshot.screenID]?.isManagedWallpaperSession == true {
                continue
            }
            if urlsMatch(snapshot.wallpaperURL, fallbackURL) {
                continue
            }
            guard snapshot.originalKind == .staticImage,
                  let originalWallpaperURL = snapshot.wallpaperURL else {
                warningMessage = currentRestoreSupport().warningMessage
                continue
            }
            guard !isMacWallDesktopFallbackURL(originalWallpaperURL) else {
                continue
            }
            records[snapshot.screenID] = OriginalDesktopWallpaperRecord(
                screenID: snapshot.screenID,
                displayUUID: snapshot.displayUUID,
                spaceUUID: snapshot.spaceUUID,
                originalKind: .staticImage,
                provider: snapshot.provider,
                originalWallpaperURL: originalWallpaperURL,
                cachedOriginalWallpaperURL: cacheOriginalWallpaperIfPossible(
                    originalWallpaperURL,
                    screenID: snapshot.screenID
                ),
                appAppliedFallbackURL: nil,
                isManagedWallpaperSession: true,
                capturedAt: Date(),
                fallbackAppliedAt: nil
            )
            capturedScreenIDs.insert(snapshot.screenID)
        }
        saveRecords(records)
        return OriginalDesktopWallpaperCaptureToken(
            capturedScreenIDs: capturedScreenIDs,
            warningMessage: warningMessage
        )
    }

    func recordAppAppliedFallback(_ fallbackURL: URL) {
        guard restoreOnStopEnabled else {
            return
        }
        var records = loadRecords()
        for (screenID, var record) in records where record.isManagedWallpaperSession {
            record.appAppliedFallbackURL = fallbackURL
            record.fallbackAppliedAt = Date()
            records[screenID] = record
        }
        saveRecords(records)
    }

    func discardUnappliedFallbackCapture(_ token: OriginalDesktopWallpaperCaptureToken) {
        guard !token.capturedScreenIDs.isEmpty else {
            return
        }
        var records = loadRecords()
        for screenID in token.capturedScreenIDs where records[screenID]?.appAppliedFallbackURL == nil {
            removeCachedOriginalIfPresent(records[screenID])
            records.removeValue(forKey: screenID)
        }
        saveRecords(records)
    }

    func synchronizeRestoreSessionWithCurrentWallpaper() {
        guard restoreOnStopEnabled else {
            saveRecords([:])
            return
        }
        var records = loadRecords()
        let snapshots = Dictionary(uniqueKeysWithValues: currentWallpapers().map { ($0.screenID, $0) })
        for (screenID, record) in records {
            guard let appAppliedFallbackURL = record.appAppliedFallbackURL,
                  let snapshot = snapshots[screenID] else {
                continue
            }
            if !urlsMatch(snapshot.wallpaperURL, appAppliedFallbackURL) {
                records.removeValue(forKey: screenID)
            }
        }
        saveRecords(records)
    }

    func restoreOriginalWallpaperIfCurrentMatchesManagedFallback() {
        guard restoreOnStopEnabled else {
            return
        }
        var records = loadRecords()
        for snapshot in currentWallpapers() {
            guard let record = records[snapshot.screenID],
                  record.isManagedWallpaperSession,
                  record.originalKind == .staticImage,
                  let appAppliedFallbackURL = record.appAppliedFallbackURL,
                  let restoreWallpaperURL = restoreURL(for: record),
                  urlsMatch(snapshot.wallpaperURL, appAppliedFallbackURL) else {
                if let record = records[snapshot.screenID],
                   let appAppliedFallbackURL = record.appAppliedFallbackURL,
                   !urlsMatch(snapshot.wallpaperURL, appAppliedFallbackURL) {
                    records.removeValue(forKey: snapshot.screenID)
                }
                continue
            }
            do {
                try restoreWallpaper(restoreWallpaperURL, snapshot.screenID)
                records.removeValue(forKey: snapshot.screenID)
            } catch {
                continue
            }
        }
        saveRecords(records)
    }

    func abandonManagedWallpaperSession() {
        let records = loadRecords()
        for record in records.values where record.isManagedWallpaperSession {
            removeCachedOriginalIfPresent(record)
        }
        saveRecords([:])
        if let contents = try? fileManager.contentsOfDirectory(
            at: originalsDirectoryURL,
            includingPropertiesForKeys: nil
        ), contents.isEmpty {
            try? fileManager.removeItem(at: originalsDirectoryURL)
        }
    }

    private func loadRecords() -> [String: OriginalDesktopWallpaperRecord] {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: OriginalDesktopWallpaperRecord].self, from: data)) ?? [:]
    }

    private func saveRecords(_ records: [String: OriginalDesktopWallpaperRecord]) {
        guard !records.isEmpty else {
            try? fileManager.removeItem(at: stateFileURL)
            return
        }
        try? fileManager.createDirectory(
            at: stateFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        try? data.write(to: stateFileURL, options: [.atomic])
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

    private var stateFileURL: URL {
        storageDirectory
            .appending(path: "DesktopWallpaperRestore")
            .appending(path: "restore-state-v2.json")
    }

    private var originalsDirectoryURL: URL {
        storageDirectory
            .appending(path: "DesktopWallpaperRestore")
            .appending(path: "Originals")
    }

    private func cacheOriginalWallpaperIfPossible(_ url: URL, screenID: String) -> URL? {
        guard url.isFileURL,
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let fileExtension = url.pathExtension.isEmpty ? "image" : url.pathExtension
        let output = originalsDirectoryURL
            .appending(path: "\(safeFileName(screenID))-\(UUID().uuidString).\(fileExtension)")
        do {
            try fileManager.createDirectory(at: originalsDirectoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: output)
            return output
        } catch {
            try? fileManager.removeItem(at: output)
            return nil
        }
    }

    private func restoreURL(for record: OriginalDesktopWallpaperRecord) -> URL? {
        if let cached = record.cachedOriginalWallpaperURL,
           fileManager.fileExists(atPath: cached.path) {
            return cached
        }
        return record.originalWallpaperURL
    }

    private func removeCachedOriginalIfPresent(_ record: OriginalDesktopWallpaperRecord?) {
        guard let cached = record?.cachedOriginalWallpaperURL else {
            return
        }
        try? fileManager.removeItem(at: cached)
    }

    private func isMacWallDesktopFallbackURL(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.lastPathComponent == "desktop-fallback.png",
              standardized.deletingLastPathComponent().lastPathComponent == "Derived" else {
            return false
        }
        let assetsPath = storageDirectory
            .appending(path: "Assets")
            .standardizedFileURL
            .path
        return standardized.path.hasPrefix(assetsPath + "/")
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(scalars)
        return result.isEmpty ? "screen" : result
    }

    private static func currentDesktopWallpapers() -> [DesktopWallpaperSnapshot] {
        DesktopWallpaperStateReader().currentSnapshots()
    }

    private static func restoreDesktopWallpaper(_ url: URL, screenID: String) throws {
        guard let screen = NSScreen.screens.first(where: { Self.screenID(for: $0) == screenID }) else {
            return
        }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
    }

    fileprivate static func screenID(for screen: NSScreen) -> String {
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

    private static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "MacWall")
    }
}

@MainActor
private final class DesktopWallpaperStateReader {
    func currentSnapshots() -> [DesktopWallpaperSnapshot] {
        let spaces = loadPlist(at: spacesPlistURL)
        let index = loadPlist(at: wallpaperIndexURL)
        return NSScreen.screens.map { screen in
            let screenID = OriginalDesktopWallpaperStore.screenID(for: screen)
            let displayUUID = Self.displayUUID(for: screen)
            let spaceUUID = Self.currentSpaceUUID(forDisplayUUID: displayUUID, screen: screen, spaces: spaces)
            let wallpaperEntry = Self.wallpaperEntry(displayUUID: displayUUID, spaceUUID: spaceUUID, index: index)
            let provider = wallpaperEntry.provider
            let workspaceURL = NSWorkspace.shared.desktopImageURL(for: screen)
            let wallpaperURL = provider == nil || provider == "com.apple.wallpaper.choice.image"
                ? wallpaperEntry.wallpaperURL ?? workspaceURL
                : wallpaperEntry.wallpaperURL
            return DesktopWallpaperSnapshot(
                screenID: screenID,
                displayUUID: displayUUID,
                spaceUUID: spaceUUID,
                provider: provider,
                wallpaperURL: wallpaperURL
            )
        }
    }

    private var spacesPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Preferences")
            .appending(path: "com.apple.spaces.plist")
    }

    private var wallpaperIndexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: "com.apple.wallpaper")
            .appending(path: "Store")
            .appending(path: "Index.plist")
    }

    private func loadPlist(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = object as? [String: Any] else {
            return [:]
        }
        return plist
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayNumber = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(displayNumber.uint32Value)) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private static func currentSpaceUUID(
        forDisplayUUID displayUUID: String?,
        screen: NSScreen,
        spaces: [String: Any]
    ) -> String? {
        guard let monitors = spaces["SpacesDisplayConfiguration"]
            .flatMap({ $0 as? [String: Any] })?["Management Data"]
            .flatMap({ $0 as? [String: Any] })?["Monitors"] as? [[String: Any]] else {
            return nil
        }
        let isMain = screen == NSScreen.main
        for monitor in monitors {
            let identifier = monitor["Display Identifier"] as? String
            guard identifier == displayUUID || (isMain && identifier == "Main"),
                  let current = monitor["Current Space"] as? [String: Any] else {
                continue
            }
            return current["uuid"] as? String ?? ""
        }
        return monitors.compactMap { ($0["Current Space"] as? [String: Any])?["uuid"] as? String }.first
    }

    private static func wallpaperEntry(
        displayUUID: String?,
        spaceUUID: String?,
        index: [String: Any]
    ) -> (provider: String?, wallpaperURL: URL?) {
        for entry in wallpaperEntryCandidates(displayUUID: displayUUID, spaceUUID: spaceUUID, index: index) {
            if let summary = summarize(entry: entry) {
                return summary
            }
        }
        return (nil, nil)
    }

    private static func wallpaperEntryCandidates(
        displayUUID: String?,
        spaceUUID: String?,
        index: [String: Any]
    ) -> [[String: Any]] {
        var candidates: [[String: Any]] = []
        let spaces = index["Spaces"] as? [String: Any]
        if let spaceUUID,
           let space = spaces?[spaceUUID] as? [String: Any] {
            if let displayUUID,
               let display = (space["Displays"] as? [String: Any])?[displayUUID] as? [String: Any] {
                candidates.append(display)
            }
            if let fallback = space["Default"] as? [String: Any] {
                candidates.append(fallback)
            }
        }
        if spaceUUID != "",
           let defaultSpace = spaces?[""] as? [String: Any] {
            if let displayUUID,
               let display = (defaultSpace["Displays"] as? [String: Any])?[displayUUID] as? [String: Any] {
                candidates.append(display)
            }
            if let fallback = defaultSpace["Default"] as? [String: Any] {
                candidates.append(fallback)
            }
        }
        if let displayUUID,
           let display = (index["Displays"] as? [String: Any])?[displayUUID] as? [String: Any] {
            candidates.append(display)
        }
        if let systemDefault = index["SystemDefault"] as? [String: Any] {
            candidates.append(systemDefault)
        }
        return candidates
    }

    private static func summarize(entry: [String: Any]) -> (provider: String?, wallpaperURL: URL?)? {
        guard let desktop = entry["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let choice = choices.first else {
            return nil
        }
        let provider = choice["Provider"] as? String
        let url = firstFileURL(in: choice) ?? firstFileURL(in: content)
        return (provider, url)
    }

    private static func firstFileURL(in value: Any) -> URL? {
        if let string = value as? String {
            if string.hasPrefix("file://") {
                return URL(string: string)
            }
            if string.hasPrefix("/") {
                return URL(filePath: string)
            }
            return nil
        }
        if let data = value as? Data,
           let decoded = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return firstFileURL(in: decoded)
        }
        if let dictionary = value as? [String: Any] {
            for key in ["relative", "url", "path", "file", "image"] {
                if let nested = dictionary[key], let url = firstFileURL(in: nested) {
                    return url
                }
            }
            for nested in dictionary.values {
                if let url = firstFileURL(in: nested) {
                    return url
                }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let url = firstFileURL(in: nested) {
                    return url
                }
            }
        }
        return nil
    }
}
