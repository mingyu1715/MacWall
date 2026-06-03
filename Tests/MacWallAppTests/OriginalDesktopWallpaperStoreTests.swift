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
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.0), ["main"])
        XCTAssertEqual(restored.map(\.1), [url("original.png")])
        XCTAssertEqual(store.records, [:])
    }

    func testSecondDeployDoesNotOverwriteOriginalWallpaper() throws {
        let source = SnapshotSource([
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-b.png"))
        store.recordAppAppliedFallback(url("fallback-b.png"))
        source.snapshots = [
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("fallback-b.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.1), [url("original.png")])
    }

    func testStopDoesNotOverwriteUserChangedWallpaper() throws {
        let source = SnapshotSource([
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("original.png"))
        ])
        var restored: [(String, URL)] = []
        let store = makeStore(current: { source.snapshots }, restored: { restored.append(($1, $0)) })

        _ = store.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        store.recordAppAppliedFallback(url("fallback-a.png"))
        source.snapshots = [
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("user-choice.png"))
        ]
        store.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertTrue(restored.isEmpty)
    }

    func testPersistedSessionRestoresAfterStoreRecreation() throws {
        let defaults = try makeUserDefaults()
        let source = SnapshotSource([
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("original.png"))
        ])
        let first = OriginalDesktopWallpaperStore(
            userDefaults: defaults,
            currentWallpapers: { source.snapshots },
            restoreWallpaper: { _, _ in }
        )
        _ = first.captureOriginalWallpaperIfNeeded(beforeApplyingFallback: url("fallback-a.png"))
        first.recordAppAppliedFallback(url("fallback-a.png"))

        var restored: [(String, URL)] = []
        source.snapshots = [
            DesktopWallpaperSnapshot(screenID: "main", wallpaperURL: url("fallback-a.png"))
        ]
        let second = OriginalDesktopWallpaperStore(
            userDefaults: defaults,
            currentWallpapers: { source.snapshots },
            restoreWallpaper: { restored.append(($1, $0)) }
        )

        second.restoreOriginalWallpaperIfCurrentMatchesManagedFallback()

        XCTAssertEqual(restored.map(\.1), [url("original.png")])
        XCTAssertEqual(second.records, [:])
    }

    private func makeStore(
        current: @escaping @MainActor () -> [DesktopWallpaperSnapshot],
        restored: @escaping @MainActor (URL, String) -> Void
    ) -> OriginalDesktopWallpaperStore {
        OriginalDesktopWallpaperStore(
            userDefaults: try! makeUserDefaults(),
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
