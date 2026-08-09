import Foundation
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport
import Metal
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureStoreTests: XCTestCase {
    func testUnknownAndReleasedGenerationsFailInvalidRequest() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let unknown = SceneTextureGenerationID()

        await assertPipelineError(.invalidRequest) {
            try await store.acquire(
                textureRequest(.dataLinear, resource: fixture.resource),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: unknown
            )
        }

        let released = await store.makeGeneration()
        await store.releaseGeneration(released)
        await assertPipelineError(.invalidRequest) {
            try await store.acquire(
                textureRequest(.dataLinear, resource: fixture.resource),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: released
            )
        }
        let prepareCount = await fake.prepareCount
        XCTAssertEqual(prepareCount, 0)
    }

    func testConcurrentSameStorageKeyLoadsOnce() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture(hasSRGBView: true)
        let prepared = preparedLoad(
            supportsSRGBView: true,
            estimatedResidentBytes: allocated.linearTexture.allocatedSize
        )
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()

        let first = acquireTask(
            store: store,
            fixture: fixture,
            intent: .dataLinear,
            generation: generationA
        )
        let second = acquireTask(
            store: store,
            fixture: fixture,
            intent: .colorSRGB,
            generation: generationB
        )

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(with: prepared)
        await fake.waitForAllocateCount(1)
        try await fake.completeAllocation(with: allocated)

        let linearLease = try await first.value
        let colorLease = try await second.value
        XCTAssertIdentical(linearLease.texture as AnyObject, allocated.linearTexture as AnyObject)
        XCTAssertIdentical(colorLease.texture as AnyObject, allocated.srgbTexture! as AnyObject)
        let prepareCount = await fake.prepareCount
        let allocateCount = await fake.allocateCount
        let snapshot = await store.snapshot()
        let inputs = await fake.preparedInputs
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(allocateCount, 1)
        XCTAssertEqual(snapshot.inFlightDedupeHits, 1)
        XCTAssertEqual(inputs.first?.request.colorIntent, .dataLinear)
    }

    func testCacheHitBypassesPipelineAndAddsNewGenerationOwner() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(
            testPipeline: fake,
            limits: .init(residentSoftBytes: 0)
        )
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()

        let first = acquireTask(store: store, fixture: fixture, generation: generationA)
        _ = try await finishNextLoad(first, fake: fake, allocated: allocated, ordinal: 1)

        let cached = try await store.acquire(
            textureRequest(.dataLinear, resource: fixture.resource),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generationB
        )
        XCTAssertIdentical(cached.texture as AnyObject, allocated.linearTexture as AnyObject)
        let prepareCount = await fake.prepareCount
        let allocateCount = await fake.allocateCount
        let hitSnapshot = await store.snapshot()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(allocateCount, 1)
        XCTAssertEqual(hitSnapshot.cacheHits, 1)

        await store.releaseGeneration(generationA)
        await store.trimToSoftBudget()
        let ownedSnapshot = await store.snapshot()
        XCTAssertEqual(ownedSnapshot.readyEntries, 1)
        await store.releaseGeneration(generationB)
        await store.trimToSoftBudget()
        let unownedSnapshot = await store.snapshot()
        XCTAssertEqual(unownedSnapshot.readyEntries, 0)
    }

    func testEveryStorageIdentityDifferenceProducesDistinctPipelineKey() async throws {
        let fake = ControllableTexturePipeline()
        let baseFixture = try textureFixture(path: "materials/base.tex")
        let movedEntryFixture = try textureFixture(
            path: "materials/base.tex",
            precedingEntryBytes: 7
        )
        let pathFixture = try textureFixture(path: "materials/other.tex")
        let packageA = SceneTexturePackageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        )
        let packageB = SceneTexturePackageID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        )
        let allocated = try allocatedTexture()

        let cases: [(SceneTexturePackageID, TextureFixture, Int, Int, UInt64)] = [
            (packageA, baseFixture, 0, 1, 41),
            (packageB, baseFixture, 0, 1, 41),
            (packageA, movedEntryFixture, 0, 1, 41),
            (packageA, pathFixture, 0, 1, 41),
            (packageA, baseFixture, 1, 1, 41),
            (packageA, baseFixture, 0, 2, 41),
            (packageA, baseFixture, 0, 1, 42)
        ]

        for (index, testCase) in cases.enumerated() {
            let (packageID, fixture, imageIndex, policyVersion, deviceRegistryID) = testCase
            let store = SceneTextureStore(
                testPipeline: fake,
                limits: .init(),
                uploadPolicyVersion: policyVersion,
                deviceRegistryID: deviceRegistryID
            )
            let generation = await store.makeGeneration()
            let request = SceneTextureRequest(
                packageID: packageID,
                resourceID: fixture.resource.id,
                imageIndex: imageIndex,
                colorIntent: .dataLinear
            )
            let task = Task {
                try await store.acquire(
                    request,
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            }

            _ = try await finishNextLoad(
                task,
                fake: fake,
                allocated: allocated,
                ordinal: index + 1
            )
        }

        let keys = await fake.preparedInputs.map(\.storageKey)
        XCTAssertEqual(Set(keys).count, cases.count)
    }

    func testIncompatibleColorWaiterFailsAfterPrepareWithoutAllocation() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let generation = await store.makeGeneration()
        let color = acquireTask(
            store: store,
            fixture: fixture,
            intent: .colorSRGB,
            generation: generation
        )

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(supportsSRGBView: false, estimatedResidentBytes: 4)
        )

        await assertTaskError(.invalidRequest, task: color)
        let allocateCount = await fake.allocateCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(allocateCount, 0)
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.loadingEntries, 0)
    }

    func testIncompatibleColorWaiterDoesNotBlockConcurrentLinearWaiter() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture(hasSRGBView: false)
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()
        let color = acquireTask(
            store: store,
            fixture: fixture,
            intent: .colorSRGB,
            generation: generationA
        )
        let linear = acquireTask(
            store: store,
            fixture: fixture,
            intent: .dataLinear,
            generation: generationB
        )

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(
                supportsSRGBView: false,
                estimatedResidentBytes: allocated.linearTexture.allocatedSize
            )
        )
        await assertTaskError(.invalidRequest, task: color)
        await fake.waitForAllocateCount(1)
        try await fake.completeAllocation(with: allocated)

        _ = try await linear.value
        let prepareCount = await fake.prepareCount
        let allocateCount = await fake.allocateCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(allocateCount, 1)
        XCTAssertEqual(snapshot.readyEntries, 1)
    }

    func testCancelingOneWaiterDoesNotCancelAnotherWaiter() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()
        let canceled = acquireTask(store: store, fixture: fixture, generation: generationA)
        let survivor = acquireTask(store: store, fixture: fixture, generation: generationB)

        await fake.waitForPrepareCount(1)
        canceled.cancel()
        await assertTaskError(.cancelled, task: canceled)
        try await fake.completePreparation(
            with: preparedLoad(
                supportsSRGBView: true,
                estimatedResidentBytes: allocated.linearTexture.allocatedSize
            )
        )
        await fake.waitForAllocateCount(1)
        try await fake.completeAllocation(with: allocated)

        _ = try await survivor.value
        let cancellationCount = await fake.prepareCancellationCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(cancellationCount, 0)
        XCTAssertEqual(snapshot.readyEntries, 1)
    }

    func testCancelingAllWaitersBeforeSubmissionCancelsPipelineTask() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        task.cancel()
        await assertTaskError(.cancelled, task: task)
        await fake.waitForPrepareCancellationCount(1)
        await waitForStoreLoadingCount(0, store: store)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
    }

    func testCancelingAllWaitersAfterSubmissionWaitsForCleanupWithoutInstall() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(
                supportsSRGBView: true,
                estimatedResidentBytes: allocated.linearTexture.allocatedSize
            )
        )
        await fake.waitForAllocateCount(1)
        try await fake.markAllocationSubmitted()
        task.cancel()
        await assertTaskError(.cancelled, task: task)
        let submittedSnapshot = await store.snapshot()
        XCTAssertEqual(submittedSnapshot.loadingEntries, 1)

        try await fake.completeAllocation(with: allocated)
        await waitForStoreLoadingCount(0, store: store)
        let cancellationCount = await fake.allocationCancellationCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(cancellationCount, 0)
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
    }

    func testReleasedGenerationCompletionIsNotInstalled() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(
                supportsSRGBView: true,
                estimatedResidentBytes: allocated.linearTexture.allocatedSize
            )
        )
        await fake.waitForAllocateCount(1)
        try await fake.markAllocationSubmitted()
        await store.releaseGeneration(generation)
        await assertTaskError(.invalidRequest, task: task)

        try await fake.completeAllocation(with: allocated)
        await waitForStoreLoadingCount(0, store: store)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
    }

    func testLoadFailureIsNotCachedAndAllWaitersReceiveSameTypedFailure() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()
        let first = acquireTask(store: store, fixture: fixture, generation: generationA)
        let second = acquireTask(store: store, fixture: fixture, generation: generationB)

        await fake.waitForPrepareCount(1)
        try await fake.failPreparation(with: .malformedPayload)
        await assertTaskError(.malformedPayload, task: first)
        await assertTaskError(.malformedPayload, task: second)
        let failedSnapshot = await store.snapshot()
        XCTAssertEqual(failedSnapshot.readyEntries, 0)

        let retry = acquireTask(store: store, fixture: fixture, generation: generationA)
        await fake.waitForPrepareCount(2)
        try await fake.failPreparation(with: .decodeFailed)
        await assertTaskError(.decodeFailed, task: retry)
        let prepareCount = await fake.prepareCount
        XCTAssertEqual(prepareCount, 2)
    }

    func testFailingGenerationBLeavesGenerationAReadyTextureAndOwnerUnchanged() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixtureA = try textureFixture(path: "materials/a.tex")
        let fixtureB = try textureFixture(path: "materials/b.tex")
        let allocated = try allocatedTexture()
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()

        let active = acquireTask(store: store, fixture: fixtureA, generation: generationA)
        _ = try await finishNextLoad(active, fake: fake, allocated: allocated, ordinal: 1)

        let failing = acquireTask(store: store, fixture: fixtureB, generation: generationB)
        await fake.waitForPrepareCount(2)
        try await fake.failPreparation(with: .uploadFailed)
        await assertTaskError(.uploadFailed, task: failing)
        await store.releaseGeneration(generationB)
        await store.trimToSoftBudget()

        let stillActive = try await store.acquire(
            textureRequest(.dataLinear, resource: fixtureA.resource),
            resource: fixtureA.resource,
            resolver: fixtureA.resolver,
            for: generationA
        )
        XCTAssertIdentical(stillActive.texture as AnyObject, allocated.linearTexture as AnyObject)
        let prepareCount = await fake.prepareCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(prepareCount, 2)
        XCTAssertEqual(snapshot.readyEntries, 1)
    }

    func testUploadCompletesBeforeCacheInstallAndLeaseReturn() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generation = await store.makeGeneration()
        let completion = CompletionProbe()
        let task = Task {
            let result: Result<SceneTextureLease, any Error>
            do {
                result = .success(
                    try await store.acquire(
                    textureRequest(.dataLinear, resource: fixture.resource),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
                )
            } catch {
                result = .failure(error)
            }
            await completion.record(result)
            return try result.get()
        }

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(
                supportsSRGBView: true,
                estimatedResidentBytes: allocated.linearTexture.allocatedSize
            )
        )
        await fake.waitForAllocateCount(1)
        let completionCount = await completion.count
        let loadingSnapshot = await store.snapshot()
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(loadingSnapshot.readyEntries, 0)
        XCTAssertEqual(loadingSnapshot.loadingEntries, 1)

        try await fake.completeAllocation(with: allocated)
        await completion.waitForCount(1)
        _ = try await task.value
        let readySnapshot = await store.snapshot()
        XCTAssertEqual(readySnapshot.readyEntries, 1)
        XCTAssertEqual(readySnapshot.loadingEntries, 0)
    }

    func testReleaseGenerationNeverRemovesAnotherGenerationOwner() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture()
        let allocated = try allocatedTexture()
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()
        let first = acquireTask(store: store, fixture: fixture, generation: generationA)
        _ = try await finishNextLoad(first, fake: fake, allocated: allocated, ordinal: 1)
        _ = try await store.acquire(
            textureRequest(.dataLinear, resource: fixture.resource),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generationB
        )

        await store.releaseGeneration(generationA)
        await store.trimToSoftBudget()
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 1)

        _ = try await store.acquire(
            textureRequest(.dataLinear, resource: fixture.resource),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generationB
        )
        let prepareCount = await fake.prepareCount
        XCTAssertEqual(prepareCount, 1)
    }

    func testTrimToSoftBudgetRemovesOnlyUnownedValues() async throws {
        let fake = ControllableTexturePipeline()
        let allocated = try allocatedTexture()
        let residentBytes = allocated.linearTexture.allocatedSize
        let store = SceneTextureStore(
            testPipeline: fake,
            limits: .init(
                residentSoftBytes: residentBytes,
                residentHardBytes: residentBytes * 3
            )
        )
        let fixtureA = try textureFixture(path: "materials/a.tex")
        let fixtureB = try textureFixture(path: "materials/b.tex")
        let generationA = await store.makeGeneration()
        let generationB = await store.makeGeneration()

        let first = acquireTask(store: store, fixture: fixtureA, generation: generationA)
        _ = try await finishNextLoad(first, fake: fake, allocated: allocated, ordinal: 1)
        let second = acquireTask(store: store, fixture: fixtureB, generation: generationB)
        _ = try await finishNextLoad(second, fake: fake, allocated: allocated, ordinal: 2)
        await store.releaseGeneration(generationB)

        await store.trimToSoftBudget()
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 1)
        XCTAssertEqual(snapshot.unownedEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, residentBytes)
        XCTAssertEqual(snapshot.evictions, 1)

        _ = try await store.acquire(
            textureRequest(.dataLinear, resource: fixtureA.resource),
            resource: fixtureA.resource,
            resolver: fixtureA.resolver,
            for: generationA
        )
        let prepareCount = await fake.prepareCount
        XCTAssertEqual(prepareCount, 2)
    }

    func testResidentReservationFailurePreventsAllocation() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(
            testPipeline: fake,
            limits: .init(residentSoftBytes: 0, residentHardBytes: 0)
        )
        let fixture = try textureFixture()
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(supportsSRGBView: true, estimatedResidentBytes: 1)
        )

        await assertTaskError(.resourceLimit(.residentBytes), task: task)
        let allocateCount = await fake.allocateCount
        let snapshot = await store.snapshot()
        XCTAssertEqual(allocateCount, 0)
        XCTAssertEqual(snapshot.resourceLimitFailures, 1)
        XCTAssertEqual(snapshot.residentBytes, 0)
    }

    func testActualResidentSizeFailureDiscardsAllocatedArtifact() async throws {
        let fake = ControllableTexturePipeline()
        let allocated = try allocatedTexture()
        let actualBytes = allocated.linearTexture.allocatedSize
        let store = SceneTextureStore(
            testPipeline: fake,
            limits: .init(
                residentSoftBytes: max(0, actualBytes - 1),
                residentHardBytes: max(0, actualBytes - 1)
            )
        )
        let fixture = try textureFixture()
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        try await fake.completePreparation(
            with: preparedLoad(supportsSRGBView: true, estimatedResidentBytes: 1)
        )
        await fake.waitForAllocateCount(1)
        try await fake.completeAllocation(with: allocated)

        await assertTaskError(.resourceLimit(.residentBytes), task: task)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
        XCTAssertEqual(snapshot.resourceLimitFailures, 1)
    }

    func testSnapshotContainsOnlyAggregateDataAndStableFailureCategories() async throws {
        let fake = ControllableTexturePipeline()
        let store = SceneTextureStore(testPipeline: fake, limits: .init())
        let fixture = try textureFixture(
            path: "Users/private-user/secret-payload.tex",
            payload: Data("private-payload-canary".utf8)
        )
        let generation = await store.makeGeneration()
        let task = acquireTask(store: store, fixture: fixture, generation: generation)

        await fake.waitForPrepareCount(1)
        try await fake.failPreparation(with: .unsupportedDescriptor(.container))
        await assertTaskError(.unsupportedDescriptor(.container), task: task)

        let snapshot = await store.snapshot()
        let description = String(reflecting: snapshot)
        XCTAssertFalse(description.contains("private-user"))
        XCTAssertFalse(description.contains("secret-payload"))
        XCTAssertFalse(description.contains("private-payload-canary"))
        XCTAssertEqual(snapshot.unsupportedCounts, ["descriptor.container": 1])
    }
}

