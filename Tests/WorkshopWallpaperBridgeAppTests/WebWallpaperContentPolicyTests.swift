import XCTest

final class WebWallpaperContentPolicyTests: XCTestCase {
    func testSharedPolicyBlocksRemoteHTTPAndHTTPSRequests() throws {
        let source = try SourceFixture.contents(
            of: "Sources/WorkshopWallpaperBridgeApp/Playback/WebWallpaperContentPolicy.swift"
        )

        XCTAssertTrue(source.contains(#""url-filter":"^https?://.*""#))
        XCTAssertTrue(source.contains("guard error == nil, let ruleList else"))
    }

    func testLiveWebWallpaperUsesSharedPolicy() throws {
        let source = try SourceFixture.contents(
            of: "Sources/WorkshopWallpaperBridgeApp/Playback/RestrictedWebWallpaperView.swift"
        )

        XCTAssertTrue(source.contains("WebWallpaperContentPolicy.install"))
        XCTAssertFalse(source.contains("compileContentRuleList"))
        XCTAssertFalse(source.contains(#""url-filter":"^https?://.*""#))
    }
}
