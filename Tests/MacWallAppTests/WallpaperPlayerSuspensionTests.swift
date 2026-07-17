import Foundation
import XCTest

final class WallpaperPlayerSuspensionTests: XCTestCase {
    func testAutoPauseDoesNotHideWallpaperWindow() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertFalse(
            source.contains("window.orderOut(nil)"),
            "Auto-pause should pause wallpaper media, not hide the desktop-layer wallpaper window."
        )
    }

    func testDisplayModeChangeDoesNotRecreateWallpaperWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let start = try XCTUnwrap(source.range(of: "func setDisplayMode"))
        let end = try XCTUnwrap(source.range(of: "func setAutoPauseWhenCovered"))
        let body = String(source[start.lowerBound..<end.lowerBound])

        // Then
        XCTAssertFalse(body.contains("reopen("))
        XCTAssertFalse(body.contains("closeWindows("))
    }

    func testWindowClosePreparesWallpaperContentBeforeClosing() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
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
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/VideoWallpaperView.swift")

        // Then
        XCTAssertTrue(source.contains("override func viewDidMoveToWindow()"))
        XCTAssertTrue(source.contains("if window != nil"))
        XCTAssertTrue(source.contains("player.play()"))
    }

    func testWallpaperPlayerExposesLiveFallbackSnapshotsForVideoAndWebOnly() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("func writeActiveDesktopFallbackSnapshot"))
        XCTAssertTrue(source.contains("DesktopFallbackLiveSnapshotting"))
        XCTAssertTrue(source.contains("asset.kind == .video || asset.kind == .web"))
    }

    func testWallpaperWindowsDisableAppKitWindowAnimations() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("window.animationBehavior = .none"))
    }

    func testWallpaperWindowsJoinFullScreenSpacesAsAuxiliaryWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains(".fullScreenAuxiliary"))
    }

    func testExperimentBranchWallpaperWindowsDoNotUseStationaryCollectionBehavior() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let line = try XCTUnwrap(
            source
                .split(separator: "\n")
                .first { $0.contains("window.collectionBehavior") }
        )

        // Then
        XCTAssertFalse(line.contains(".stationary"))
    }

    func testExperimentBranchWallpaperWindowsJoinAllApplications() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let line = try XCTUnwrap(
            source
                .split(separator: "\n")
                .first { $0.contains("window.collectionBehavior") }
        )

        // Then
        XCTAssertTrue(line.contains(".canJoinAllApplications"))
    }

    func testExperimentBranchLogsSpaceReturnWindowAndRendererDiagnostics() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let windowMapSource = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/WindowServerWindowMapDiagnostics.swift"
        )
        let videoSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/VideoWallpaperView.swift")
        let webSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/RestrictedWebWallpaperView.swift")

        // Then
        XCTAssertTrue(playerSource.contains("NSWorkspace.activeSpaceDidChangeNotification"))
        XCTAssertTrue(playerSource.contains("CGWindowListCopyWindowInfo"))
        XCTAssertTrue(playerSource.contains("kCGWindowLayer"))
        XCTAssertTrue(playerSource.contains("kCGWindowIsOnscreen"))
        XCTAssertTrue(playerSource.contains("WindowServerWindowMapDiagnostics.log"))
        XCTAssertTrue(windowMapSource.contains("SLSCopySpacesForWindows"))
        XCTAssertTrue(windowMapSource.contains("SLSGetWindowLevel"))
        XCTAssertTrue(windowMapSource.contains("SLSWindowIteratorGetTags"))
        XCTAssertTrue(windowMapSource.contains("dlopen"))
        XCTAssertTrue(windowMapSource.contains("windowMapSummary"))
        XCTAssertTrue(windowMapSource.contains("MacWallWallpaper"))
        XCTAssertTrue(windowMapSource.contains("Dock"))
        XCTAssertTrue(windowMapSource.contains("Finder"))
        XCTAssertTrue(playerSource.contains("window.occlusionState"))
        XCTAssertTrue(playerSource.contains("window.isOnActiveSpace"))
        XCTAssertTrue(playerSource.contains("diagnosticRenderState"))
        XCTAssertTrue(videoSource.contains("diagnosticRenderState"))
        XCTAssertTrue(webSource.contains("diagnosticRenderState"))
    }

    func testExperimentBranchKeepsStickyTagControllerAvailableButDisabled() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let tagSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WindowServerWindowTagController.swift")

        // Then
        XCTAssertTrue(tagSource.contains("appliesStickyTagToWallpaperWindows = false"))
        XCTAssertTrue(playerSource.contains("WindowServerWindowTagController.shared.applyStickyTag"))
        XCTAssertTrue(playerSource.contains("WindowServerWindowTagController.shared.clearStickyTag"))
        XCTAssertTrue(tagSource.contains("SLSSetWindowTags"))
        XCTAssertTrue(tagSource.contains("SLSClearWindowTags"))
        XCTAssertTrue(tagSource.contains("1 << 11"))
        XCTAssertTrue(tagSource.contains("tagWords"))
    }

    func testExperimentBranchAppliesDockHostAdjacentLevelWithoutStickyTag() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let tagSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WindowServerWindowTagController.swift")
        let levelSource = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/WindowServerWindowLevelController.swift"
        )
        let showStart = try XCTUnwrap(playerSource.range(of: "func show()"))
        let showEnd = try XCTUnwrap(playerSource.range(of: "func close()", range: showStart.lowerBound..<playerSource.endIndex))
        let showBody = String(playerSource[showStart.lowerBound..<showEnd.lowerBound])

        // Then
        XCTAssertTrue(tagSource.contains("appliesStickyTagToWallpaperWindows = false"))
        XCTAssertTrue(playerSource.contains("WindowServerWindowLevelController.shared.applyDockHostAdjacentLevel"))
        XCTAssertTrue(playerSource.contains("WindowServerWindowLevelController.shared.restoreOriginalLevel"))
        XCTAssertTrue(playerSource.contains("window.level = NSWindow.Level(rawValue: Int(WindowServerWindowLevelExperiment.targetLevel))"))
        XCTAssertTrue(playerSource.contains("window.level = WallpaperWindowLevel.desktopWallpaper"))
        XCTAssertTrue(playerSource.contains("originalLevel: Int32(WallpaperWindowLevel.desktopWallpaper.rawValue)"))
        XCTAssertEqual(showBody.components(separatedBy: "window.orderFrontRegardless()").count - 1, 1)
        XCTAssertTrue(levelSource.contains("SLSSetWindowLevel"))
        XCTAssertTrue(levelSource.contains("CGSSetWindowLevel"))
        XCTAssertTrue(levelSource.contains("SLSGetWindowLevel"))
        XCTAssertTrue(levelSource.contains("CGWindowLevelForKey(.desktopWindow) + 2"))
        XCTAssertTrue(levelSource.contains("windowLevel operation="))
        XCTAssertTrue(levelSource.contains("verifyLevel(windowNumber: windowNumber, label: \"immediate-after-apply\")"))
        XCTAssertTrue(playerSource.contains("verifyAppliedLevelLater"))
        XCTAssertTrue(playerSource.contains("delayMilliseconds: 100"))
    }

    func testExperimentBranchKeepsFreezeOverlayAvailableButDisabledAfterFailedFeasibility() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let overlaySource = try SourceFixture.contents(
            of: "Sources/MacWallApp/Playback/DesktopTransitionFreezeOverlay.swift"
        )

        // Then
        XCTAssertTrue(playerSource.contains("private let freezeOverlay = DesktopTransitionFreezeOverlay()"))
        XCTAssertTrue(playerSource.contains("presentDesktopTransitionFreezeOverlay(label: \"active-space-change\")"))
        XCTAssertTrue(playerSource.contains("freezeSnapshot()"))
        XCTAssertTrue(playerSource.contains("freezeOverlay.clear()"))
        XCTAssertTrue(overlaySource.contains("static let isEnabled = false"))
        XCTAssertTrue(overlaySource.contains("CGWindowListCreateImage"))
        XCTAssertTrue(overlaySource.contains("NSPanel"))
        XCTAssertFalse(overlaySource.contains(".screenSaver"))
        XCTAssertTrue(overlaySource.contains("WallpaperWindowLevel.desktopWallpaper"))
        XCTAssertTrue(overlaySource.contains(".fullScreenAuxiliary"))
        XCTAssertTrue(overlaySource.contains("orderFrontRegardless()"))
        XCTAssertTrue(overlaySource.contains("Task.sleep"))
        XCTAssertTrue(overlaySource.contains("freezeOverlay operation=present"))
    }

    func testTransactionalReplacementStagesAllWindowsBeforeClosingOldWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let replaceStart = try XCTUnwrap(source.range(of: "func replaceWindows"))
        let replaceEnd = try XCTUnwrap(
            source.range(of: "func makeStagedReplacementWindows", range: replaceStart.lowerBound..<source.endIndex)
        )
        let body = String(source[replaceStart.lowerBound..<replaceEnd.lowerBound])

        // Then
        XCTAssertTrue(body.contains("makeStagedReplacementWindows"))
        XCTAssertTrue(body.contains("showReplacementWindows(replacements)"))
        XCTAssertTrue(body.contains("windows = replacements"))
        XCTAssertTrue(body.contains("closeWindows(oldWindows)"))
        let show = try XCTUnwrap(body.range(of: "showReplacementWindows(replacements)"))
        let swap = try XCTUnwrap(body.range(of: "windows = replacements"))
        let close = try XCTUnwrap(body.range(of: "closeWindows(oldWindows)"))
        XCTAssertLessThan(show.lowerBound, swap.lowerBound)
        XCTAssertLessThan(swap.lowerBound, close.lowerBound)
    }

    func testPartialReplacementFailureCleansOnlyStagedWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("cleanupStagedWindows(replacements)"))
        XCTAssertTrue(source.contains("throw error"))
    }

    func testLifecycleRestoreUsesFixedDebounceDelays() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(300)"))
        XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(500)"))
        XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(200)"))
        XCTAssertTrue(source.contains("screenRestoreTask?.cancel()"))
        XCTAssertTrue(source.contains("wakeRestoreTask?.cancel()"))
        XCTAssertTrue(source.contains("visibilityTask?.cancel()"))
    }

    func testRestoreChecksGenerationBeforeReopening() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("beginRestoring()"))
        XCTAssertTrue(source.contains("isCurrentGeneration"))
    }

    func testMonitorAndWakeTestsUseInjectedSchedulerNotRealSleep() throws {
        // Given
        let source = try SourceFixture.contents(of: "Tests/MacWallAppTests/PlaybackSchedulerTests.swift")

        // Then
        XCTAssertTrue(source.contains("TestPlaybackScheduler"))
        XCTAssertTrue(source.contains("advance(by: .milliseconds(300))"))
        XCTAssertTrue(source.contains("advance(by: .milliseconds(500))"))
        XCTAssertFalse(source.contains("Task.sleep"))
        XCTAssertFalse(source.contains("Thread.sleep"))
    }

    func testWallpaperPlayerCanBeConstructedWithSchedulerForSimulation() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("init(scheduler: PlaybackScheduling = MainActorPlaybackScheduler())"))
    }

    func testWallpaperWindowsAreNotReleasedByAppKitWhenClosed() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("window.isReleasedWhenClosed = false"))
    }

    func testWebMouseInteractionOnlyAppliesToWebWallpaperWindows() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

        // Then
        XCTAssertTrue(source.contains("supportsWebMouseInteraction = asset.kind == .web"))
        XCTAssertTrue(source.contains("window.ignoresMouseEvents = !supportsWebMouseInteraction || !enabled"))
    }

    func testSceneWallpaperReceivesPreviewFallback() throws {
        // Given
        let playerSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")
        let sceneSource = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/SceneWallpaperView.swift")

        // Then
        XCTAssertTrue(playerSource.contains("let previewURL = asset.thumbnail.map { URL(filePath: $0) }"))
        XCTAssertTrue(playerSource.contains("previewURL: previewURL"))
        XCTAssertTrue(playerSource.contains("return try makeImageContentView(url: previewURL"))
        XCTAssertTrue(sceneSource.contains("private let previewLayer = CALayer()"))
        XCTAssertTrue(sceneSource.contains("sceneLayer.backgroundColor = nil"))
    }

    func testSceneWallpaperAppliesTransformAndOpacityAnimationChannels() throws {
        // Given
        let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/SceneWallpaperView.swift")

        // Then
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "position")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.scale.x")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.scale.y")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "transform.rotation.z")"#))
        XCTAssertTrue(source.contains(#"CAKeyframeAnimation(keyPath: "opacity")"#))
    }
}
