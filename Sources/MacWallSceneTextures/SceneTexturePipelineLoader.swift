import Foundation
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import Metal

func runSceneTextureDetachedWork<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let task = Task.detached(operation: operation)
    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}

actor SceneTextureWorkLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []

    var queuedWaiterCount: Int {
        waiters.count
    }

    init(limit: Int) {
        precondition(limit > 0)
        availablePermits = limit
    }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquirePermit()
        defer { releasePermit() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquirePermit() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard availablePermits == 0 else {
                    availablePermits -= 1
                    continuation.resume()
                    return
                }
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releasePermit() {
        guard !waiters.isEmpty else {
            availablePermits += 1
            return
        }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume()
    }
}

struct DefaultSceneTexturePipelineLoader: SceneTexturePipelineLoading, @unchecked Sendable {
    private let device: any MTLDevice
    private let capabilities: SceneTextureDeviceCapabilities
    private let limits: SceneTextureLimits
    private let memoryBudget: SceneTextureMemoryBudget
    private let allocator: any SceneTextureAllocator
    private let decodeLimiter: SceneTextureWorkLimiter
    private let uploadLimiter: SceneTextureWorkLimiter

    init(
        device: any MTLDevice,
        capabilities: SceneTextureDeviceCapabilities,
        limits: SceneTextureLimits,
        memoryBudget: SceneTextureMemoryBudget,
        allocator: any SceneTextureAllocator
    ) throws {
        guard limits.maximumConcurrentDecodes > 0,
              limits.maximumConcurrentUploads > 0 else {
            throw SceneTexturePipelineError.invalidRequest
        }
        self.device = device
        self.capabilities = capabilities
        self.limits = limits
        self.memoryBudget = memoryBudget
        self.allocator = allocator
        decodeLimiter = SceneTextureWorkLimiter(limit: limits.maximumConcurrentDecodes)
        uploadLimiter = SceneTextureWorkLimiter(limit: limits.maximumConcurrentUploads)
    }

    func prepare(
        _ input: SceneTexturePipelineInput
    ) async throws -> SceneTexturePreparedLoad {
        let source: SceneBoundedByteSource
        let selected: SceneResolvedAsset
        do {
            (selected, source) = try validatedSource(for: input)
        } catch {
            throw Self.normalizedPrepareError(error)
        }

        let descriptor: SceneTextureDescriptor
        do {
            switch try SceneTextureFormatReader().inspect(
                source: source,
                path: selected.canonicalPath.rawValue
            ) {
            case let .parsed(parsed):
                descriptor = parsed
            case let .unsupported(metadata):
                if metadata.kind == .animationVersion {
                    throw SceneTexturePipelineError.unsupportedAnimation
                }
                throw SceneTexturePipelineError.unsupportedDescriptor(metadata.kind)
            }
        } catch {
            throw Self.normalizedDescriptorError(error)
        }

        let plan: SceneTextureLoadPlan
        do {
            plan = try SceneTextureLoadPlanner(
                capabilities: capabilities,
                limits: limits
            ).makePlan(
                descriptor: descriptor,
                imageIndex: input.request.imageIndex,
                colorIntent: .dataLinear
            )
        } catch {
            throw Self.normalizedPrepareError(error)
        }

        let reservation: SceneTextureMemoryReservation
        do {
            reservation = try memoryBudget.reserve(
                try maximumDecodedFootprint(for: plan),
                kind: .decodedCPU
            )
        } catch {
            throw Self.normalizedPrepareError(error)
        }

        do {
            let preparedSource = try await decodeLimiter.withPermit {
                try await runSceneTextureDetachedWork {
                    let payload = try SceneTexturePayloadLoader().prepare(
                        plan: plan,
                        descriptor: descriptor,
                        source: source,
                        limits: limits
                    )
                    switch payload {
                    case .upload:
                        return payload
                    case let .encodedImages(encodedMips):
                        return try SceneTextureImageDecoder().decode(
                            encodedMips: encodedMips,
                            expectedContentExtents: plan.mips.map(\.contentExtent),
                            storageExtents: plan.mips.map(\.storageExtent),
                            limits: limits
                        )
                    }
                }
            }
            guard case let .upload(format, uploadPath, mips) = preparedSource,
                  !mips.isEmpty else {
                throw SceneTexturePipelineError.decodeFailed
            }

            let retainedDecodedBytes = try checkedSum(
                mips.map { $0.bytes.count },
                limit: .decodedCPUBytes
            )
            try memoryBudget.resize(reservation, actualBytes: retainedDecodedBytes)
            let stagingLayout = try SceneTextureStagingLayout.make(
                format: format,
                mips: mips,
                minimumAlignment: sceneTextureStagingAlignment(
                    device: device,
                    format: format
                )
            )
            let estimatedResidentBytes = try checkedSum(
                mips.map { $0.bytes.count },
                limit: .residentBytes
            )
            return SceneTexturePreparedLoad(
                allocationPlan: SceneTextureAllocationPlan(
                    format: format,
                    uploadPath: uploadPath,
                    mips: mips,
                    stagingLayout: stagingLayout,
                    supportsSRGBView: plan.supportsSRGBView,
                    storageExtent: plan.storageExtent,
                    contentExtent: plan.contentExtent,
                    contentRect: plan.contentRect,
                    origin: plan.origin
                ),
                estimatedResidentBytes: estimatedResidentBytes,
                decodedReservation: reservation
            )
        } catch {
            release(reservation)
            throw Self.normalizedPrepareError(error)
        }
    }

