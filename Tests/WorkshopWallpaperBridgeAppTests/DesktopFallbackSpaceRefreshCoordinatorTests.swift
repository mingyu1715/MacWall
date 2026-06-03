import AppKit
import Foundation
import XCTest
@testable import WorkshopWallpaperBridgeApp
import WorkshopWallpaperCore

@MainActor
final class DesktopFallbackSpaceRefreshCoordinatorTests: XCTestCase {
    func testPostedActiveSpaceNotificationRefreshesActiveVideoFallbackAfterDelay() async throws {
        let fixture = try makeFixture(kind: .video, existingCache: Data("old".utf8))
        let notificationCenter = NotificationCenter()
        var captured: [WallpaperAsset.ID] = []
        var applied: [URL] = []
        let fallbackCoordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in },
            applyDesktopImage: { applied.append($0) }
        )
        let coordinator = DesktopFallbackSpaceRefreshCoordinator(
            notificationCenter: notificationCenter,
            fallbackCoordinator: fallbackCoordinator,
            options: .init(stabilizationDelay: .milliseconds(1), throttle: .seconds(20)),
            captureLiveSnapshot: { asset, output in
                captured.append(asset.id)
                try Data("fresh".utf8).write(to: output)
            }
        )

        fallbackCoordinator.applyOrGenerate(asset: fixture.asset)
        applied.removeAll()
        coordinator.start()
        coordinator.setActiveAsset(fixture.asset)
        notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        await coordinator.waitForRefresh()
        coordinator.stop()

        XCTAssertEqual(captured, [fixture.asset.id])
        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("fresh".utf8))
        XCTAssertEqual(applied, [fixture.cacheURL])
    }

    func testSpaceRefreshIgnoresImageAndSceneAssets() async throws {
        let image = try makeFixture(kind: .image)
        let scene = try makeFixture(kind: .scene)
        var captureCount = 0
        let fallbackCoordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in },
            applyDesktopImage: { _ in }
        )
        let coordinator = DesktopFallbackSpaceRefreshCoordinator(
            fallbackCoordinator: fallbackCoordinator,
            options: .init(stabilizationDelay: .milliseconds(1), throttle: .seconds(20)),
            captureLiveSnapshot: { _, _ in captureCount += 1 }
        )

        coordinator.setActiveAsset(image.asset)
        coordinator.handleActiveSpaceDidChange()
        await coordinator.waitForRefresh()
        coordinator.setActiveAsset(scene.asset)
        coordinator.handleActiveSpaceDidChange()
        await coordinator.waitForRefresh()

        XCTAssertEqual(captureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.cacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scene.cacheURL.path))
    }

    func testSpaceRefreshThrottlesRepeatedNotifications() async throws {
        let fixture = try makeFixture(kind: .web, existingCache: Data("old".utf8))
        var captureCount = 0
        let fallbackCoordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in },
            applyDesktopImage: { _ in }
        )
        let coordinator = DesktopFallbackSpaceRefreshCoordinator(
            fallbackCoordinator: fallbackCoordinator,
            options: .init(stabilizationDelay: .milliseconds(1), throttle: .seconds(20)),
            captureLiveSnapshot: { _, output in
                captureCount += 1
                try Data("fresh".utf8).write(to: output)
            }
        )

        fallbackCoordinator.applyOrGenerate(asset: fixture.asset)
        coordinator.setActiveAsset(fixture.asset)
        coordinator.handleActiveSpaceDidChange()
        coordinator.handleActiveSpaceDidChange()
        await coordinator.waitForRefresh()

        XCTAssertEqual(captureCount, 1)
    }

    func testSpaceRefreshDoesNotApplyWhenActiveAssetChangesBeforeCaptureCompletes() async throws {
        let first = try makeFixture(kind: .video, existingCache: Data("first-old".utf8))
        let second = try makeFixture(kind: .video, existingCache: Data("second-old".utf8))
        let captureStarted = SpaceRefreshAsyncGate()
        let gate = SpaceRefreshAsyncGate()
        var applied: [URL] = []
        let fallbackCoordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in },
            applyDesktopImage: { applied.append($0) }
        )
        let coordinator = DesktopFallbackSpaceRefreshCoordinator(
            fallbackCoordinator: fallbackCoordinator,
            options: .init(stabilizationDelay: .milliseconds(1), throttle: .seconds(20)),
            captureLiveSnapshot: { _, output in
                await captureStarted.open()
                await gate.wait()
                try Data("first-fresh".utf8).write(to: output)
            }
        )

        fallbackCoordinator.applyOrGenerate(asset: first.asset)
        coordinator.setActiveAsset(first.asset)
        coordinator.handleActiveSpaceDidChange()
        await captureStarted.wait()
        fallbackCoordinator.applyOrGenerate(asset: second.asset)
        coordinator.setActiveAsset(second.asset)
        await gate.open()
        await coordinator.waitForRefresh()

        XCTAssertEqual(try Data(contentsOf: first.cacheURL), Data("first-fresh".utf8))
        XCTAssertFalse(applied.dropFirst().contains(first.cacheURL))
    }

    private func makeFixture(kind: WallpaperKind, existingCache: Data? = nil) throws -> SpaceRefreshFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DesktopFallbackSpaceRefreshCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let asset = WallpaperAsset(
            id: UUID().uuidString,
            title: kind.rawValue,
            kind: kind,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: root.path,
            entrypoint: root.appending(path: "source.\(kind == .web ? "html" : "mp4")").path,
            thumbnail: root.appending(path: "preview.jpg").path,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
        let cacheURL = DesktopFallbackCoordinator.cacheURL(for: asset)
        if let existingCache {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try existingCache.write(to: cacheURL)
        }
        return SpaceRefreshFixture(asset: asset, cacheURL: cacheURL)
    }
}

private struct SpaceRefreshFixture {
    let asset: WallpaperAsset
    let cacheURL: URL
}

private actor SpaceRefreshAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
