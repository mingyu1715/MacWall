import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeRecoveryPolicyTests: XCTestCase {
    func testFirstFailureForActiveGenerationRetries() {
        let generation = UUID()
        var policy = NativeRuntimeRecoveryPolicy()

        XCTAssertEqual(
            policy.registerFailure(
                generation: generation,
                activeGeneration: generation
            ),
            .retry(generation)
        )
    }

    func testSecondFailureForSameGenerationExhaustsRecovery() {
        let generation = UUID()
        var policy = NativeRuntimeRecoveryPolicy()
        _ = policy.registerFailure(
            generation: generation,
            activeGeneration: generation
        )

        XCTAssertEqual(
            policy.registerFailure(
                generation: generation,
                activeGeneration: generation
            ),
            .exhausted(generation)
        )
    }

    func testReplacementCandidateFailureExhaustsStartedRecovery() {
        let generation = UUID()
        var policy = NativeRuntimeRecoveryPolicy()
        _ = policy.registerFailure(
            generation: generation,
            activeGeneration: generation
        )

        XCTAssertEqual(
            policy.registerReplacementFailure(
                generation: generation,
                activeGeneration: generation
            ),
            .exhausted(generation)
        )
    }

    func testUnexpectedReplacementCandidateFailureIsIgnored() {
        let generation = UUID()
        let policy = NativeRuntimeRecoveryPolicy()

        XCTAssertEqual(
            policy.registerReplacementFailure(
                generation: generation,
                activeGeneration: generation
            ),
            .ignored
        )
    }

    func testNewGenerationGetsIndependentRetryBudget() {
        let first = UUID()
        let second = UUID()
        var policy = NativeRuntimeRecoveryPolicy()
        _ = policy.registerFailure(
            generation: first,
            activeGeneration: first
        )
        _ = policy.registerFailure(
            generation: first,
            activeGeneration: first
        )

        XCTAssertEqual(
            policy.registerFailure(
                generation: second,
                activeGeneration: second
            ),
            .retry(second)
        )
    }

    func testStaleFailureIsIgnored() {
        var policy = NativeRuntimeRecoveryPolicy()

        XCTAssertEqual(
            policy.registerFailure(
                generation: UUID(),
                activeGeneration: UUID()
            ),
            .ignored
        )
    }

    func testClearRestoresRetryBudget() {
        let generation = UUID()
        var policy = NativeRuntimeRecoveryPolicy()
        _ = policy.registerFailure(
            generation: generation,
            activeGeneration: generation
        )

        policy.clear()

        XCTAssertEqual(
            policy.registerFailure(
                generation: generation,
                activeGeneration: generation
            ),
            .retry(generation)
        )
    }
}