private actor ControllableTexturePipeline: SceneTexturePipelineLoading {
    private struct PendingPreparation {
        let continuation: CheckedContinuation<SceneTexturePreparedLoad, any Error>
    }

    private struct PendingAllocation {
        let submission: SceneTextureSubmissionState
        let continuation: CheckedContinuation<SceneAllocatedTexture, any Error>
    }

    private(set) var preparedInputs: [SceneTexturePipelineInput] = []
    private(set) var prepareCount = 0
    private(set) var allocateCount = 0
    private(set) var prepareCancellationCount = 0
    private(set) var allocationCancellationCount = 0

    private var pendingPreparations: [UUID: PendingPreparation] = [:]
    private var preparationOrder: [UUID] = []
    private var pendingAllocations: [UUID: PendingAllocation] = [:]
    private var allocationOrder: [UUID] = []
    private var canceledPreparationIDs: Set<UUID> = []
    private var canceledAllocationIDs: Set<UUID> = []
    private var prepareCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var allocateCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var prepareCancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func prepare(_ input: SceneTexturePipelineInput) async throws -> SceneTexturePreparedLoad {
        let operationID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                prepareCount += 1
                preparedInputs.append(input)
                if canceledPreparationIDs.remove(operationID) != nil {
                    prepareCancellationCount += 1
                    continuation.resume(throwing: SceneTexturePipelineError.cancelled)
                    resumePrepareCancellationWaiters()
                } else {
                    pendingPreparations[operationID] = PendingPreparation(
                        continuation: continuation
                    )
                    preparationOrder.append(operationID)
                }
                resumePrepareCountWaiters()
            }
        } onCancel: {
            Task { await self.cancelPreparation(operationID) }
        }
    }

    func allocate(
        _ prepared: SceneTexturePreparedLoad,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture {
        let operationID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                allocateCount += 1
                if canceledAllocationIDs.remove(operationID) != nil {
                    allocationCancellationCount += 1
                    continuation.resume(throwing: SceneTexturePipelineError.cancelled)
                } else {
                    pendingAllocations[operationID] = PendingAllocation(
                        submission: submission,
                        continuation: continuation
                    )
                    allocationOrder.append(operationID)
                }
                resumeAllocateCountWaiters()
            }
        } onCancel: {
            Task { await self.cancelAllocation(operationID) }
        }
    }

    func waitForPrepareCount(_ target: Int) async {
        guard prepareCount < target else {
            return
        }
        await withCheckedContinuation { continuation in
            prepareCountWaiters.append((target, continuation))
        }
    }

    func waitForAllocateCount(_ target: Int) async {
        guard allocateCount < target else {
            return
        }
        await withCheckedContinuation { continuation in
            allocateCountWaiters.append((target, continuation))
        }
    }

    func waitForPrepareCancellationCount(_ target: Int) async {
        guard prepareCancellationCount < target else {
            return
        }
        await withCheckedContinuation { continuation in
            prepareCancellationWaiters.append((target, continuation))
        }
    }

    func completePreparation(with prepared: SceneTexturePreparedLoad) throws {
        let continuation = try takePreparation()
        continuation.resume(returning: prepared)
    }

    func failPreparation(with error: SceneTexturePipelineError) throws {
        let continuation = try takePreparation()
        continuation.resume(throwing: error)
    }

    func markAllocationSubmitted() throws {
        guard let operationID = allocationOrder.first,
              let pending = pendingAllocations[operationID] else {
            throw TexturePipelineControlError.noPendingAllocation
        }
        pending.submission.markSubmitted()
    }

    func completeAllocation(with allocated: SceneAllocatedTexture) throws {
        let continuation = try takeAllocation()
        continuation.resume(returning: allocated)
    }

    private func cancelPreparation(_ operationID: UUID) {
        guard let pending = pendingPreparations.removeValue(forKey: operationID) else {
            canceledPreparationIDs.insert(operationID)
            return
        }
        preparationOrder.removeAll(where: { $0 == operationID })
        prepareCancellationCount += 1
        pending.continuation.resume(throwing: SceneTexturePipelineError.cancelled)
        resumePrepareCancellationWaiters()
    }

    private func cancelAllocation(_ operationID: UUID) {
        guard let pending = pendingAllocations.removeValue(forKey: operationID) else {
            canceledAllocationIDs.insert(operationID)
            return
        }
        allocationOrder.removeAll(where: { $0 == operationID })
        allocationCancellationCount += 1
        pending.continuation.resume(throwing: SceneTexturePipelineError.cancelled)
    }

    private func takePreparation() throws -> CheckedContinuation<SceneTexturePreparedLoad, any Error> {
        guard let operationID = preparationOrder.first else {
            throw TexturePipelineControlError.noPendingPreparation
        }
        preparationOrder.removeFirst()
        guard let pending = pendingPreparations.removeValue(forKey: operationID) else {
            throw TexturePipelineControlError.noPendingPreparation
        }
        return pending.continuation
    }

    private func takeAllocation() throws -> CheckedContinuation<SceneAllocatedTexture, any Error> {
        guard let operationID = allocationOrder.first else {
            throw TexturePipelineControlError.noPendingAllocation
        }
        allocationOrder.removeFirst()
        guard let pending = pendingAllocations.removeValue(forKey: operationID) else {
            throw TexturePipelineControlError.noPendingAllocation
        }
        return pending.continuation
    }

    private func resumePrepareCountWaiters() {
        let ready = prepareCountWaiters.filter { $0.0 <= prepareCount }
        prepareCountWaiters.removeAll(where: { $0.0 <= prepareCount })
        ready.forEach { $0.1.resume() }
    }

    private func resumeAllocateCountWaiters() {
        let ready = allocateCountWaiters.filter { $0.0 <= allocateCount }
        allocateCountWaiters.removeAll(where: { $0.0 <= allocateCount })
        ready.forEach { $0.1.resume() }
    }

    private func resumePrepareCancellationWaiters() {
        let ready = prepareCancellationWaiters.filter { $0.0 <= prepareCancellationCount }
        prepareCancellationWaiters.removeAll(where: { $0.0 <= prepareCancellationCount })
        ready.forEach { $0.1.resume() }
    }
}

