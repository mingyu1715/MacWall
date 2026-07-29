import AVFoundation
import CoreMedia
import CoreVideo
import MacWallNativeRuntimeSupport
import QuartzCore

enum NativeVideoFrameBridgeError: Error, Equatable, Sendable {
    case sourceUnavailable
    case readerCreationFailed
    case readerFailed
    case rendererFailed
    case sampleRetimingFailed
}

final class NativeVideoFrameBridge: @unchecked Sendable {
    struct Callbacks: Sendable {
        let firstFrameEnqueued: @Sendable () -> Void
        let failed: @Sendable (NativeVideoFrameBridgeError) -> Void

        init(
            firstFrameEnqueued: @escaping @Sendable () -> Void,
            failed: @escaping @Sendable (NativeVideoFrameBridgeError) -> Void
        ) {
            self.firstFrameEnqueued = firstFrameEnqueued
            self.failed = failed
        }
    }

    private let bridgeID = UUID().uuidString.uppercased()
    private let videoURL: URL
    private let callbacks: Callbacks
    private let rendererAdapter: NativeVideoRendererAdapter
    private let playbackClock: NativeVideoPlaybackClock
    private let timingPolicy = NativeVideoPlaybackTimingPolicy(
        configuration: .normal
    )
    private let queue = DispatchQueue(
        label: "macwall.native-video-frame-bridge",
        qos: .userInitiated
    )

    private var assetReader: AVAssetReader?
    private var assetOutput: AVAssetReaderTrackOutput?
    private var assetDuration: CMTime = .invalid
    private var assetLoopIndex: Int64 = 0
    private var pendingSampleBuffer: CMSampleBuffer?
    private var pumpGeneration = NativeVideoAssetPumpGeneration()
    private var queuedFrameCount: Int64 = 0
    private var droppedFrameCount: Int64 = 0
    private var lastEnqueuedPTSSeconds: Double?
    private var hardResetTracker = NativeVideoHardResetTracker(
        windowSeconds: 5
    )
    private var lastTimingLogHostTime: CFTimeInterval = 0
    private var isRunning = false
    private var didEnqueueFirstFrame = false
    private var didFail = false
    private var didTearDown = false

    let layer: AVSampleBufferDisplayLayer

    init(
        videoURL: URL,
        frame: CGRect,
        contentsScale: CGFloat,
        displayMode: NativeRuntimeDisplayMode,
        callbacks: Callbacks
    ) {
        self.videoURL = videoURL
        self.callbacks = callbacks

        let layer = AVSampleBufferDisplayLayer()
        layer.name = "MacWallSampleBufferDisplayLayer"
        layer.frame = normalizedBridgeFrame(frame)
        layer.bounds = CGRect(
            origin: .zero,
            size: normalizedBridgeFrame(frame).size
        )
        layer.contentsScale = max(contentsScale, 1)
        layer.videoGravity = videoGravity(for: displayMode)
        self.layer = layer

        let rendererAdapter = NativeVideoRendererAdapter(
            displayLayer: layer
        )
        self.rendererAdapter = rendererAdapter
        playbackClock = NativeVideoPlaybackClock(
            renderer: rendererAdapter.renderer
        )
    }

    func start() {
        queue.async { [weak self] in
            guard let self,
                  !self.isRunning,
                  !self.didTearDown,
                  !self.didFail else {
                return
            }
            self.isRunning = true
            self.startAssetPlayback()
        }
    }

    func setDisplayMode(_ displayMode: NativeRuntimeDisplayMode) {
        layer.videoGravity = videoGravity(for: displayMode)
    }

