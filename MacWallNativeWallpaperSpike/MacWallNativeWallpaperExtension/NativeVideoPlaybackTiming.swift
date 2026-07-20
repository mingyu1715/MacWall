import Foundation

struct NativeVideoPlaybackTimingConfiguration: Equatable, Sendable {
    let minBufferLeadSeconds: Double
    let targetBufferLeadSeconds: Double
    let maxBufferLeadSeconds: Double
    let lateDropStartSeconds: Double
    let hardResetLagSeconds: Double
    let minimumFrameIntervalSeconds: Double

    static let normal = NativeVideoPlaybackTimingConfiguration(
        minBufferLeadSeconds: 0.100,
        targetBufferLeadSeconds: 0.300,
        maxBufferLeadSeconds: 0.500,
        lateDropStartSeconds: 0.150,
        hardResetLagSeconds: 0.500,
        minimumFrameIntervalSeconds: 0
    )

    static let reduced = NativeVideoPlaybackTimingConfiguration(
        minBufferLeadSeconds: 0.075,
        targetBufferLeadSeconds: 0.150,
        maxBufferLeadSeconds: 0.250,
        lateDropStartSeconds: 0.100,
        hardResetLagSeconds: 0.400,
        minimumFrameIntervalSeconds: 1.0 / 30.0
    )
}

enum NativeVideoFrameDropReason: Equatable, Sendable {
    case late
    case cadence
}

enum NativeVideoBufferBand: String, Equatable, Sendable {
    case late
    case belowMinimum
    case target
    case aboveMaximum
}

enum NativeVideoPlaybackDecision: Equatable, Sendable {
    case enqueue
    case wait(seconds: Double)
    case waitForRenderer
    case drop(reason: NativeVideoFrameDropReason)
    case reset
}

struct NativeVideoPlaybackEvaluation: Equatable, Sendable {
    let decision: NativeVideoPlaybackDecision
    let leadSeconds: Double
    let bufferBand: NativeVideoBufferBand

    var lagSeconds: Double { max(-leadSeconds, 0) }
}

struct NativeVideoPlaybackTimingPolicy: Sendable {
    let configuration: NativeVideoPlaybackTimingConfiguration

    func evaluate(
        samplePTSSeconds: Double,
        mediaTimeSeconds: Double,
        rendererReady: Bool,
        lastEnqueuedPTSSeconds: Double?
    ) -> NativeVideoPlaybackEvaluation {
        let lead = samplePTSSeconds - mediaTimeSeconds
        if -lead >= configuration.hardResetLagSeconds {
            return makeEvaluation(decision: .reset, lead: lead)
        }
        if -lead >= configuration.lateDropStartSeconds {
            return makeEvaluation(decision: .drop(reason: .late), lead: lead)
        }
        if let lastEnqueuedPTSSeconds,
           configuration.minimumFrameIntervalSeconds > 0,
           samplePTSSeconds - lastEnqueuedPTSSeconds < configuration.minimumFrameIntervalSeconds {
            return makeEvaluation(decision: .drop(reason: .cadence), lead: lead)
        }
        guard rendererReady else {
            return makeEvaluation(decision: .waitForRenderer, lead: lead)
        }
        if lead > configuration.maxBufferLeadSeconds {
            return makeEvaluation(
                decision: .wait(seconds: lead - configuration.targetBufferLeadSeconds),
                lead: lead
            )
        }
        return makeEvaluation(decision: .enqueue, lead: lead)
    }

    private func makeEvaluation(
        decision: NativeVideoPlaybackDecision,
        lead: Double
    ) -> NativeVideoPlaybackEvaluation {
        let bufferBand: NativeVideoBufferBand
        if lead < 0 {
            bufferBand = .late
        } else if lead < configuration.minBufferLeadSeconds {
            bufferBand = .belowMinimum
        } else if lead > configuration.maxBufferLeadSeconds {
            bufferBand = .aboveMaximum
        } else {
            bufferBand = .target
        }
        return NativeVideoPlaybackEvaluation(
            decision: decision,
            leadSeconds: lead,
            bufferBand: bufferBand
        )
    }
}