private actor CompletionProbe {
    private(set) var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record<T>(_ result: Result<T, any Error>) {
        count += 1
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll(where: { $0.0 <= count })
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ target: Int) async {
        guard count < target else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
    }
}

private enum TexturePipelineControlError: Error {
    case noPendingPreparation
    case noPendingAllocation
}

private struct TextureFixture: Sendable {
    let resolver: ScenePackageAssetResolver
    let resource: SceneTextureResource
}

private func textureFixture(
    path: String = "materials/test.tex",
    payload: Data = Data([1, 2, 3, 4]),
    precedingEntryBytes: Int = 0
) throws -> TextureFixture {
    var entries: [ScenePackageFixtureEntry] = []
    if precedingEntryBytes > 0 {
        entries.append(
            ScenePackageFixtureEntry(
                path: "padding.bin",
                data: Data(repeating: 0, count: precedingEntryBytes)
            )
        )
    }
    entries.append(ScenePackageFixtureEntry(path: path, data: payload))
    let resolver = try ScenePackageAssetResolver.open(
        source: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(entries: entries))
    )
    let resolution = resolver.resolve(
        SceneAssetRequest(
            requestedPath: path,
            ownerPath: nil,
            role: .texture,
            key: "texture"
        )
    )
    guard let selected = resolution.selected else {
        throw SceneTexturePipelineError.invalidRequest
    }
    let id = SceneResourceID(kind: .texture, path: selected.canonicalPath)
    return TextureFixture(
        resolver: resolver,
        resource: SceneTextureResource(
            id: id,
            path: selected.canonicalPath,
            resolution: resolution
        )
    )
}

