import Foundation
import MacWallCore

enum PlaybackBackendKind: Equatable {
    case legacy
    case native
}

struct PlaybackReceipt: Equatable {
    let backend: PlaybackBackendKind
    let assetID: WallpaperAsset.ID
    let projectDirectory: String
    let nativeGeneration: UUID?
    let restoreSupport: DesktopWallpaperRestoreSupport?
}

struct PendingPlaybackRequest: Equatable {
    let requestID: UUID
    let asset: WallpaperAsset
    let options: PlaybackOptions
    let remember: Bool
}

enum PlaybackStartOutcome: Equatable {
    case started(PlaybackReceipt)
    case nativeSetupRequired(PendingPlaybackRequest)
    case cancelled
}

enum NativeWallpaperSetupChoice: Equatable {
    case cancel
    case useLegacyOnce
    case openSettings
}

@MainActor
protocol WallpaperPlaybackCoordinating: AnyObject {
    func play(_ request: PendingPlaybackRequest) async throws -> PlaybackStartOutcome
    func resolveNativeSetup(
        _ choice: NativeWallpaperSetupChoice,
        pending: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome
    func stop() async throws
}

@MainActor
final class WallpaperPlaybackCoordinator: WallpaperPlaybackCoordinating {
    private enum Route {
        case automatic
        case legacy
        case nativeAfterSettings
    }

    private struct InFlightRequest {
        let request: PendingPlaybackRequest
        let task: Task<PlaybackStartOutcome, Error>
    }

    private let eligibility: NativeWallpaperEligibility
    private let nativeBackend: NativeWallpaperBackendManaging
    private let legacyBackend: LegacyWallpaperBackendManaging
    private var inFlight: InFlightRequest?
    private var latestRequestID: UUID?
    private(set) var activeReceipt: PlaybackReceipt?

    init(
        eligibility: NativeWallpaperEligibility = NativeWallpaperEligibility(),
        nativeBackend: NativeWallpaperBackendManaging,
        legacyBackend: LegacyWallpaperBackendManaging
    ) {
        self.eligibility = eligibility
        self.nativeBackend = nativeBackend
        self.legacyBackend = legacyBackend
    }

    func play(_ request: PendingPlaybackRequest) async throws -> PlaybackStartOutcome {
        try await start(request, route: .automatic)
    }

    func resolveNativeSetup(
        _ choice: NativeWallpaperSetupChoice,
        pending: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome {
        switch choice {
        case .cancel:
            return .cancelled
        case .useLegacyOnce:
            return try await start(pending, route: .legacy)
        case .openSettings:
            return try await start(pending, route: .nativeAfterSettings)
        }
    }

    func stop() async throws {
        latestRequestID = nil
        inFlight?.task.cancel()
        inFlight = nil

        switch activeReceipt?.backend {
        case .legacy:
            legacyBackend.stop(reason: .userStop)
            activeReceipt = nil
        case .native:
            try await nativeBackend.stop(generation: UUID())
            activeReceipt = nil
        case nil:
            break
        }
    }

    private func start(
        _ request: PendingPlaybackRequest,
        route: Route
    ) async throws -> PlaybackStartOutcome {
        if route == .automatic,
           let inFlight,
           inFlight.request.asset.id == request.asset.id,
           inFlight.request.asset.projectDirectory == request.asset.projectDirectory,
           inFlight.request.options == request.options {
            return try await inFlight.task.value
        }

        inFlight?.task.cancel()
        latestRequestID = request.requestID
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return PlaybackStartOutcome.cancelled
            }
            return try await self.perform(request, route: route)
        }
        inFlight = InFlightRequest(request: request, task: task)

        do {
            let outcome = try await task.value
            if inFlight?.request.requestID == request.requestID {
                inFlight = nil
            }
            return outcome
        } catch {
            if inFlight?.request.requestID == request.requestID {
                inFlight = nil
            }
            throw error
        }
    }

    private func perform(
        _ request: PendingPlaybackRequest,
        route: Route
    ) async throws -> PlaybackStartOutcome {
        switch route {
        case .legacy:
            return try await startLegacy(request)
        case .nativeAfterSettings:
            guard case .active = await nativeBackend.activationStatus(timeout: .seconds(120)) else {
                return .nativeSetupRequired(request)
            }
            return try await startNative(request)
        case .automatic:
            guard eligibility.isEligible(request.asset) else {
                return try await startLegacy(request)
            }
            guard case .active = await nativeBackend.activationStatus(timeout: .milliseconds(500)) else {
                return .nativeSetupRequired(request)
            }
            return try await startNative(request)
        }
    }

    private func startNative(
        _ request: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome {
        let generation = UUID()
        let nativeReceipt = try await nativeBackend.play(
            asset: request.asset,
            displayMode: request.options.displayMode,
            generation: generation,
            timeout: .seconds(5)
        )
        try Task.checkCancellation()
        guard latestRequestID == request.requestID else {
            return .cancelled
        }

        if activeReceipt?.backend == .legacy {
            legacyBackend.stop(reason: .handoffToNative)
        }
        let receipt = PlaybackReceipt(
            backend: .native,
            assetID: nativeReceipt.assetID,
            projectDirectory: nativeReceipt.projectDirectory,
            nativeGeneration: nativeReceipt.generation,
            restoreSupport: nil
        )
        activeReceipt = receipt
        return .started(receipt)
    }

    private func startLegacy(
        _ request: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome {
        let legacyReceipt = try legacyBackend.play(
            asset: request.asset,
            options: request.options
        )
        try Task.checkCancellation()
        guard latestRequestID == request.requestID else {
            return .cancelled
        }

        if activeReceipt?.backend == .native {
            do {
                try await nativeBackend.stop(generation: UUID())
            } catch {
                legacyBackend.stop(reason: .handoffToNative)
                throw error
            }
        }
        let receipt = PlaybackReceipt(
            backend: .legacy,
            assetID: legacyReceipt.snapshot.assetId,
            projectDirectory: legacyReceipt.snapshot.projectDirectory,
            nativeGeneration: nil,
            restoreSupport: legacyReceipt.restoreSupport
        )
        activeReceipt = receipt
        return .started(receipt)
    }
}
