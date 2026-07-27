import AVFoundation
import CoreMedia

final class NativeVideoPlaybackClock: @unchecked Sendable {
    private let renderer: AVSampleBufferVideoRenderer
    private let synchronizer: AVSampleBufferRenderSynchronizer
    private var isRunning = false
    private var isStopped = false

    init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
        synchronizer = AVSampleBufferRenderSynchronizer()
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        synchronizer.addRenderer(renderer)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=created mode=synchronizer"
        )
    }

    var currentTime: CMTime {
        synchronizer.currentTime()
    }

    func start(at time: CMTime) {
        isRunning = true
        isStopped = false
        synchronizer.setRate(1, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=start mode=synchronizer time=\(CMTimeGetSeconds(time))"
        )
    }

    func pause() {
        let time = currentTime
        isRunning = false
        synchronizer.setRate(0, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=pause mode=synchronizer time=\(CMTimeGetSeconds(time))"
        )
    }

    func seek(to time: CMTime) {
        synchronizer.setRate(isRunning ? 1 : 0, time: time)
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=seek mode=synchronizer time=\(CMTimeGetSeconds(time))"
        )
    }

    func stop(completion: (@Sendable () -> Void)? = nil) {
        guard !isStopped else {
            completion?()
            return
        }
        let time = currentTime
        isRunning = false
        synchronizer.setRate(0, time: time)
        isStopped = true
        synchronizer.removeRenderer(renderer, at: .invalid) { _ in
            completion?()
        }
        macWallNativeWallpaperLogger.info(
            "nativeVideoClock event=stop mode=synchronizer time=\(CMTimeGetSeconds(time))"
        )
    }
}
