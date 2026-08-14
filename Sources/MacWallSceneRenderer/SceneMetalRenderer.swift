import Foundation
import Metal
import simd
import MacWallSceneGraph
import MacWallSceneTextures

actor SceneMetalRenderer {
    private static let maximumMipCount = 16
    private static let mipUniformStride = 288

    private let device: any MTLDevice
    private let limits: SceneRenderLimits
    private let commandQueue: any MTLCommandQueue
    private let pipelines: SceneMetalPipelineResources
    private let targetPool: SceneRenderTargetPool
    private let frameGate: SceneInFlightFrameGate
    private let snapshotReader = SceneSnapshotReader()
    private let textureLeases: [Int: SceneTextureLease]
    private let mipUniformBuffer: any MTLBuffer
    private let passSlots: [SceneMetalPassSlot]
    private var externalTargetReservations = SceneExternalTargetReservations()
    private var evaluationScratch = SceneEvaluationScratch()
    private var framePlan = SceneFramePlan()
    private var invalidated = false

    init(
        device: any MTLDevice,
        program: SceneRenderProgram,
        textureLeases: [Int: SceneTextureLease],
        limits: SceneRenderLimits
    ) throws {
        self.device = device
        self.limits = limits
        self.textureLeases = textureLeases
        guard let commandQueue = device.makeCommandQueue() else {
            throw SceneRenderError.incompatibleDevice
        }
        self.commandQueue = commandQueue

        let drawStride = MemoryLayout<SceneImageDrawUniforms>.stride
        let (uniformBytes, overflow) = max(program.drawCount, 1)
            .multipliedReportingOverflow(by: drawStride)
        guard !overflow else {
            throw SceneRenderError.resourceLimit(.renderTargetBytes)
        }
        pipelines = try SceneMetalPipelines.makeResources(
            device: device,
            maximumInFlightFrameCount: limits.maximumInFlightFrameCount,
            uniformBytesPerFrame: uniformBytes
        )
        targetPool = SceneRenderTargetPool(device: device, limits: limits)
        frameGate = SceneInFlightFrameGate(count: limits.maximumInFlightFrameCount)

        let (mipBytes, mipOverflow) = max(program.textureManifest.count, 1)
            .multipliedReportingOverflow(by: Self.mipUniformStride)
        guard !mipOverflow,
              let mipUniformBuffer = device.makeBuffer(
                length: mipBytes,
                options: .storageModeShared
              ) else {
            throw SceneRenderError.incompatibleDevice
        }
        mipUniformBuffer.label = "MacWall Scene mip content regions"
        self.mipUniformBuffer = mipUniformBuffer
        try Self.populateMipUniforms(
            buffer: mipUniformBuffer,
            manifestCount: program.textureManifest.count,
            textureLeases: textureLeases
        )
        passSlots = (0..<limits.maximumInFlightFrameCount).map {
            SceneMetalPassSlot(index: $0)
        }
    }

    func render(
        program: SceneRenderProgram,
        request: SceneRenderFrameRequest,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic]
    ) async throws -> SceneRenderCompletedFrame {
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        guard request.mediaTimeSeconds.isFinite,
              request.mediaTimeSeconds >= 0,
              request.clearColor.isFinite else {
            throw SceneRenderError.invalidProgram
        }
        _ = try limits.validateFrame(
            outputWidth: request.outputWidth,
            outputHeight: request.outputHeight,
            drawItemCount: program.drawCount,
            requestedInFlightFrameCount: limits.maximumInFlightFrameCount,
            requestsSnapshot: false
        )

        let externalReservation: ObjectIdentifier?
        switch request.output {
        case .owned:
            externalReservation = nil
        case .external(let lease):
            externalReservation = try externalTargetReservations.reserve(lease)
        }

        let slotIndex: Int
        do {
            slotIndex = try await frameGate.acquire()
        } catch {
            if let externalReservation {
                externalTargetReservations.release(externalReservation)
            }
            throw error
        }
        do {
            let frame = try await render(
                program: program,
                request: request,
                status: status,
                diagnostics: diagnostics,
                slotIndex: slotIndex
            )
            await frameGate.release(slotIndex)
            if let externalReservation {
                externalTargetReservations.release(externalReservation)
            }
            return frame
        } catch {
            await frameGate.release(slotIndex)
            if let externalReservation {
                externalTargetReservations.release(externalReservation)
            }
            throw error
        }
    }

    func invalidate() async {
        guard !invalidated else { return }
        invalidated = true
        externalTargetReservations.removeAll()
        await frameGate.invalidate()
        await targetPool.invalidate()
    }

    private func render(
        program: SceneRenderProgram,
        request: SceneRenderFrameRequest,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic],
        slotIndex: Int
    ) async throws -> SceneRenderCompletedFrame {
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        let allocation = try await targetPool.acquire(
            width: request.outputWidth,
            height: request.outputHeight
        )
        let finalTexture: any MTLTexture
        let retainedAllocation: SceneRenderTargetAllocation?
        switch request.output {
        case .owned:
            finalTexture = allocation.texture
            retainedAllocation = allocation
        case .external(let lease):
            try SceneMetalPipelines.validateExternalTarget(
                lease.texture,
                device: device,
                width: request.outputWidth,
                height: request.outputHeight
            )
            finalTexture = lease.texture
            retainedAllocation = nil
        }

        try SceneTimelineEvaluator().evaluate(
            program: program,
            mediaTimeSeconds: request.mediaTimeSeconds,
            into: &evaluationScratch
        )
        try SceneTransformEvaluator().makeFramePlan(
            program: program,
            properties: evaluationScratch,
            output: .init(
                width: request.outputWidth,
                height: request.outputHeight,
                scalingMode: request.scalingMode
            ),
            into: &framePlan
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SceneRenderError.incompatibleDevice
        }
        commandBuffer.label = "MacWall Scene frame"
        let uniformBuffer = pipelines.uniformBuffers.buffer(at: slotIndex)
        let passSlot = passSlots[slotIndex]

        passSlot.composition.colorAttachments[0].texture = allocation.compositionTexture
        passSlot.composition.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(request.clearColor.red),
            green: Double(request.clearColor.green),
            blue: Double(request.clearColor.blue),
            alpha: Double(request.clearColor.alpha)
        )
        guard let compositionEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: passSlot.composition
        ) else {
            throw SceneRenderError.commandFailed
        }
        compositionEncoder.label = "MacWall Scene composition"
        compositionEncoder.setRenderPipelineState(pipelines.imagePipeline)
        compositionEncoder.setFragmentSamplerState(pipelines.sampler, index: 0)

        var encodedDrawCount = 0
        var skippedDrawCount = framePlan.skippedDrawCount
        for item in framePlan.drawItems {
            guard let lease = textureLeases[item.textureManifestIndex] else {
                skippedDrawCount += 1
                continue
            }
            guard let localSize = Self.localSize(
                explicit: item.localSize,
                textureLease: lease
            ) else {
                skippedDrawCount += 1
                continue
            }
            let uniformOffset = encodedDrawCount * MemoryLayout<SceneImageDrawUniforms>.stride
            var uniforms = SceneImageDrawUniforms(
                clipTransform: item.clipTransform
                    * Self.centeredQuadTransform(size: localSize),
                textureCoordinates: item.textureCoordinates,
                premultipliedTint: item.linearPremultipliedTint
            )
            memcpy(
                uniformBuffer.contents().advanced(by: uniformOffset),
                &uniforms,
                MemoryLayout<SceneImageDrawUniforms>.stride
            )
            compositionEncoder.setVertexBuffer(
                uniformBuffer,
                offset: uniformOffset,
                index: 0
            )
            compositionEncoder.setFragmentBuffer(
                uniformBuffer,
                offset: uniformOffset,
                index: 0
            )
            compositionEncoder.setFragmentBuffer(
                mipUniformBuffer,
                offset: item.textureManifestIndex * Self.mipUniformStride,
                index: 1
            )
            compositionEncoder.setFragmentTexture(lease.texture, index: 0)
            compositionEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4
            )
            encodedDrawCount += 1
        }
        compositionEncoder.endEncoding()

        passSlot.final.colorAttachments[0].texture = finalTexture
        guard let finalEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: passSlot.final
        ) else {
            throw SceneRenderError.commandFailed
        }
        finalEncoder.label = "MacWall Scene final conversion"
        finalEncoder.setRenderPipelineState(pipelines.finalPipeline)
        finalEncoder.setFragmentSamplerState(pipelines.sampler, index: 0)
        finalEncoder.setFragmentTexture(allocation.compositionTexture, index: 0)
        finalEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
        finalEncoder.endEncoding()

        try await commitAndWait(commandBuffer)
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        var snapshotPNG: Data?
        var completedDiagnostics = diagnostics
        if request.requestsSnapshot {
            do {
                snapshotPNG = try await snapshotReader.pngData(
                    from: finalTexture,
                    commandQueue: commandQueue,
                    limits: limits
                )
            } catch let error as SceneRenderError {
                guard error != .cancelled else { throw error }
                completedDiagnostics.append(.init(
                    severity: .warning,
                    code: "renderer.snapshot-failed",
                    arguments: [Self.snapshotDiagnosticArgument(error)]
                ))
            } catch is CancellationError {
                throw SceneRenderError.cancelled
            } catch {
                completedDiagnostics.append(.init(
                    severity: .warning,
                    code: "renderer.snapshot-failed",
                    arguments: ["snapshotEncodingFailed"]
                ))
            }
        }
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        return SceneRenderCompletedFrame(
            texture: finalTexture,
            mediaTimeSeconds: request.mediaTimeSeconds,
            status: status,
            diagnostics: completedDiagnostics,
            drawCount: encodedDrawCount,
            skippedDrawCount: skippedDrawCount,
            snapshotPNG: snapshotPNG,
            targetAllocation: retainedAllocation
        )
    }

    private func commitAndWait(
        _ commandBuffer: any MTLCommandBuffer
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            commandBuffer.addCompletedHandler { completed in
                if completed.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SceneRenderError.commandFailed)
                }
            }
            commandBuffer.commit()
        }
    }

    private static func populateMipUniforms(
        buffer: any MTLBuffer,
        manifestCount: Int,
        textureLeases: [Int: SceneTextureLease]
    ) throws {
        memset(buffer.contents(), 0, buffer.length)
        for manifestIndex in 0..<manifestCount {
            guard let lease = textureLeases[manifestIndex] else {
                continue
            }
            guard lease.origin == .topLeft,
                  lease.mipmapLevelCount == lease.mipContentRegions.count,
                  !lease.mipContentRegions.isEmpty,
                  lease.mipContentRegions.count <= maximumMipCount else {
                throw SceneRenderError.invalidProgram
            }
            let base = buffer.contents().advanced(
                by: manifestIndex * mipUniformStride
            )
            base.storeBytes(
                of: UInt32(lease.mipContentRegions.count),
                as: UInt32.self
            )
            for (index, region) in lease.mipContentRegions.enumerated() {
                guard region.level == index,
                      region.storageExtent.width > 0,
                      region.storageExtent.height > 0,
                      region.contentExtent.width > 0,
                      region.contentExtent.height > 0 else {
                    throw SceneRenderError.invalidProgram
                }
                var rect = SIMD4<Float>(
                    region.contentRect.u,
                    region.contentRect.v,
                    region.contentRect.width,
                    region.contentRect.height
                )
                memcpy(
                    base.advanced(by: 16 + index * MemoryLayout<SIMD4<Float>>.stride),
                    &rect,
                    MemoryLayout<SIMD4<Float>>.stride
                )
            }
        }
    }

    private static func snapshotDiagnosticArgument(
        _ error: SceneRenderError
    ) -> String {
        switch error {
        case .resourceLimit(let limit):
            return "resourceLimit.\(limit.rawValue)"
        case .invalidProgram: return "invalidProgram"
        case .unsupported: return "unsupported"
        case .incompatibleDevice: return "incompatibleDevice"
        case .invalidTarget: return "invalidTarget"
        case .sessionInvalidated: return "sessionInvalidated"
        case .cancelled: return "cancelled"
        case .commandFailed: return "commandFailed"
        case .snapshotEncodingFailed: return "snapshotEncodingFailed"
        case .texturePipeline: return "texturePipeline"
        }
    }

    private static func localSize(
        explicit: SceneGraphSize?,
        textureLease: SceneTextureLease
    ) -> SIMD2<Float>? {
        let width: Double
        let height: Double
        if let explicit {
            width = explicit.width
            height = explicit.height
        } else if let region = textureLease.mipContentRegions.first {
            width = Double(region.contentExtent.width)
            height = Double(region.contentExtent.height)
        } else {
            return nil
        }
        guard width.isFinite, height.isFinite,
              width > 0, height > 0 else {
            return nil
        }
        let floatSize = SIMD2<Float>(Float(width), Float(height))
        guard floatSize.x.isFinite, floatSize.y.isFinite,
              floatSize.x > 0, floatSize.y > 0 else {
            return nil
        }
        return floatSize
    }

    private static func centeredQuadTransform(
        size: SIMD2<Float>
    ) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(size.x, 0, 0, 0),
            SIMD4<Float>(0, size.y, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-size.x * 0.5, -size.y * 0.5, 0, 1)
        ))
    }
}

