import Foundation
import MacWallCore

enum LegacyPlaybackStopReason: Equatable {
    case userStop
    case handoffToNative
}

struct LegacyPlaybackReceipt: Equatable {
    let snapshot: PlaybackSessionSnapshot
    let restoreSupport: DesktopWallpaperRestoreSupport
}

@MainActor
protocol LegacyWallpaperBackendManaging: AnyObject {
    func play(
        asset: WallpaperAsset,
        options: PlaybackOptions
    ) throws -> LegacyPlaybackReceipt
    func stop(reason: LegacyPlaybackStopReason)
}

@MainActor
final class LegacyWallpaperBackend: LegacyWallpaperBackendManaging {
    private let wallpaperPlayer: WallpaperPlayerManaging
    private let fallbackCoordinator: DesktopFallbackCoordinating
    private let spaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating
    private var activeAsset: WallpaperAsset?

    init(
        wallpaperPlayer: WallpaperPlayerManaging = WallpaperPlayer.shared,
        fallbackCoordinator: DesktopFallbackCoordinating,
        spaceRefreshCoordinator: DesktopFallbackSpaceRefreshCoordinating
    ) {
        self.wallpaperPlayer = wallpaperPlayer
        self.fallbackCoordinator = fallbackCoordinator
        self.spaceRefreshCoordinator = spaceRefreshCoordinator
    }

    func play(
        asset: WallpaperAsset,
        options: PlaybackOptions
    ) throws -> LegacyPlaybackReceipt {
        let previousAsset = activeAsset
        do {
            let snapshot = try wallpaperPlayer.play(
                asset: asset,
                autoPauseWhenCovered: options.autoPauseWhenCovered,
                experimentalSceneRendering: options.experimentalSceneRendering,
                webMouseInteractionEnabled: options.webMouseInteractionEnabled,
                displayMode: options.displayMode
            )
            activeAsset = asset
            spaceRefreshCoordinator.setActiveAsset(asset)
            let restoreSupport = fallbackCoordinator.applyOrGenerate(asset: asset)
            return LegacyPlaybackReceipt(
                snapshot: snapshot,
                restoreSupport: restoreSupport
            )
        } catch {
            if let previousAsset {
                spaceRefreshCoordinator.setActiveAsset(previousAsset)
            } else {
                fallbackCoordinator.clearActiveAsset()
                spaceRefreshCoordinator.setActiveAsset(nil)
            }
            throw error
        }
    }

    func stop(reason: LegacyPlaybackStopReason) {
        wallpaperPlayer.stop()
        activeAsset = nil
        fallbackCoordinator.clearActiveAsset()
        spaceRefreshCoordinator.setActiveAsset(nil)
        if reason == .userStop {
            fallbackCoordinator.restoreOriginalWallpaperIfNeeded()
        }
    }
}
