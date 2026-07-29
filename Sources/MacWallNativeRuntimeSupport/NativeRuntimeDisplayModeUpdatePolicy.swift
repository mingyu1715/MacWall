import Foundation

public struct NativeRuntimeDisplayModeUpdateTargets: Equatable, Sendable {
    public let active: Bool
    public let candidate: Bool

    public init(active: Bool, candidate: Bool) {
        self.active = active
        self.candidate = candidate
    }
}

public enum NativeRuntimeDisplayModeUpdateDecision: Equatable, Sendable {
    case apply(NativeRuntimeDisplayModeUpdateTargets)
    case deferred
    case ignore
}

public enum NativeRuntimeDisplayModeUpdatePolicy {
    public static func decision(
        targetGeneration: UUID,
        activeGeneration: UUID?,
        candidateGeneration: UUID?,
        persistedPlayGeneration: UUID?
    ) -> NativeRuntimeDisplayModeUpdateDecision {
        let targets = NativeRuntimeDisplayModeUpdateTargets(
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
