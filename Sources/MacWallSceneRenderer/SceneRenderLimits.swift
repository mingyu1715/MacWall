import Foundation

public struct SceneRenderLimits: Equatable, Sendable {
    public var maximumDimension: Int
    public var maximumPixelCount: Int
    public var maximumDrawItemCount: Int
    public var maximumInFlightFrameCount: Int
    public var renderTargetBudgetBytes: Int
    public var snapshotReadbackBudgetBytes: Int

    public init(
        maximumDimension: Int = 16_384,
        maximumPixelCount: Int = 33_177_600,
        maximumDrawItemCount: Int = 100_000,
        maximumInFlightFrameCount: Int = 3,
        renderTargetBudgetBytes: Int = 512 * 1_024 * 1_024,
        snapshotReadbackBudgetBytes: Int = 256 * 1_024 * 1_024
    ) {
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.maximumDrawItemCount = maximumDrawItemCount
        self.maximumInFlightFrameCount = maximumInFlightFrameCount
        self.renderTargetBudgetBytes = renderTargetBudgetBytes
        self.snapshotReadbackBudgetBytes = snapshotReadbackBudgetBytes
    }
}

struct SceneValidatedFrameLimits: Equatable, Sendable {
    let pixelCount: Int
    let compositionTargetBytes: Int
    let finalTargetBytes: Int
    let bytesPerFrame: Int
    let effectiveInFlightFrameCount: Int
    let snapshotReadbackBytes: Int?
}

extension SceneRenderLimits {
    func validate(canvas: SceneRenderCanvas) throws {
        try validateConfiguration()
        guard canvas.width.isFinite,
              canvas.height.isFinite,
              canvas.width > 0,
              canvas.height > 0 else {
            throw SceneRenderError.invalidProgram
        }
        guard canvas.width <= Double(maximumDimension),
              canvas.height <= Double(maximumDimension) else {
            throw SceneRenderError.resourceLimit(.outputDimension)
        }
    }

    func validateFrame(
        outputWidth: Int,
        outputHeight: Int,
        drawItemCount: Int,
        requestedInFlightFrameCount: Int,
        requestsSnapshot: Bool
    ) throws -> SceneValidatedFrameLimits {
        try validateConfiguration()
        guard outputWidth > 0, outputHeight > 0 else {
            throw SceneRenderError.invalidTarget
        }
        guard drawItemCount >= 0, requestedInFlightFrameCount > 0 else {
            throw SceneRenderError.invalidProgram
        }
        guard outputWidth <= maximumDimension,
              outputHeight <= maximumDimension else {
            throw SceneRenderError.resourceLimit(.outputDimension)
        }
        guard drawItemCount <= maximumDrawItemCount else {
            throw SceneRenderError.resourceLimit(.drawItems)
        }
        guard requestedInFlightFrameCount <= maximumInFlightFrameCount else {
            throw SceneRenderError.resourceLimit(.inFlightFrames)
        }

        let pixelCount = try checkedProduct(
            outputWidth,
            outputHeight,
            limit: .outputPixels
        )
        guard pixelCount <= maximumPixelCount else {
            throw SceneRenderError.resourceLimit(.outputPixels)
        }

        let compositionBytes = try checkedProduct(
            pixelCount,
            8,
            limit: .renderTargetBytes
        )
        let finalBytes = try checkedProduct(
            pixelCount,
            4,
            limit: .renderTargetBytes
        )
        let (bytesPerFrame, frameBytesOverflow) = compositionBytes.addingReportingOverflow(
            finalBytes
        )
        guard !frameBytesOverflow, bytesPerFrame <= renderTargetBudgetBytes else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }

        let effectiveInFlight = min(
            requestedInFlightFrameCount,
            renderTargetBudgetBytes / bytesPerFrame
        )
        guard effectiveInFlight > 0 else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }

        let snapshotBytes: Int?
        if requestsSnapshot {
            let required = try checkedProduct(
                pixelCount,
                4,
                limit: .snapshotReadbackBytes
            )
            guard required <= snapshotReadbackBudgetBytes else {
                throw SceneRenderError.resourceLimit(.snapshotReadbackBytes)
            }
            snapshotBytes = required
        } else {
            snapshotBytes = nil
        }

        return SceneValidatedFrameLimits(
            pixelCount: pixelCount,
            compositionTargetBytes: compositionBytes,
            finalTargetBytes: finalBytes,
            bytesPerFrame: bytesPerFrame,
            effectiveInFlightFrameCount: effectiveInFlight,
            snapshotReadbackBytes: snapshotBytes
        )
    }

    private func validateConfiguration() throws {
        guard maximumDimension > 0,
              maximumPixelCount > 0,
              maximumDrawItemCount >= 0,
              maximumInFlightFrameCount > 0,
              renderTargetBudgetBytes > 0,
              snapshotReadbackBudgetBytes > 0 else {
            throw SceneRenderError.invalidProgram
        }
    }

    private func checkedProduct(
        _ lhs: Int,
        _ rhs: Int,
        limit: SceneRenderLimit
    ) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw SceneRenderError.resourceLimit(limit)
        }
        return result
    }
}
