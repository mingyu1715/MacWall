import Foundation
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import Metal

struct SceneTexturePipelineInput: Sendable {
    let request: SceneTextureRequest
    let resource: SceneTextureResource
    let resolver: ScenePackageAssetResolver
    let storageKey: SceneTextureStorageKey
}

struct SceneTextureCachedArtifact: @unchecked Sendable {
    let texture: SceneAllocatedTexture
    let residentReservation: SceneTextureMemoryReservation
}

protocol SceneTexturePipelineLoading: Sendable {
    func prepare(
        _ input: SceneTexturePipelineInput
    ) async throws -> SceneTexturePreparedLoad

    func allocate(
        _ prepared: SceneTexturePreparedLoad,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture
}

protocol SceneTextureStoreLoadObserving: Sendable {
    func preparationFinished(_ prepared: SceneTexturePreparedLoad) async throws
}

public actor SceneTextureStore {
    private struct Waiter {
        let generation: SceneTextureGenerationID
        let colorIntent: SceneTextureColorIntent
        let continuation: CheckedContinuation<SceneTextureLease, any Error>
    }

    private struct LoadingEntry {
        let id: UUID
        let submission: SceneTextureSubmissionState
        var waiters: [UUID: Waiter]
        var task: Task<Void, Never>?
        var residentReservation: SceneTextureMemoryReservation?
        var supportsSRGBView: Bool?
    }

    private let pipeline: any SceneTexturePipelineLoading
    private let limits: SceneTextureLimits
    private let memoryBudget: SceneTextureMemoryBudget
    private let uploadPolicyVersion: Int
    private let deviceRegistryID: UInt64
    private let loadObserver: (any SceneTextureStoreLoadObserving)?

    private var cache = SceneTextureCache<SceneTextureCachedArtifact>()
    private var readySRGBViewSupport: [SceneTextureStorageKey: Bool] = [:]
    private var liveGenerations: Set<SceneTextureGenerationID> = []
    private var loadingEntries: [SceneTextureStorageKey: LoadingEntry] = [:]
    private var inFlightDedupeHits = 0
    private var resourceLimitFailures = 0
    private var uploadPathCounts: [SceneTextureUploadPath: Int] = [:]
    private var unsupportedCounts: [String: Int] = [:]

    public init(
        device: any MTLDevice,
        limits: SceneTextureLimits = SceneTextureLimits()
    ) throws {
        try Self.validateProductionLimits(limits)
        let memoryBudget = SceneTextureMemoryBudget(limits: limits)
        let capabilities = Self.runtimeCapabilities(device: device)
        let allocator = try DirectSceneTextureAllocator(device: device, limits: limits)
        pipeline = try DefaultSceneTexturePipelineLoader(
            device: device,
            capabilities: capabilities,
            limits: limits,
            memoryBudget: memoryBudget,
            allocator: allocator
        )
        self.limits = limits
        self.memoryBudget = memoryBudget
        uploadPolicyVersion = 1
        deviceRegistryID = device.registryID
        loadObserver = nil
    }

    init(
        device: any MTLDevice,
        limits: SceneTextureLimits,
        capabilities: SceneTextureDeviceCapabilities,
        allocator: any SceneTextureAllocator
    ) throws {
        try Self.validateProductionLimits(limits)
        let memoryBudget = SceneTextureMemoryBudget(limits: limits)
        pipeline = try DefaultSceneTexturePipelineLoader(
            device: device,
            capabilities: capabilities,
            limits: limits,
            memoryBudget: memoryBudget,
            allocator: allocator
        )
        self.limits = limits
        self.memoryBudget = memoryBudget
        uploadPolicyVersion = 1
        deviceRegistryID = device.registryID
        loadObserver = nil
    }

    init(
        testPipeline: any SceneTexturePipelineLoading,
        limits: SceneTextureLimits,
        memoryBudget: SceneTextureMemoryBudget? = nil,
        loadObserver: (any SceneTextureStoreLoadObserving)? = nil,
        uploadPolicyVersion: Int = 1,
        deviceRegistryID: UInt64 = 0
    ) {
        pipeline = testPipeline
        self.limits = limits
        self.memoryBudget = memoryBudget ?? SceneTextureMemoryBudget(limits: limits)
        self.uploadPolicyVersion = uploadPolicyVersion
        self.deviceRegistryID = deviceRegistryID
        self.loadObserver = loadObserver
    }

    public func makeGeneration() -> SceneTextureGenerationID {
        let generation = SceneTextureGenerationID()
        liveGenerations.insert(generation)
        return generation
    }

    public func acquire(
        _ request: SceneTextureRequest,
        resource: SceneTextureResource,
        resolver: ScenePackageAssetResolver,
        for generation: SceneTextureGenerationID
    ) async throws -> SceneTextureLease {
        guard !Task.isCancelled else {
            throw SceneTexturePipelineError.cancelled
        }
        guard liveGenerations.contains(generation) else {
            throw SceneTexturePipelineError.invalidRequest
        }

        let key = try storageKey(
            request: request,
            resource: resource,
            resolver: resolver
        )
        if request.colorIntent == .colorSRGB,
           readySRGBViewSupport[key] == false {
            throw SceneTexturePipelineError.invalidRequest
        }
        if let artifact = cache.value(for: key, owner: generation) {
            return try lease(
                from: artifact.texture,
                colorIntent: request.colorIntent,
                residentBytes: artifact.texture.linearTexture.allocatedSize
            )
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                throw SceneTexturePipelineError.cancelled
            }
            return try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    waiterID: waiterID,
                    continuation: continuation,
                    request: request,
                    resource: resource,
                    resolver: resolver,
                    key: key,
                    generation: generation
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID, for: key)
            }
        }
    }

    public func releaseGeneration(_ generation: SceneTextureGenerationID) {
        guard liveGenerations.remove(generation) != nil else {
            return
        }
        cache.releaseGeneration(generation)

        for key in loadingEntries.keys.sorted() {
            guard var entry = loadingEntries[key] else {
                continue
            }
            let staleWaiterIDs = entry.waiters
                .filter { $0.value.generation == generation }
                .map(\.key)
            for waiterID in staleWaiterIDs {
                guard let waiter = entry.waiters.removeValue(forKey: waiterID) else {
                    continue
                }
                waiter.continuation.resume(
                    throwing: SceneTexturePipelineError.invalidRequest
                )
            }
            loadingEntries[key] = entry
            cancelIfAbandoned(key: key)
        }
    }

    public func trimToSoftBudget() async {
        trimUnownedCache(toResidentBytes: max(0, limits.residentSoftBytes))
    }

    public func snapshot() -> SceneTextureStoreSnapshot {
        let cacheSnapshot = cache.snapshot()
        let memorySnapshot = memoryBudget.snapshot()
        return SceneTextureStoreSnapshot(
            schemaVersion: 1,
            cacheHits: cacheSnapshot.cacheHits,
            cacheMisses: cacheSnapshot.cacheMisses,
            inFlightDedupeHits: inFlightDedupeHits,
            readyEntries: cacheSnapshot.readyEntries,
            loadingEntries: loadingEntries.count,
            unownedEntries: cacheSnapshot.unownedEntries,
            residentBytes: memorySnapshot.residentBytes,
            peakResidentBytes: memorySnapshot.peakResidentBytes,
            stagingBytes: memorySnapshot.stagingBytes,
            peakStagingBytes: memorySnapshot.peakStagingBytes,
            decodedCPUBytes: memorySnapshot.decodedCPUBytes,
            peakDecodedCPUBytes: memorySnapshot.peakDecodedCPUBytes,
            evictions: cacheSnapshot.evictions,
            resourceLimitFailures: resourceLimitFailures,
            uploadPathCounts: uploadPathCounts,
            unsupportedCounts: unsupportedCounts
        )
    }

    private func enqueue(
        waiterID: UUID,
        continuation: CheckedContinuation<SceneTextureLease, any Error>,
        request: SceneTextureRequest,
        resource: SceneTextureResource,
        resolver: ScenePackageAssetResolver,
        key: SceneTextureStorageKey,
        generation: SceneTextureGenerationID
    ) {
        guard liveGenerations.contains(generation) else {
            continuation.resume(throwing: SceneTexturePipelineError.invalidRequest)
            return
        }
        guard !Task.isCancelled else {
            continuation.resume(throwing: SceneTexturePipelineError.cancelled)
            return
        }

        let waiter = Waiter(
            generation: generation,
            colorIntent: request.colorIntent,
            continuation: continuation
        )
        if var entry = loadingEntries[key] {
            if request.colorIntent == .colorSRGB,
               entry.supportsSRGBView == false {
                inFlightDedupeHits += 1
                continuation.resume(throwing: SceneTexturePipelineError.invalidRequest)
                return
            }
            entry.waiters[waiterID] = waiter
            loadingEntries[key] = entry
            inFlightDedupeHits += 1
            return
        }

        let loadID = UUID()
        let submission = SceneTextureSubmissionState()
        let storageRequest = SceneTextureRequest(
            packageID: request.packageID,
            resourceID: request.resourceID,
            imageIndex: request.imageIndex,
            colorIntent: .dataLinear
        )
        let input = SceneTexturePipelineInput(
            request: storageRequest,
            resource: resource,
            resolver: resolver,
            storageKey: key
        )
        loadingEntries[key] = LoadingEntry(
            id: loadID,
            submission: submission,
            waiters: [waiterID: waiter],
            task: nil,
            residentReservation: nil,
            supportsSRGBView: nil
        )

        let pipeline = self.pipeline
        let loadObserver = self.loadObserver
        let task = Task.detached { [self] in
            await Self.runLoad(
                store: self,
                pipeline: pipeline,
                input: input,
                key: key,
                loadID: loadID,
                submission: submission,
                loadObserver: loadObserver
            )
        }
        loadingEntries[key]?.task = task
    }

    private nonisolated static func runLoad(
        store: SceneTextureStore,
        pipeline: any SceneTexturePipelineLoading,
        input: SceneTexturePipelineInput,
        key: SceneTextureStorageKey,
        loadID: UUID,
        submission: SceneTextureSubmissionState,
        loadObserver: (any SceneTextureStoreLoadObserving)?
    ) async {
        let prepared: SceneTexturePreparedLoad
        do {
            prepared = try await pipeline.prepare(input)
        } catch {
            await store.failLoad(
                key: key,
                loadID: loadID,
                error: normalized(error, fallback: .decodeFailed)
            )
            return
        }

        if let loadObserver {
            do {
                try await loadObserver.preparationFinished(prepared)
            } catch {
                await store.releaseDecodedReservation(from: prepared)
                await store.failLoad(
                    key: key,
                    loadID: loadID,
                    error: normalized(error, fallback: .decodeFailed)
                )
                return
            }
        }

        do {
            guard try await store.beginAllocation(
                prepared: prepared,
                key: key,
                loadID: loadID
            ) else {
                await store.releaseDecodedReservation(from: prepared)
                return
            }
        } catch {
            await store.releaseDecodedReservation(from: prepared)
            await store.failLoad(
                key: key,
                loadID: loadID,
                error: normalized(error, fallback: .allocationFailed)
            )
            return
        }

        do {
            let allocated = try await pipeline.allocate(
                prepared,
                submission: submission
            )
            await store.completeLoad(
                allocated: allocated,
                key: key,
                loadID: loadID,
                estimatedResidentBytes: prepared.estimatedResidentBytes
            )
        } catch {
            await store.failLoad(
                key: key,
                loadID: loadID,
                error: normalized(error, fallback: .uploadFailed)
            )
        }
    }

    private func beginAllocation(
        prepared: SceneTexturePreparedLoad,
        key: SceneTextureStorageKey,
        loadID: UUID
    ) throws -> Bool {
        guard var entry = loadingEntries[key], entry.id == loadID else {
            return false
        }
        entry.supportsSRGBView = prepared.allocationPlan.supportsSRGBView

        for waiterID in entry.waiters.keys.sorted(by: uuidLessThan) {
            guard let waiter = entry.waiters[waiterID] else {
                continue
            }
            guard liveGenerations.contains(waiter.generation) else {
                entry.waiters.removeValue(forKey: waiterID)
                waiter.continuation.resume(
                    throwing: SceneTexturePipelineError.invalidRequest
                )
                continue
            }
            if waiter.colorIntent == .colorSRGB,
               !prepared.allocationPlan.supportsSRGBView {
                entry.waiters.removeValue(forKey: waiterID)
                waiter.continuation.resume(
                    throwing: SceneTexturePipelineError.invalidRequest
                )
            }
        }

        guard !entry.waiters.isEmpty else {
            loadingEntries.removeValue(forKey: key)
            return false
        }

        let estimate = prepared.estimatedResidentBytes
        let hardAvailable = estimate >= 0 && estimate <= limits.residentHardBytes
            ? limits.residentHardBytes - estimate
            : 0
        let trimTarget = min(
            max(0, limits.residentSoftBytes),
            max(0, hardAvailable)
        )
        trimUnownedCache(toResidentBytes: trimTarget)
        let reservation = try memoryBudget.reserve(estimate, kind: .resident)
        entry.residentReservation = reservation
        loadingEntries[key] = entry
        return true
    }

    private func completeLoad(
        allocated: SceneAllocatedTexture,
        key: SceneTextureStorageKey,
        loadID: UUID,
        estimatedResidentBytes: Int
    ) {
        guard let entry = loadingEntries[key],
              entry.id == loadID,
              let reservation = entry.residentReservation else {
            return
        }

        let actualResidentBytes = allocated.linearTexture.allocatedSize
        do {
            try reconcileResidentReservation(
                reservation,
                estimatedBytes: estimatedResidentBytes,
                actualBytes: actualResidentBytes
            )
        } catch {
            loadingEntries.removeValue(forKey: key)
            releaseReservation(reservation)
            let pipelineError = Self.normalized(error, fallback: .allocationFailed)
            recordFailure(pipelineError)
            resumeAll(entry.waiters, throwing: pipelineError)
            return
        }

        var successfulWaiters: [(Waiter, SceneTextureLease)] = []
        for waiterID in entry.waiters.keys.sorted(by: uuidLessThan) {
            guard let waiter = entry.waiters[waiterID] else {
                continue
            }
            guard liveGenerations.contains(waiter.generation) else {
                waiter.continuation.resume(
                    throwing: SceneTexturePipelineError.invalidRequest
                )
                continue
            }
            do {
                let lease = try lease(
                    from: allocated,
                    colorIntent: waiter.colorIntent,
                    residentBytes: actualResidentBytes
                )
                successfulWaiters.append((waiter, lease))
            } catch {
                waiter.continuation.resume(
                    throwing: SceneTexturePipelineError.invalidRequest
                )
            }
        }

        guard !successfulWaiters.isEmpty else {
            loadingEntries.removeValue(forKey: key)
            releaseReservation(reservation)
            return
        }

        let cachedArtifact = SceneTextureCachedArtifact(
            texture: allocated,
            residentReservation: reservation
        )
        readySRGBViewSupport[key] = allocated.srgbTexture != nil
        for generation in Set(successfulWaiters.map { $0.0.generation }) {
            cache.install(
                cachedArtifact,
                residentBytes: actualResidentBytes,
                uploadPath: allocated.uploadPath,
                for: key,
                owner: generation
            )
        }
        loadingEntries.removeValue(forKey: key)
        uploadPathCounts[allocated.uploadPath, default: 0] += 1
        for (waiter, lease) in successfulWaiters {
            waiter.continuation.resume(returning: lease)
        }
    }

    private func failLoad(
        key: SceneTextureStorageKey,
        loadID: UUID,
        error: SceneTexturePipelineError
    ) {
        guard let entry = loadingEntries[key], entry.id == loadID else {
            return
        }
        loadingEntries.removeValue(forKey: key)
        if let reservation = entry.residentReservation {
            releaseReservation(reservation)
        }
        recordFailure(error)
        resumeAll(entry.waiters, throwing: error)
    }

    private func cancelWaiter(_ waiterID: UUID, for key: SceneTextureStorageKey) {
        guard var entry = loadingEntries[key],
              let waiter = entry.waiters.removeValue(forKey: waiterID) else {
            return
        }
        loadingEntries[key] = entry
        waiter.continuation.resume(throwing: SceneTexturePipelineError.cancelled)
        cancelIfAbandoned(key: key)
    }

    private func cancelIfAbandoned(key: SceneTextureStorageKey) {
        guard let entry = loadingEntries[key],
              entry.waiters.isEmpty,
              entry.submission.cancelIfPending() else {
            return
        }
        loadingEntries.removeValue(forKey: key)
        if let reservation = entry.residentReservation {
            releaseReservation(reservation)
        }
        entry.task?.cancel()
    }

    private func reconcileResidentReservation(
        _ reservation: SceneTextureMemoryReservation,
        estimatedBytes: Int,
        actualBytes: Int
    ) throws {
        do {
            try memoryBudget.resize(reservation, actualBytes: actualBytes)
        } catch let error as SceneTexturePipelineError
            where error == .resourceLimit(.residentBytes) {
            let currentResidentBytes = memoryBudget.snapshot().residentBytes
            let (residentWithoutEstimate, subtractionOverflow) = currentResidentBytes
                .subtractingReportingOverflow(estimatedBytes)
            let (projectedResidentBytes, additionOverflow) = residentWithoutEstimate
                .addingReportingOverflow(actualBytes)
            guard estimatedBytes >= 0,
                  actualBytes >= 0,
                  !subtractionOverflow,
                  residentWithoutEstimate >= 0,
                  !additionOverflow else {
                throw SceneTexturePipelineError.resourceLimit(.residentBytes)
            }

            let hardLimit = max(0, limits.residentHardBytes)
            let bytesToEvict = max(0, projectedResidentBytes - hardLimit)
            let cacheResidentBytes = cache.snapshot().residentBytes
            let cacheTarget = max(0, cacheResidentBytes - bytesToEvict)
            trimUnownedCache(toResidentBytes: cacheTarget)
            try memoryBudget.resize(reservation, actualBytes: actualBytes)
        }
    }

    private func trimUnownedCache(toResidentBytes target: Int) {
        let evicted = cache.trimUnowned(toResidentBytes: max(0, target))
        for entry in evicted {
            readySRGBViewSupport.removeValue(forKey: entry.key)
            releaseReservation(entry.value.residentReservation)
        }
    }

    private func releaseDecodedReservation(from prepared: SceneTexturePreparedLoad) {
        guard let reservation = prepared.decodedReservation else {
            return
        }
        releaseReservation(reservation)
    }

    private func releaseReservation(_ reservation: SceneTextureMemoryReservation) {
        do {
            try memoryBudget.release(reservation)
        } catch {
            assertionFailure("Scene texture memory reservation invariant failed: \(error)")
        }
    }

    private func resumeAll(
        _ waiters: [UUID: Waiter],
        throwing error: SceneTexturePipelineError
    ) {
        for waiterID in waiters.keys.sorted(by: uuidLessThan) {
            waiters[waiterID]?.continuation.resume(throwing: error)
        }
    }

    private func recordFailure(_ error: SceneTexturePipelineError) {
        if case .resourceLimit = error {
            resourceLimitFailures += 1
        }
        guard let category = Self.unsupportedCategory(for: error) else {
            return
        }
        unsupportedCounts[category, default: 0] += 1
    }

    private func storageKey(
        request: SceneTextureRequest,
        resource: SceneTextureResource,
        resolver: ScenePackageAssetResolver
    ) throws -> SceneTextureStorageKey {
        guard request.resourceID == resource.id,
              resource.id.kind == .texture,
              resource.id.path == resource.path,
              resource.resolution.kind == .package,
              let selected = resource.resolution.selected,
              selected.canonicalPath == resource.path,
              selected.request == resource.resolution.request,
              case let .package(identity) = selected.provenance else {
            throw SceneTexturePipelineError.invalidRequest
        }

        let verifiedResolution = resolver.resolve(resource.resolution.request)
        guard verifiedResolution.kind == .package,
              verifiedResolution.selected == selected else {
            throw SceneTexturePipelineError.invalidRequest
        }
        do {
            _ = try resolver.source(for: selected)
        } catch {
            throw SceneTexturePipelineError.invalidRequest
        }

        return SceneTextureStorageKey(
            packageID: request.packageID,
            canonicalPath: selected.canonicalPath.rawValue,
            entryRelativeOffset: identity.relativeOffset,
            entryByteCount: identity.byteCount,
            imageIndex: request.imageIndex,
            uploadPolicyVersion: uploadPolicyVersion,
            deviceRegistryID: deviceRegistryID
        )
    }

    private func lease(
        from allocated: SceneAllocatedTexture,
        colorIntent: SceneTextureColorIntent,
        residentBytes: Int
    ) throws -> SceneTextureLease {
        let texture: any MTLTexture
        switch colorIntent {
        case .dataLinear:
            texture = allocated.linearTexture
        case .colorSRGB:
            guard let srgbTexture = allocated.srgbTexture else {
                throw SceneTexturePipelineError.invalidRequest
            }
            texture = srgbTexture
        }
        return SceneTextureLease(
            texture: texture,
            storageExtent: allocated.storageExtent,
            contentExtent: allocated.contentExtent,
            contentRect: allocated.contentRect,
            origin: allocated.origin,
            mipmapLevelCount: allocated.mipmapLevelCount,
            residentBytes: residentBytes
        )
    }

    private nonisolated static func normalized(
        _ error: any Error,
        fallback: SceneTexturePipelineError
    ) -> SceneTexturePipelineError {
        if let pipelineError = error as? SceneTexturePipelineError {
            return pipelineError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        return fallback
    }

    private nonisolated static func unsupportedCategory(
        for error: SceneTexturePipelineError
    ) -> String? {
        switch error {
        case let .unsupportedDescriptor(kind):
            "descriptor.\(kind.rawValue)"
        case .unsupportedAnimation:
            "animation"
        case .unsupportedVideo:
            "video"
        case .unsupportedMultiImage:
            "multiImage"
        case .unsupportedPixelFormat:
            "pixelFormat"
        default:
            nil
        }
    }

    private nonisolated static func validateProductionLimits(
        _ limits: SceneTextureLimits
    ) throws {
        let positiveValues = [
            limits.residentSoftBytes,
            limits.residentHardBytes,
            limits.stagingBytes,
            limits.decodedCPUBytes,
            limits.singlePayloadBytes,
            limits.maximumTextureDimension,
            limits.maximumDecodedPixels,
            limits.maximumConcurrentDecodes,
            limits.maximumConcurrentUploads
        ]
        guard positiveValues.allSatisfy({ $0 > 0 }),
              limits.residentSoftBytes <= limits.residentHardBytes,
              limits.uploadTimeout > .zero else {
            throw SceneTexturePipelineError.invalidRequest
        }
    }

    private nonisolated static func runtimeCapabilities(
        device: any MTLDevice
    ) -> SceneTextureDeviceCapabilities {
        let rgbaAlignment = device.minimumLinearTextureAlignment(for: .rgba8Unorm)
        return SceneTextureDeviceCapabilities(
            supportsBCTextureCompression: device.supportsBCTextureCompression,
            linearTextureAlignment: [
                .rgba8Unorm: rgbaAlignment,
                .rg8Unorm: device.minimumLinearTextureAlignment(for: .rg8Unorm),
                .r8Unorm: device.minimumLinearTextureAlignment(for: .r8Unorm),
                .bc1RGBA: rgbaAlignment,
                .bc2RGBA: rgbaAlignment,
                .bc3RGBA: rgbaAlignment
            ]
        )
    }

    private nonisolated func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
