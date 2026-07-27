import AVFoundation
import CoreMedia

final class NativeVideoRendererAdapter: @unchecked Sendable {
    let renderer: AVSampleBufferVideoRenderer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        renderer = displayLayer.sampleBufferRenderer
    }

    var isReadyForMoreMediaData: Bool { renderer.isReadyForMoreMediaData }
    var status: AVQueuedSampleBufferRenderingStatus { renderer.status }
    var error: Error? { renderer.error }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        renderer.enqueue(sampleBuffer)
    }

    func requestMediaDataWhenReady(
        on queue: DispatchQueue,
        block: @escaping @Sendable () -> Void
    ) {
        renderer.requestMediaDataWhenReady(on: queue, using: block)
    }

    func stopRequestingMediaData() {
        renderer.stopRequestingMediaData()
    }

    func flush(
        removeDisplayedImage: Bool,
        completion: (@Sendable () -> Void)? = nil
    ) {
        renderer.flush(
            removingDisplayedImage: removeDisplayedImage,
            completionHandler: completion
        )
    }
}
