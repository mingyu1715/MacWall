import Metal
import XCTest
@testable import MacWallSceneRenderer

final class SceneMetalPipelineTests: XCTestCase {
    func testImagePipelineUsesPremultipliedSourceOverIntoLinearTarget() {
        let attachment = SceneMetalPipelines.makeImageColorAttachmentDescriptor()

        XCTAssertEqual(attachment.pixelFormat, .rgba16Float)
        XCTAssertTrue(attachment.isBlendingEnabled)
        XCTAssertEqual(attachment.sourceRGBBlendFactor, .one)
        XCTAssertEqual(attachment.destinationRGBBlendFactor, .oneMinusSourceAlpha)
        XCTAssertEqual(attachment.rgbBlendOperation, .add)
        XCTAssertEqual(attachment.sourceAlphaBlendFactor, .one)
        XCTAssertEqual(attachment.destinationAlphaBlendFactor, .oneMinusSourceAlpha)
        XCTAssertEqual(attachment.alphaBlendOperation, .add)
    }

    func testFinalPipelineWritesSRGBTargetWithoutBlending() {
        let attachment = SceneMetalPipelines.makeFinalColorAttachmentDescriptor()

        XCTAssertEqual(attachment.pixelFormat, .bgra8Unorm_srgb)
        XCTAssertFalse(attachment.isBlendingEnabled)
    }

    func testSamplerUsesLinearMipFilteringClampAndBoundedAnisotropy() {
        let descriptor = SceneMetalPipelines.makeSamplerDescriptor()

        XCTAssertTrue(descriptor.normalizedCoordinates)
        XCTAssertEqual(descriptor.minFilter, .linear)
        XCTAssertEqual(descriptor.magFilter, .linear)
        XCTAssertEqual(descriptor.mipFilter, .linear)
        XCTAssertEqual(descriptor.sAddressMode, .clampToEdge)
        XCTAssertEqual(descriptor.tAddressMode, .clampToEdge)
        XCTAssertEqual(descriptor.rAddressMode, .clampToEdge)
        XCTAssertEqual(descriptor.maxAnisotropy, 8)
    }

    func testUniformRingAllocatesAtMostThreeReusableBuffers() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        let ring = try SceneUniformBufferRing(
            device: device,
            count: 3,
            bytesPerBuffer: 160
        )

