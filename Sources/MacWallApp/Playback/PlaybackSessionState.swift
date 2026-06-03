import Foundation
import MacWallCore

enum PlaybackSessionPhase: Equatable {
    case idle
    case playing
    case suspended
    case restoring
    case failed
}

struct PlaybackOptions: Equatable {
    let autoPauseWhenCovered: Bool
    let experimentalSceneRendering: Bool
    let webMouseInteractionEnabled: Bool
    let displayMode: WallpaperDisplayMode

    static let defaults = PlaybackOptions(
        autoPauseWhenCovered: true,
        experimentalSceneRendering: false,
        webMouseInteractionEnabled: false,
        displayMode: .fit
    )
}

struct PlaybackSessionSnapshot: Equatable {
    let assetId: WallpaperAsset.ID
    let projectDirectory: String
    let phase: PlaybackSessionPhase
    let generation: UInt64
    let options: PlaybackOptions
}

struct PlaybackSessionState {
    private(set) var activeSnapshot: PlaybackSessionSnapshot?
    private(set) var phase: PlaybackSessionPhase = .idle
    private(set) var generation: UInt64 = 0

    mutating func startPlaying(asset: WallpaperAsset, options: PlaybackOptions) -> PlaybackSessionSnapshot {
        generation &+= 1
        phase = .playing
        let snapshot = PlaybackSessionSnapshot(
            assetId: asset.id,
            projectDirectory: asset.projectDirectory,
            phase: .playing,
            generation: generation,
            options: options
        )
        activeSnapshot = snapshot
        return snapshot
    }

    mutating func setSuspended(_ suspended: Bool) {
        guard let snapshot = activeSnapshot else {
            phase = .idle
            return
        }
        phase = suspended ? .suspended : .playing
        activeSnapshot = snapshot.withPhase(phase)
    }

    mutating func setRestoring() {
        guard let snapshot = activeSnapshot else {
            phase = .idle
            return
        }
        phase = .restoring
        activeSnapshot = snapshot.withPhase(.restoring)
    }

    mutating func beginRestoring() -> UInt64? {
        guard let snapshot = activeSnapshot else {
            phase = .idle
            return nil
        }
        generation &+= 1
        phase = .restoring
        activeSnapshot = snapshot.withPhase(.restoring, generation: generation)
        return generation
    }

    mutating func setFailed() {
        phase = .failed
        if let snapshot = activeSnapshot {
            activeSnapshot = snapshot.withPhase(.failed)
        }
    }

    mutating func stop() {
        generation &+= 1
        activeSnapshot = nil
        phase = .idle
    }

    func isCurrentGeneration(_ generation: UInt64) -> Bool {
        self.generation == generation
    }
}

private extension PlaybackSessionSnapshot {
    func withPhase(_ phase: PlaybackSessionPhase, generation: UInt64? = nil) -> PlaybackSessionSnapshot {
        PlaybackSessionSnapshot(
            assetId: assetId,
            projectDirectory: projectDirectory,
            phase: phase,
            generation: generation ?? self.generation,
            options: options
        )
    }
}
