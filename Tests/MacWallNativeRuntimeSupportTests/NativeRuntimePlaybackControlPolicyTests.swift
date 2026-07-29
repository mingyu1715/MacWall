import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimePlaybackControlPolicyTests: XCTestCase {
    func testActiveGenerationAppliesImmediately() {
        let generation = UUID()

        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: generation,
            activeGeneration: generation,
            candidateGeneration: nil,
            persistedPlayGeneration: generation
        )

        XCTAssertEqual(
            decision,
            .apply(.init(active: true, candidate: false))
        )
    }

    func testCandidateGenerationRecordsDesiredState() {
        let generation = UUID()

        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: generation,
            activeGeneration: nil,
            candidateGeneration: generation,
            persistedPlayGeneration: generation
        )

        XCTAssertEqual(
            decision,
            .apply(.init(active: false, candidate: true))
        )
    }

    func testSameGenerationTopologyTargetsActiveAndCandidate() {
        let generation = UUID()

        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: generation,
            activeGeneration: generation,
            candidateGeneration: generation,
            persistedPlayGeneration: generation
        )

        XCTAssertEqual(
            decision,
            .apply(.init(active: true, candidate: true))
        )
    }

    func testPersistedPlayWithoutContextDefersControl() {
        let generation = UUID()

        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: generation,
            activeGeneration: nil,
            candidateGeneration: nil,
            persistedPlayGeneration: generation
        )

        XCTAssertEqual(decision, .deferred)
    }

    func testStaleGenerationIsIgnored() {
        let decision = NativeRuntimePlaybackControlPolicy.decision(
            targetGeneration: UUID(),
            activeGeneration: UUID(),
            candidateGeneration: nil,
            persistedPlayGeneration: UUID()
        )

        XCTAssertEqual(decision, .ignore)
    }
}
