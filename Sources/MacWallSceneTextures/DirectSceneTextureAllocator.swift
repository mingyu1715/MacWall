import Foundation
import Metal

struct DirectSceneTextureAllocatorOperations: @unchecked Sendable {
    var makeCommandQueue: (any MTLDevice) -> (any MTLCommandQueue)?
    var makeCommandBuffer: (any MTLCommandQueue) -> (any MTLCommandBuffer)?
    var makeBuffer: (
        any MTLDevice,
        Int,
        MTLResourceOptions
    ) -> (any MTLBuffer)?
    var makeTexture: (
        any MTLDevice,
        MTLTextureDescriptor
    ) -> (any MTLTexture)?
    var makeBlitCommandEncoder: (
        any MTLCommandBuffer
    ) -> (any MTLBlitCommandEncoder)?
    var addCompletedHandler: (
        any MTLCommandBuffer,
        @escaping @Sendable () -> Void
    ) -> Void
    var commandBufferStatus: (any MTLCommandBuffer) -> MTLCommandBufferStatus
    var commit: (any MTLCommandBuffer) -> Void

    static let live = DirectSceneTextureAllocatorOperations(
        makeCommandQueue: { $0.makeCommandQueue() },
        makeCommandBuffer: { $0.makeCommandBuffer() },
        makeBuffer: { device, length, options in
            device.makeBuffer(length: length, options: options)
        },
        makeTexture: { device, descriptor in
            device.makeTexture(descriptor: descriptor)
        },
        makeBlitCommandEncoder: { $0.makeBlitCommandEncoder() },
        addCompletedHandler: { commandBuffer, completion in
            commandBuffer.addCompletedHandler { _ in
                completion()
            }
        },
        commandBufferStatus: { $0.status },
        commit: { $0.commit() }
    )
}

struct DirectSceneTextureAllocator: SceneTextureAllocator, @unchecked Sendable {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let limits: SceneTextureLimits
    private let executor: SceneTextureUploadExecutor
    private let operations: DirectSceneTextureAllocatorOperations

