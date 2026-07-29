import XCTest
@testable import MacWallApp
import MacWallCore
import MacWallNativeRuntimeSupport

@MainActor
final class WallpaperPlaybackCoordinatorTests: XCTestCase {
    func testFreshActiveStatusRoutesVideoToNative() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        let request = Self.request(asset: Self.asset(id: "video", kind: .video))

        let outcome = try await coordinator.play(request)

        guard case .started(let receipt) = outcome else {
            return XCTFail("Expected started")
        }
        XCTAssertEqual(receipt.backend, .native)
        XCTAssertEqual(native.playedAssetIDs, ["video"])
        XCTAssertTrue(legacy.playedAssetIDs.isEmpty)
    }

    func testInactiveNativeReturnsSetupRequired() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .inactive
        let coordinator = makeCoordinator(native: native)
        let request = Self.request(asset: Self.asset(id: "video", kind: .video))

        let outcome = try await coordinator.play(request)

        XCTAssertEqual(outcome, .nativeSetupRequired(request))
        XCTAssertTrue(native.playedAssetIDs.isEmpty)
    }

    func testNonVideoRoutesDirectlyToLegacy() async throws {
        let native = MockNativeWallpaperBackend()
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        let request = Self.request(asset: Self.asset(id: "web", kind: .web))

        let outcome = try await coordinator.play(request)

        guard case .started(let receipt) = outcome else {
            return XCTFail("Expected started")
        }
        XCTAssertEqual(receipt.backend, .legacy)
        XCTAssertEqual(legacy.playedAssetIDs, ["web"])
        XCTAssertEqual(native.activationCallCount, 0)
    }

    func testUseLegacyOnceDoesNotChangeLaterNativeRouting() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .inactive
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        let request = Self.request(asset: Self.asset(id: "video", kind: .video))

        let first = try await coordinator.resolveNativeSetup(.useLegacyOnce, pending: request)
        native.activation = .active(Self.status())
        let second = try await coordinator.play(
            Self.request(asset: Self.asset(id: "video-2", kind: .video))
        )

        guard case .started(let firstReceipt) = first,
              case .started(let secondReceipt) = second else {
            return XCTFail("Expected both plays to start")
        }
        XCTAssertEqual(firstReceipt.backend, .legacy)
        XCTAssertEqual(secondReceipt.backend, .native)
    }

    func testNativeFailurePreservesPreviousLegacyReceipt() async throws {
        let native = MockNativeWallpaperBackend()
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        let legacyRequest = Self.request(asset: Self.asset(id: "web", kind: .web))
        _ = try await coordinator.play(legacyRequest)
        native.activation = .active(Self.status())
        native.playError = TestError.expected

        do {
            _ = try await coordinator.play(
                Self.request(asset: Self.asset(id: "video", kind: .video))
            )
            XCTFail("Expected failure")
        } catch TestError.expected {
        }

        XCTAssertEqual(coordinator.activeReceipt?.assetID, "web")
        XCTAssertEqual(coordinator.activeReceipt?.backend, .legacy)
        XCTAssertTrue(legacy.stopReasons.isEmpty)
    }

    func testLegacyToNativeStopsLegacyOnlyAfterNativeAck() async throws {
        let events = EventLog()
        let native = MockNativeWallpaperBackend(events: events)
        let legacy = MockLegacyWallpaperBackend(events: events)
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "web", kind: .web))
        )
        native.activation = .active(Self.status())

        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "video", kind: .video))
        )

        XCTAssertEqual(
            events.values,
            ["legacy-play-web", "native-play-video", "legacy-stop-handoffToNative"]
        )
    }

    func testSameInflightRequestIsDeduped() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        native.suspendPlay = true
        let coordinator = makeCoordinator(native: native)
        let request = Self.request(asset: Self.asset(id: "video", kind: .video))

        async let first = coordinator.play(request)
        await native.waitForSuspendedPlay()
        async let second = coordinator.play(request)
        await Task.yield()
        XCTAssertEqual(native.playedAssetIDs, ["video"])

        native.resumeAllPlays()
        _ = try await (first, second)
        XCTAssertEqual(native.playedAssetIDs, ["video"])
    }

    func testStaleAsyncResultCannotReplaceNewerReceipt() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        native.suspendPlay = true
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)

        let oldTask = Task {
            try await coordinator.play(
                Self.request(asset: Self.asset(id: "old", kind: .video))
            )
        }
        await native.waitForSuspendedPlay()
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "new", kind: .web))
        )
        native.resumeAllPlays()
        _ = try? await oldTask.value

        XCTAssertEqual(coordinator.activeReceipt?.assetID, "new")
        XCTAssertEqual(coordinator.activeReceipt?.backend, .legacy)
    }

    func testNativeStopDoesNotInvokeLegacyRestoreOrDeleteFallbackCache() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let legacy = MockLegacyWallpaperBackend()
        let coordinator = makeCoordinator(native: native, legacy: legacy)
        let project = FileManager.default.temporaryDirectory
            .appending(path: "MacWallCoordinatorTests-\(UUID().uuidString)")
        let fallback = project.appending(path: "Derived/desktop-fallback.png")
        try FileManager.default.createDirectory(
            at: fallback.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cache".utf8).write(to: fallback)
        defer { try? FileManager.default.removeItem(at: project) }
        let asset = WallpaperAsset(
            id: "native",
            title: "native",
            kind: .video,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: project.path,
            entrypoint: project.appending(path: "source.mp4").path,
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
        _ = try await coordinator.play(Self.request(asset: asset))

        try await coordinator.stop()

        XCTAssertEqual(native.stoppedGenerations.count, 1)
        XCTAssertTrue(legacy.stopReasons.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fallback.path))
    }

    func testNativeStopFailureKeepsActiveReceipt() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "native", kind: .video))
        )
        native.stopError = TestError.expected

        do {
            try await coordinator.stop()
            XCTFail("Expected Stop failure")
        } catch TestError.expected {
        }

        XCTAssertEqual(coordinator.activeReceipt?.backend, .native)
        XCTAssertEqual(coordinator.activeReceipt?.assetID, "native")
    }

    func testDisplayModeUpdateTargetsActiveNativeGeneration() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "native", kind: .video))
        )

        coordinator.updateDisplayMode(.stretch)

        XCTAssertEqual(native.displayModeUpdates.count, 1)
        XCTAssertEqual(native.displayModeUpdates.first?.mode, .stretch)
        XCTAssertEqual(
            native.displayModeUpdates.first?.activeGeneration,
            native.playedGenerations.first
        )
    }

    func testDisplayModeUpdateDoesNotPublishForLegacyPlayback() async throws {
        let native = MockNativeWallpaperBackend()
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "web", kind: .web))
        )

        coordinator.updateDisplayMode(.fill)

        XCTAssertTrue(native.displayModeUpdates.isEmpty)
    }

    func testDisplayModeUpdateDuringNativePlayIsDeferredUntilCommit() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        native.suspendPlay = true
        let coordinator = makeCoordinator(native: native)
        let playTask = Task {
            try await coordinator.play(
                Self.request(asset: Self.asset(id: "native", kind: .video))
            )
        }
        await native.waitForSuspendedPlay()

        coordinator.updateDisplayMode(.stretch)
        XCTAssertTrue(native.displayModeUpdates.isEmpty)

        native.resumeAllPlays()
        _ = try await playTask.value

        XCTAssertEqual(native.displayModeUpdates.count, 1)
        XCTAssertEqual(native.displayModeUpdates.first?.mode, .stretch)
        XCTAssertEqual(
            native.displayModeUpdates.first?.activeGeneration,
            native.playedGenerations.first
        )
    }

    func testDeferredDisplayModeUpdateKeepsOnlyLatestValue() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        native.suspendPlay = true
        let coordinator = makeCoordinator(native: native)
        let playTask = Task {
            try await coordinator.play(
                Self.request(asset: Self.asset(id: "native", kind: .video))
            )
        }
        await native.waitForSuspendedPlay()

        coordinator.updateDisplayMode(.fill)
        coordinator.updateDisplayMode(.stretch)
        native.resumeAllPlays()
        _ = try await playTask.value

        XCTAssertEqual(native.displayModeUpdates.map(\.mode), [.stretch])
    }

    func testPlaybackSuspensionTargetsActiveNativeGeneration() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "native", kind: .video))
        )
        native.playbackControlUpdates.removeAll()

        coordinator.updatePlaybackSuspended(true)

        XCTAssertEqual(native.playbackControlUpdates.count, 1)
        XCTAssertTrue(native.playbackControlUpdates[0].isSuspended)
        XCTAssertEqual(
            native.playbackControlUpdates[0].activeGeneration,
            native.playedGenerations[0]
        )
    }

    func testSuspensionDuringReplacementTargetsAThenCommittedB() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "a", kind: .video))
        )
        native.playbackControlUpdates.removeAll()
        native.suspendPlay = true

        let replacement = Task {
            try await coordinator.play(
                Self.request(asset: Self.asset(id: "b", kind: .video))
            )
        }
        await native.waitForSuspendedPlay()

        coordinator.updatePlaybackSuspended(true)
        XCTAssertEqual(
            native.playbackControlUpdates.map(\.activeGeneration),
            [native.playedGenerations[0]]
        )

        native.resumeAllPlays()
        _ = try await replacement.value

        XCTAssertEqual(
            native.playbackControlUpdates.map(\.activeGeneration),
            native.playedGenerations
        )
        XCTAssertEqual(
            native.playbackControlUpdates.map(\.isSuspended),
            [true, true]
        )
    }

    func testFailingReplacementKeepsAControlTarget() async throws {
        let native = MockNativeWallpaperBackend()
        native.activation = .active(Self.status())
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "a", kind: .video))
        )
        native.playbackControlUpdates.removeAll()
        coordinator.updatePlaybackSuspended(true)
        native.playError = TestError.expected

        do {
            _ = try await coordinator.play(
                Self.request(asset: Self.asset(id: "b", kind: .video))
            )
            XCTFail("Expected failure")
        } catch TestError.expected {
        }

        XCTAssertEqual(coordinator.activeReceipt?.assetID, "a")
        XCTAssertEqual(
            native.playbackControlUpdates.map(\.activeGeneration),
            [native.playedGenerations[0]]
        )
    }

    func testPlaybackSuspensionDoesNotPublishForLegacyPlayback() async throws {
        let native = MockNativeWallpaperBackend()
        let coordinator = makeCoordinator(native: native)
        _ = try await coordinator.play(
            Self.request(asset: Self.asset(id: "web", kind: .web))
        )

        coordinator.updatePlaybackSuspended(true)

        XCTAssertTrue(native.playbackControlUpdates.isEmpty)
    }

    private func makeCoordinator(
        native: MockNativeWallpaperBackend = MockNativeWallpaperBackend(),
        legacy: MockLegacyWallpaperBackend = MockLegacyWallpaperBackend()
    ) -> WallpaperPlaybackCoordinator {
        WallpaperPlaybackCoordinator(
            eligibility: NativeWallpaperEligibility(
                environment: .init(macOSMajorVersion: 26, isAppleSilicon: true)
            ),
            nativeBackend: native,
            legacyBackend: legacy
        )
    }

    private static func request(asset: WallpaperAsset) -> PendingPlaybackRequest {
        PendingPlaybackRequest(
            requestID: UUID(),
            asset: asset,
            options: .defaults,
            remember: true
        )
    }

    private static func asset(id: String, kind: WallpaperKind) -> WallpaperAsset {
        WallpaperAsset(
            id: id,
            title: id,
            kind: kind,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: "/tmp/\(id)",
            entrypoint: "/tmp/\(id)/source.mp4",
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }

    private static func status() -> NativeRuntimeStatus {
        NativeRuntimeStatus(
            requestedGeneration: nil,
            activeGeneration: nil,
            state: .stopped,
            activeDesktopContextCount: 1,
            extensionInstanceID: UUID(),
            processIdentifier: 1,
            heartbeatAt: Date(),
            failure: nil
        )
    }
}

