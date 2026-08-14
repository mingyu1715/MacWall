import Foundation
import Metal
import MacWallSceneTextures

public actor SceneRenderSession {
    let program: SceneRenderProgram
    let device: any MTLDevice

    private let textureStore: SceneTextureStore
    private let generationOwner: SceneTextureGenerationOwner
    private let preparedStatus: SceneRenderStatus
    private let preparationDiagnostics: [SceneRenderDiagnostic]
    private let preparedDrawIndices: [Int]
    private var textureLeasesByManifestIndex: [Int: SceneTextureLease]
    private var invalidated = false

    private init(
        program: SceneRenderProgram,
        device: any MTLDevice,
        textureStore: SceneTextureStore,
        generationOwner: SceneTextureGenerationOwner,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic],
        survivingDrawIndices: [Int],
        textureLeasesByManifestIndex: [Int: SceneTextureLease]
    ) {
        self.program = program
        self.device = device
        self.textureStore = textureStore
        self.generationOwner = generationOwner
        preparedStatus = status
        preparationDiagnostics = diagnostics
        preparedDrawIndices = survivingDrawIndices
        self.textureLeasesByManifestIndex = textureLeasesByManifestIndex
    }

    public static func prepare(
        program: SceneRenderProgram,
        device: any MTLDevice,
        textureStore: SceneTextureStore,
        textureContext: SceneTexturePackageContext,
        limits: SceneRenderLimits = .init()
    ) async throws -> SceneRenderSession {
        guard !Task.isCancelled else {
            throw SceneRenderError.cancelled
        }
        try validate(program: program, limits: limits)
        guard await textureStore.registryID() == device.registryID else {
            throw SceneRenderError.incompatibleDevice
        }

        let generation = await textureStore.makeGeneration()
        let outcomes = await acquireTextures(
            program: program,
            textureStore: textureStore,
            textureContext: textureContext,
            generation: generation
        )

        if let fatalError = outcomes
            .sorted(by: { $0.manifestIndex < $1.manifestIndex })
            .compactMap(\.fatalError)
            .first {
            await textureStore.releaseGeneration(generation)
            throw mapFatalError(fatalError)
        }

        var leases: [Int: SceneTextureLease] = [:]
        var failedManifestIndices = Set<Int>()
        var diagnostics: [SceneRenderDiagnostic] = []
        for outcome in outcomes.sorted(by: { $0.manifestIndex < $1.manifestIndex }) {
            switch outcome.result {
            case .success(let lease):
                leases[outcome.manifestIndex] = lease
            case .failure(let error):
                failedManifestIndices.insert(outcome.manifestIndex)
                let entry = program.textureManifest[outcome.manifestIndex]
                diagnostics.append(.init(
                    severity: .warning,
                    code: "renderer.texture-load-failed",
                    resourceID: entry.resource.id,
                    arguments: [diagnosticArgument(error)]
                ))
            }
        }

        let survivingDrawIndices = program.drawTemplates.indices.filter { drawIndex in
            !failedManifestIndices.contains(
                program.drawTemplates[drawIndex].textureManifestIndex
            )
        }
        guard !survivingDrawIndices.isEmpty else {
            await textureStore.releaseGeneration(generation)
            return SceneRenderSession(
                program: program,
                device: device,
                textureStore: textureStore,
                generationOwner: .init(store: textureStore, generation: nil),
                status: .unsupported,
                diagnostics: diagnostics,
                survivingDrawIndices: [],
                textureLeasesByManifestIndex: [:]
            )
        }

        return SceneRenderSession(
            program: program,
            device: device,
            textureStore: textureStore,
            generationOwner: .init(store: textureStore, generation: generation),
            status: failedManifestIndices.isEmpty ? .exact : .degraded,
            diagnostics: diagnostics,
            survivingDrawIndices: survivingDrawIndices,
            textureLeasesByManifestIndex: leases
        )
    }

    public func snapshot() -> SceneRenderSessionSnapshot {
        SceneRenderSessionSnapshot(
            status: preparedStatus,
            diagnostics: preparationDiagnostics,
            survivingDrawIndices: preparedDrawIndices,
            textureLeaseCount: textureLeasesByManifestIndex.count,
            deviceRegistryID: device.registryID,
            isInvalidated: invalidated
        )
    }

    public func invalidate() async {
        guard !invalidated else {
            return
        }
        invalidated = true
        textureLeasesByManifestIndex.removeAll(keepingCapacity: false)
        if let generation = generationOwner.take() {
            await textureStore.releaseGeneration(generation)
        }
    }

    func textureLease(atManifestIndex index: Int) throws -> SceneTextureLease {
        guard !invalidated else {
            throw SceneRenderError.sessionInvalidated
        }
        guard let lease = textureLeasesByManifestIndex[index] else {
            throw SceneRenderError.unsupported
        }
        return lease
    }

    private nonisolated static func validate(
        program: SceneRenderProgram,
        limits: SceneRenderLimits
    ) throws {
        try limits.validate(canvas: program.canvas)
        guard program.drawCount == program.drawTemplates.count,
              !program.drawTemplates.isEmpty,
              program.drawTemplates.count <= limits.maximumDrawItemCount,
              !program.textureManifest.isEmpty else {
            throw SceneRenderError.invalidProgram
        }

        var expectedDependents = Array(
            repeating: [Int](),
            count: program.textureManifest.count
        )
        for (drawIndex, draw) in program.drawTemplates.enumerated() {
            guard program.nodeTemplates.indices.contains(draw.evaluationNodeIndex),
                  program.textureManifest.indices.contains(draw.textureManifestIndex) else {
                throw SceneRenderError.invalidProgram
            }
            expectedDependents[draw.textureManifestIndex].append(drawIndex)
        }
        for (index, entry) in program.textureManifest.enumerated() {
            guard entry.imageIndex >= 0,
                  !entry.dependentDrawIndices.isEmpty,
                  entry.dependentDrawIndices == expectedDependents[index] else {
                throw SceneRenderError.invalidProgram
            }
        }
    }

    private nonisolated static func acquireTextures(
        program: SceneRenderProgram,
        textureStore: SceneTextureStore,
        textureContext: SceneTexturePackageContext,
        generation: SceneTextureGenerationID
    ) async -> [SceneTextureAcquisitionOutcome] {
        await withTaskGroup(of: SceneTextureAcquisitionOutcome.self) { group in
            for (manifestIndex, entry) in program.textureManifest.enumerated() {
                group.addTask {
                    do {
                        guard !Task.isCancelled else {
                            throw SceneTexturePipelineError.cancelled
                        }
                        let lease = try await textureStore.acquire(
                            SceneTextureRequest(
                                packageID: textureContext.packageID,
                                resourceID: entry.resource.id,
                                imageIndex: entry.imageIndex,
                                colorIntent: entry.colorIntent
                            ),
                            resource: entry.resource,
                            context: textureContext,
                            for: generation
                        )
                        return .init(
                            manifestIndex: manifestIndex,
                            result: .success(lease)
                        )
                    } catch let error as SceneTexturePipelineError {
                        return .init(
                            manifestIndex: manifestIndex,
                            result: .failure(error)
                        )
                    } catch is CancellationError {
                        return .init(
                            manifestIndex: manifestIndex,
                            result: .failure(.cancelled)
                        )
                    } catch {
                        return .init(
                            manifestIndex: manifestIndex,
                            result: .failure(.allocationFailed)
                        )
                    }
                }
            }
            var outcomes: [SceneTextureAcquisitionOutcome] = []
            outcomes.reserveCapacity(program.textureManifest.count)
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private nonisolated static func mapFatalError(
        _ error: SceneTexturePipelineError
    ) -> SceneRenderError {
        switch error {
        case .cancelled:
            return .cancelled
        case .invalidRequest:
            return .invalidProgram
        default:
            return .texturePipeline(error)
        }
    }

    private nonisolated static func diagnosticArgument(
        _ error: SceneTexturePipelineError
    ) -> String {
        switch error {
        case .unsupportedDescriptor(let kind):
            return "unsupportedDescriptor.\(String(describing: kind))"
        case .unsupportedAnimation: return "unsupportedAnimation"
        case .unsupportedVideo: return "unsupportedVideo"
        case .unsupportedMultiImage: return "unsupportedMultiImage"
        case .unsupportedPixelFormat(let value): return "unsupportedPixelFormat.\(value)"
        case .malformedDescriptor: return "malformedDescriptor"
        case .malformedPayload: return "malformedPayload"
        case .decodeFailed: return "decodeFailed"
        case .invalidRequest: return "invalidRequest"
        case .resourceLimit(let limit): return "resourceLimit.\(limit.rawValue)"
        case .allocationFailed: return "allocationFailed"
        case .uploadFailed: return "uploadFailed"
        case .uploadTimedOut: return "uploadTimedOut"
        case .cancelled: return "cancelled"
        }
    }
}

private struct SceneTextureAcquisitionOutcome: Sendable {
    let manifestIndex: Int
    let result: Result<SceneTextureLease, SceneTexturePipelineError>

    var fatalError: SceneTexturePipelineError? {
        guard case .failure(let error) = result else {
            return nil
        }
        switch error {
        case .unsupportedDescriptor,
             .unsupportedAnimation,
             .unsupportedVideo,
             .unsupportedMultiImage,
             .unsupportedPixelFormat,
             .malformedDescriptor,
             .malformedPayload,
             .decodeFailed:
            return nil
        case .invalidRequest,
             .resourceLimit,
             .allocationFailed,
             .uploadFailed,
             .uploadTimedOut,
             .cancelled:
            return error
        }
    }
}

private final class SceneTextureGenerationOwner: @unchecked Sendable {
    private let lock = NSLock()
    private let store: SceneTextureStore
    private var generation: SceneTextureGenerationID?

    init(store: SceneTextureStore, generation: SceneTextureGenerationID?) {
        self.store = store
        self.generation = generation
    }

    func take() -> SceneTextureGenerationID? {
        lock.lock()
        defer { lock.unlock() }
        let generation = generation
        self.generation = nil
        return generation
    }

    deinit {
        guard let generation = take() else {
            return
        }
        let store = store
        Task {
            await store.releaseGeneration(generation)
        }
    }
}