        XCTAssertEqual(ring.count, 3)
        XCTAssertGreaterThanOrEqual(ring.buffer(at: 0).length, 160)
        XCTAssertEqual(
            ObjectIdentifier(ring.buffer(at: 0) as AnyObject),
            ObjectIdentifier(ring.buffer(at: 3) as AnyObject)
        )
        XCTAssertThrowsError(try SceneUniformBufferRing(
            device: device,
            count: 4,
            bytesPerBuffer: 160
        )) { error in
            XCTAssertEqual(error as? SceneRenderError, .resourceLimit(.inFlightFrames))
        }
    }

    func testTargetPoolCreatesReusesAndCapsLinearAndFinalTargets() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        let bytesPerFrame = 4 * 4 * (8 + 4)
        let pool = SceneRenderTargetPool(
            device: device,
            limits: .init(
                maximumDimension: 32,
                maximumPixelCount: 1_024,
                maximumDrawItemCount: 10,
                maximumInFlightFrameCount: 2,
                renderTargetBudgetBytes: bytesPerFrame * 2,
                snapshotReadbackBudgetBytes: 1_024
            )
        )
        var first: SceneRenderTargetAllocation? = try await pool.acquire(
            width: 4,
            height: 4
        )
        let firstCompositionID = ObjectIdentifier(
            try XCTUnwrap(first?.compositionTexture) as AnyObject
        )
        let firstFinalID = ObjectIdentifier(try XCTUnwrap(first?.texture) as AnyObject)
        var firstAlias = first
        let second = try await pool.acquire(width: 4, height: 4)

        try assertTexturePair(first, device: device, width: 4, height: 4)
        try assertTexturePair(second, device: device, width: 4, height: 4)
        await assertAsyncRenderError(.resourceLimit(.inFlightFrames)) {
            _ = try await pool.acquire(width: 4, height: 4)
        }

        first = nil
        await assertAsyncRenderError(.resourceLimit(.inFlightFrames)) {
            _ = try await pool.acquire(width: 4, height: 4)
        }
        firstAlias = nil
        let reused = try await pool.acquire(width: 4, height: 4)
        XCTAssertEqual(
            ObjectIdentifier(reused.compositionTexture as AnyObject),
            firstCompositionID
        )
        XCTAssertEqual(ObjectIdentifier(reused.texture as AnyObject), firstFinalID)
        _ = firstAlias
    }

    func testTargetPoolEnforcesAggregateBudgetAndInvalidation() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        let bytesPerFrame = 4 * 4 * (8 + 4)
        let pool = SceneRenderTargetPool(
            device: device,
            limits: .init(
                maximumDimension: 32,
                maximumPixelCount: 1_024,
                maximumDrawItemCount: 10,
                maximumInFlightFrameCount: 3,
                renderTargetBudgetBytes: bytesPerFrame,
                snapshotReadbackBudgetBytes: 1_024
            )
        )
        let allocation = try await pool.acquire(width: 4, height: 4)
        await assertAsyncRenderError(.resourceLimit(.renderTargetBytes)) {
            _ = try await pool.acquire(width: 4, height: 4)
        }

        await pool.invalidate()
        await pool.invalidate()
        await assertAsyncRenderError(.sessionInvalidated) {
            _ = try await pool.acquire(width: 4, height: 4)
        }
        _ = allocation
    }

    func testExternalTargetValidationChecksDeviceFormatSizeAndUsage() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        let validDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: 4,
            height: 3,
            mipmapped: false
        )
        validDescriptor.usage = [.renderTarget, .shaderRead]
        validDescriptor.storageMode = .private
        let valid = try XCTUnwrap(device.makeTexture(descriptor: validDescriptor))

        XCTAssertNoThrow(try SceneMetalPipelines.validateExternalTarget(
            valid,
            device: device,
            width: 4,
            height: 3
        ))
        XCTAssertThrowsError(try SceneMetalPipelines.validateExternalTarget(
            valid,
            device: device,
            width: 3,
            height: 4
        )) { error in
            XCTAssertEqual(error as? SceneRenderError, .invalidTarget)
        }

        let invalidDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 4,
            height: 3,
            mipmapped: false
        )
        invalidDescriptor.usage = .shaderRead
        let invalid = try XCTUnwrap(device.makeTexture(descriptor: invalidDescriptor))
        XCTAssertThrowsError(try SceneMetalPipelines.validateExternalTarget(
            invalid,
            device: device,
            width: 4,
            height: 3
        )) { error in
            XCTAssertEqual(error as? SceneRenderError, .invalidTarget)
        }
    }

    func testDefaultShaderLibraryContainsSceneFunctions() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        guard SceneMetalPipelines.hasPackagedDefaultLibrary else {
            throw XCTSkip(
                "The native SwiftPM engine does not compile Metal sources; "
                    + "run this gate with --build-system swiftbuild"
            )
        }

        let library = try SceneMetalPipelines.makeDefaultLibrary(device: device)
        XCTAssertNotNil(library.makeFunction(name: "sceneImageVertex"))
        XCTAssertNotNil(library.makeFunction(name: "sceneImageFragment"))
        XCTAssertNotNil(library.makeFunction(name: "sceneFinalVertex"))
        XCTAssertNotNil(library.makeFunction(name: "sceneFinalFragment"))
        XCTAssertNoThrow(try SceneMetalPipelines.makeResources(
            device: device,
            maximumInFlightFrameCount: 3
        ))
    }

    private func assertTexturePair(
        _ allocation: SceneRenderTargetAllocation?,
        device: any MTLDevice,
        width: Int,
        height: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let allocation = try XCTUnwrap(allocation, file: file, line: line)
        XCTAssertEqual(allocation.compositionTexture.pixelFormat, .rgba16Float, file: file, line: line)
        XCTAssertEqual(allocation.texture.pixelFormat, .bgra8Unorm_srgb, file: file, line: line)
        for texture in [allocation.compositionTexture, allocation.texture] {
            XCTAssertEqual(texture.device.registryID, device.registryID, file: file, line: line)
            XCTAssertEqual(texture.width, width, file: file, line: line)
            XCTAssertEqual(texture.height, height, file: file, line: line)
            XCTAssertTrue(texture.usage.contains(.renderTarget), file: file, line: line)
            XCTAssertTrue(texture.usage.contains(.shaderRead), file: file, line: line)
        }
    }

    private func assertAsyncRenderError(
        _ expected: SceneRenderError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SceneRenderError, expected, file: file, line: line)
        }
    }
}
