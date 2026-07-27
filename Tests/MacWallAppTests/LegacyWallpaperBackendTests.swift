import XCTest
@testable import MacWallApp
import MacWallCore

@MainActor
final class LegacyWallpaperBackendTests: XCTestCase {
    func testFallbackRunsOnlyAfterPlayerSuccess() throws {
        let events = LegacyEventLog()
        let player = LegacyMockWallpaperPlayer(events: events)
        let fallback = LegacyMockFallbackCoordinator(events: events)
        let backend = LegacyWallpaperBackend(
            wallpaperPlayer: player,
            fallbackCoordinator: fallback,
            spaceRefreshCoordinator: LegacyMockSpaceRefreshCoordinator(events: events)
        )

        _ = try backend.play(asset: Self.asset(), options: .defaults)

        XCTAssertEqual(events.values, ["player-play", "space-active", "fallback-apply"])
    }

    func testPlayerFailureDoesNotApplyFallback() {
        let events = LegacyEventLog()
        let player = LegacyMockWallpaperPlayer(events: events)
        player.error = LegacyTestError.expected
        let fallback = LegacyMockFallbackCoordinator(events: events)
        let backend = LegacyWallpaperBackend(
            wallpaperPlayer: player,
            fallbackCoordinator: fallback,
            spaceRefreshCoordinator: LegacyMockSpaceRefreshCoordinator(events: events)
        )

        XCTAssertThrowsError(try backend.play(asset: Self.asset(), options: .defaults))

        XCTAssertFalse(events.values.contains("fallback-apply"))
    }

    func testHandoffToNativeAbandonsWithoutRestoring() throws {
        let events = LegacyEventLog()
        let backend = LegacyWallpaperBackend(
            wallpaperPlayer: LegacyMockWallpaperPlayer(events: events),
            fallbackCoordinator: LegacyMockFallbackCoordinator(events: events),
            spaceRefreshCoordinator: LegacyMockSpaceRefreshCoordinator(events: events)
        )
        _ = try backend.play(asset: Self.asset(), options: .defaults)
        events.values.removeAll()

        backend.stop(reason: .handoffToNative)

        XCTAssertEqual(
            events.values,
            ["player-stop", "fallback-clear", "space-clear", "fallback-abandon"]
        )
        XCTAssertFalse(events.values.contains("fallback-restore"))
    }

    func testUserStopRestoresManagedWallpaper() throws {
        let events = LegacyEventLog()
        let backend = LegacyWallpaperBackend(
            wallpaperPlayer: LegacyMockWallpaperPlayer(events: events),
            fallbackCoordinator: LegacyMockFallbackCoordinator(events: events),
            spaceRefreshCoordinator: LegacyMockSpaceRefreshCoordinator(events: events)
        )
        _ = try backend.play(asset: Self.asset(), options: .defaults)
        events.values.removeAll()

        backend.stop(reason: .userStop)

        XCTAssertEqual(
            events.values,
            ["player-stop", "fallback-clear", "space-clear", "fallback-restore"]
        )
    }

    private static func asset() -> WallpaperAsset {
        WallpaperAsset(
            id: "legacy",
            title: "Legacy",
            kind: .web,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: "/tmp/legacy",
            entrypoint: "/tmp/legacy/index.html",
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }
}

@MainActor
private final class LegacyMockWallpaperPlayer: WallpaperPlayerManaging {
    var activeSessionSnapshot: PlaybackSessionSnapshot?
    var error: Error?
    private let events: LegacyEventLog

    init(events: LegacyEventLog) {
        self.events = events
    }

    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool,
        displayMode: WallpaperDisplayMode
    ) throws -> PlaybackSessionSnapshot {
        events.values.append("player-play")
        if let error {
            throw error
        }
        let snapshot = PlaybackSessionSnapshot(
            assetId: asset.id,
            projectDirectory: asset.projectDirectory,
            phase: .playing,
            generation: 1,
            options: .defaults
        )
        activeSessionSnapshot = snapshot
        return snapshot
    }

    func stop() {
        events.values.append("player-stop")
        activeSessionSnapshot = nil
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {}
    func setAutoPauseWhenCovered(_ enabled: Bool) {}
    func setExperimentalSceneRendering(_ enabled: Bool) {}
    func setWebMouseInteractionEnabled(_ enabled: Bool) {}
}

@MainActor
private final class LegacyMockFallbackCoordinator: DesktopFallbackCoordinating {
    private let events: LegacyEventLog

    init(events: LegacyEventLog) {
        self.events = events
    }

    func setRestoreOriginalWallpaperOnStop(_ enabled: Bool) {}
    func currentRestoreSupport() -> DesktopWallpaperRestoreSupport { .restorable }
    func synchronizeRestoreSessionWithCurrentWallpaper() {}
    func clearActiveAsset() { events.values.append("fallback-clear") }
    func hasCache(for asset: WallpaperAsset) -> Bool { false }

    func applyOrGenerate(asset: WallpaperAsset) -> DesktopWallpaperRestoreSupport {
        events.values.append("fallback-apply")
        return .restorable
    }

    func invalidate(asset: WallpaperAsset) {}
    func generate(asset: WallpaperAsset) async throws {}
    func regenerate(asset: WallpaperAsset) async throws {}
    func restoreOriginalWallpaperIfNeeded() { events.values.append("fallback-restore") }
    func abandonManagedWallpaperSession() { events.values.append("fallback-abandon") }
}

@MainActor
private final class LegacyMockSpaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating {
    private let events: LegacyEventLog

    init(events: LegacyEventLog) {
        self.events = events
    }

    func start() {}
    func stop() {}

    func setActiveAsset(_ asset: WallpaperAsset?) {
        events.values.append(asset == nil ? "space-clear" : "space-active")
    }
}

@MainActor
private final class LegacyEventLog {
    var values: [String] = []
}

private enum LegacyTestError: Error {
    case expected
}
