import Foundation

public enum NativeRuntimeRecoveryDecision: Equatable, Sendable {
    case retry(UUID)
    case exhausted(UUID)
    case ignored
}

public struct NativeRuntimeRecoveryPolicy: Equatable, Sendable {
    private var attemptedGeneration: UUID?

    public init() {}

    public mutating func registerFailure(
        generation: UUID,
        activeGeneration: UUID?
    ) -> NativeRuntimeRecoveryDecision {
        guard activeGeneration == generation else {
            return .ignored
        }
        guard attemptedGeneration != generation else {
            return .exhausted(generation)
        }
        attemptedGeneration = generation
        return .retry(generation)
    }

    public func registerReplacementFailure(
        generation: UUID,
        activeGeneration: UUID?
    ) -> NativeRuntimeRecoveryDecision {
        guard activeGeneration == generation,
              attemptedGeneration == generation else {
            return .ignored
        }
        return .exhausted(generation)
    }

    public mutating func clear() {
        attemptedGeneration = nil
    }
}