@MainActor
private final class MockNativeWallpaperBackend: NativeWallpaperBackendManaging {
    struct DisplayModeUpdate: Equatable {
        let mode: WallpaperDisplayMode
        let activeGeneration: UUID
        let commandID: UUID
    }

    struct PlaybackControlUpdate: Equatable {
        let isSuspended: Bool
        let activeGeneration: UUID
        let commandID: UUID
    }

    var activation: NativeWallpaperActivationStatus = .inactive
    var activationCallCount = 0
    var playedAssetIDs: [WallpaperAsset.ID] = []
    var playedGenerations: [UUID] = []
    var displayModeUpdates: [DisplayModeUpdate] = []
    var playbackControlUpdates: [PlaybackControlUpdate] = []
    var stoppedGenerations: [UUID] = []
    var playError: Error?
    var stopError: Error?
    var suspendPlay = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private let events: EventLog?

    init(events: EventLog? = nil) {
        self.events = events
    }

    func activationStatus(timeout: Duration) async -> NativeWallpaperActivationStatus {
        activationCallCount += 1
        return activation
    }

    func play(
        asset: WallpaperAsset,
        displayMode: WallpaperDisplayMode,
        generation: UUID,
        timeout: Duration
    ) async throws -> NativePlaybackReceipt {
        playedAssetIDs.append(asset.id)
        playedGenerations.append(generation)
        events?.values.append("native-play-\(asset.id)")
        if suspendPlay {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
                let waiters = suspensionWaiters
                suspensionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        if let playError {
            throw playError
        }
        return NativePlaybackReceipt(
            generation: generation,
            assetID: asset.id,
            projectDirectory: asset.projectDirectory
        )
    }

    func updateDisplayMode(
        _ displayMode: WallpaperDisplayMode,
        activeGeneration: UUID,
        commandID: UUID
    ) throws {
        displayModeUpdates.append(
            DisplayModeUpdate(
                mode: displayMode,
                activeGeneration: activeGeneration,
                commandID: commandID
            )
        )
    }

    func updatePlaybackSuspended(
        _ isSuspended: Bool,
        activeGeneration: UUID,
        commandID: UUID
    ) throws {
        playbackControlUpdates.append(
            PlaybackControlUpdate(
                isSuspended: isSuspended,
                activeGeneration: activeGeneration,
                commandID: commandID
            )
        )
    }

    func stop(generation: UUID) async throws {
        stoppedGenerations.append(generation)
        if let stopError {
            throw stopError
        }
    }

    func resumeAllPlays() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForSuspendedPlay() async {
        guard continuations.isEmpty else {
            return
        }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }
}

@MainActor
private final class MockLegacyWallpaperBackend: LegacyWallpaperBackendManaging {
    var playedAssetIDs: [WallpaperAsset.ID] = []
    var stopReasons: [LegacyPlaybackStopReason] = []
    var playError: Error?
    private var generation: UInt64 = 0
    private let events: EventLog?

    init(events: EventLog? = nil) {
        self.events = events
    }

    func play(
        asset: WallpaperAsset,
        options: PlaybackOptions
    ) throws -> LegacyPlaybackReceipt {
        if let playError {
            throw playError
        }
        generation += 1
        playedAssetIDs.append(asset.id)
        events?.values.append("legacy-play-\(asset.id)")
        return LegacyPlaybackReceipt(
            snapshot: PlaybackSessionSnapshot(
                assetId: asset.id,
                projectDirectory: asset.projectDirectory,
                phase: .playing,
                generation: generation,
                options: options
            ),
            restoreSupport: .restorable
        )
    }

    func stop(reason: LegacyPlaybackStopReason) {
        stopReasons.append(reason)
        events?.values.append("legacy-stop-\(reason)")
    }
}

@MainActor
private final class EventLog {
    var values: [String] = []
}

private enum TestError: Error {
    case expected
}
