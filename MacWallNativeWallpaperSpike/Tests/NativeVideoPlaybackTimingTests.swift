import Foundation
import CoreMedia
import CoreVideo

enum NativeVideoPlaybackTimingTests {
    static func runAll() {
        testNormalSampleEnqueues()
        testLeadBelowMinimumIsReported()
        testFarAheadSampleWaitsTowardTargetLead()
        testLateSampleDrops()
        testSeverelyLateSampleResets()
        testRendererBackpressureDoesNotConsumeSample()
        testReducedProfileDropsExcessCadence()
        testWaitTransitionRetainsPendingSampleAndReschedules()
        testRendererWaitTransitionRetainsPendingSampleWithoutRescheduling()
        testPumpGenerationRejectsStaleCallbacks()
        testLoopOffsetIsMonotonic()
        testTimingInfoAddsLoopOffset()
        testRetimingCopiesVideoSampleBufferPTS()
        testRetimerRejectsNonnumericTiming()
        testLoopOffsetRejectsInvalidDuration()
        testRepeatedHardResetWithinWindowFallsBack()
    }

    private static func testNormalSampleEnqueues() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.25,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .enqueue)
        precondition(abs(result.leadSeconds - 0.25) < 0.000_001)
    }

    private static func testLeadBelowMinimumIsReported() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.05,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .enqueue)
        precondition(result.bufferBand == .belowMinimum)
    }

    private static func testFarAheadSampleWaitsTowardTargetLead() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.80,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        guard case .wait(let seconds) = result.decision else {
            preconditionFailure("expected wait decision")
        }
        precondition(abs(seconds - 0.50) < 0.000_001)
    }

    private static func testLateSampleDrops() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 1.0,
            mediaTimeSeconds: 1.20,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .drop(reason: .late))
    }

    private static func testSeverelyLateSampleResets() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 1.0,
            mediaTimeSeconds: 1.60,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .reset)
    }

    private static func testRendererBackpressureDoesNotConsumeSample() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.25,
            mediaTimeSeconds: 0,
            rendererReady: false,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .waitForRenderer)
    }

    private static func testReducedProfileDropsExcessCadence() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .reduced).evaluate(
            samplePTSSeconds: 1.01,
            mediaTimeSeconds: 1.0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: 1.0
        )
        precondition(result.decision == .drop(reason: .cadence))
    }

    private static func testWaitTransitionRetainsPendingSampleAndReschedules() {
        let transition = NativeVideoAssetPumpTransition(decision: .wait(seconds: 0.25))
        precondition(!transition.consumesPendingSample)
        precondition(transition.stopsRequestingMediaData)
        precondition(transition.retryDelaySeconds == 0.25)
    }

    private static func testRendererWaitTransitionRetainsPendingSampleWithoutRescheduling() {
        let transition = NativeVideoAssetPumpTransition(decision: .waitForRenderer)
        precondition(!transition.consumesPendingSample)
        precondition(!transition.stopsRequestingMediaData)
        precondition(transition.retryDelaySeconds == nil)
    }

    private static func testPumpGenerationRejectsStaleCallbacks() {
        var generation = NativeVideoAssetPumpGeneration()
        let first = generation.advance()
        precondition(generation.accepts(first))

        let second = generation.advance()
        precondition(!generation.accepts(first))
        precondition(generation.accepts(second))
    }

    private static func testLoopOffsetIsMonotonic() {
        let duration = CMTime(value: 300, timescale: 30)
        precondition(NativeVideoSampleRetimer.loopOffset(assetDuration: duration, loopIndex: 0) == .zero)
        precondition(
            CMTimeGetSeconds(NativeVideoSampleRetimer.loopOffset(assetDuration: duration, loopIndex: 2)) == 20
        )
    }

    private static func testTimingInfoAddsLoopOffset() {
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 15, timescale: 30),
            decodeTimeStamp: .invalid
        )
        let shifted = NativeVideoSampleRetimer.offset(
            timing,
            by: CMTime(seconds: 10, preferredTimescale: 600)
        )
        precondition(CMTimeGetSeconds(shifted.presentationTimeStamp) == 10.5)
        precondition(shifted.decodeTimeStamp == .invalid)
    }

    private static func testRetimingCopiesVideoSampleBufferPTS() {
        var pixelBuffer: CVPixelBuffer?
        precondition(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                2,
                2,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            ) == kCVReturnSuccess
        )
        var formatDescription: CMVideoFormatDescription?
        precondition(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer!,
                formatDescriptionOut: &formatDescription
            ) == noErr
        )
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 15, timescale: 30),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        precondition(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer!,
                formatDescription: formatDescription!,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ) == noErr
        )

        let retimed = try! NativeVideoSampleRetimer.retime(
            sampleBuffer!,
            by: CMTime(seconds: 10, preferredTimescale: 600)
        )
        precondition(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(retimed)) == 10.5)
        precondition(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer!)) == 0.5)
    }

    private static func testRetimerRejectsNonnumericTiming() {
        let validTiming = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        precondition(
            throwsRetimingError(.nonnumericOffset) {
                try NativeVideoSampleRetimer.validate(validTiming, offset: .invalid)
            }
        )

        let invalidPTS = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        precondition(
            throwsRetimingError(.nonnumericPresentationTime) {
                try NativeVideoSampleRetimer.validate(invalidPTS, offset: .zero)
            }
        )

        let indefiniteDuration = CMSampleTimingInfo(
            duration: .indefinite,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        precondition(
            throwsRetimingError(.nonnumericDuration) {
                try NativeVideoSampleRetimer.validate(indefiniteDuration, offset: .zero)
            }
        )

        try! NativeVideoSampleRetimer.validate(validTiming, offset: .zero)
    }

    private static func testLoopOffsetRejectsInvalidDuration() {
        precondition(!NativeVideoSampleRetimer.loopOffset(assetDuration: .invalid, loopIndex: 0).isValid)
    }

    private static func testRepeatedHardResetWithinWindowFallsBack() {
        var tracker = NativeVideoHardResetTracker(windowSeconds: 5)
        precondition(tracker.registerReset(at: 100) == .retry)
        precondition(tracker.registerReset(at: 105) == .fallback)
        precondition(tracker.registerReset(at: 106) == .retry)
    }

    private static func throwsRetimingError(
        _ expected: NativeVideoSampleRetimer.RetimingError,
        operation: () throws -> Void
    ) -> Bool {
        do {
            try operation()
            return false
        } catch let error as NativeVideoSampleRetimer.RetimingError {
            return error == expected
        } catch {
            return false
        }
    }
}
