import XCTest

final class DesktopFallbackMenuTests: XCTestCase {
    func testNativeBackendDoesNotReferenceDesktopFallback() throws {
        let native = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
        )
        let legacy = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift"
        )

        XCTAssertFalse(native.contains("DesktopFallback"))
        XCTAssertTrue(legacy.contains("fallbackCoordinator.applyOrGenerate"))
        XCTAssertTrue(legacy.contains("fallbackCoordinator.abandonManagedWallpaperSession"))
    }

    func testAppViewModelHasNoExperimentWideFallbackDisableFlag() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/App/AppViewModel.swift"
        )

        XCTAssertFalse(source.contains("DesktopFallbackRuntime"))
        XCTAssertTrue(source.contains("desktopFallbackControlsEnabled"))
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

    func testLibraryItemMenuKeepsFallbackControls() throws {
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
