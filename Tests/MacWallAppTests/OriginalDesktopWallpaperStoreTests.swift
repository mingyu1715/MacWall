import XCTest
@testable import MacWallApp

@MainActor
final class OriginalDesktopWallpaperStoreTests: XCTestCase {
    func testRestoreWithoutManagedFallbackIsNoOp() throws {
        let source = SnapshotSource([
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })

        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(store.records, [:])
    }

    func testCapturesOriginalBeforeApplyingFallbackAndRestoresOnStop() throws {
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })
        store.restoreOnStopEnabled = true

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.0), ["main"])
        XCTAssertEqual(restored.map(\.1), [url("original.png")])
        XCTAssertEqual(store.records, [:])
    }

    func testSecondDeployDoesNotOverwriteOriginalWallpaper() throws {
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })
        store.restoreOnStopEnabled = true

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-b.png"))
        store.recordAppAppliedFallback(url("fallback-b.png"))
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("fallback-b.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.1), [url("original.png")])
    }

    func testStopDoesNotOverwriteUserChangedWallpaper() throws {
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })
        store.restoreOnStopEnabled = true

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("user-choice.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertTrue(restored.isEmpty)
    }

    func testPersistedSessionRestoresAfterStoreRecreation() throws {
        let defaults = try makeUserDefaults()
        let storageDirectory = try makeTempDirectory()
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        let first = OriginalDesktopWallpaperStore(
            userDefaults: defaults,
            storageDirectory: storageDirectory,
            currentWallpapers: { source.snapshots },
            restoreWallpaper: { _, _ in }
        )
        first.restoreOnStopEnabled = true
        _ = first.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        first.recordAppAppliedFallback(url("fallback-a.png"))

        var restored: [(String, URL)] = []
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        let second = OriginalDesktopWallpaperStore(
            userDefaults: defaults,
            storageDirectory: storageDirectory,
            currentWallpapers: { source.snapshots },
            restoreWallpaper: { restored.append(($1, $0)) }
        )
        second.restoreOnStopEnabled = true

        second.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.1), [url("original.png")])
        XCTAssertEqual(second.records, [:])
    }

    func testRestoreOptionOffDoesNotCaptureOrRestore() throws {
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(store.records, [:])
        XCTAssertTrue(restored.isEmpty)
    }

    func testAppleManagedWallpaperIsNotCapturedAsStaleStaticURL() throws {
        let source = SnapshotSource([
            .appleManaged(
                screenID: "main",
                provider: "com.apple.wallpaper.choice.macintosh",
                staleWorkspaceURL: url("stale.jpg")
            )
        ])
        let store = makeStore(current: { source.snapshots }, restored: { _, _ in })
        store.restoreOnStopEnabled = true

        let support = store.currentRestoreSupport()
        let token = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))

        XCTAssertFalse(support.isRestorable)
        XCTAssertTrue(support.warningMessage?.contains("macOS dynamic or built-in wallpaper") == true)
        XCTAssertEqual(token.capturedScreenIDs, [])
        XCTAssertEqual(store.records, [:])
    }

    func testStateIsWrittenToApplicationSupportStyleRestoreCacheFile() throws {
        let storageDirectory = try makeTempDirectory()
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: url("original.png"))
        ])
        let store = makeStore(
            storageDirectory: storageDirectory,
            current: { source.snapshots },
            restored: { _, _ in }
        )
        store.restoreOnStopEnabled = true

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))

        let stateFile = storageDirectory
            .appending(path: "DesktopWallpaperRestore")
            .appending(path: "restore-state-v2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateFile.path))
    }

    func testRestoresFromCachedOriginalWhenOriginalImageFileDisappears() throws {
        let storageDirectory = try makeTempDirectory()
        let original = storageDirectory.appending(path: "original.jpg")
        try Data("original-image".utf8).write(to: original)
        let fallback = storageDirectory.appending(path: "desktop-fallback.png")
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: original)
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(
            storageDirectory: storageDirectory,
            current: { source.snapshots },
            restored: { restored.append(($1, $0)) }
        )
        store.restoreOnStopEnabled = true

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: fallback)
        store.recordAppAppliedFallback(fallback)
        try FileManager.default.removeItem(at: original)
        source.snapshots = [
            .staticImage(screenID: "main", wallpaperURL: fallback)
        ]

        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        let restoredURL = try XCTUnwrap(restored.first?.1)
        XCTAssertEqual(restored.first?.0, "main")
        XCTAssertTrue(restoredURL.path.hasPrefix(storageDirectory.appending(path: "DesktopWallpaperRestore/Originals").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredURL.path))
        XCTAssertEqual(try Data(contentsOf: restoredURL), Data("original-image".utf8))
        XCTAssertEqual(store.records, [:])
    }

    func testDoesNotCaptureMacWallFallbackCacheAsOriginalWallpaper() throws {
        let storageDirectory = try makeTempDirectory()
        let previousFallback = storageDirectory
            .appending(path: "Assets")
            .appending(path: "id-previous")
            .appending(path: "Derived")
            .appending(path: "desktop-fallback.png")
        try FileManager.default.createDirectory(
            at: previousFallback.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("previous-fallback".utf8).write(to: previousFallback)
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: previousFallback)
        ])
        let store = makeStore(
            storageDirectory: storageDirectory,
            current: { source.snapshots },
            restored: { _, _ in }
        )
        store.restoreOnStopEnabled = true

        let token = store.captureOriginalWallpaperIfNeeded(
            beforeApplyingFallback: storageDirectory.appending(path: "next-fallback.png")
        )

        XCTAssertEqual(token.capturedScreenIDs, [])
        XCTAssertEqual(store.records, [:])
    }

    func testAbandonManagedSessionRemovesStateWithoutRestoringWallpaper() throws {
        let storageDirectory = try makeTempDirectory()
        let original = storageDirectory.appending(path: "original.jpg")
        try Data("original".utf8).write(to: original)
        let fallback = storageDirectory
            .appending(path: "Assets/id/Derived/desktop-fallback.png")
        try FileManager.default.createDirectory(
            at: fallback.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fallback".utf8).write(to: fallback)
        let source = SnapshotSource([
            .staticImage(screenID: "main", wallpaperURL: original)
        ])
        var restored: [URL] = []
        let store = makeStore(
            storageDirectory: storageDirectory,
            current: { source.snapshots },
            restored: { url, _ in restored.append(url) }
        )
        store.restoreOnStopEnabled = true
        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: fallback)
        store.recordAppAppliedFallback(fallback)
        let cachedOriginal = try XCTUnwrap(
            store.records["main"]?.cachedOriginalWallpaperURL
        )

        store.abandonManagedWallpaperSession()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedOriginal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fallback.path))
    }

    private func makeStore(
        storageDirectory: URL? = nil,
        current: @escaping @MainActor () -> [DesktopWallpaperSnapshot],
        restored: @escaping @MainActor (URL, String) -> Void
    ) -> OriginalDesktopWallpaperStore {
        OriginalDesktopWallpaperStore(
            userDefaults: try! makeUserDefaults(),
            storageDirectory: storageDirectory ?? (try! makeTempDirectory()),
            currentWallpapers: current,
            restoreWallpaper: restored
        )
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "MacWallOriginalWallpaperStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MacWallOriginalWallpaperStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func url(_ filename: String) -> URL {
        URL(filePath: "/tmp/\(filename)")
    }
}

@MainActor
private final class SnapshotSource {
    var snapshots: [DesktopWallpaperSnapshot]

    init(_ snapshots: [DesktopWallpaperSnapshot]) {
        self.snapshots = snapshots
    }
}

private extension DesktopWallpaperSnapshot {
    static func staticImage(screenID: String, wallpaperURL: URL) -> DesktopWallpaperSnapshot {
        DesktopWallpaperSnapshot(
            screenID: screenID,
            displayUUID: "display-\(screenID)",
            spaceUUID: "",
            provider: "com.apple.wallpaper.choice.image",
            wallpaperURL: wallpaperURL
        )
    }

    static func appleManaged(
        screenID: String,
        provider: String,
        staleWorkspaceURL: URL
    ) -> DesktopWallpaperSnapshot {
        DesktopWallpaperSnapshot(
            screenID: screenID,
            displayUUID: "display-\(screenID)",
            spaceUUID: "",
            provider: provider,
            wallpaperURL: staleWorkspaceURL
        )
    }
}
