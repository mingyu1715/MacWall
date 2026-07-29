import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeDisplayModeUpdatePolicyTests: XCTestCase {
    func testSameGenerationTopologyCandidateUpdatesActiveAndCandidate() {
        let generation = UUID()

        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
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

    func testRestartCandidateReceivesPersistedDisplayMode() {
        let generation = UUID()

        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
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

    func testZeroContextPlayDefersUpdateUntilSurfaceRegistration() {
        let generation = UUID()

        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
            targetGeneration: generation,
            activeGeneration: nil,
            candidateGeneration: nil,
            persistedPlayGeneration: generation
        )

        XCTAssertEqual(decision, .deferred)
    }

    func testActiveGenerationWithoutCurrentBridgeStillPersistsMode() {
        let generation = UUID()

        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
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

    func testStaleGenerationIsIgnored() {
        let decision = NativeRuntimeDisplayModeUpdatePolicy.decision(
            targetGeneration: UUID(),
            activeGeneration: UUID(),
            candidateGeneration: nil,
            persistedPlayGeneration: nil
        )

        XCTAssertEqual(decision, .ignore)
    }
}
