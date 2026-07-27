import Foundation

public enum NativeRuntimeSessionDecision: Equatable, Sendable {
    case waiting
    case commit(UUID)
    case reject(UUID)
    case ignored
}

public struct NativeRuntimeSessionState: Equatable, Sendable {
    public private(set) var activeGeneration: UUID?
    public private(set) var candidateGeneration: UUID?
    public private(set) var targetContextIDs: Set<String> = []
    public private(set) var readyContextIDs: Set<String> = []

    public init(activeGeneration: UUID? = nil) {
        self.activeGeneration = activeGeneration
    }

    public mutating func beginCandidate(
        generation: UUID,
        contextIDs: Set<String>
    ) {
        candidateGeneration = generation
        targetContextIDs = contextIDs
        readyContextIDs = []
    }

    public mutating func markReady(
        generation: UUID,
        contextID: String
    ) -> NativeRuntimeSessionDecision {
        guard candidateGeneration == generation,
              targetContextIDs.contains(contextID) else {
            return .ignored
        }

        readyContextIDs.insert(contextID)
        guard readyContextIDs == targetContextIDs else {
            return .waiting
        }

        activeGeneration = generation
        candidateGeneration = nil
        targetContextIDs = []
        readyContextIDs = []
        return .commit(generation)
    }

    public mutating func failCandidate(
        generation: UUID
    ) -> NativeRuntimeSessionDecision {
        guard candidateGeneration == generation else {
            return .ignored
        }

        candidateGeneration = nil
        targetContextIDs = []
        readyContextIDs = []
        return .reject(generation)
    }
}