    func allocate(
        _ prepared: SceneTexturePreparedLoad,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture {
        defer {
            if let reservation = prepared.decodedReservation {
                release(reservation)
            }
        }

        let stagingReservation: SceneTextureMemoryReservation
        do {
            stagingReservation = try memoryBudget.reserve(
                prepared.allocationPlan.stagingLayout.totalBytes,
                kind: .staging
            )
        } catch {
            throw Self.normalizedAllocationError(error)
        }
        defer { release(stagingReservation) }

        do {
            return try await uploadLimiter.withPermit {
                try await allocator.allocate(prepared.allocationPlan, submission: submission)
            }
        } catch {
            throw Self.normalizedAllocationError(error)
        }
    }

    private func validatedSource(
        for input: SceneTexturePipelineInput
    ) throws -> (SceneResolvedAsset, SceneBoundedByteSource) {
        let request = input.request
        let resource = input.resource
        guard request.resourceID == resource.id,
              resource.id.kind == .texture,
              resource.id.path == resource.path,
              resource.resolution.kind == .package,
              let selected = resource.resolution.selected,
              selected.request == resource.resolution.request,
              selected.canonicalPath == resource.path,
              case let .package(identity) = selected.provenance,
              input.storageKey.packageID == request.packageID,
              input.storageKey.canonicalPath == selected.canonicalPath.rawValue,
              input.storageKey.entryRelativeOffset == identity.relativeOffset,
              input.storageKey.entryByteCount == identity.byteCount,
              input.storageKey.imageIndex == request.imageIndex else {
            throw SceneTexturePipelineError.invalidRequest
        }

        let verified = input.resolver.resolve(resource.resolution.request)
        guard verified.kind == .package,
              verified.selected == selected else {
            throw SceneTexturePipelineError.invalidRequest
        }
        do {
            return (selected, try input.resolver.source(for: selected))
        } catch {
            throw SceneTexturePipelineError.invalidRequest
        }
    }

    private func maximumDecodedFootprint(
        for plan: SceneTextureLoadPlan
    ) throws -> Int {
        let maximumPayloadBytes = min(limits.singlePayloadBytes, 64 * 1_024 * 1_024)
        var total = 0
        for mip in plan.mips {
            guard let payloadBytes = Int(exactly:
                mip.payloadRange.upperBound - mip.payloadRange.lowerBound
            ), payloadBytes <= maximumPayloadBytes else {
                throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
            }
            let expandedBytes: Int
            if mip.isLZ4Compressed {
                guard let declared = mip.declaredDecompressedBytes,
                      let converted = Int(exactly: declared),
                      converted <= maximumPayloadBytes else {
                    throw SceneTexturePipelineError.resourceLimit(.payloadBytes)
                }
                expandedBytes = converted
            } else {
                expandedBytes = payloadBytes
            }

            let bytesForMip: Int
            switch plan.payloadStrategy {
            case .exactUncompressed, .exactBlockCompressed:
                bytesForMip = expandedBytes
            case .softwareBC, .encodedImageProbe:
                bytesForMip = try checkedSum(
                    [expandedBytes, try physicalRGBABytes(mip.storageExtent)],
                    limit: .decodedCPUBytes
                )
            }
            total = try checkedSum([total, bytesForMip], limit: .decodedCPUBytes)
        }
        return total
    }

    private func physicalRGBABytes(_ extent: SceneTextureExtent) throws -> Int {
        let (pixels, pixelOverflow) = extent.width.multipliedReportingOverflow(
            by: extent.height
        )
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else {
            throw SceneTexturePipelineError.resourceLimit(.decodedCPUBytes)
        }
        return bytes
    }

    private func checkedSum(
        _ values: [Int],
        limit: SceneTextureLimit
    ) throws -> Int {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard value >= 0, !overflow else {
                throw SceneTexturePipelineError.resourceLimit(limit)
            }
            total = next
        }
        return total
    }

    private func release(_ reservation: SceneTextureMemoryReservation) {
        do {
            try memoryBudget.release(reservation)
        } catch {
            assertionFailure("Scene texture memory reservation invariant failed: \(error)")
        }
    }

    private static func normalizedDescriptorError(
        _ error: any Error
    ) -> SceneTexturePipelineError {
        if let pipelineError = error as? SceneTexturePipelineError {
            return pipelineError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .malformedDescriptor
    }

    private static func normalizedPrepareError(
        _ error: any Error
    ) -> SceneTexturePipelineError {
        if let pipelineError = error as? SceneTexturePipelineError {
            return pipelineError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .decodeFailed
    }

    private static func normalizedAllocationError(
        _ error: any Error
    ) -> SceneTexturePipelineError {
        if let pipelineError = error as? SceneTexturePipelineError {
            return pipelineError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return .allocationFailed
    }
}
