import XCTest

final class DesktopFallbackMenuTests: XCTestCase {
    func testPlaybackStartsLivePlayerBeforeFallbackSideEffects() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/App/AppViewModel.swift"
        )
        let methodStart = try XCTUnwrap(source.range(of: "private func play(asset:"))
        let methodEnd = try XCTUnwrap(
            source.range(
                of: "private func refreshLockScreenAnimationConfiguration",
                range: methodStart.lowerBound..<source.endIndex
            )
        )
        let body = String(source[methodStart.lowerBound..<methodEnd.lowerBound])
        let play = try XCTUnwrap(body.range(of: "WallpaperPlayer.shared.play"))
        let applyOrGenerate = try XCTUnwrap(body.range(of: "desktopFallbackCoordinator.applyOrGenerate"))

        XCTAssertFalse(body.contains("desktopFallbackCoordinator.prepareForPlayback"))
        XCTAssertLessThan(play.lowerBound, applyOrGenerate.lowerBound)
    }

    func testPlaybackFailureAndStopClearActiveFallbackAsset() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/App/AppViewModel.swift"
        )

        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "desktopFallbackCoordinator.clearActiveAsset()").count - 1,
            2
        )
    }

    func testRemoveAndReimportInvalidateOlderFallbackGeneration() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/App/AppViewModel.swift"
        )

        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "desktopFallbackCoordinator.invalidate(asset:").count - 1,
            2
        )
    }

    func testLibraryItemMenuExposesFinderGenerateRegenerateAndRemove() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/UI/ContentView.swift"
        )

        XCTAssertTrue(source.contains(#"Button("Show in Finder")"#))
        XCTAssertTrue(source.contains(#"Button("Regenerate Desktop Fallback")"#))
        XCTAssertTrue(source.contains(#"Button("Generate Desktop Fallback")"#))
        XCTAssertTrue(source.contains(#"Button("Remove")"#))
    }
}