private func textureRequest(
    _ intent: SceneTextureColorIntent,
    resource: SceneTextureResource,
    packageID: SceneTexturePackageID = defaultPackageID,
    imageIndex: Int = 0
) -> SceneTextureRequest {
    SceneTextureRequest(
        packageID: packageID,
        resourceID: resource.id,
        imageIndex: imageIndex,
        colorIntent: intent
    )
}

private let defaultPackageID = SceneTexturePackageID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
)

private func preparedLoad(
    supportsSRGBView: Bool = true,
    estimatedResidentBytes: Int
) -> SceneTexturePreparedLoad {
    SceneTexturePreparedLoad(
        allocationPlan: SceneTextureAllocationPlan(
            format: supportsSRGBView ? .rgba8Unorm : .r8Unorm,
            uploadPath: .directUncompressed,
            mips: [],
            stagingLayout: SceneTextureStagingLayout(mips: [], totalBytes: 0),
            supportsSRGBView: supportsSRGBView,
            storageExtent: .init(width: 4, height: 4),
            contentExtent: .init(width: 4, height: 4),
            contentRect: .init(u: 0, v: 0, width: 1, height: 1),
            origin: .topLeft
        ),
        estimatedResidentBytes: estimatedResidentBytes,
        decodedReservation: nil
    )
}

