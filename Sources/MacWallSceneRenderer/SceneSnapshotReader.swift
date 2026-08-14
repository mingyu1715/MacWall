import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct SceneSnapshotReaderOperations: @unchecked Sendable {
    var makeBuffer: (
        any MTLDevice,
        Int,
        MTLResourceOptions
    ) -> (any MTLBuffer)?
    var makeCommandBuffer: (
        any MTLCommandQueue
    ) -> (any MTLCommandBuffer)?
    var makeBlitCommandEncoder: (
        any MTLCommandBuffer
    ) -> (any MTLBlitCommandEncoder)?
    var addCompletedHandler: (
        any MTLCommandBuffer,
        @escaping @Sendable () -> Void
    ) -> Void
    var commandBufferStatus: (
        any MTLCommandBuffer
    ) -> MTLCommandBufferStatus
    var commit: (any MTLCommandBuffer) -> Void

    static let live = SceneSnapshotReaderOperations(
        makeBuffer: { device, length, options in
            device.makeBuffer(length: length, options: options)
        },
        makeCommandBuffer: { $0.makeCommandBuffer() },
        makeBlitCommandEncoder: { $0.makeBlitCommandEncoder() },
        addCompletedHandler: { commandBuffer, completion in
            commandBuffer.addCompletedHandler { _ in completion() }
        },
        commandBufferStatus: { $0.status },
        commit: { $0.commit() }
    )
}

struct SceneSnapshotReader: Sendable {
    private static let readbackRowAlignment = 256

    private let operations: SceneSnapshotReaderOperations

    init(operations: SceneSnapshotReaderOperations = .live) {
        self.operations = operations
    }

    func pngData(
        from completedTexture: any MTLTexture,
        commandQueue: any MTLCommandQueue,
        limits: SceneRenderLimits
    ) async throws -> Data {
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        try validate(texture: completedTexture, commandQueue: commandQueue)
        _ = try limits.validateFrame(
            outputWidth: completedTexture.width,
            outputHeight: completedTexture.height,
            drawItemCount: 0,
            requestedInFlightFrameCount: 1,
            requestsSnapshot: true
        )
        let layout = try SceneSnapshotReadbackLayout.make(
            width: completedTexture.width,
            height: completedTexture.height,
            alignment: Self.readbackRowAlignment,
            budgetBytes: limits.snapshotReadbackBudgetBytes
        )
        guard let readbackBuffer = operations.makeBuffer(
            completedTexture.device,
            layout.totalBytes,
            .storageModeShared
        ), let commandBuffer = operations.makeCommandBuffer(commandQueue),
           let blit = operations.makeBlitCommandEncoder(commandBuffer) else {
            throw SceneRenderError.incompatibleDevice
        }
        readbackBuffer.label = "MacWall Scene snapshot readback"
        commandBuffer.label = "MacWall Scene snapshot readback"
        blit.label = "MacWall Scene snapshot blit"
        blit.copy(
            from: completedTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: completedTexture.width,
                height: completedTexture.height,
                depth: 1
            ),
            to: readbackBuffer,
            destinationOffset: 0,
            destinationBytesPerRow: layout.alignedBytesPerRow,
            destinationBytesPerImage: 0
        )
        blit.endEncoding()

