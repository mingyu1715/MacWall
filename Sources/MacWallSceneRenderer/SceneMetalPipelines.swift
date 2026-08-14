import Foundation
import Metal

enum SceneMetalPipelines {
    static var hasPackagedDefaultLibrary: Bool {
        Bundle.module.url(
            forResource: "default",
            withExtension: "metallib"
        ) != nil
    }

    static func makeDefaultLibrary(
        device: any MTLDevice
    ) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: Bundle.module)
    }

    static func makeImageColorAttachmentDescriptor()
        -> MTLRenderPipelineColorAttachmentDescriptor {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        attachment.pixelFormat = .rgba16Float
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.alphaBlendOperation = .add
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return attachment
    }

    static func makeFinalColorAttachmentDescriptor()
        -> MTLRenderPipelineColorAttachmentDescriptor {
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        attachment.pixelFormat = .bgra8Unorm_srgb
        attachment.isBlendingEnabled = false
        return attachment
    }

    static func makeSamplerDescriptor() -> MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = "MacWall Scene linear clamp sampler"
        descriptor.normalizedCoordinates = true
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.rAddressMode = .clampToEdge
        descriptor.maxAnisotropy = 8
        return descriptor
    }

    static func makeResources(
        device: any MTLDevice,
        maximumInFlightFrameCount: Int
    ) throws -> SceneMetalPipelineResources {
        let library = try makeDefaultLibrary(device: device)
        guard let imageVertex = library.makeFunction(name: "sceneImageVertex"),
              let imageFragment = library.makeFunction(name: "sceneImageFragment"),
              let finalVertex = library.makeFunction(name: "sceneFinalVertex"),
              let finalFragment = library.makeFunction(name: "sceneFinalFragment") else {
            throw SceneRenderError.incompatibleDevice
        }

        let imageDescriptor = MTLRenderPipelineDescriptor()
        imageDescriptor.label = "MacWall Scene image composition"
        imageDescriptor.vertexFunction = imageVertex
        imageDescriptor.fragmentFunction = imageFragment
        imageDescriptor.colorAttachments[0] = makeImageColorAttachmentDescriptor()

        let finalDescriptor = MTLRenderPipelineDescriptor()
        finalDescriptor.label = "MacWall Scene final conversion"
        finalDescriptor.vertexFunction = finalVertex
        finalDescriptor.fragmentFunction = finalFragment
        finalDescriptor.colorAttachments[0] = makeFinalColorAttachmentDescriptor()

        guard let sampler = device.makeSamplerState(descriptor: makeSamplerDescriptor()) else {
            throw SceneRenderError.incompatibleDevice
        }
        return SceneMetalPipelineResources(
            imagePipeline: try device.makeRenderPipelineState(descriptor: imageDescriptor),
            finalPipeline: try device.makeRenderPipelineState(descriptor: finalDescriptor),
            sampler: sampler,
            uniformBuffers: try SceneUniformBufferRing(
                device: device,
                count: maximumInFlightFrameCount,
                bytesPerBuffer: 256
            )
        )
    }

    static func validateExternalTarget(
        _ texture: any MTLTexture,
        device: any MTLDevice,
        width: Int,
        height: Int
    ) throws {
        guard width > 0, height > 0,
              texture.device.registryID == device.registryID,
              texture.textureType == .type2D,
              texture.pixelFormat == .bgra8Unorm_srgb,
              texture.width == width,
              texture.height == height,
              texture.depth == 1,
              texture.arrayLength == 1,
              texture.mipmapLevelCount == 1,
              texture.sampleCount == 1,
              texture.usage.contains(.renderTarget) else {
            throw SceneRenderError.invalidTarget
        }
    }
}

struct SceneMetalPipelineResources: @unchecked Sendable {
    let imagePipeline: any MTLRenderPipelineState
    let finalPipeline: any MTLRenderPipelineState
    let sampler: any MTLSamplerState
    let uniformBuffers: SceneUniformBufferRing
}

final class SceneUniformBufferRing: @unchecked Sendable {
    private let buffers: [any MTLBuffer]

    var count: Int { buffers.count }

    init(
        device: any MTLDevice,
        count: Int,
        bytesPerBuffer: Int
    ) throws {
        guard count > 0 else {
            throw SceneRenderError.invalidProgram
        }
        guard count <= 3 else {
            throw SceneRenderError.resourceLimit(.inFlightFrames)
        }
        guard bytesPerBuffer > 0 else {
            throw SceneRenderError.invalidProgram
        }
        let (withPadding, overflow) = bytesPerBuffer.addingReportingOverflow(255)
        guard !overflow else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }
        let alignedLength = withPadding & ~255
        var created: [any MTLBuffer] = []
        created.reserveCapacity(count)
        for index in 0..<count {
            guard let buffer = device.makeBuffer(
                length: alignedLength,
                options: .storageModeShared
            ) else {
                throw SceneRenderError.incompatibleDevice
            }
            buffer.label = "MacWall Scene uniforms \(index)"
            created.append(buffer)
        }
        buffers = created
    }

    func buffer(at frameIndex: Int) -> any MTLBuffer {
        let index = frameIndex % buffers.count
        return buffers[index >= 0 ? index : index + buffers.count]
    }
}
