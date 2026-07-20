import AVFoundation
import CoreMedia

final class NativeVideoPlaybackClock: @unchecked Sendable {
    let mode: MacWallNativeWallpaperTimingClockMode

    private let renderer: AVSampleBufferVideoRenderer
    private var timebase: CMTimebase?
    private var synchronizer: AVSampleBufferRenderSynchronizer?
    private var isRunning = false
    private var isStopped = false

    init(
        mode: MacWallNativeWallpaperTimingClockMode,
        displayLayer: AVSampleBufferDisplayLayer,
        renderer: AVSampleBufferVideoRenderer
    ) {
        self.mode = mode
        self.renderer = renderer

        switch mode {
        case .controlTimebase:
            var createdTimebase: CMTimebase?
            let status = CMTimebaseCreateWithSourceClock(
                allocator: kCFAllocatorDefault,
                sourceClock: CMClockGetHostTimeClock(),
                timebaseOut: &createdTimebase
            )
            precondition(status == noErr && createdTimebase != nil, "failed to create native video timebase")
            timebase = createdTimebase
            displayLayer.controlTimebase = createdTimebase
        case .synchronizer:
            displayLayer.controlTimebase = nil
            let createdSynchronizer = AVSampleBufferRenderSynchronizer()
            createdSynchronizer.addRenderer(renderer)
            synchronizer = createdSynchronizer
        }

        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=created mode=\(mode.rawValue, privacy: .public)"
        )
    }

    var currentTime: CMTime {
        switch mode {
        case .controlTimebase:
            guard let timebase else { return .invalid }
            return CMTimebaseGetTime(timebase)
        case .synchronizer:
            return synchronizer?.currentTime() ?? .invalid
        }
    }

    func start(at time: CMTime) {
        isRunning = true
        isStopped = false
        setRate(1, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=start mode=\(self.mode.rawValue, privacy: .public) time=\(CMTimeGetSeconds(time))"
        )
    }

    func pause() {
        let time = currentTime
        isRunning = false
        setRate(0, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=pause mode=\(self.mode.rawValue, privacy: .public) time=\(CMTimeGetSeconds(time))"
        )
    }

    func seek(to time: CMTime) {
        setRate(isRunning ? 1 : 0, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=seek mode=\(self.mode.rawValue, privacy: .public) time=\(CMTimeGetSeconds(time))"
        )
    }

    func stop() {
        guard !isStopped else { return }
        let time = currentTime
        isRunning = false
        setRate(0, time: time)
        if let synchronizer {
            synchronizer.removeRenderer(renderer, at: .invalid, completionHandler: nil)
        }
        isStopped = true
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=stop mode=\(self.mode.rawValue, privacy: .public) time=\(CMTimeGetSeconds(time))"
        )
    }

    private func setRate(_ rate: Float, time: CMTime) {
        switch mode {
        case .controlTimebase:
            guard let timebase else { return }
            CMTimebaseSetTime(timebase, time: time)
            CMTimebaseSetRate(timebase, rate: Double(rate))
        case .synchronizer:
            synchronizer?.setRate(rate, time: time)
        }
    }
}
