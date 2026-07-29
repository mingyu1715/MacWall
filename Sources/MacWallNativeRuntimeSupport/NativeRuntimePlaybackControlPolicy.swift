import Foundation

public struct NativeRuntimePlaybackControlTargets: Equatable, Sendable {
    public let active: Bool
    public let candidate: Bool

    public init(active: Bool, candidate: Bool) {
        self.active = active
        self.candidate = candidate
    }
}

public enum NativeRuntimePlaybackControlDecision: Equatable, Sendable {
    case apply(NativeRuntimePlaybackControlTargets)
    case deferred
    case ignore
}

public enum NativeRuntimePlaybackControlPolicy {
    public static func decision(
        targetGeneration: UUID,
        activeGeneration: UUID?,
        candidateGeneration: UUID?,
        persistedPlayGeneration: UUID?
    ) -> NativeRuntimePlaybackControlDecision {
        let targets = NativeRuntimePlaybackControlTargets(
            active: activeGeneration == targetGeneration,
            candidate: candidateGeneration == targetGeneration
        )
        if targets.active || targets.candidate {
            return .apply(targets)
        }
        if persistedPlayGeneration == targetGeneration {
            return .deferred
        }
        return .ignore
    }
}
