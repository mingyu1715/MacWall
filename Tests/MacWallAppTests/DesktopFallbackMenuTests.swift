import XCTest

final class DesktopFallbackMenuTests: XCTestCase {
    func testExperimentBranchKeepsFallbackSideEffectsBehindDisabledRuntimeFlag() throws {
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
        let play = try XCTUnwrap(body.range(of: "wallpaperPlayer.play"))
        let applyOrGenerate = try XCTUnwrap(body.range(of: "desktopFallbackCoordinator.applyOrGenerate"))

        XCTAssertTrue(source.contains("static let isEnabled = false"))
        XCTAssertTrue(body.contains("if DesktopFallbackRuntime.isEnabled"))
        XCTAssertFalse(body.contains("desktopFallbackCoordinator.prepareForPlayback"))
        XCTAssertLessThan(play.lowerBound, applyOrGenerate.lowerBound)
    }

    func testFallbackCleanupIsGuardedBehindRuntimeFlag() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/App/AppViewModel.swift"
        )

        XCTAssertTrue(source.contains("if DesktopFallbackRuntime.isEnabled"))
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

    func testLibraryItemMenuKeepsFallbackControlsBehindExperimentFlag() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/UI/ContentView.swift"
        )

        XCTAssertTrue(source.contains(#"Button("Show in Finder")"#))
        XCTAssertTrue(source.contains("model.desktopFallbackControlsEnabled"))
        XCTAssertTrue(source.contains(#"Button("Regenerate Desktop Fallback")"#))
        XCTAssertTrue(source.contains(#"Button("Generate Desktop Fallback")"#))
        XCTAssertTrue(source.contains(#"Button("Remove")"#))
    }
}
