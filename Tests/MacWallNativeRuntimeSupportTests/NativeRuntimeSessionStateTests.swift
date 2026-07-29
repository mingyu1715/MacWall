import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeSessionStateTests: XCTestCase {
    func testCandidateCommitsOnlyAfterEveryContextIsReady() {
        var state = NativeRuntimeSessionState(activeGeneration: UUID())
        let candidate = UUID()
        state.beginCandidate(
            generation: candidate,
            contextIDs: ["display-1", "display-2"]
        )

        XCTAssertEqual(
            state.markReady(generation: candidate, contextID: "display-1"),
            .waiting
        )
        XCTAssertEqual(
            state.markReady(generation: candidate, contextID: "display-2"),
            .commit(candidate)
        )
        XCTAssertEqual(state.activeGeneration, candidate)
        XCTAssertNil(state.candidateGeneration)
    }

    func testCandidateFailureKeepsPreviousGeneration() {
        let previous = UUID()
        let candidate = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: previous)
        state.beginCandidate(
            generation: candidate,
            contextIDs: ["display-1", "display-2"]
        )

        XCTAssertEqual(
            state.failCandidate(generation: candidate),
            .reject(candidate)
        )
        XCTAssertEqual(state.activeGeneration, previous)
        XCTAssertNil(state.candidateGeneration)
    }

    func testFailureAfterOneReadyContextRejectsWholeCandidate() {
        let previous = UUID()
        let candidate = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: previous)
        state.beginCandidate(
            generation: candidate,
            contextIDs: ["display-1", "display-2"]
        )

        XCTAssertEqual(
            state.markReady(generation: candidate, contextID: "display-1"),
            .waiting
        )
        XCTAssertEqual(
            state.failCandidate(generation: candidate),
            .reject(candidate)
        )
        XCTAssertEqual(state.activeGeneration, previous)
        XCTAssertNil(state.candidateGeneration)
        XCTAssertTrue(state.targetContextIDs.isEmpty)
        XCTAssertTrue(state.readyContextIDs.isEmpty)
    }

    func testStaleReadyFromOldGenerationIsIgnored() {
        let active = UUID()
        let stale = UUID()
        let current = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: active)
        state.beginCandidate(
            generation: current,
            contextIDs: ["display-1"]
        )

        XCTAssertEqual(
            state.markReady(generation: stale, contextID: "display-1"),
            .ignored
        )
        XCTAssertEqual(state.activeGeneration, active)
        XCTAssertEqual(state.candidateGeneration, current)
    }

    func testUnknownContextCannotCommitCandidate() {
        let active = UUID()
        let candidate = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: active)
        state.beginCandidate(
            generation: candidate,
            contextIDs: ["display-1"]
        )

        XCTAssertEqual(
            state.markReady(generation: candidate, contextID: "display-2"),
            .ignored
        )
        XCTAssertEqual(state.activeGeneration, active)
        XCTAssertEqual(state.candidateGeneration, candidate)
    }

    func testNewCandidateReplacesOnlyCandidateState() {
        let active = UUID()
        let firstCandidate = UUID()
        let secondCandidate = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: active)
        state.beginCandidate(
            generation: firstCandidate,
            contextIDs: ["display-1"]
        )
        state.beginCandidate(
            generation: secondCandidate,
            contextIDs: ["display-1", "display-2"]
        )

        XCTAssertEqual(state.activeGeneration, active)
        XCTAssertEqual(state.candidateGeneration, secondCandidate)
        XCTAssertEqual(state.targetContextIDs, ["display-1", "display-2"])
        XCTAssertTrue(state.readyContextIDs.isEmpty)
    }

    func testStopClearsActiveAndCandidateState() {
        let active = UUID()
        let candidate = UUID()
        var state = NativeRuntimeSessionState(activeGeneration: active)
        state.beginCandidate(
            generation: candidate,
            contextIDs: ["display-1", "display-2"]
        )
        _ = state.markReady(
            generation: candidate,
            contextID: "display-1"
        )

        state.stop()

        XCTAssertNil(state.activeGeneration)
        XCTAssertNil(state.candidateGeneration)
        XCTAssertTrue(state.targetContextIDs.isEmpty)
        XCTAssertTrue(state.readyContextIDs.isEmpty)
    }
}