    func freezeKeepingLastFrame(reason: String) {
        queue.async { [weak self] in
            guard let self, !self.didTearDown else {
                return
            }
            self.isRunning = false
            _ = self.pumpGeneration.advance()
            self.pendingSampleBuffer = nil
            self.rendererAdapter.stopRequestingMediaData()
            self.playbackClock.pause()
            self.resetAssetReader()
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge frozen bridgeID=\(self.bridgeID, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }
    }

    func teardown(reason: String) {
        queue.async { [weak self] in
            guard let self, !self.didTearDown else {
                return
            }
            self.didTearDown = true
            self.isRunning = false
            _ = self.pumpGeneration.advance()
            self.pendingSampleBuffer = nil
            self.rendererAdapter.stopRequestingMediaData()
            self.resetAssetReader()
            self.playbackClock.stop { [weak self] in
                guard let self else {
                    return
                }
                self.queue.async {
                    self.rendererAdapter.flush(removeDisplayedImage: true)
                    self.layer.removeFromSuperlayer()
                    macWallNativeWallpaperLogger.info(
                        "nativeVideoBridge tornDown bridgeID=\(self.bridgeID, privacy: .public) reason=\(reason, privacy: .public)"
                    )
                }
            }
        }
    }

    private func startAssetPlayback() {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            fail(.sourceUnavailable)
            return
        }
        guard startAssetReader() else {
            return
        }

        let generation = pumpGeneration.advance()
        pendingSampleBuffer = nil
        queuedFrameCount = 0
        droppedFrameCount = 0
        assetLoopIndex = 0
        lastEnqueuedPTSSeconds = nil
        hardResetTracker = NativeVideoHardResetTracker(windowSeconds: 5)
        playbackClock.start(at: .zero)
        requestPump(generation: generation)
        macWallNativeWallpaperLogger.info(
            "nativeVideoBridge started bridgeID=\(self.bridgeID, privacy: .public) source=\(self.videoURL.lastPathComponent, privacy: .public)"
        )
    }

