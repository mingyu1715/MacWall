import Foundation

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
        testLoopTailWaitPreservesQueuedFrames()
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

    private static func testLoopTailWaitPreservesQueuedFrames() {
        precondition(
            abs(NativeVideoAssetLoopTail.remainingSeconds(lastQueuedEndPTSSeconds: 1.5, mediaNowSeconds: 1.2) - 0.3)
                < 0.000_001
        )
        precondition(
            NativeVideoAssetLoopTail.remainingSeconds(lastQueuedEndPTSSeconds: 1.5, mediaNowSeconds: 1.6) == 0
        )
        precondition(
            NativeVideoAssetLoopTail.remainingSeconds(lastQueuedEndPTSSeconds: nil, mediaNowSeconds: 1.2) == 0
        )
    }
}