struct SceneExternalTargetReservations {
    private var active: Set<ObjectIdentifier> = []

    mutating func reserve(
        _ lease: SceneExternalRenderTargetLease
    ) throws -> ObjectIdentifier {
        let identifier = ObjectIdentifier(lease)
        guard active.insert(identifier).inserted else {
            throw SceneRenderError.invalidTarget
        }
        return identifier
    }

    mutating func release(_ identifier: ObjectIdentifier) {
        active.remove(identifier)
    }

    mutating func removeAll() {
        active.removeAll(keepingCapacity: true)
    }
}

private struct SceneImageDrawUniforms {
    let clipTransform: simd_float4x4
    let textureCoordinates: SIMD4<Float>
    let premultipliedTint: SIMD4<Float>
}

private final class SceneMetalPassSlot: @unchecked Sendable {
    let composition: MTLRenderPassDescriptor
    let final: MTLRenderPassDescriptor

    init(index: Int) {
        composition = MTLRenderPassDescriptor()
        composition.colorAttachments[0].loadAction = .clear
        composition.colorAttachments[0].storeAction = .store

        final = MTLRenderPassDescriptor()
        final.colorAttachments[0].loadAction = .dontCare
        final.colorAttachments[0].storeAction = .store
    }
}

private actor SceneInFlightFrameGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Int, any Error>
    }

    private var availableSlots: [Int]
    private var waiters: [Waiter] = []
    private var invalidated = false

    init(count: Int) {
        availableSlots = Array(0..<count)
    }

    func acquire() async throws -> Int {
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        if !availableSlots.isEmpty {
            return availableSlots.removeFirst()
        }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: SceneRenderError.cancelled)
                    return
                }
                waiters.append(.init(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release(_ slot: Int) {
        guard !invalidated else { return }
        if waiters.isEmpty {
            availableSlots.append(slot)
            availableSlots.sort()
        } else {
            waiters.removeFirst().continuation.resume(returning: slot)
        }
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        availableSlots.removeAll(keepingCapacity: false)
        for waiter in pending {
            waiter.continuation.resume(throwing: SceneRenderError.sessionInvalidated)
        }
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(
            throwing: SceneRenderError.cancelled
        )
    }
}

private extension SceneRenderColor {
    var isFinite: Bool {
        red.isFinite && green.isFinite && blue.isFinite && alpha.isFinite
    }
}