private func allocatedTexture(hasSRGBView: Bool = true) throws -> SceneAllocatedTexture {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SceneTexturePipelineError.allocationFailed
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 4,
        height: 4,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = hasSRGBView ? [.shaderRead, .pixelFormatView] : [.shaderRead]
    guard let linearTexture = device.makeTexture(descriptor: descriptor) else {
        throw SceneTexturePipelineError.allocationFailed
    }
    let srgbTexture = hasSRGBView
        ? linearTexture.makeTextureView(pixelFormat: .rgba8Unorm_srgb)
        : nil
    if hasSRGBView, srgbTexture == nil {
        throw SceneTexturePipelineError.allocationFailed
    }
    return SceneAllocatedTexture(
        linearTexture: linearTexture,
        srgbTexture: srgbTexture,
        uploadPath: .directUncompressed,
        storageExtent: .init(width: 4, height: 4),
        contentExtent: .init(width: 4, height: 4),
        contentRect: .init(u: 0, v: 0, width: 1, height: 1),
        origin: .topLeft,
        mipmapLevelCount: 1,
        residentBytes: linearTexture.allocatedSize
    )
}

private func acquireTask(
    store: SceneTextureStore,
    fixture: TextureFixture,
    intent: SceneTextureColorIntent = .dataLinear,
    generation: SceneTextureGenerationID
) -> Task<SceneTextureLease, any Error> {
    Task {
        try await store.acquire(
            textureRequest(intent, resource: fixture.resource),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )
    }
}

