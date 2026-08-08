import Foundation
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureMemoryBudgetTests: XCTestCase {
    func testStagingLayoutUsesInjectedDeviceAlignment() throws {
        let layout = try SceneTextureStagingLayout.make(
            format: .rgba8Unorm,
            mips: [
                preparedMip(width: 3, height: 2, rowBytes: 12),
                preparedMip(width: 1, height: 1, rowBytes: 4)
            ],
            minimumAlignment: 16
        )

        XCTAssertEqual(layout.mips[0].alignedBytesPerRow, 16)
        XCTAssertEqual(layout.mips[0].bytesPerImage, 32)
        XCTAssertEqual(layout.mips[1].offset, 32)
        XCTAssertEqual(layout.mips[1].alignedBytesPerRow, 16)
        XCTAssertEqual(layout.totalBytes, 48)
    }

    func testBCLayoutCountsBlockRowsInsteadOfPixelRows() throws {
        let layout = try SceneTextureStagingLayout.make(
            format: .bc3RGBA,
            mips: [preparedMip(width: 8, height: 5, rowBytes: 32)],
            minimumAlignment: 64
        )

        XCTAssertEqual(layout.mips[0].blockOrPixelRowCount, 2)
        XCTAssertEqual(layout.mips[0].bytesPerImage, 128)
    }

    func testStagingLayoutRejectsInvalidAlignmentAndArithmeticOverflow() {
        XCTAssertThrowsError(
            try SceneTextureStagingLayout.make(
                format: .rgba8Unorm,
                mips: [preparedMip(width: 1, height: 1, rowBytes: 4)],
                minimumAlignment: 3
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
        }
        XCTAssertThrowsError(
            try SceneTextureStagingLayout.make(
                format: .rgba8Unorm,
                mips: [preparedMip(width: 1, height: 2, rowBytes: Int.max)],
                minimumAlignment: 2
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
        }
    }

    func testStagingReservationAllowsExactLimitAndRejectsOneByteOver() throws {
        let limit = 128 * 1_024 * 1_024
        let budget = SceneTextureMemoryBudget(limits: .init(stagingBytes: limit))

        let reservation = try budget.reserve(limit, kind: .staging)
        XCTAssertEqual(budget.snapshot().stagingBytes, limit)
        try budget.release(reservation)

        assertPipelineError(.resourceLimit(.stagingBytes)) {
            _ = try budget.reserve(limit + 1, kind: .staging)
        }
    }

    func testDecodedReservationAllowsExactLimitAndRejectsOneByteOver() throws {
        let limit = 160 * 1_024 * 1_024
        let budget = SceneTextureMemoryBudget(limits: .init(decodedCPUBytes: limit))

        let reservation = try budget.reserve(limit, kind: .decodedCPU)
        XCTAssertEqual(budget.snapshot().decodedCPUBytes, limit)
        try budget.release(reservation)

        assertPipelineError(.resourceLimit(.decodedCPUBytes)) {
            _ = try budget.reserve(limit + 1, kind: .decodedCPU)
        }
    }

    func testResidentReservationsEnforceHardLimit() throws {
        let budget = SceneTextureMemoryBudget(limits: .init(residentHardBytes: 512))
        let reservation = try budget.reserve(512, kind: .resident)

        assertPipelineError(.resourceLimit(.residentBytes)) {
            _ = try budget.reserve(1, kind: .resident)
        }
        try budget.release(reservation)
    }

    func testResizeReplacesEstimateAndRejectsActualBytesAboveCap() throws {
        let budget = SceneTextureMemoryBudget(limits: .init(stagingBytes: 10))
        let reservation = try budget.reserve(6, kind: .staging)

        try budget.resize(reservation, actualBytes: 8)
        XCTAssertEqual(budget.snapshot().stagingBytes, 8)
        XCTAssertEqual(budget.snapshot().peakStagingBytes, 8)

        assertPipelineError(.resourceLimit(.stagingBytes)) {
            try budget.resize(reservation, actualBytes: 11)
        }
        XCTAssertEqual(budget.snapshot().stagingBytes, 8)

        try budget.resize(reservation, actualBytes: 4)
        XCTAssertEqual(budget.snapshot().stagingBytes, 4)
        XCTAssertEqual(budget.snapshot().peakStagingBytes, 8)
    }

    func testCurrentAndPeakCountsUpdateIndependently() throws {
        let budget = SceneTextureMemoryBudget(limits: .init(
            residentHardBytes: 20,
            stagingBytes: 20,
            decodedCPUBytes: 20
        ))
        let resident = try budget.reserve(2, kind: .resident)
        let staging = try budget.reserve(4, kind: .staging)
        let decoded = try budget.reserve(6, kind: .decodedCPU)

        XCTAssertEqual(
            budget.snapshot(),
            .init(
                residentBytes: 2,
                peakResidentBytes: 2,
                stagingBytes: 4,
                peakStagingBytes: 4,
                decodedCPUBytes: 6,
                peakDecodedCPUBytes: 6
            )
        )

        try budget.release(resident)
        try budget.release(staging)
        try budget.release(decoded)
        XCTAssertEqual(
            budget.snapshot(),
            .init(
                residentBytes: 0,
                peakResidentBytes: 2,
                stagingBytes: 0,
                peakStagingBytes: 4,
                decodedCPUBytes: 0,
                peakDecodedCPUBytes: 6
            )
        )
    }

    func testFailureAndCancellationCleanupReleaseEveryReservation() throws {
        let budget = SceneTextureMemoryBudget(limits: .init(
            residentHardBytes: 20,
            stagingBytes: 20,
            decodedCPUBytes: 20
        ))
        let staging = try budget.reserve(5, kind: .staging)
        let decoded = try budget.reserve(7, kind: .decodedCPU)
        let resident = try budget.reserve(9, kind: .resident)

        try budget.release(staging)
        try budget.release(decoded)
        try budget.release(resident)

        XCTAssertEqual(
            budget.snapshot(),
            .init(
                residentBytes: 0,
                peakResidentBytes: 9,
                stagingBytes: 0,
                peakStagingBytes: 5,
                decodedCPUBytes: 0,
                peakDecodedCPUBytes: 7
            )
        )
    }

    func testUnknownAndDoubleReleaseAreInvariantErrors() throws {
        let budget = SceneTextureMemoryBudget(limits: .init())
        let unknown = SceneTextureMemoryReservation(rawValue: UUID(), kind: .staging)
        assertInvariantError(.unknownReservation) {
            try budget.release(unknown)
        }

        let reservation = try budget.reserve(1, kind: .staging)
        let mismatched = SceneTextureMemoryReservation(
            rawValue: reservation.rawValue,
            kind: .decodedCPU
        )
        assertInvariantError(.reservationKindMismatch) {
            try budget.release(mismatched)
        }

        try budget.release(reservation)
        assertInvariantError(.unknownReservation) {
            try budget.release(reservation)
        }
    }

    func testConcurrentReservationsNeverExceedAggregateCap() {
        let budget = SceneTextureMemoryBudget(limits: .init(residentHardBytes: 8))
        let observation = ConcurrentObservation()

        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            do {
                let reservation = try budget.reserve(1, kind: .resident)
                observation.record(budget.snapshot().residentBytes)
                try budget.release(reservation)
            } catch let error as SceneTexturePipelineError {
                XCTAssertEqual(error, .resourceLimit(.residentBytes))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertLessThanOrEqual(observation.maximumResidentBytes, 8)
        XCTAssertLessThanOrEqual(budget.snapshot().residentBytes, 8)
        XCTAssertEqual(budget.snapshot().residentBytes, 0)
    }

    private func preparedMip(
        width: Int,
        height: Int,
        rowBytes: Int
    ) -> SceneTexturePreparedMip {
        SceneTexturePreparedMip(
            level: 0,
            storageExtent: .init(width: width, height: height),
            contentExtent: .init(width: width, height: height),
            unalignedBytesPerRow: rowBytes,
            bytes: Data()
        )
    }

    private func assertPipelineError(
        _ expected: SceneTexturePipelineError,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, expected, file: file, line: line)
        }
    }

    private func assertInvariantError(
        _ expected: SceneTextureMemoryInvariantError,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? SceneTextureMemoryInvariantError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private final class ConcurrentObservation: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var maximumResidentBytes = 0

    func record(_ residentBytes: Int) {
        lock.lock()
        maximumResidentBytes = max(maximumResidentBytes, residentBytes)
        lock.unlock()
    }
}