    init(
        device: any MTLDevice,
        limits: SceneTextureLimits,
        executor: SceneTextureUploadExecutor = SceneTextureUploadExecutor(),
        operations: DirectSceneTextureAllocatorOperations = .live
    ) throws {
        guard let commandQueue = operations.makeCommandQueue(device) else {
            throw SceneTexturePipelineError.allocationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        self.limits = limits
        self.executor = executor
        self.operations = operations
    }

    func allocate(
        _ plan: SceneTextureAllocationPlan,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture {
        let linearFormat = plan.format.linearMetalPixelFormat
        let srgbFormat: MTLPixelFormat?
        if plan.supportsSRGBView {
            guard let compatibleFormat = plan.format.sRGBMetalPixelFormat else {
                throw SceneTexturePipelineError.allocationFailed
            }
            srgbFormat = compatibleFormat
        } else {
            srgbFormat = nil
        }
        let alignment = sceneTextureStagingAlignment(device: device, format: plan.format)
        let expectedLayout: SceneTextureStagingLayout
        do {
            expectedLayout = try SceneTextureStagingLayout.make(
                format: plan.format,
                mips: plan.mips,
                minimumAlignment: alignment
            )
        } catch {
            throw SceneTexturePipelineError.allocationFailed
        }
        guard expectedLayout == plan.stagingLayout,
              !plan.mips.isEmpty,
              plan.mips.count == plan.stagingLayout.mips.count,
              plan.mips[0].storageExtent == plan.storageExtent else {
            throw SceneTexturePipelineError.allocationFailed
        }

        guard let commandBuffer = operations.makeCommandBuffer(commandQueue),
              let stagingBuffer = operations.makeBuffer(
                  device,
                  expectedLayout.totalBytes,
                  .storageModeShared
              ) else {
            throw SceneTexturePipelineError.allocationFailed
        }
        try copyPayloads(
            plan.mips,
            layout: expectedLayout,
            to: stagingBuffer
        )

        let descriptor = textureDescriptor(
            plan: plan,
            pixelFormat: linearFormat,
            supportsView: srgbFormat != nil
        )
        guard let linearTexture = operations.makeTexture(device, descriptor),
              let blitEncoder = operations.makeBlitCommandEncoder(commandBuffer) else {
            throw SceneTexturePipelineError.allocationFailed
        }

        for stagingMip in expectedLayout.mips {
            blitEncoder.copy(
                from: stagingBuffer,
                sourceOffset: stagingMip.offset,
                sourceBytesPerRow: stagingMip.alignedBytesPerRow,
                sourceBytesPerImage: stagingMip.bytesPerImage,
                sourceSize: MTLSize(
                    width: stagingMip.copySize.width,
                    height: stagingMip.copySize.height,
                    depth: 1
                ),
                to: linearTexture,
                destinationSlice: 0,
                destinationLevel: stagingMip.level,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        blitEncoder.endEncoding()

        let submittedResources = SceneTextureSubmittedResources(
            commandBuffer: commandBuffer,
            stagingBuffer: stagingBuffer,
            linearTexture: linearTexture,
            operations: operations
        )
        try await executor.execute(timeout: limits.uploadTimeout) { finish in
            submittedResources.operations.addCompletedHandler(
                submittedResources.commandBuffer
            ) {
                _ = submittedResources.stagingBuffer
                _ = submittedResources.linearTexture
                let status = submittedResources.operations.commandBufferStatus(
                    submittedResources.commandBuffer
                )
                if status == .completed {
                    finish(.success(()))
                } else {
                    finish(.failure(SceneTexturePipelineError.uploadFailed))
                }
            }
            submission.markSubmitted()
            submittedResources.operations.commit(submittedResources.commandBuffer)
        }

        let srgbTexture: (any MTLTexture)?
        if let srgbFormat {
            guard let view = linearTexture.makeTextureView(pixelFormat: srgbFormat) else {
                throw SceneTexturePipelineError.allocationFailed
            }
            srgbTexture = view
        } else {
            srgbTexture = nil
        }

        return SceneAllocatedTexture(
            linearTexture: linearTexture,
            srgbTexture: srgbTexture,
            uploadPath: plan.uploadPath,
            storageExtent: plan.storageExtent,
            contentExtent: plan.contentExtent,
            contentRect: plan.contentRect,
            origin: plan.origin,
            mipmapLevelCount: plan.mips.count,
            residentBytes: linearTexture.allocatedSize
        )
    }

    private func textureDescriptor(
        plan: SceneTextureAllocationPlan,
        pixelFormat: MTLPixelFormat,
        supportsView: Bool
    ) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = plan.storageExtent.width
        descriptor.height = plan.storageExtent.height
        descriptor.depth = 1
        descriptor.mipmapLevelCount = plan.mips.count
        descriptor.sampleCount = 1
        descriptor.arrayLength = 1
        descriptor.storageMode = .private
        descriptor.usage = supportsView
            ? [.shaderRead, .pixelFormatView]
            : [.shaderRead]
        return descriptor
    }

    private func copyPayloads(
        _ mips: [SceneTexturePreparedMip],
        layout: SceneTextureStagingLayout,
        to buffer: any MTLBuffer
    ) throws {
        memset(buffer.contents(), 0, layout.totalBytes)

        for (mip, stagingMip) in zip(mips, layout.mips) {
            let (expectedBytes, overflow) = mip.unalignedBytesPerRow
                .multipliedReportingOverflow(by: stagingMip.blockOrPixelRowCount)
            guard !overflow,
                  mip.level == stagingMip.level,
                  mip.storageExtent == stagingMip.copySize,
                  mip.unalignedBytesPerRow <= stagingMip.alignedBytesPerRow,
                  mip.bytes.count == expectedBytes else {
                throw SceneTexturePipelineError.allocationFailed
            }

            mip.bytes.withUnsafeBytes { source in
                guard let sourceBase = source.baseAddress else {
                    return
                }
                for row in 0..<stagingMip.blockOrPixelRowCount {
                    memcpy(
                        buffer.contents().advanced(
                            by: stagingMip.offset + row * stagingMip.alignedBytesPerRow
                        ),
                        sourceBase.advanced(by: row * mip.unalignedBytesPerRow),
                        mip.unalignedBytesPerRow
                    )
                }
            }
        }
    }
}

func sceneTextureStagingAlignment(
    device: any MTLDevice,
    format: SceneTextureGPUFormat
) -> Int {
    switch format {
    case .rgba8Unorm, .rg8Unorm, .r8Unorm:
        device.minimumLinearTextureAlignment(for: format.linearMetalPixelFormat)
    case .bc1RGBA, .bc2RGBA, .bc3RGBA:
        // Metal rejects compressed formats in its linear-alignment queries.
        device.minimumLinearTextureAlignment(for: .rgba8Unorm)
    }
}

private final class SceneTextureSubmittedResources: @unchecked Sendable {
    let commandBuffer: any MTLCommandBuffer
    let stagingBuffer: any MTLBuffer
    let linearTexture: any MTLTexture
    let operations: DirectSceneTextureAllocatorOperations

    init(
        commandBuffer: any MTLCommandBuffer,
        stagingBuffer: any MTLBuffer,
        linearTexture: any MTLTexture,
        operations: DirectSceneTextureAllocatorOperations
    ) {
        self.commandBuffer = commandBuffer
        self.stagingBuffer = stagingBuffer
        self.linearTexture = linearTexture
        self.operations = operations
    }
}
