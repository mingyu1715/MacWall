import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

final class NativeVideoFrameBridge: @unchecked Sendable {
    private enum Source {
        case generated
        case asset(URL)

        var logName: String {
            switch self {
            case .generated:
                "generated"
            case .asset:
                "asset"
            }
        }
    }

    private let bridgeID = UUID().uuidString.uppercased()
    private let displayLayer: AVSampleBufferDisplayLayer
    private let rendererAdapter: NativeVideoRendererAdapter
    private let playbackClock: NativeVideoPlaybackClock?
    private let timingPolicy: NativeVideoPlaybackTimingPolicy
    private let timingProfile: MacWallNativeWallpaperTimingProfile
    private let source: Source
    private let queue = DispatchQueue(label: "macwall.native-video-frame-bridge", qos: .userInitiated)
    private let width = 640
    private let height = 360
    private let frameRate: Int32 = 30
    private var frameIndex: Int64 = 0
    private var timer: DispatchSourceTimer?
    private var assetReader: AVAssetReader?
    private var assetOutput: AVAssetReaderTrackOutput?
    private var assetDuration: CMTime = .invalid
    private var assetLoopIndex: Int64 = 0
    private var pendingAssetSampleBuffer: CMSampleBuffer?
    private var assetPumpGeneration = NativeVideoAssetPumpGeneration()
    private var queuedFrameCount: Int64 = 0
    private var droppedFrameCount: Int64 = 0
    private var lastEnqueuedPTSSeconds: Double?
    private var hardResetTracker = NativeVideoHardResetTracker(windowSeconds: 5)
    private var lastTimingLogHostTime: CFTimeInterval = 0
    private var isRunning = false
    private var didStop = false

    private init(rootLayer: CALayer, size: CGSize, scale: CGFloat, source: Source) {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.name = "MacWallSampleBufferDisplayLayer"
        displayLayer.frame = CGRect(origin: .zero, size: normalizedBridgeSize(size))
        displayLayer.bounds = CGRect(origin: .zero, size: normalizedBridgeSize(size))
        displayLayer.contentsScale = max(scale, 1)
        displayLayer.videoGravity = .resizeAspectFill

        let rendererAdapter = NativeVideoRendererAdapter(displayLayer: displayLayer)
        let timingProfile = MacWallNativeWallpaperTimingConfiguration.profile
        let timingConfiguration: NativeVideoPlaybackTimingConfiguration = switch timingProfile {
        case .normal:
            .normal
        case .reduced:
            .reduced
        }

        self.displayLayer = displayLayer
        self.rendererAdapter = rendererAdapter
        self.playbackClock = switch source {
        case .generated:
            nil
        case .asset:
            NativeVideoPlaybackClock(
                mode: MacWallNativeWallpaperTimingConfiguration.clockMode,
                displayLayer: displayLayer,
                renderer: rendererAdapter.renderer
            )
        }
        self.timingPolicy = NativeVideoPlaybackTimingPolicy(configuration: timingConfiguration)
        self.timingProfile = timingProfile
        self.source = source
        rootLayer.addSublayer(displayLayer)
    }

    static func attachDesktopProbe(to rootLayer: CALayer, size: CGSize, scale: CGFloat) -> NativeVideoFrameBridge {
        switch MacWallNativeWallpaperVideoSourceModeConfiguration.mode {
        case .generated:
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge videoSourceMode=generated; bypassing bundled mp4 and AVAssetReader"
            )
            return attachGeneratedProbe(to: rootLayer, size: size, scale: scale)
        case .asset:
            if let videoURL = MacWallNativeWallpaperVideoSource.bundledProbeURL() {
                macWallNativeWallpaperLogger.info(
                    "nativeVideoBridge videoSourceMode=asset; using bundled mp4"
                )
                return attachAssetProbe(videoURL: videoURL, to: rootLayer, size: size, scale: scale)
            }
        }

