import Foundation
import XCTest

final class WallpaperPlayerSuspensionTests: XCTestCase {
    func testAutoPauseDoesNotHideWallpaperWindow() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertFalse(
            source.contains("window.orderOut(nil)"),
            "Auto-pause should pause wallpaper media, not hide the desktop-layer wallpaper window."
        )
    }

    func testDisplayModeChangeDoesNotRecreateWallpaperWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")
        let start = try XCTUnwrap(source.range(of: "func setDisplayMode"))
        let end = try XCTUnwrap(source.range(of: "func setAutoPauseWhenCovered"))
        let body = String(source[start.lowerBound..<end.lowerBound])

        // Then
        XCTAssertFalse(body.contains("reopen("))
        XCTAssertFalse(body.contains("closeWindows("))
    }

    func testWindowClosePreparesWallpaperContentBeforeClosing() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")
        let windowStart = try XCTUnwrap(source.range(of: "private final class WallpaperWindow"))
        let start = try XCTUnwrap(source.range(of: "func close()", range: windowStart.lowerBound..<source.endIndex))
        let end = try XCTUnwrap(source.range(of: "func setSuspended", range: start.lowerBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])

        // Then
        XCTAssertTrue(body.contains("prepareForClose()"))
        XCTAssertTrue(body.contains("window.contentView = nil"))
    }

    func testVideoWallpaperStartsPlaybackAfterAttachingToWindow() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/VideoWallpaperView.swift")

        // Then
        XCTAssertTrue(source.contains("override func viewDidMoveToWindow()"))
        XCTAssertTrue(source.contains("if window != nil"))
        XCTAssertTrue(source.contains("player.play()"))
    }

    func testWallpaperPlayerExposesLiveFallbackSnapshotsForVideoAndWebOnly() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("func writeActiveDesktopFallbackSnapshot"))
        XCTAssertTrue(source.contains("DesktopFallbackLiveSnapshotting"))
        XCTAssertTrue(source.contains("asset.kind == .video || asset.kind == .web"))
    }

    func testWallpaperWindowsDisableAppKitWindowAnimations() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("window.animationBehavior = .none"))
    }

    func testWallpaperWindowsAreNotReleasedByAppKitWhenClosed() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("window.isReleasedWhenClosed = false"))
    }

    func testWebMouseInteractionOnlyAppliesToWebWallpaperWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("supportsWebMouseInteraction = asset.kind == .web"))
        XCTAssertTrue(source.contains("window.ignoresMouseEvents = !supportsWebMouseInteraction || !enabled"))
    }

    func testSceneWallpaperReceivesPreviewFallback() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/WallpaperPlayer.swift")
        let sceneSource = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/SceneWallpaperView.swift")

        // Then
        XCTAssertTrue(playerSource.contains("let previewURL = asset.thumbnail.map { URL(filePath: $0) }"))
        XCTAssertTrue(playerSource.contains("previewURL: previewURL"))
        XCTAssertTrue(playerSource.contains("return try makeImageContentView(url: previewURL"))
        XCTAssertTrue(sceneSource.contains("private let previewLayer = CALayer()"))
        XCTAssertTrue(sceneSource.contains("sceneLayer.backgroundColor = nil"))
    }

    func testSceneWallpaperAppliesTransformAndOpacityAnimationChannels() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/WorkshopWallpaperBridgeApp/Playback/SceneWallpaperView.swift")

        // Then
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "position")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.scale.x")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.scale.y")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.rotation.z")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "opacity")"#))
    }
}
