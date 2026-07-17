import AppKit
import AVFoundation

@MainActor
final class VideoWallpaperView: NSView,
    PausableWallpaperContent,
    DisplayModeUpdatableContent,
    WallpaperContentLifecycle,
    WallpaperRenderDiagnosticReporting,
    DesktopFallbackLiveSnapshotting {
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    private let playerLayer: AVPlayerLayer

    init(url: URL, frame: CGRect, displayMode: WallpaperDisplayMode) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        player = queue
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: frame)
        playerLayer.videoGravity = WallpaperContentLayout.videoGravity(for: displayMode)
        wantsLayer = true
        layer = playerLayer
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            player.play()
        }
    }

    func setPlaybackSuspended(_ suspended: Bool) {
        if suspended {
            player.pause()
        } else {
            player.play()
        }
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = WallpaperContentLayout.videoGravity(for: displayMode)
        CATransaction.commit()
    }

    func prepareForClose() {
        player.pause()
        player.removeAllItems()
    }

    func diagnosticRenderState(label: String) -> String {
        [
            "renderer=video",
            "renderLabel=\(label)",
            "playerAttached=\(playerLayer.player != nil)",
            "rate=\(player.rate)",
            "timeControlStatus=\(Self.timeControlStatusDescription(player.timeControlStatus))",
            "currentTime=\(Self.timeDescription(player.currentTime()))",
            "itemStatus=\(Self.itemStatusDescription(player.currentItem?.status))",
            "layerIsViewLayer=\(layer === playerLayer)",
            "layerHidden=\(playerLayer.isHidden)",
            "layerOpacity=\(playerLayer.opacity)",
            "layerBounds=\(NSStringFromRect(NSRectFromCGRect(playerLayer.bounds)))",
            "viewWindowAttached=\(window != nil)"
        ].joined(separator: " ")
    }

    func writeDesktopFallbackSnapshot(to output: URL) async throws {
        guard let input = (player.currentItem?.asset as? AVURLAsset)?.url else {
            throw DesktopFallbackError.liveSnapshotUnavailable
        }
        let seconds = CMTimeGetSeconds(player.currentTime())
        let requestedTime = CMTime(
            seconds: seconds.isFinite && seconds >= 0 ? seconds : 0.5,
            preferredTimescale: 600
        )
        try await Task.detached {
            let asset = AVURLAsset(url: input)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .positiveInfinity
            let image = try generator.copyCGImage(at: requestedTime, actualTime: nil)
            try DesktopFallbackPNGWriter.write(image, to: output)
        }.value
    }

    private static func timeControlStatusDescription(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    private static func itemStatusDescription(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .some(.unknown):
            return "unknown"
        case .some(.readyToPlay):
            return "readyToPlay"
        case .some(.failed):
            return "failed"
        case .none:
            return "nil"
        @unknown default:
            return "unknown"
        }
    }

    private static func timeDescription(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else {
            return "nonfinite"
        }
        return String(format: "%.3f", seconds)
    }
}
