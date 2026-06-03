import XCTest

final class RestrictedWebWallpaperViewTests: XCTestCase {
    func testWebWallpaperDoesNotLoadWhenRemoteBlockerCompilationFails() throws {
        let source = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/WebWallpaperContentPolicy.swift"
        )

        XCTAssertTrue(source.contains("guard error == nil, let ruleList else"))
        XCTAssertFalse(source.contains("if let ruleList {"))
    }

    func testWebWallpaperAcceptsFirstMouseClick() throws {
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/RestrictedWebWallpaperView.swift")

        XCTAssertTrue(source.contains("override func acceptsFirstMouse"))
    }

    func testWebWallpaperPausesCSSAnimationsButKeepsVideoPlayingWhenCovered() throws {
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/RestrictedWebWallpaperView.swift")

        XCTAssertTrue(source.contains("animation-play-state:paused!important"))
        XCTAssertTrue(source.contains(#"document.getElementById("macwall-playback-suspension")?.remove()"#))
        XCTAssertTrue(source.contains(#"document.querySelectorAll("audio")"#))
        XCTAssertFalse(source.contains(#"document.querySelectorAll("video,audio")"#))
    }
}