private func finishNextLoad(
    _ task: Task<SceneTextureLease, any Error>,
    fake: ControllableTexturePipeline,
    allocated: SceneAllocatedTexture,
    ordinal: Int
) async throws -> SceneTextureLease {
    await fake.waitForPrepareCount(ordinal)
    try await fake.completePreparation(
        with: preparedLoad(
            supportsSRGBView: allocated.srgbTexture != nil,
            estimatedResidentBytes: allocated.linearTexture.allocatedSize
        )
    )
    await fake.waitForAllocateCount(ordinal)
    try await fake.completeAllocation(with: allocated)
    return try await task.value
}

private func assertTaskError(
    _ expected: SceneTexturePipelineError,
    task: Task<SceneTextureLease, any Error>,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await task.value
        XCTFail("Expected pipeline error \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? SceneTexturePipelineError, expected, file: file, line: line)
    }
}

private func assertPipelineError<T>(
    _ expected: SceneTexturePipelineError,
    operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected pipeline error \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? SceneTexturePipelineError, expected, file: file, line: line)
    }
}

private func waitForStoreLoadingCount(
    _ expected: Int,
    store: SceneTextureStore,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<10_000 {
        if await store.snapshot().loadingEntries == expected {
            return
        }
        await Task.yield()
    }
    XCTFail("Store loading count did not become \(expected)", file: file, line: line)
}
