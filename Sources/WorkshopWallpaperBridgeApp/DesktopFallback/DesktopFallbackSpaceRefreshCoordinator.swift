import AppKit
import Foundation
import WorkshopWallpaperCore

@MainActor
final class DesktopFallbackSpaceRefreshCoordinator {
    typealias CaptureLiveSnapshot = @MainActor (WallpaperAsset, URL) async throws -> Void

    struct Options: Equatable, Sendable {
        let stabilizationDelay: Duration
        let throttle: Duration

        static let `default` = Options(
            stabilizationDelay: .milliseconds(500),
            throttle: .seconds(20)
        )
    }

    private let notificationCenter: NotificationCenter
    private let fallbackCoordinator: DesktopFallbackCoordinator
    private let options: Options
    private let captureLiveSnapshot: CaptureLiveSnapshot
    private let clock = ContinuousClock()
    private var activeAsset: WallpaperAsset?
    private var observer: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: ContinuousClock.Instant?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        fallbackCoordinator: DesktopFallbackCoordinator,
        options: Options = .default,
        captureLiveSnapshot: CaptureLiveSnapshot? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.fallbackCoordinator = fallbackCoordinator
        self.options = options
        self.captureLiveSnapshot = captureLiveSnapshot ?? { asset, output in
            try await WallpaperPlayer.shared.writeActiveDesktopFallbackSnapshot(asset: asset, to: output)
        }
    }

    func start() {
        guard observer == nil else {
            return
        }
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleActiveSpaceDidChange()
            }
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func setActiveAsset(_ asset: WallpaperAsset?) {
        activeAsset = asset
    }

    func handleActiveSpaceDidChange() {
        guard let asset = activeAsset, Self.supportsRefresh(asset) else {
            return
        }
        let now = clock.now
        if let lastRefresh, lastRefresh.duration(to: now) < options.throttle {
            return
        }
        lastRefresh = now
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self, asset, options] in
            try? await Task.sleep(for: options.stabilizationDelay)
            guard let self, self.activeAssetKey == Self.assetKey(asset) else {
                return
            }
            try? await self.fallbackCoordinator.refreshFromLiveSnapshot(asset: asset) { output in
                try await self.captureLiveSnapshot(asset, output)
            }
        }
    }

    func waitForRefresh() async {
        await refreshTask?.value
    }

    private var activeAssetKey: String? {
        activeAsset.map(Self.assetKey)
    }

    private static func supportsRefresh(_ asset: WallpaperAsset) -> Bool {
        asset.kind == .video || asset.kind == .web
    }

    private static func assetKey(_ asset: WallpaperAsset) -> String {
        URL(filePath: asset.projectDirectory).standardizedFileURL.path
    }
}
