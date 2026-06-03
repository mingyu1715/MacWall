import XCTest
@testable import MacWallApp
import MacWallCore

final class PlaybackSessionStateTests: XCTestCase {
    func testStartPlayingStoresSnapshotAndGeneration() {
        var state = PlaybackSessionState()
        let asset = Self.asset(id: "A")

        let snapshot = state.startPlaying(asset: asset, options: .defaults)

        XCTAssertEqual(snapshot.assetId, "A")
        XCTAssertEqual(snapshot.projectDirectory, "/tmp/A")
        XCTAssertEqual(snapshot.phase, .playing)
        XCTAssertEqual(state.activeSnapshot, snapshot)
        XCTAssertEqual(state.generation, snapshot.generation)
    }

    func testSuspendAndResumeAreIdempotent() {
        var state = PlaybackSessionState()
        let asset = Self.asset(id: "A")
        _ = state.startPlaying(asset: asset, options: .defaults)

        state.setSuspended(true)
        state.setSuspended(true)
        XCTAssertEqual(state.activeSnapshot?.phase, .suspended)

        state.setSuspended(false)
        state.setSuspended(false)
        XCTAssertEqual(state.activeSnapshot?.phase, .playing)
    }

    func testRestoreGenerationRejectsStaleCompletion() {
        var state = PlaybackSessionState()
        let first = state.startPlaying(asset: Self.asset(id: "A"), options: .defaults)
        let second = state.startPlaying(asset: Self.asset(id: "B"), options: .defaults)

        XCTAssertFalse(state.isCurrentGeneration(first.generation))
        XCTAssertTrue(state.isCurrentGeneration(second.generation))
    }

    func testStopReturnsToIdle() {
        var state = PlaybackSessionState()
        _ = state.startPlaying(asset: Self.asset(id: "A"), options: .defaults)

        state.stop()

        XCTAssertNil(state.activeSnapshot)
        XCTAssertEqual(state.phase, .idle)
    }

    private static func asset(id: String) -> WallpaperAsset {
        WallpaperAsset(
            id: id,
            title: id,
            kind: .video,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: "/tmp/\(id)",
            entrypoint: "/tmp/\(id)/video.mp4",
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }
}
