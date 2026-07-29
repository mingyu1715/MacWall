import Foundation
import XCTest
@testable import MacWallApp
import MacWallCore
import MacWallNativeRuntimeSupport

@MainActor
final class NativeWallpaperBackendTests: XCTestCase {
    func testFreshActiveStatusDoesNotProbeExtension() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let harness = try makeHarness(
            now: now,
            statuses: [
                Self.status(state: .stopped, heartbeatAt: now, contextCount: 1)
            ]
        )

        let result = await harness.backend.activationStatus()

        guard case .active = result else {
            return XCTFail("Expected active status")
        }
        XCTAssertEqual(harness.notifier.postCount, 0)
    }

    func testStaleHeartbeatProbesAndAcceptsNewActiveStatus() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let harness = try makeHarness(
            now: now,
            statuses: [
                Self.status(
                    state: .stopped,
                    heartbeatAt: now.addingTimeInterval(-10),
                    contextCount: 1
                ),
                Self.status(state: .stopped, heartbeatAt: now, contextCount: 1)
            ]
        )

        let result = await harness.backend.activationStatus()

        guard case .active = result else {
            return XCTFail("Expected active status after probe")
        }
        XCTAssertEqual(harness.notifier.postCount, 1)
    }

    func testPlayPublishesCommandAndAcceptsMatchingAck() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let generation = UUID()
        let harness = try makeHarness(
            now: now,
            statuses: [
                nil,
                Self.status(
                    state: .playing,
                    heartbeatAt: now,
                    contextCount: 1,
                    requestedGeneration: generation,
                    activeGeneration: generation
                )
            ]
        )
        let asset = try makeVideoAsset(root: harness.root)

        let receipt = try await harness.backend.play(
            asset: asset,
            displayMode: .fill,
            generation: generation,
            timeout: .seconds(5)
        )

        XCTAssertEqual(receipt.generation, generation)
        XCTAssertEqual(receipt.assetID, asset.id)
        XCTAssertEqual(harness.notifier.postCount, 1)
        let command = try XCTUnwrap(harness.store.readCommand())
        XCTAssertEqual(command.kind, .play)
        XCTAssertEqual(command.generation, generation)
        XCTAssertEqual(command.assetID, asset.id)
        XCTAssertEqual(command.displayMode, .fill)
        XCTAssertNotNil(try harness.store.resolveSourceURL(for: command))
    }

    func testSuccessfulNewGenerationRemovesOnlyOlderGeneration() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let oldGeneration = UUID()
        let newGeneration = UUID()
        let harness = try makeHarness(
            now: now,
            statuses: [
                nil,
                Self.status(
                    state: .playing,
                    heartbeatAt: now,
                    contextCount: 1,
                    requestedGeneration: newGeneration,
                    activeGeneration: newGeneration
                )
            ]
        )
        let asset = try makeVideoAsset(root: harness.root)
        _ = try harness.store.stageVideo(
            sourceURL: URL(filePath: try XCTUnwrap(asset.entrypoint)),
            generation: oldGeneration
        )

        _ = try await harness.backend.play(
            asset: asset,
            displayMode: .fit,
            generation: newGeneration,
            timeout: .seconds(5)
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.store.generationsURL
                    .appending(path: oldGeneration.uuidString)
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.store.generationsURL
                    .appending(path: newGeneration.uuidString)
                    .path
            )
        )
    }

    func testUpdateDisplayModePublishesCommandForActiveGeneration() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let activeGeneration = UUID()
        let commandID = UUID()
        let harness = try makeHarness(now: now, statuses: [])
        let playCommand = NativeRuntimeCommand.play(
            generation: activeGeneration,
            assetID: "video",
            relativeSourcePath: "Generations/\(activeGeneration.uuidString)/source.mp4",
            displayMode: .fit,
            createdAt: now.addingTimeInterval(-1)
        )
        try harness.store.writeCommand(playCommand)

        try harness.backend.updateDisplayMode(
            .stretch,
            activeGeneration: activeGeneration,
            commandID: commandID
        )

        XCTAssertEqual(harness.notifier.postCount, 1)
        let update = try XCTUnwrap(harness.store.readDisplayModeUpdate())
        XCTAssertEqual(update.commandID, commandID)
        XCTAssertEqual(update.targetGeneration, activeGeneration)
        XCTAssertEqual(update.displayMode, .stretch)
        XCTAssertEqual(try harness.store.readCommand(), playCommand)
    }

    func testUpdateDisplayModeDoesNotOverwriteStopCommand() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let harness = try makeHarness(now: now, statuses: [])
        let stopCommand = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: now.addingTimeInterval(-1)
        )
        try harness.store.writeCommand(stopCommand)

        try harness.backend.updateDisplayMode(
            .fill,
            activeGeneration: UUID(),
            commandID: UUID()
        )

        XCTAssertEqual(try harness.store.readCommand(), stopCommand)
        XCTAssertEqual(
            try harness.store.readDisplayModeUpdate()?.displayMode,
            .fill
        )
    }

    func testUpdatePlaybackSuspendedPublishesGenerationScopedControl() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let activeGeneration = UUID()
        let commandID = UUID()
        let harness = try makeHarness(now: now, statuses: [])
        let playCommand = NativeRuntimeCommand.play(
            generation: activeGeneration,
            assetID: "video",
            relativeSourcePath: "Generations/\(activeGeneration.uuidString)/source.mp4",
            displayMode: .fit,
            createdAt: now.addingTimeInterval(-1)
        )
        try harness.store.writeCommand(playCommand)

        try harness.backend.updatePlaybackSuspended(
            true,
            activeGeneration: activeGeneration,
            commandID: commandID
        )

        XCTAssertEqual(harness.notifier.postCount, 1)
        let update = try XCTUnwrap(
            harness.store.readPlaybackControlUpdate()
        )
        XCTAssertEqual(update.commandID, commandID)
        XCTAssertEqual(update.targetGeneration, activeGeneration)
        XCTAssertTrue(update.isSuspended)
        XCTAssertEqual(try harness.store.readCommand(), playCommand)
    }

    func testPlayRejectsExplicitFailureAndRemovesCandidateGeneration() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let generation = UUID()
        let harness = try makeHarness(
            now: now,
            statuses: [
                nil,
                Self.status(
                    state: .failed,
                    heartbeatAt: now,
                    contextCount: 1,
                    requestedGeneration: generation,
                    failure: .init(
                        category: "playback",
                        code: "decode-failed",
                        message: "decode failed"
                    )
                )
            ]
        )
        let asset = try makeVideoAsset(root: harness.root)

        do {
            _ = try await harness.backend.play(
                asset: asset,
                displayMode: .fit,
                generation: generation,
                timeout: .seconds(5)
            )
            XCTFail("Expected native runtime failure")
        } catch let error as NativeWallpaperBackendError {
            XCTAssertEqual(error, .runtimeFailed(code: "decode-failed", message: "decode failed"))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.store.generationsURL
                    .appending(path: generation.uuidString)
                    .path
            )
        )
    }

    func testStopCleansStagedRuntimeOnlyAfterMatchingAck() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stopGeneration = UUID()
        let stagedGeneration = UUID()
        let harness = try makeHarness(
            now: now,
            statuses: [
                nil,
                Self.status(
                    state: .stopped,
                    heartbeatAt: now,
                    contextCount: 1,
                    requestedGeneration: stopGeneration
                )
            ]
        )
        let asset = try makeVideoAsset(root: harness.root)
        _ = try harness.store.stageVideo(
            sourceURL: URL(filePath: try XCTUnwrap(asset.entrypoint)),
            generation: stagedGeneration
        )
        try harness.store.writePlaybackControlUpdate(
            NativeRuntimePlaybackControlUpdate(
                commandID: UUID(),
                targetGeneration: stagedGeneration,
                isSuspended: true,
                createdAt: now
            )
        )

        try await harness.backend.stop(generation: stopGeneration)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.store.generationsURL.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.store.playbackControlUpdateURL.path
            )
        )
        XCTAssertEqual(
            try harness.store.readCommand()?.generation,
            stopGeneration
        )
    }

    func testStopTimeoutPreservesStagedRuntime() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stopGeneration = UUID()
        let stagedGeneration = UUID()
        let harness = try makeHarness(now: now, statuses: [nil])
        let asset = try makeVideoAsset(root: harness.root)
        _ = try harness.store.stageVideo(
            sourceURL: URL(filePath: try XCTUnwrap(asset.entrypoint)),
            generation: stagedGeneration
        )

        do {
            try await harness.backend.stop(generation: stopGeneration)
            XCTFail("Expected timeout")
        } catch let error as NativeWallpaperBackendError {
            XCTAssertEqual(error, .timedOut)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: harness.store.generationsURL
                    .appending(path: stagedGeneration.uuidString)
                    .path
            )
        )
    }

    func testStopCleanupDoesNotDeletePlayStartedWhileAwaitingAck() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stopGeneration = UUID()
        let playGeneration = UUID()
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacWallNativeBackendTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let store = NativeRuntimeStore(rootURL: root.appending(path: "Runtime"))
        let statusSource = MutableNativeRuntimeStatusSource()
        let sleeper = SuspendedNativeRuntimeSleeper()
        let clock = MutableDateProvider(now: now)
        let backend = NativeWallpaperBackend(
            store: store,
            notifier: RecordingNativeRuntimeNotifier(),
            waiter: NativeRuntimeWaiter(
                readStatus: { statusSource.read() },
                sleeper: sleeper,
                dateProvider: clock
            ),
            dateProvider: clock
        )
        let asset = try makeVideoAsset(root: root)

        let stopTask = Task { @MainActor in
            try await backend.stop(generation: stopGeneration)
        }
        await sleeper.waitUntilSleeping()

        statusSource.set(
            Self.status(
                state: .playing,
                heartbeatAt: now,
                contextCount: 1,
                requestedGeneration: playGeneration,
                activeGeneration: playGeneration
            )
        )
        _ = try await backend.play(
            asset: asset,
            displayMode: .fill,
            generation: playGeneration,
            timeout: .seconds(5)
        )

        statusSource.set(
            Self.status(
                state: .stopped,
                heartbeatAt: now,
                contextCount: 1,
                requestedGeneration: stopGeneration
            )
        )
        await sleeper.release()
        try await stopTask.value

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.generationsURL
                    .appending(path: playGeneration.uuidString)
                    .path
            )
        )
        XCTAssertEqual(try store.readCommand()?.generation, playGeneration)
        XCTAssertEqual(try store.readCommand()?.kind, .play)
    }

    private func makeHarness(
        now: Date,
        statuses: [NativeRuntimeStatus?]
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacWallNativeBackendTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let store = NativeRuntimeStore(rootURL: root.appending(path: "Runtime"))
        let sequence = StatusSequence(statuses)
        let clock = MutableDateProvider(now: now)
        let notifier = RecordingNativeRuntimeNotifier()
        let waiter = NativeRuntimeWaiter(
            readStatus: { try sequence.next() },
            sleeper: AdvancingNativeRuntimeSleeper(clock: clock),
            dateProvider: clock
        )
        return Harness(
            root: root,
            store: store,
            notifier: notifier,
            backend: NativeWallpaperBackend(
                store: store,
                notifier: notifier,
                waiter: waiter,
                dateProvider: clock
            )
        )
    }

    private func makeVideoAsset(root: URL) throws -> WallpaperAsset {
        let project = root.appending(path: "Asset")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appending(path: "source.mp4")
        try Data([1, 2, 3]).write(to: source)
        return WallpaperAsset(
            id: "video",
            title: "Video",
            kind: .video,
            supportStatus: .playable,
            source: .manualFolder,
            projectDirectory: project.path,
            entrypoint: source.path,
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }

    private static func status(
        state: NativeRuntimeStatusState,
        heartbeatAt: Date,
        contextCount: Int,
        requestedGeneration: UUID? = nil,
        activeGeneration: UUID? = nil,
        failure: NativeRuntimeFailure? = nil
    ) -> NativeRuntimeStatus {
        NativeRuntimeStatus(
            requestedGeneration: requestedGeneration,
            activeGeneration: activeGeneration,
            state: state,
            activeDesktopContextCount: contextCount,
            extensionInstanceID: UUID(),
            processIdentifier: 1,
            heartbeatAt: heartbeatAt,
            failure: failure
        )
    }
}

