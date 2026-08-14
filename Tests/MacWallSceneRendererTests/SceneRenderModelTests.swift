import Metal
import XCTest
@testable import MacWallSceneRenderer

final class SceneRenderModelTests: XCTestCase {
    func testDefaultLimitsMatchS4Contract() {
        XCTAssertEqual(SceneRenderLimits(), .init(
            maximumDimension: 16_384,
            maximumPixelCount: 33_177_600,
            maximumDrawItemCount: 100_000,
            maximumInFlightFrameCount: 3,
            renderTargetBudgetBytes: 512 * 1_024 * 1_024,
            snapshotReadbackBudgetBytes: 256 * 1_024 * 1_024
        ))
    }

    func testPublicFrameModelsPreserveDeterministicValues() {
        let request = SceneRenderFrameRequest(
            mediaTimeSeconds: 1.25,
            outputWidth: 3_840,
            outputHeight: 2_160,
            scalingMode: .fill,
            clearColor: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            output: .owned,
            requestsSnapshot: true
        )

        XCTAssertEqual(request.mediaTimeSeconds, 1.25)
        XCTAssertEqual(request.outputWidth, 3_840)
        XCTAssertEqual(request.outputHeight, 2_160)
        XCTAssertEqual(request.scalingMode, .fill)
        XCTAssertEqual(
            request.clearColor,
            .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
        XCTAssertTrue(request.requestsSnapshot)
        guard case .owned = request.output else {
            return XCTFail("Expected renderer-owned output")
        }
    }

    func testRejectsInvalidAndNonFiniteCanvas() {
        let limits = SceneRenderLimits()
        for canvas in [
            SceneRenderCanvas(width: 0, height: 100),
            SceneRenderCanvas(width: -1, height: 100),
            SceneRenderCanvas(width: .infinity, height: 100),
            SceneRenderCanvas(width: 100, height: .nan)
        ] {
            XCTAssertThrowsError(try limits.validate(canvas: canvas)) { error in
                XCTAssertEqual(error as? SceneRenderError, .invalidProgram)
            }
        }
    }

    func testValidatesFrameRequirementsWithCheckedArithmetic() throws {
        let validated = try SceneRenderLimits().validateFrame(
            outputWidth: 3_840,
            outputHeight: 2_160,
            drawItemCount: 10,
            requestedInFlightFrameCount: 3,
            requestsSnapshot: true
        )

        XCTAssertEqual(validated.pixelCount, 8_294_400)
        XCTAssertEqual(validated.compositionTargetBytes, 66_355_200)
        XCTAssertEqual(validated.finalTargetBytes, 33_177_600)
        XCTAssertEqual(validated.bytesPerFrame, 99_532_800)
        XCTAssertEqual(validated.effectiveInFlightFrameCount, 3)
        XCTAssertEqual(validated.snapshotReadbackBytes, 33_177_600)
    }

    func testReducesInFlightCountToFitAggregateTargetBudget() throws {
        let validated = try SceneRenderLimits().validateFrame(
            outputWidth: 7_680,
            outputHeight: 4_320,
            drawItemCount: 1,
            requestedInFlightFrameCount: 3,
            requestsSnapshot: false
        )

        XCTAssertEqual(validated.effectiveInFlightFrameCount, 1)
    }

    func testRejectsDimensionPixelAndIntegerOverflowBeforeAllocation() {
        assertFrameLimit(
            .outputDimension,
            width: 16_385,
            height: 1
        )
        assertFrameLimit(
            .outputPixels,
            width: 8_192,
            height: 8_192
        )
        assertFrameLimit(
            .outputPixels,
            width: Int.max,
            height: 2,
            limits: .init(maximumDimension: Int.max, maximumPixelCount: Int.max)
        )
    }

    func testRejectsDrawAndInFlightLimits() {
        assertFrameLimit(.drawItems, drawItemCount: 100_001)
        assertFrameLimit(.inFlightFrames, requestedInFlightFrameCount: 4)
    }

    func testRejectsTargetAndSnapshotBudgetsBeforeAllocation() {
        assertFrameLimit(
            .renderTargetBytes,
            limits: .init(renderTargetBudgetBytes: 11)
        )
        assertFrameLimit(
            .snapshotReadbackBytes,
            requestsSnapshot: true,
            limits: .init(snapshotReadbackBudgetBytes: 3)
        )
    }

    func testRejectsInvalidFrameDimensionsAndConfiguration() {
        assertFrameError(.invalidTarget, width: 0)
        assertFrameError(.invalidTarget, height: -1)
        assertFrameError(.invalidProgram, drawItemCount: -1)
        assertFrameError(.invalidProgram, requestedInFlightFrameCount: 0)
    }

    private func assertFrameLimit(
        _ expected: SceneRenderLimit,
        width: Int = 1,
        height: Int = 1,
        drawItemCount: Int = 0,
        requestedInFlightFrameCount: Int = 1,
        requestsSnapshot: Bool = false,
        limits: SceneRenderLimits = .init(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFrameError(
            .resourceLimit(expected),
            width: width,
            height: height,
            drawItemCount: drawItemCount,
            requestedInFlightFrameCount: requestedInFlightFrameCount,
            requestsSnapshot: requestsSnapshot,
            limits: limits,
            file: file,
            line: line
        )
    }

    private func assertFrameError(
        _ expected: SceneRenderError,
        width: Int = 1,
        height: Int = 1,
        drawItemCount: Int = 0,
        requestedInFlightFrameCount: Int = 1,
        requestsSnapshot: Bool = false,
        limits: SceneRenderLimits = .init(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try limits.validateFrame(
                outputWidth: width,
                outputHeight: height,
                drawItemCount: drawItemCount,
                requestedInFlightFrameCount: requestedInFlightFrameCount,
                requestsSnapshot: requestsSnapshot
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? SceneRenderError, expected, file: file, line: line)
        }
    }
}

