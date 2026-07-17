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
    private let source: Source
    private let queue = DispatchQueue(label: "macwall.native-video-frame-bridge", qos: .userInitiated)
    private let width = 640
    private let height = 360
    private let frameRate: Int32 = 30
    private var frameIndex: Int64 = 0
    private var timer: DispatchSourceTimer?
    private var assetReader: AVAssetReader?
    private var assetOutput: AVAssetReaderTrackOutput?
    private var assetLoopIndex: Int64 = 0
    private var isRunning = false
    private var didStop = false

    private init(rootLayer: CALayer, size: CGSize, scale: CGFloat, source: Source) {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.name = "MacWallSampleBufferDisplayLayer"
        displayLayer.frame = CGRect(origin: .zero, size: normalizedBridgeSize(size))
        displayLayer.bounds = CGRect(origin: .zero, size: normalizedBridgeSize(size))
        displayLayer.contentsScale = max(scale, 1)
        displayLayer.videoGravity = .resizeAspectFill

        self.displayLayer = displayLayer
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
            self.resetAssetReader()
            self.displayLayer.stopRequestingMediaData()
            self.displayLayer.flushAndRemoveImage()
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

        displayLayer.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.enqueueAssetFrames(videoURL: videoURL)
        }
    }

    private func enqueueNextGeneratedFrame() {
        guard isRunning else {
            return
        }

        if displayLayer.status == .failed {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge displayLayer failed: \(String(describing: self.displayLayer.error), privacy: .public)"
            )
            displayLayer.flush()
        }

        guard displayLayer.isReadyForMoreMediaData,
              let sampleBuffer = makeSampleBuffer(frameIndex: frameIndex) else {
            return
        }

        displayLayer.enqueue(sampleBuffer)
        if frameIndex % Int64(frameRate) == 0 {
            macWallNativeWallpaperLogger.info(
                "nativeVideoBridge enqueued bridgeID=\(self.bridgeID, privacy: .public) generatedFrame=\(self.frameIndex)"
            )
        }
        frameIndex += 1
    }

    private func enqueueAssetFrames(videoURL: URL) {
        guard isRunning, !didStop else {
            return
        }

        if displayLayer.status == .failed {
            macWallNativeWallpaperLogger.error(
                "nativeVideoBridge asset displayLayer failed bridgeID=\(self.bridgeID, privacy: .public) error=\(String(describing: self.displayLayer.error), privacy: .public)"
            )
            fallbackToGeneratedFrames(reason: "asset-display-layer-failed")
            return
        }

        while isRunning, !didStop, displayLayer.isReadyForMoreMediaData {
            guard let assetOutput else {
                fallbackToGeneratedFrames(reason: "asset-output-missing")
                return
            }

            if let sampleBuffer = assetOutput.copyNextSampleBuffer() {
                displayLayer.enqueue(sampleBuffer)
                if frameIndex % Int64(frameRate) == 0 {
                    macWallNativeWallpaperLogger.info(
                        "nativeVideoBridge enqueued bridgeID=\(self.bridgeID, privacy: .public) assetFrame=\(self.frameIndex) loop=\(self.assetLoopIndex)"
                    )
                }
                frameIndex += 1
                continue
            }

            switch assetReader?.status {
            case .completed:
                assetLoopIndex += 1
                macWallNativeWallpaperLogger.info(
                    "nativeVideoBridge asset loop bridgeID=\(self.bridgeID, privacy: .public) loop=\(self.assetLoopIndex)"
                )
                displayLayer.flush()
                resetAssetReader()
                guard startAssetReader(videoURL: videoURL) else {
                    fallbackToGeneratedFrames(reason: "asset-loop-restart-failed")
                    return
                }
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

        resetAssetReader()
        displayLayer.stopRequestingMediaData()
        displayLayer.flush()
        frameIndex = 0
        startGeneratedFrames(reason: reason)
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