private struct Harness {
    let root: URL
    let store: NativeRuntimeStore
    let notifier: RecordingNativeRuntimeNotifier
    let backend: NativeWallpaperBackend
}

private final class RecordingNativeRuntimeNotifier: NativeRuntimeNotifying, @unchecked Sendable {
    private(set) var postCount = 0

    func postChange() {
        postCount += 1
    }
}

private final class MutableDateProvider: NativeRuntimeDateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        value = now
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func advance(by duration: Duration) {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        lock.withLock {
            value = value.addingTimeInterval(seconds)
        }
    }
}

private struct AdvancingNativeRuntimeSleeper: NativeRuntimeSleeping {
    let clock: MutableDateProvider

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        clock.advance(by: duration)
    }
}

private final class StatusSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [NativeRuntimeStatus?]
    private var last: NativeRuntimeStatus?

    init(_ statuses: [NativeRuntimeStatus?]) {
        self.statuses = statuses
    }

    func next() throws -> NativeRuntimeStatus? {
        lock.withLock {
            guard !statuses.isEmpty else {
                return last
            }
            let next = statuses.removeFirst()
            last = next
            return next
        }
    }
}

private final class MutableNativeRuntimeStatusSource: @unchecked Sendable {
    private let lock = NSLock()
    private var status: NativeRuntimeStatus?

    func read() -> NativeRuntimeStatus? {
        lock.withLock { status }
    }

    func set(_ status: NativeRuntimeStatus?) {
        lock.withLock {
            self.status = status
        }
    }
}

private actor SuspendedNativeRuntimeSleeper: NativeRuntimeSleeping {
    private var didStartSleeping = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleepContinuation: CheckedContinuation<Void, any Error>?

    func sleep(for duration: Duration) async throws {
        didStartSleeping = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters = []
        try await withCheckedThrowingContinuation { continuation in
            sleepContinuation = continuation
        }
        try Task.checkCancellation()
    }

    func waitUntilSleeping() async {
        guard !didStartSleeping else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        sleepContinuation?.resume()
        sleepContinuation = nil
    }
}
