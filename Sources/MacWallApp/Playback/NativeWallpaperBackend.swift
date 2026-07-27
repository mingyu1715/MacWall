import Foundation
import MacWallCore
import MacWallNativeRuntimeSupport

enum NativeWallpaperActivationStatus: Equatable {
    case active(NativeRuntimeStatus)
    case inactive
}

struct NativePlaybackReceipt: Equatable {
    let generation: UUID
    let assetID: WallpaperAsset.ID
    let projectDirectory: String
}

enum NativeWallpaperBackendError: Error, Equatable, LocalizedError {
    case runtimeUnavailable
    case missingEntrypoint
    case timedOut
    case runtimeFailed(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "The Native wallpaper runtime is unavailable."
        case .missingEntrypoint:
            return "The Native wallpaper video source is missing."
        case .timedOut:
            return "The Native wallpaper runtime did not acknowledge the request in time."
        case .runtimeFailed(_, let message):
            return message
        }
    }
}

@MainActor
final class UnavailableNativeWallpaperBackend: NativeWallpaperBackendManaging {
    func activationStatus(timeout: Duration) async -> NativeWallpaperActivationStatus {
        .inactive
    }

    func play(
        asset: WallpaperAsset,
        displayMode: WallpaperDisplayMode,
        generation: UUID,
        timeout: Duration
    ) async throws -> NativePlaybackReceipt {
        throw NativeWallpaperBackendError.runtimeUnavailable
    }

    func stop(generation: UUID) async throws {}
}

@MainActor
protocol NativeWallpaperBackendManaging: AnyObject {
    func activationStatus(timeout: Duration) async -> NativeWallpaperActivationStatus
    func play(
        asset: WallpaperAsset,
        displayMode: WallpaperDisplayMode,
        generation: UUID,
        timeout: Duration
    ) async throws -> NativePlaybackReceipt
    func stop(generation: UUID) async throws
}

extension NativeWallpaperBackendManaging {
    func activationStatus() async -> NativeWallpaperActivationStatus {
        await activationStatus(timeout: .milliseconds(500))
    }
}

@MainActor
final class NativeWallpaperBackend: NativeWallpaperBackendManaging {
    private let store: NativeRuntimeStore
    private let notifier: any NativeRuntimeNotifying
    private let waiter: NativeRuntimeWaiter
    private let dateProvider: any NativeRuntimeDateProviding

    init(
        store: NativeRuntimeStore,
        notifier: any NativeRuntimeNotifying = NativeRuntimeDarwinNotifier(),
        waiter: NativeRuntimeWaiter? = nil,
        dateProvider: any NativeRuntimeDateProviding = SystemNativeRuntimeDateProvider()
    ) {
        self.store = store
        self.notifier = notifier
        self.dateProvider = dateProvider
        self.waiter = waiter ?? NativeRuntimeWaiter(
            readStatus: { try store.readStatus() },
            dateProvider: dateProvider
        )
    }

    convenience init() throws {
        try self.init(store: .live())
    }

    func activationStatus(timeout: Duration) async -> NativeWallpaperActivationStatus {
        let initialStatus = try? waiter.currentStatus()
        if let initialStatus, isActive(initialStatus) {
            return .active(initialStatus)
        }

        let previousHeartbeat = initialStatus?.heartbeatAt
        notifier.postChange()
        do {
            let status = try await waiter.wait(timeout: timeout) { [waiter] status in
                guard waiter.isFresh(status),
                      status.activeDesktopContextCount > 0 else {
                    return false
                }
                guard let previousHeartbeat else {
                    return true
                }
                return status.heartbeatAt > previousHeartbeat
            }
            return .active(status)
        } catch {
            return .inactive
        }
    }

    func play(
        asset: WallpaperAsset,
        displayMode: WallpaperDisplayMode,
        generation: UUID,
        timeout: Duration
    ) async throws -> NativePlaybackReceipt {
        guard let entrypoint = asset.entrypoint else {
            throw NativeWallpaperBackendError.missingEntrypoint
        }

        let sourceURL = URL(filePath: entrypoint)
        let relativeSourcePath = try await Task.detached(priority: .userInitiated) { [store] in
            try store.stageVideo(sourceURL: sourceURL, generation: generation)
        }.value
        let createdAt = dateProvider.now()
        let command = NativeRuntimeCommand.play(
            generation: generation,
            assetID: asset.id,
            relativeSourcePath: relativeSourcePath,
            displayMode: displayMode.nativeRuntimeDisplayMode,
            createdAt: createdAt
        )

        do {
            try store.writeCommand(command)
            notifier.postChange()
            _ = try await waiter.wait(timeout: timeout) { [waiter] status in
                guard waiter.isFresh(status),
                      status.heartbeatAt >= createdAt,
                      status.requestedGeneration == generation else {
                    return false
                }
                if status.state == .failed {
                    let failure = status.failure
                    throw NativeWallpaperBackendError.runtimeFailed(
                        code: failure?.code ?? "unknown",
                        message: failure?.message ?? "Native wallpaper playback failed."
                    )
                }
                return status.state == .playing
                    && status.activeGeneration == generation
                    && status.activeDesktopContextCount > 0
            }
            try Task.checkCancellation()
        } catch is NativeRuntimeWaiterError {
            await removeGeneration(generation)
            throw NativeWallpaperBackendError.timedOut
        } catch {
            await removeGeneration(generation)
            throw error
        }

        await removeUnreferencedGenerations(keeping: [generation])
        return NativePlaybackReceipt(
            generation: generation,
            assetID: asset.id,
            projectDirectory: asset.projectDirectory
        )
    }

    func stop(generation: UUID) async throws {
        let createdAt = dateProvider.now()
        try store.writeCommand(.stop(generation: generation, createdAt: createdAt))
        notifier.postChange()
        do {
            _ = try await waiter.wait(timeout: .seconds(5)) { [waiter] status in
                waiter.isFresh(status)
                    && status.heartbeatAt >= createdAt
                    && status.requestedGeneration == generation
                    && status.state == .stopped
            }
        } catch is NativeRuntimeWaiterError {
            throw NativeWallpaperBackendError.timedOut
        }
    }

    private func isActive(_ status: NativeRuntimeStatus) -> Bool {
        waiter.isFresh(status) && status.activeDesktopContextCount > 0
    }

    private func removeGeneration(_ generation: UUID) async {
        _ = try? await Task.detached(priority: .utility) { [store] in
            try store.removeGeneration(generation)
        }.value
    }

    private func removeUnreferencedGenerations(keeping generations: Set<UUID>) async {
        _ = try? await Task.detached(priority: .utility) { [store] in
            try store.removeUnreferencedGenerations(keeping: generations)
        }.value
    }
}

private extension WallpaperDisplayMode {
    var nativeRuntimeDisplayMode: NativeRuntimeDisplayMode {
        switch self {
        case .fit:
            return .fit
        case .fill:
            return .fill
        case .stretch:
            return .stretch
        }
    }
}