        macWallNativeWallpaperLogger.warning(
            "nativeVideoBridge videoSourceMode=asset bundled mp4 resource missing; falling back to generated sample-buffer probe"
        )
        return attachGeneratedProbe(to: rootLayer, size: size, scale: scale)
    }

    static func attachGeneratedProbe(to rootLayer: CALayer, size: CGSize, scale: CGFloat) -> NativeVideoFrameBridge {
        let bridge = NativeVideoFrameBridge(rootLayer: rootLayer, size: size, scale: scale, source: .generated)
        macWallNativeWallpaperLogger.info(
            "nativeVideoBridge attached bridgeID=\(bridge.bridgeID, privacy: .public) generated AVSampleBufferDisplayLayer frame=\(formatBridgeSize(size), privacy: .public) scale=\(scale) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        return bridge
    }

    static func attachAssetProbe(videoURL: URL, to rootLayer: CALayer, size: CGSize, scale: CGFloat) -> NativeVideoFrameBridge {
        let bridge = NativeVideoFrameBridge(rootLayer: rootLayer, size: size, scale: scale, source: .asset(videoURL))
        macWallNativeWallpaperLogger.info(
            "nativeVideoBridge attached bridgeID=\(bridge.bridgeID, privacy: .public) asset AVSampleBufferDisplayLayer url=\(videoURL.lastPathComponent, privacy: .public) frame=\(formatBridgeSize(size), privacy: .public) scale=\(scale) \(MacWallNativeWallpaperRuntimeIdentity.current.logDescription, privacy: .public)"
        )
        return bridge
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning, !self.didStop else {
                return
            }

            self.isRunning = true

            switch self.source {
            case .generated:
                self.startGeneratedFrames(reason: "start-generated")
            case .asset(let url):
                self.startAssetFrames(videoURL: url)
            }

            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge started bridgeID=\(self.bridgeID, privacy: .public) source=\(self.source.logName, privacy: .public)"
            )
        }
    }

    func stop(reason: String) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard !self.didStop else {
                macWallNativeWallpaperLogger.info(
                    "nativeVideoBridge stop skipped bridgeID=\(self.bridgeID, privacy: .public) reason=\(reason, privacy: .public) alreadyStopped=true"
                )
                return
            }
            self.didStop = true
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.assetPumpGeneration.advance()
            self.pendingAssetSampleBuffer = nil
            self.rendererAdapter.stopRequestingMediaData()
            self.playbackClock?.stop()
            self.resetAssetReader()
            self.rendererAdapter.flush(removeDisplayedImage: true)
            self.displayLayer.removeFromSuperlayer()
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge stopped bridgeID=\(self.bridgeID, privacy: .public) reason=\(reason, privacy: .public) lastFrame=\(self.frameIndex)"
            )
        }
    }

    private func startGeneratedFrames(reason: String) {
        guard isRunning, !didStop else {
            return
        }

        timer?.cancel()
        timer = nil
        enqueueNextGeneratedFrame()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(Int(1_000 / frameRate)),
            repeating: .milliseconds(Int(1_000 / frameRate))
        )
        timer.setEventHandler { [weak self] in
            self?.enqueueNextGeneratedFrame()
        }
        self.timer = timer
        timer.resume()
        macWallNativeWallpaperLogger.info(
            "nativeVideoBridge generated stream active bridgeID=\(self.bridgeID, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    private func startAssetFrames(videoURL: URL) {
        guard isRunning, !didStop else {
            return
        }

        guard startAssetReader(videoURL: videoURL) else {
            fallbackToGeneratedFrames(reason: "asset-reader-start-failed")
            return
        }
        guard let playbackClock else {
            fallbackToGeneratedFrames(reason: "asset-playback-clock-missing")
            return
        }

        let generation = assetPumpGeneration.advance()
        pendingAssetSampleBuffer = nil
        queuedFrameCount = 0
        droppedFrameCount = 0
        assetLoopIndex = 0
        lastEnqueuedPTSSeconds = nil
        hardResetTracker = NativeVideoHardResetTracker(windowSeconds: 5)
        playbackClock.start(at: .zero)
        requestAssetPump(videoURL: videoURL, generation: generation)
    }

    private func enqueueNextGeneratedFrame() {
        guard isRunning else {
            return
        }

        if rendererAdapter.status == .failed {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge displayLayer failed: \(String(describing: self.rendererAdapter.error), privacy: .public)"
            )
            rendererAdapter.flush(removeDisplayedImage: false)
        }

        guard rendererAdapter.isReadyForMoreMediaData,
              let sampleBuffer = makeSampleBuffer(frameIndex: frameIndex) else {
            return
        }

        rendererAdapter.enqueue(sampleBuffer)
        if frameIndex % Int64(frameRate) == 0 {
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge enqueued bridgeID=\(self.bridgeID, privacy: .public) generatedFrame=\(self.frameIndex)"
            )
        }
        frameIndex += 1
    }

    private func requestAssetPump(videoURL: URL, generation: UInt64) {
        guard isRunning, !didStop, assetPumpGeneration.accepts(generation) else {
            return
        }

        rendererAdapter.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.pumpAssetFrames(videoURL: videoURL, generation: generation)
        }
    }

    private func scheduleAssetPump(
        videoURL: URL,
        generation: UInt64,
        transition: NativeVideoAssetPumpTransition
    ) {
        guard let delay = transition.retryDelaySeconds else {
            return
        }
        let clampedDelay = min(max(delay, 0.005), 0.500)
        let delayMilliseconds = Int((clampedDelay * 1_000).rounded(.up))
        if transition.stopsRequestingMediaData {
            rendererAdapter.stopRequestingMediaData()
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(delayMilliseconds)) { [weak self] in
            guard let self,
                  self.isRunning,
                  !self.didStop,
                  self.assetPumpGeneration.accepts(generation) else {
                return
            }
            self.requestAssetPump(videoURL: videoURL, generation: generation)
        }
    }

    private func pumpAssetFrames(videoURL: URL, generation: UInt64) {
        guard isRunning, !didStop, assetPumpGeneration.accepts(generation) else {
            return
        }
        guard let playbackClock else {
            fallbackToGeneratedFrames(reason: "asset-playback-clock-missing")
            return
        }

        if rendererAdapter.status == .failed {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge asset renderer failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: self.rendererAdapter.error), privacy: .public)"
            )
            fallbackToGeneratedFrames(reason: "asset-display-layer-failed")
            return
        }

        while isRunning, !didStop, assetPumpGeneration.accepts(generation) {
            guard let assetOutput else {
                fallbackToGeneratedFrames(reason: "asset-output-missing")
                return
            }

            let sampleBuffer: CMSampleBuffer
            if let pendingAssetSampleBuffer {
                sampleBuffer = pendingAssetSampleBuffer
            } else {
                guard let sourceSampleBuffer = assetOutput.copyNextSampleBuffer() else {
                    switch assetReader?.status {
                    case .completed:
                        assetLoopIndex += 1
                        logAssetLoopTiming()
                        macWallNativeWallpaperLogger.info(
                            "nativeVideoBridge asset loop bridgeID=\(self.bridgeID, privacy: .public) loop=\(self.assetLoopIndex)"
                        )
                        resetAssetReader()
                        guard startAssetReader(videoURL: videoURL) else {
                            fallbackToGeneratedFrames(reason: "asset-loop-restart-failed")
                            return
                        }
                        continue
                    case .failed:
                        macWallNativeWallpaperLogger.error(
                            "nativeVideoBridge assetReader failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: self.assetReader?.error), privacy: .public)"
                        )
                        fallbackToGeneratedFrames(reason: "asset-reader-failed")
                        return
                    case .cancelled:
                        macWallNativeWallpaperLogger.warning(
                            "nativeVideoBridge assetReader cancelled bridgeID=\(self.bridgeID, privacy: .public)"
                        )
                        fallbackToGeneratedFrames(reason: "asset-reader-cancelled")
                        return
                    default:
                        return
                    }
                }

                let loopOffset = NativeVideoSampleRetimer.loopOffset(
                    assetDuration: assetDuration,
                    loopIndex: assetLoopIndex
                )
                do {
                    sampleBuffer = try NativeVideoSampleRetimer.retime(sourceSampleBuffer, by: loopOffset)
                } catch let error as NativeVideoSampleRetimer.RetimingError {
                    let osStatus: String
                    if case .status(let status) = error {
                        osStatus = String(status)
                    } else {
                        osStatus = "none"
                    }
                    macWallNativeWallpaperLogger.error(
                        "nativeVideoBridge sample retiming failed bridgeID=\(self.bridgeID, privacy: .public) loop=\(self.assetLoopIndex) osStatus=\(osStatus, privacy: .public) error=\(String(describing: error), privacy: .public)"
                    )
                    fallbackToGeneratedFrames(reason: "asset-sample-retiming-failed")
                    return
                } catch {
                    macWallNativeWallpaperLogger.error(
                        "nativeVideoBridge sample retiming failed bridgeID=\(self.bridgeID, privacy: .public) loop=\(self.assetLoopIndex) osStatus=none error=\(String(describing: error), privacy: .public)"
                    )
                    fallbackToGeneratedFrames(reason: "asset-sample-retiming-failed")
                    return
                }
                pendingAssetSampleBuffer = sampleBuffer
            }

            let samplePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let samplePTSSeconds = CMTimeGetSeconds(samplePTS)
            let mediaNowSeconds = CMTimeGetSeconds(playbackClock.currentTime)
            let rendererReady = rendererAdapter.isReadyForMoreMediaData
            let evaluation = timingPolicy.evaluate(
                samplePTSSeconds: samplePTSSeconds,
                mediaTimeSeconds: mediaNowSeconds,
                rendererReady: rendererReady,
                lastEnqueuedPTSSeconds: lastEnqueuedPTSSeconds
            )
            let transition = NativeVideoAssetPumpTransition(decision: evaluation.decision)

            switch evaluation.decision {
            case .enqueue:
                rendererAdapter.enqueue(sampleBuffer)
                if transition.consumesPendingSample {
                    pendingAssetSampleBuffer = nil
                }
                queuedFrameCount += 1
                frameIndex += 1
                lastEnqueuedPTSSeconds = samplePTSSeconds
                logAssetTiming(
                    samplePTSSeconds: samplePTSSeconds,
                    mediaNowSeconds: mediaNowSeconds,
                    evaluation: evaluation,
                    rendererReady: rendererReady
                )
            case .wait:
                logAssetTiming(
                    samplePTSSeconds: samplePTSSeconds,
                    mediaNowSeconds: mediaNowSeconds,
                    evaluation: evaluation,
                    rendererReady: rendererReady
                )
                scheduleAssetPump(
                    videoURL: videoURL,
                    generation: generation,
                    transition: transition
                )
                return
            case .waitForRenderer:
                logAssetTiming(
                    samplePTSSeconds: samplePTSSeconds,
                    mediaNowSeconds: mediaNowSeconds,
                    evaluation: evaluation,
                    rendererReady: rendererReady
                )
                return
            case .drop:
                if transition.consumesPendingSample {
                    pendingAssetSampleBuffer = nil
                }
                droppedFrameCount += 1
                logAssetTiming(
                    samplePTSSeconds: samplePTSSeconds,
                    mediaNowSeconds: mediaNowSeconds,
                    evaluation: evaluation,
                    rendererReady: rendererReady
                )
            case .reset:
                let hardResetAction = hardResetTracker.registerReset(at: CACurrentMediaTime())
                if hardResetAction == .fallback {
                    logAssetTiming(
                        samplePTSSeconds: samplePTSSeconds,
                        mediaNowSeconds: mediaNowSeconds,
                        evaluation: evaluation,
                        rendererReady: rendererReady,
                        decisionName: "repeated-hard-reset",
                        force: true
                    )
                    macWallNativeWallpaperLogger.warning(
                        "nativeVideoBridge repeated hard reset bridgeID=\(self.bridgeID, privacy: .public) windowSeconds=5 fallback=generated"
                    )
                    fallbackToGeneratedFrames(reason: "asset-repeated-hard-reset")
                    return
                }
                logAssetTiming(
                    samplePTSSeconds: samplePTSSeconds,
                    mediaNowSeconds: mediaNowSeconds,
                    evaluation: evaluation,
                    rendererReady: rendererReady,
                    force: true
                )
                rendererAdapter.stopRequestingMediaData()
                rendererAdapter.flush(removeDisplayedImage: false) { [weak self] in
                    guard let self else {
                        return
                    }
                    self.queue.async { [weak self] in
                        guard let self,
                              self.isRunning,
                              !self.didStop,
                              self.assetPumpGeneration.accepts(generation),
                              let playbackClock = self.playbackClock else {
                            return
                        }
                        self.lastEnqueuedPTSSeconds = nil
                        playbackClock.seek(to: samplePTS)
                        self.scheduleAssetPump(
                            videoURL: videoURL,
                            generation: generation,
                            transition: transition
                        )
                    }
                }
                return
            }
        }
    }

    private func logAssetLoopTiming() {
        guard let playbackClock else {
            return
        }
        let mediaNowSeconds = CMTimeGetSeconds(playbackClock.currentTime)
        let samplePTSSeconds = lastEnqueuedPTSSeconds ?? mediaNowSeconds
        let leadSeconds = samplePTSSeconds - mediaNowSeconds
        let evaluation = NativeVideoPlaybackEvaluation(
            decision: .enqueue,
            leadSeconds: leadSeconds,
            bufferBand: bufferBand(for: leadSeconds)
        )
        logAssetTiming(
            samplePTSSeconds: samplePTSSeconds,
            mediaNowSeconds: mediaNowSeconds,
            evaluation: evaluation,
            rendererReady: rendererAdapter.isReadyForMoreMediaData,
            decisionName: "loop",
            force: true
        )
    }

    private func logAssetTiming(
        samplePTSSeconds: Double,
        mediaNowSeconds: Double,
        evaluation: NativeVideoPlaybackEvaluation,
        rendererReady: Bool,
        decisionName: String? = nil,
        force: Bool = false
    ) {
        let hostTime = CACurrentMediaTime()
        guard force || hostTime - lastTimingLogHostTime >= 1 else {
            return
        }
        lastTimingLogHostTime = hostTime

        let samplePTS = String(format: "%.6f", samplePTSSeconds)
        let mediaNow = String(format: "%.6f", mediaNowSeconds)
        let lead = String(format: "%.6f", evaluation.leadSeconds)
        let lag = String(format: "%.6f", evaluation.lagSeconds)
        let decision = decisionName ?? timingDecisionName(evaluation.decision)
        let clockMode = playbackClock?.mode.rawValue ?? "none"
        macWallNativeWallpaperLogger.info(
            "nativeVideoTiming bridgeID=\(self.bridgeID, privacy: .public) samplePTS=\(samplePTS, privacy: .public) mediaNow=\(mediaNow, privacy: .public) lead=\(lead, privacy: .public) lag=\(lag, privacy: .public) bufferBand=\(evaluation.bufferBand.rawValue, privacy: .public) rendererReady=\(rendererReady) loopIndex=\(self.assetLoopIndex) droppedFrameCount=\(self.droppedFrameCount) queuedFrameCount=\(self.queuedFrameCount) decision=\(decision, privacy: .public) clockMode=\(clockMode, privacy: .public) profile=\(self.timingProfile.rawValue, privacy: .public)"
        )
    }

    private func bufferBand(for lead: Double) -> NativeVideoBufferBand {
        if lead < 0 {
            return .late
        }
        if lead < timingPolicy.configuration.minBufferLeadSeconds {
            return .belowMinimum
        }
        if lead > timingPolicy.configuration.maxBufferLeadSeconds {
            return .aboveMaximum
        }
        return .target
    }

    private func startAssetReader(videoURL: URL) -> Bool {
        resetAssetReader()

        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge asset has no video track bridgeID=\(self.bridgeID, privacy: .public) url=\(videoURL.lastPathComponent, privacy: .public)"
            )
            return false
        }
        let videoDuration = videoTrack.timeRange.duration
        guard videoDuration.isNumeric, CMTimeCompare(videoDuration, .zero) > 0 else {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge asset has invalid duration bridgeID=\(self.bridgeID, privacy: .public) url=\(videoURL.lastPathComponent, privacy: .public)"
            )
            return false
        }

        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                ]
            )
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                macWallNativeWallpaperLogger.error(
                    "nativeVideoBridge assetReader cannot add output bridgeID=\(self.bridgeID, privacy: .public)"
                )
                return false
            }

            reader.add(output)
            guard reader.startReading() else {
                macWallNativeWallpaperLogger.error(
                    "nativeVideoBridge assetReader start failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: reader.error), privacy: .public)"
                )
                return false
            }

            assetReader = reader
            assetOutput = output
            assetDuration = videoDuration
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge assetReader started bridgeID=\(self.bridgeID, privacy: .public) url=\(videoURL.lastPathComponent, privacy: .public) naturalSize=\(formatBridgeSize(videoTrack.naturalSize), privacy: .public)"
            )
            return true
        } catch {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge assetReader creation failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func resetAssetReader() {
        assetOutput = nil
        assetReader?.cancelReading()
        assetReader = nil
    }

    private func fallbackToGeneratedFrames(reason: String) {
        guard isRunning, !didStop else {
            return
        }

        let generation = assetPumpGeneration.advance()
        pendingAssetSampleBuffer = nil
        rendererAdapter.stopRequestingMediaData()
        resetAssetReader()
        frameIndex = 0
        let finishFallback: @Sendable () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.queue.async { [weak self] in
                guard let self,
                      self.isRunning,
                      !self.didStop,
                      self.assetPumpGeneration.accepts(generation) else {
                    return
                }
                self.rendererAdapter.flush(removeDisplayedImage: false)
                self.startGeneratedFrames(reason: reason)
            }
        }
        if let playbackClock {
            playbackClock.stop(completion: finishFallback)
        } else {
            finishFallback()
        }
    }

    private func makeSampleBuffer(frameIndex: Int64) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        let pixelBufferStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard pixelBufferStatus == kCVReturnSuccess, let pixelBuffer else {
            macWallNativeWallpaperLogger.error("nativeVideoBridge pixelBuffer creation failed status=\(pixelBufferStatus)")
            return nil
        }

        fill(pixelBuffer: pixelBuffer, frameIndex: frameIndex)

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            macWallNativeWallpaperLogger.error("nativeVideoBridge formatDescription failed status=\(formatStatus)")
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: frameRate),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: frameRate),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            macWallNativeWallpaperLogger.error("nativeVideoBridge sampleBuffer failed status=\(sampleStatus)")
            return nil
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    private func fill(pixelBuffer: CVPixelBuffer, frameIndex: Int64) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let phase = UInt8((frameIndex * 4) % 255)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let offset = x * 4
                let stripe = UInt8((x / 40 + Int(frameIndex / 8)) % 3)
                switch stripe {
                case 0:
                    row.storeBytes(of: phase, toByteOffset: offset + 0, as: UInt8.self)
                    row.storeBytes(of: UInt8(32), toByteOffset: offset + 1, as: UInt8.self)
                    row.storeBytes(of: UInt8(255), toByteOffset: offset + 2, as: UInt8.self)
                case 1:
                    row.storeBytes(of: UInt8(255), toByteOffset: offset + 0, as: UInt8.self)
                    row.storeBytes(of: phase, toByteOffset: offset + 1, as: UInt8.self)
                    row.storeBytes(of: UInt8(32), toByteOffset: offset + 2, as: UInt8.self)
                default:
                    row.storeBytes(of: UInt8(32), toByteOffset: offset + 0, as: UInt8.self)
                    row.storeBytes(of: UInt8(255), toByteOffset: offset + 1, as: UInt8.self)
                    row.storeBytes(of: phase, toByteOffset: offset + 2, as: UInt8.self)
                }
                row.storeBytes(of: UInt8(255), toByteOffset: offset + 3, as: UInt8.self)
            }
        }
    }
}

private func timingDecisionName(_ decision: NativeVideoPlaybackDecision) -> String {
    switch decision {
    case .enqueue:
        "enqueue"
    case .wait:
        "wait"
    case .waitForRenderer:
        "wait-for-renderer"
    case .drop(let reason):
        switch reason {
        case .late:
            "drop-late"
        case .cadence:
            "drop-cadence"
        }
    case .reset:
        "reset"
    }
}

private func normalizedBridgeSize(_ size: CGSize) -> CGSize {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
        return CGSize(width: 1920, height: 1080)
    }
    return size
}

private func formatBridgeSize(_ size: CGSize) -> String {
    let normalized = normalizedBridgeSize(size)
    return String(format: "(%.1fx%.1f)", Double(normalized.width), Double(normalized.height))
}