        let submitted = SceneSnapshotSubmittedResources(
            texture: completedTexture,
            buffer: readbackBuffer,
            commandBuffer: commandBuffer
        )
        try await commitAndWait(submitted)
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        let straightRGBA = try Self.makeStraightRGBA(
            from: submitted.buffer,
            layout: layout,
            height: completedTexture.height
        )
        let width = completedTexture.width
        let height = completedTexture.height
        return try await Task.detached(priority: .utility) {
            try Self.encodePNG(
                straightRGBA: straightRGBA,
                width: width,
                height: height,
                bytesPerRow: layout.tightBytesPerRow
            )
        }.value
    }

    private func validate(
        texture: any MTLTexture,
        commandQueue: any MTLCommandQueue
    ) throws {
        guard texture.device.registryID == commandQueue.device.registryID else {
            throw SceneRenderError.incompatibleDevice
        }
        guard texture.textureType == .type2D,
              texture.pixelFormat == .bgra8Unorm_srgb,
              texture.width > 0,
              texture.height > 0,
              texture.depth == 1,
              texture.arrayLength == 1,
              texture.mipmapLevelCount == 1,
              texture.sampleCount == 1 else {
            throw SceneRenderError.invalidTarget
        }
    }

    private func commitAndWait(
        _ submitted: SceneSnapshotSubmittedResources
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            operations.addCompletedHandler(submitted.commandBuffer) {
                _ = submitted.texture
                _ = submitted.buffer
                if operations.commandBufferStatus(submitted.commandBuffer) == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SceneRenderError.commandFailed)
                }
            }
            operations.commit(submitted.commandBuffer)
        }
    }

    private static func makeStraightRGBA(
        from buffer: any MTLBuffer,
        layout: SceneSnapshotReadbackLayout,
        height: Int
    ) throws -> Data {
        let (tightByteCount, overflow) = layout.tightBytesPerRow
            .multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw SceneRenderError.resourceLimit(.snapshotReadbackBytes)
        }
        var result = Data(count: tightByteCount)
        result.withUnsafeMutableBytes { destination in
            let source = buffer.contents().assumingMemoryBound(to: UInt8.self)
            let output = destination.bindMemory(to: UInt8.self)
            for row in 0..<height {
                let sourceRow = source.advanced(by: row * layout.alignedBytesPerRow)
                let destinationRow = output.baseAddress!.advanced(
                    by: row * layout.tightBytesPerRow
                )
                for pixel in 0..<layout.width {
                    let sourcePixel = sourceRow.advanced(by: pixel * 4)
                    let destinationPixel = destinationRow.advanced(by: pixel * 4)
                    let alphaByte = sourcePixel[3]
                    let alpha = Double(alphaByte) / 255
                    destinationPixel[0] = straightSRGB(
                        premultipliedSRGB: sourcePixel[2],
                        alpha: alpha
                    )
                    destinationPixel[1] = straightSRGB(
                        premultipliedSRGB: sourcePixel[1],
                        alpha: alpha
                    )
                    destinationPixel[2] = straightSRGB(
                        premultipliedSRGB: sourcePixel[0],
                        alpha: alpha
                    )
                    destinationPixel[3] = alphaByte
                }
            }
        }
        return result
    }

    private static func straightSRGB(
        premultipliedSRGB byte: UInt8,
        alpha: Double
    ) -> UInt8 {
        guard alpha > 0 else { return 0 }
        let encoded = Double(byte) / 255
        let premultipliedLinear = encoded <= 0.04045
            ? encoded / 12.92
            : pow((encoded + 0.055) / 1.055, 2.4)
        let straightLinear = min(max(premultipliedLinear / alpha, 0), 1)
        let straightEncoded = straightLinear <= 0.0031308
            ? straightLinear * 12.92
            : 1.055 * pow(straightLinear, 1 / 2.4) - 0.055
        return UInt8((min(max(straightEncoded, 0), 1) * 255).rounded())
    }

    private static func encodePNG(
        straightRGBA: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> Data {
        guard let provider = CGDataProvider(data: straightRGBA as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw SceneRenderError.snapshotEncodingFailed
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        )
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw SceneRenderError.snapshotEncodingFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SceneRenderError.snapshotEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SceneRenderError.snapshotEncodingFailed
        }
        return output as Data
    }
}

struct SceneSnapshotReadbackLayout: Equatable, Sendable {
    let width: Int
    let tightBytesPerRow: Int
    let alignedBytesPerRow: Int
    let totalBytes: Int

    static func make(
        width: Int,
        height: Int,
        alignment: Int,
        budgetBytes: Int
    ) throws -> SceneSnapshotReadbackLayout {
        guard width > 0, height > 0,
              alignment > 0, alignment.nonzeroBitCount == 1,
              budgetBytes > 0 else {
            throw SceneRenderError.invalidTarget
        }
        let (tightBytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow else {
            throw SceneRenderError.resourceLimit(.snapshotReadbackBytes)
        }
        let (withPadding, paddingOverflow) = tightBytesPerRow
            .addingReportingOverflow(alignment - 1)
        guard !paddingOverflow else {
            throw SceneRenderError.resourceLimit(.snapshotReadbackBytes)
        }
        let alignedBytesPerRow = withPadding & ~(alignment - 1)
        let (totalBytes, totalOverflow) = alignedBytesPerRow
            .multipliedReportingOverflow(by: height)
        guard !totalOverflow, totalBytes <= budgetBytes else {
            throw SceneRenderError.resourceLimit(.snapshotReadbackBytes)
        }
        return SceneSnapshotReadbackLayout(
            width: width,
            tightBytesPerRow: tightBytesPerRow,
            alignedBytesPerRow: alignedBytesPerRow,
            totalBytes: totalBytes
        )
    }
}

private final class SceneSnapshotSubmittedResources: @unchecked Sendable {
    let texture: any MTLTexture
    let buffer: any MTLBuffer
    let commandBuffer: any MTLCommandBuffer

    init(
        texture: any MTLTexture,
        buffer: any MTLBuffer,
        commandBuffer: any MTLCommandBuffer
    ) {
        self.texture = texture
        self.buffer = buffer
        self.commandBuffer = commandBuffer
    }
}
