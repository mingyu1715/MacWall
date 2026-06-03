import Foundation
import XCTest
@testable import MacWallApp
import MacWallCore

@MainActor
final class DesktopFallbackCoordinatorTests: XCTestCase {
    func testCacheURLUsesImportedProjectDirectoryInsteadOfAssetId() {
        let asset = makeAsset(
            id: "plain-id",
            projectDirectory: "/tmp/Assets/id-cGxhaW4taWQ"
        )

        XCTAssertEqual(
            DesktopFallbackCoordinator.cacheURL(for: asset).path,
            "/tmp/Assets/id-cGxhaW4taWQ/Derived/desktop-fallback.png"
        )
    }

    func testPrepareForPlaybackAppliesExistingCacheWithoutGenerating() async throws {
        let fixture = try makeFixture(existingCache: Data("cached".utf8))
        var applied: [URL] = []
        var generationCount = 0
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in generationCount += 1 },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(applied, [fixture.cacheURL])
        XCTAssertEqual(generationCount, 0)
    }

    func testApplyOrGenerateReappliesExistingCacheAfterPlaybackWithoutGenerating() async throws {
        let fixture = try makeFixture(existingCache: Data("cached".utf8))
        var applied: [URL] = []
        var generationCount = 0
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in generationCount += 1 },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        applied.removeAll()
        coordinator.applyOrGenerate(asset: fixture.asset)
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(applied, [fixture.cacheURL])
        XCTAssertEqual(generationCount, 0)
    }

    func testApplyOrGenerateMarksAssetActiveBeforeMissingCacheGeneration() async throws {
        let fixture = try makeFixture()
        var applied: [URL] = []
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                try Data("generated".utf8).write(to: output)
            },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.applyOrGenerate(asset: fixture.asset)
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("generated".utf8))
        XCTAssertEqual(applied, [fixture.cacheURL])
    }

    func testMissingCacheGeneratesAndAppliesAfterPlaybackStarts() async throws {
        let fixture = try makeFixture()
        var applied: [URL] = []
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                try Data("generated".utf8).write(to: output)
            },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        XCTAssertTrue(applied.isEmpty)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("generated".utf8))
        XCTAssertEqual(applied, [fixture.cacheURL])
    }

    func testRepeatedAutomaticRequestsDeduplicatePerProjectDirectory() async throws {
        let fixture = try makeFixture()
        let gate = AsyncGate()
        var generationCount = 0
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                generationCount += 1
                await gate.wait()
                try Data("generated".utf8).write(to: output)
            },
            applyDesktopImage: { _ in }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        await waitUntil { generationCount == 1 }
        await gate.open()
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(generationCount, 1)
    }

    func testCompletedStaleGenerationCachesPNGWithoutApplyingIt() async throws {
        let first = try makeFixture()
        let second = try makeFixture()
        let gate = AsyncGate()
        var applied: [URL] = []
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                await gate.wait()
                try Data("generated".utf8).write(to: output)
            },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: first.asset)
        coordinator.scheduleGenerationIfNeeded(asset: first.asset)
        coordinator.prepareForPlayback(asset: second.asset)
        await gate.open()
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(try Data(contentsOf: first.cacheURL), Data("generated".utf8))
        XCTAssertFalse(applied.contains(first.cacheURL))
    }

    func testClearActiveAssetKeepsCompletedCacheWithoutApplyingIt() async throws {
        let fixture = try makeFixture()
        let gate = AsyncGate()
        var applied: [URL] = []
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                await gate.wait()
                try Data("generated".utf8).write(to: output)
            },
            applyDesktopImage: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        coordinator.clearActiveAsset()
        await gate.open()
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("generated".utf8))
        XCTAssertTrue(applied.isEmpty)
    }

    func testInvalidatePreventsOlderGenerationFromInstallingCache() async throws {
        let fixture = try makeFixture()
        let gate = AsyncGate()
        var generationFinished = false
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                await gate.wait()
                try FileManager.default.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("generated".utf8).write(to: output)
                generationFinished = true
            },
            applyDesktopImage: { _ in }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        coordinator.invalidate(asset: fixture.asset)
        try FileManager.default.removeItem(at: URL(filePath: fixture.asset.projectDirectory))
        await gate.open()
        await waitUntil { generationFinished }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.asset.projectDirectory))
    }

    func testFailedManualRegenerationPreservesPreviousCache() async throws {
        let fixture = try makeFixture(existingCache: Data("previous".utf8))
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, _ in throw TestError.expected },
            applyDesktopImage: { _ in }
        )

        await XCTAssertThrowsErrorAsync(
            try await coordinator.regenerate(asset: fixture.asset)
        )

        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("previous".utf8))
    }

    func testManualRegenerateInvalidatesOlderAutomaticGeneration() async throws {
        let fixture = try makeFixture()
        let gate = AsyncGate()
        var generationCount = 0
        let coordinator = DesktopFallbackCoordinator(
            generateFallback: { _, output in
                generationCount += 1
                if generationCount == 1 {
                    await gate.wait()
                    try Data("older".utf8).write(to: output)
                } else {
                    try Data("newer".utf8).write(to: output)
                }
            },
            applyDesktopImage: { _ in }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)
        await waitUntil { generationCount == 1 }
        try await coordinator.regenerate(asset: fixture.asset)
        await gate.open()
        await coordinator.waitForAutomaticGeneration()

        XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("newer".utf8))
    }

    private func makeFixture(existingCache: Data? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DesktopFallbackCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let asset = makeAsset(id: UUID().uuidString, projectDirectory: root.path)
        let cacheURL = DesktopFallbackCoordinator.cacheURL(for: asset)
        if let existingCache {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try existingCache.write(to: cacheURL)
        }
        return Fixture(asset: asset, cacheURL: cacheURL)
    }

    private func makeAsset(id: String, projectDirectory: String) -> WallpaperAsset {
        WallpaperAsset(
            id: id,
            title: id,
            kind: .image,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: projectDirectory,
            entrypoint: "\(projectDirectory)/source.png",
            thumbnail: "\(projectDirectory)/preview.jpg",
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }
}

private struct Fixture {
    let asset: WallpaperAsset
    let cacheURL: URL
}

private actor AsyncGate {
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

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

private enum TestError: Error {
    case expected
}