    private func requestPump(generation: UInt64) {
        guard isRunning,
              !didTearDown,
              pumpGeneration.accepts(generation) else {
            return
        }
        rendererAdapter.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.pumpAssetFrames(generation: generation)
        }
    }

    private func schedulePump(
        generation: UInt64,
        transition: NativeVideoAssetPumpTransition
    ) {
        guard let delay = transition.retryDelaySeconds else {
            return
        }
        let clampedDelay = min(max(delay, 0.005), 0.500)
        if transition.stopsRequestingMediaData {
            rendererAdapter.stopRequestingMediaData()
        }
        queue.asyncAfter(deadline: .now() + clampedDelay) { [weak self] in
            guard let self,
                  self.isRunning,
                  !self.didTearDown,
                  self.pumpGeneration.accepts(generation) else {
                return
            }
            self.requestPump(generation: generation)
        }
    }

    private func pumpAssetFrames(generation: UInt64) {
        guard isRunning,
              !didTearDown,
              pumpGeneration.accepts(generation) else {
            return
        }
        if rendererAdapter.status == .failed {
            fail(.rendererFailed)
            return
        }

        while isRunning,
              !didTearDown,
              pumpGeneration.accepts(generation) {
            guard let assetOutput else {
                fail(.readerFailed)
                return
            }

            let sampleBuffer: CMSampleBuffer
            if let pendingSampleBuffer {
                sampleBuffer = pendingSampleBuffer
            } else {
                guard let sourceSample = assetOutput.copyNextSampleBuffer() else {
                    switch assetReader?.status {
                    case .completed:
                        assetLoopIndex += 1
                        resetAssetReader()
                        guard startAssetReader() else {
                            return
                        }
                        continue
                    case .failed, .cancelled:
                        fail(.readerFailed)
                    default:
                        break
                    }
                    return
                }

                let loopOffset = NativeVideoSampleRetimer.loopOffset(
                    assetDuration: assetDuration,
                    loopIndex: assetLoopIndex
                )
                do {
                    sampleBuffer = try NativeVideoSampleRetimer.retime(
                        sourceSample,
                        by: loopOffset
                    )
                } catch {
                    fail(.sampleRetimingFailed)
                    return
                }
                pendingSampleBuffer = sampleBuffer
            }

            let samplePTS = CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )
            let samplePTSSeconds = CMTimeGetSeconds(samplePTS)
            let mediaTimeSeconds = CMTimeGetSeconds(
                playbackClock.currentTime
            )
            guard samplePTSSeconds.isFinite,
                  mediaTimeSeconds.isFinite else {
                fail(.sampleRetimingFailed)
                return
            }

            let rendererReady = rendererAdapter.isReadyForMoreMediaData
            let evaluation = timingPolicy.evaluate(
                samplePTSSeconds: samplePTSSeconds,
                mediaTimeSeconds: mediaTimeSeconds,
                rendererReady: rendererReady,
                lastEnqueuedPTSSeconds: lastEnqueuedPTSSeconds
            )
            let transition = NativeVideoAssetPumpTransition(
                decision: evaluation.decision
            )

            switch evaluation.decision {
            case .enqueue:
                rendererAdapter.enqueue(sampleBuffer)
                pendingSampleBuffer = nil
                queuedFrameCount += 1
                lastEnqueuedPTSSeconds = samplePTSSeconds
                notifyFirstFrameIfNeeded()
                logTiming(
                    evaluation,
                    samplePTSSeconds: samplePTSSeconds,
                    mediaTimeSeconds: mediaTimeSeconds,
                    rendererReady: rendererReady
                )
            case .wait:
                logTiming(
                    evaluation,
                    samplePTSSeconds: samplePTSSeconds,
                    mediaTimeSeconds: mediaTimeSeconds,
                    rendererReady: rendererReady
                )
                schedulePump(
                    generation: generation,
                    transition: transition
                )
                return
            case .waitForRenderer:
                return
            case .drop:
                pendingSampleBuffer = nil
                droppedFrameCount += 1
                logTiming(
                    evaluation,
                    samplePTSSeconds: samplePTSSeconds,
                    mediaTimeSeconds: mediaTimeSeconds,
                    rendererReady: rendererReady
                )
            case .reset:
                guard hardResetTracker.registerReset(
                    at: CACurrentMediaTime()
                ) == .retry else {
                    fail(.readerFailed)
                    return
                }
                rendererAdapter.stopRequestingMediaData()
                rendererAdapter.flush(
                    removeDisplayedImage: false
                ) { [weak self] in
                    guard let self else {
                        return
                    }
                    self.queue.async {
                        guard self.isRunning,
                              !self.didTearDown,
                              self.pumpGeneration.accepts(generation) else {
                            return
                        }
                        self.lastEnqueuedPTSSeconds = nil
                        self.playbackClock.seek(to: samplePTS)
                        self.schedulePump(
                            generation: generation,
                            transition: transition
                        )
                    }
                }
                return
            }
        }
    }

    private func startAssetReader() -> Bool {
        resetAssetReader()
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(
            withMediaType: .video
        ).first else {
            fail(.readerCreationFailed)
            return false
        }
        let duration = videoTrack.timeRange.duration
        guard duration.isNumeric,
              CMTimeCompare(duration, .zero) > 0 else {
            fail(.readerCreationFailed)
            return false
        }

        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA,
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                fail(.readerCreationFailed)
                return false
            }
            reader.add(output)
            guard reader.startReading() else {
                fail(.readerFailed)
                return false
            }
            assetReader = reader
            assetOutput = output
            assetDuration = duration
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge assetReader started bridgeID=\(self.bridgeID, privacy: .public) url=\(self.videoURL.lastPathComponent, privacy: .public)"
            )
            return true
        } catch {
            fail(.readerCreationFailed)
            return false
        }
    }

    private func resetAssetReader() {
        assetOutput = nil
        assetReader?.cancelReading()
        assetReader = nil
    }

    private func notifyFirstFrameIfNeeded() {
        guard !didEnqueueFirstFrame else {
            return
        }
        didEnqueueFirstFrame = true
        callbacks.firstFrameEnqueued()
    }

    private func fail(_ error: NativeVideoFrameBridgeError) {
        guard !didFail, !didTearDown else {
            return
        }
        didFail = true
        isRunning = false
        _ = pumpGeneration.advance()
        pendingSampleBuffer = nil
        rendererAdapter.stopRequestingMediaData()
        playbackClock.pause()
        resetAssetReader()
        macWallNativeWallpaperLogger.error(
            "nativeVideoBridge failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
        callbacks.failed(error)
    }

    private func logTiming(
        _ evaluation: NativeVideoPlaybackEvaluation,
        samplePTSSeconds: Double,
        mediaTimeSeconds: Double,
        rendererReady: Bool
    ) {
        let hostTime = CACurrentMediaTime()
        guard hostTime - lastTimingLogHostTime >= 1 else {
            return
        }
        lastTimingLogHostTime = hostTime
        macWallNativeWallpaperLogger.info(
            "nativeVideoTiming bridgeID=\(self.bridgeID, privacy: .public) samplePTS=\(samplePTSSeconds) mediaNow=\(mediaTimeSeconds) lead=\(evaluation.leadSeconds) bufferBand=\(evaluation.bufferBand.rawValue, privacy: .public) rendererReady=\(rendererReady) loopIndex=\(self.assetLoopIndex) droppedFrameCount=\(self.droppedFrameCount) queuedFrameCount=\(self.queuedFrameCount) profile=normal clockMode=synchronizer"
        )
    }
}

private func normalizedBridgeFrame(_ frame: CGRect) -> CGRect {
    guard frame.width.isFinite,
          frame.height.isFinite,
          frame.width > 0,
          frame.height > 0 else {
        return CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    return frame
}

private func videoGravity(
    for displayMode: NativeRuntimeDisplayMode
) -> AVLayerVideoGravity {
    switch displayMode {
    case .fit:
        return .resizeAspect
    case .fill:
        return .resizeAspectFill
    case .stretch:
        return .resize
    }
}
