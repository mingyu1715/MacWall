import Foundation
import Metal
import XCTest
@testable import MacWallSceneTextures

final class DirectSceneTextureAllocatorTests: XCTestCase {
    func testSubmissionStateAllowsExactlyOneTerminalTransition() async {
        let submission = SceneTextureSubmissionState()

        let wins = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<64 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        return submission.submitIfPending()
                    }
                    return submission.cancelIfPending()
                }
            }

            var wins = 0
            for await won in group where won {
                wins += 1
            }
            return wins
        }

        XCTAssertEqual(wins, 1)
        XCTAssertFalse(submission.submitIfPending())
        XCTAssertFalse(submission.cancelIfPending())
    }

    func testSubmittedResourceCleanupRunsAfterCompletionExactlyOnce() {
        let submission = SceneTextureSubmissionState()
        let cleanupCount = LockedInt()
        XCTAssertTrue(submission.submitIfPending())

        submission.performAfterSubmittedResourcesComplete {
            cleanupCount.increment()
        }
        XCTAssertEqual(cleanupCount.value, 0)

        submission.completeSubmittedResources()
        submission.completeSubmittedResources()
        XCTAssertEqual(cleanupCount.value, 1)

        submission.performAfterSubmittedResourcesComplete {
            cleanupCount.increment()
        }
        XCTAssertEqual(cleanupCount.value, 2)
    }

    func testUnsubmittedResourceCleanupRunsImmediately() {
        let pending = SceneTextureSubmissionState()
        let pendingCount = LockedInt()
        pending.performAfterSubmittedResourcesComplete {
            pendingCount.increment()
        }
        XCTAssertEqual(pendingCount.value, 1)

        let cancelled = SceneTextureSubmissionState()
        XCTAssertTrue(cancelled.cancelIfPending())
        let cancelledCount = LockedInt()
        cancelled.performAfterSubmittedResourcesComplete {
            cancelledCount.increment()
        }
        XCTAssertEqual(cancelledCount.value, 1)
    }

    func testCancellationBeforeSubmissionPreventsCommit() async throws {
        let device = try metalDevice()
        let submission = SceneTextureSubmissionState()
        XCTAssertTrue(submission.cancelIfPending())

        let commitCount = LockedInt()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.commit = { _ in commitCount.increment() }

        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )
        let plan = try allocationPlan(
            device: device,
            format: .rgba8Unorm,
            width: 1,
            height: 1,
            mipBytes: [Data([1, 2, 3, 4])],
            colorView: true
        )

        await XCTAssertThrowsErrorAsync(
            try await allocator.allocate(plan, submission: submission)
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .cancelled)
        }
        XCTAssertEqual(commitCount.value, 0)
    }

    func testPreSubmitCancellationInstallsNoHandlerAndReleasesResourceCapture() async throws {
        let device = try metalDevice()
        let submission = SceneTextureSubmissionState()
        XCTAssertTrue(submission.cancelIfPending())

        let completion = VoidCallbackBox()
        let commitCount = LockedInt()
        let lifetime = WeakObjectReference()
        let plan = try allocationPlan(
            device: device,
            format: .rgba8Unorm,
            width: 1,
            height: 1,
            mipBytes: [Data([1, 2, 3, 4])],
            colorView: true
        )

        try await runPreCancelledAllocation(
            device: device,
            plan: plan,
            submission: submission,
            completion: completion,
            commitCount: commitCount,
            lifetime: lifetime
        )

        XCTAssertFalse(completion.hasCallback)
        XCTAssertNil(lifetime.value)
        XCTAssertEqual(commitCount.value, 0)
    }

    func testUploadExecutorAcceptsExactlyOneSuccessfulCompletion() async throws {
        let executor = SceneTextureUploadExecutor()

        try await executor.execute(timeout: .seconds(10)) { finish in
            finish(.success(()))
            finish(.failure(SceneTexturePipelineError.uploadFailed))
        }
    }

    func testUploadExecutorPropagatesFailureCompletion() async {
        let executor = SceneTextureUploadExecutor()

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(timeout: .seconds(10)) { finish in
                finish(.failure(SceneTexturePipelineError.uploadFailed))
            }
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .uploadFailed)
        }
    }

    func testUploadExecutorTimesOutWhenCommandNeverCompletesAndIgnoresLateCallback() async {
        let completion = UploadCompletionBox()
        let executor = SceneTextureUploadExecutor(sleeper: ImmediateSleeper())

        await XCTAssertThrowsErrorAsync(
            try await executor.execute(timeout: .seconds(10)) { finish in
                completion.store(finish)
            }
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .uploadTimedOut)
        }

        completion.resolve(.success(()))
        XCTAssertEqual(completion.resolutionCount, 1)
    }

    func testUploadExecutorCancellationWinsAndIgnoresLateCallback() async {
        let completion = UploadCompletionBox()
        let executor = SceneTextureUploadExecutor()
        let task = Task.detached {
            try await executor.execute(timeout: .seconds(10)) { finish in
                completion.store(finish)
            }
        }

        await waitUntil { completion.hasCompletion }
        task.cancel()
        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .cancelled)
        }

        completion.resolve(.success(()))
        XCTAssertEqual(completion.resolutionCount, 1)
    }

    func testUploadsRGBA8ToPrivateTextureAndReadsItBack() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let bytes = Data([255, 0, 0, 255, 0, 255, 0, 255])
        let artifact = try await allocator.allocate(
            try allocationPlan(
                device: device,
                format: .rgba8Unorm,
                width: 2,
                height: 1,
                mipBytes: [bytes],
                colorView: true
            ),
            submission: SceneTextureSubmissionState()
        )

        XCTAssertEqual(artifact.linearTexture.storageMode, .private)
        XCTAssertEqual(artifact.linearTexture.mipmapLevelCount, 1)
        XCTAssertNotNil(artifact.srgbTexture)
        XCTAssertEqual(try readBack(artifact.linearTexture), bytes)
        XCTAssertEqual(artifact.residentBytes, artifact.linearTexture.allocatedSize)
    }

    func testUploadsR8AndRG8WithoutSRGBViews() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let cases: [(SceneTextureGPUFormat, Data)] = [
            (.r8Unorm, Data([7, 19, 231])),
            (.rg8Unorm, Data([1, 2, 3, 4, 5, 6]))
        ]

        for (format, bytes) in cases {
            let artifact = try await allocator.allocate(
                try allocationPlan(
                    device: device,
                    format: format,
                    width: 3,
                    height: 1,
                    mipBytes: [bytes],
                    colorView: false
                ),
                submission: SceneTextureSubmissionState()
            )

            XCTAssertNil(artifact.srgbTexture)
            XCTAssertEqual(try readBack(artifact.linearTexture), bytes)
        }
    }

    func testUploadsEveryRGBA8MipAndReadsEachBack() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let level0 = Data([
            1, 2, 3, 4, 5, 6, 7, 8,
            9, 10, 11, 12, 13, 14, 15, 16
        ])
        let level1 = Data([21, 22, 23, 24])
        let artifact = try await allocator.allocate(
            try allocationPlan(
                device: device,
                format: .rgba8Unorm,
                width: 2,
                height: 2,
                mipBytes: [level0, level1],
                colorView: true
            ),
            submission: SceneTextureSubmissionState()
        )

        XCTAssertEqual(artifact.mipmapLevelCount, 2)
        XCTAssertEqual(try readBack(artifact.linearTexture, level: 0), level0)
        XCTAssertEqual(try readBack(artifact.linearTexture, level: 1), level1)
    }

    func testUploadsSupportedBCFormatsAndReadsCompressedBytesBack() async throws {
        let device = try metalDevice()
        guard device.supportsBCTextureCompression else {
            return
        }
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let cases: [(SceneTextureGPUFormat, Data)] = [
            (.bc1RGBA, Data([0x00, 0xf8, 0x00, 0xf8, 0, 0, 0, 0])),
            (.bc2RGBA, Data(repeating: 0x5a, count: 16)),
            (.bc3RGBA, Data(repeating: 0xa5, count: 16))
        ]

        for (format, bytes) in cases {
            let artifact = try await allocator.allocate(
                try allocationPlan(
                    device: device,
                    format: format,
                    width: 4,
                    height: 4,
                    mipBytes: [bytes],
                    colorView: true
                ),
                submission: SceneTextureSubmissionState()
            )

            XCTAssertEqual(try readBack(artifact.linearTexture), bytes)
        }
    }

    func testCompatibleSRGBViewsShareTheLinearTextureAllocation() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        var cases: [(SceneTextureGPUFormat, Data)] = [
            (.rgba8Unorm, Data([1, 2, 3, 4]))
        ]
        if device.supportsBCTextureCompression {
            cases.append((.bc1RGBA, Data(repeating: 0x3c, count: 8)))
            cases.append((.bc2RGBA, Data(repeating: 0x4d, count: 16)))
            cases.append((.bc3RGBA, Data(repeating: 0x5e, count: 16)))
        }

        for (format, bytes) in cases {
            let dimension = format == .rgba8Unorm ? 1 : 4
            let artifact = try await allocator.allocate(
                try allocationPlan(
                    device: device,
                    format: format,
                    width: dimension,
                    height: dimension,
                    mipBytes: [bytes],
                    colorView: true
                ),
                submission: SceneTextureSubmissionState()
            )

            let view = try XCTUnwrap(artifact.srgbTexture)
            XCTAssertTrue(view.parent === artifact.linearTexture)
            XCTAssertEqual(try readBack(view), bytes)
        }
    }

    func testMissingCommandQueueFailsInitialization() throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.makeCommandQueue = { _ in nil }

        XCTAssertThrowsError(
            try DirectSceneTextureAllocator(
                device: device,
                limits: .init(),
                operations: operations
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
        }
    }

    func testMissingCommandBufferFailsAllocation() async throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.makeCommandBuffer = { _ in nil }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )

        await assertAllocationFailed(allocator: allocator, device: device)
    }

    func testMissingStagingBufferFailsAllocation() async throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.makeBuffer = { _, _, _ in nil }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )

        await assertAllocationFailed(allocator: allocator, device: device)
    }

    func testMissingPrivateTextureFailsAllocation() async throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.makeTexture = { _, _ in nil }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )

        await assertAllocationFailed(allocator: allocator, device: device)
    }

    func testMissingBlitEncoderFailsAllocation() async throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.makeBlitCommandEncoder = { _ in nil }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )

        await assertAllocationFailed(allocator: allocator, device: device)
    }

    func testRejectsStagingLayoutThatDiffersFromDeviceAlignment() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let validPlan = try allocationPlan(
            device: device,
            format: .rgba8Unorm,
            width: 1,
            height: 1,
            mipBytes: [Data([1, 2, 3, 4])],
            colorView: true
        )
        let invalidPlan = SceneTextureAllocationPlan(
            format: validPlan.format,
            uploadPath: validPlan.uploadPath,
            mips: validPlan.mips,
            stagingLayout: SceneTextureStagingLayout(
                mips: validPlan.stagingLayout.mips,
                totalBytes: validPlan.stagingLayout.totalBytes + 1
            ),
            supportsSRGBView: validPlan.supportsSRGBView,
            storageExtent: validPlan.storageExtent,
            contentExtent: validPlan.contentExtent,
            contentRect: validPlan.contentRect,
            origin: validPlan.origin
        )

        await XCTAssertThrowsErrorAsync(
            try await allocator.allocate(
                invalidPlan,
                submission: SceneTextureSubmissionState()
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
        }
    }

    func testRejectsIncompatibleSRGBViewBeforeSubmission() async throws {
        let device = try metalDevice()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: .init())
        let submission = SceneTextureSubmissionState()

        await XCTAssertThrowsErrorAsync(
            try await allocator.allocate(
                try allocationPlan(
                    device: device,
                    format: .rg8Unorm,
                    width: 1,
                    height: 1,
                    mipBytes: [Data([1, 2])],
                    colorView: true
                ),
                submission: submission
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
        }
        XCTAssertTrue(submission.cancelIfPending())
    }

    func testCommandBufferErrorFailsUpload() async throws {
        let device = try metalDevice()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.commandBufferStatus = { _ in .error }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )

        await XCTAssertThrowsErrorAsync(
            try await allocator.allocate(
                try allocationPlan(
                    device: device,
                    format: .rgba8Unorm,
                    width: 1,
                    height: 1,
                    mipBytes: [Data([1, 2, 3, 4])],
                    colorView: true
                ),
                submission: SceneTextureSubmissionState()
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .uploadFailed)
        }
    }

    func testArtifactIsReturnedOnlyAfterCompletionCallback() async throws {
        let device = try metalDevice()
        let callback = VoidCallbackBox()
        let committed = LockedBool()
        let returned = LockedBool()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.addCompletedHandler = { _, completion in
            callback.store(completion)
        }
        operations.commandBufferStatus = { _ in .completed }
        let liveCommit = operations.commit
        operations.commit = { commandBuffer in
            liveCommit(commandBuffer)
            committed.setTrue()
        }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: .init(),
            operations: operations
        )
        let submission = SceneTextureSubmissionState()
        let plan = try allocationPlan(
            device: device,
            format: .rgba8Unorm,
            width: 1,
            height: 1,
            mipBytes: [Data([1, 2, 3, 4])],
            colorView: true
        )
        let task = Task.detached {
            let artifact = try await allocator.allocate(plan, submission: submission)
            returned.setTrue()
            return artifact
        }

        await waitUntil { committed.value && callback.hasCallback }
        XCTAssertFalse(submission.cancelIfPending())
        XCTAssertFalse(returned.value)

        callback.invoke()
        let artifact = try await task.value
        XCTAssertTrue(returned.value)
        XCTAssertEqual(try readBack(artifact.linearTexture), Data([1, 2, 3, 4]))
    }

    private func assertAllocationFailed(
        allocator: DirectSceneTextureAllocator,
        device: any MTLDevice
    ) async {
        do {
            let plan = try allocationPlan(
                device: device,
                format: .rgba8Unorm,
                width: 1,
                height: 1,
                mipBytes: [Data([1, 2, 3, 4])],
                colorView: true
            )
            await XCTAssertThrowsErrorAsync(
                try await allocator.allocate(
                    plan,
                    submission: SceneTextureSubmissionState()
                )
            ) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, .allocationFailed)
            }
        } catch {
            XCTFail("Failed to build allocation plan: \(error)")
        }
    }

    private func metalDevice(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> any MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device is available", file: file, line: line)
        }
        return device
    }

    private func allocationPlan(
        device: any MTLDevice,
        format: SceneTextureGPUFormat,
        width: Int,
        height: Int,
        mipBytes: [Data],
        colorView: Bool
    ) throws -> SceneTextureAllocationPlan {
        let mips = try mipBytes.enumerated().map { level, bytes in
            let mipWidth = max(1, width >> level)
            let mipHeight = max(1, height >> level)
            let bytesPerRow = try unalignedBytesPerRow(format: format, width: mipWidth)
            let rows = blockOrPixelRows(format: format, height: mipHeight)
            guard bytes.count == bytesPerRow * rows else {
                throw SceneTexturePipelineError.malformedPayload
            }
            return SceneTexturePreparedMip(
                level: level,
                storageExtent: .init(width: mipWidth, height: mipHeight),
                contentExtent: .init(width: mipWidth, height: mipHeight),
                unalignedBytesPerRow: bytesPerRow,
                bytes: bytes
            )
        }
        let alignment = sceneTextureStagingAlignment(device: device, format: format)
        let stagingLayout = try SceneTextureStagingLayout.make(
            format: format,
            mips: mips,
            minimumAlignment: alignment
        )
        return SceneTextureAllocationPlan(
            format: format,
            uploadPath: isBlockCompressed(format) ? .directBlockCompressed : .directUncompressed,
            mips: mips,
            stagingLayout: stagingLayout,
            supportsSRGBView: colorView,
            storageExtent: .init(width: width, height: height),
            contentExtent: .init(width: width, height: height),
            contentRect: .init(u: 0, v: 0, width: 1, height: 1),
            origin: .topLeft
        )
    }

    private func readBack(
        _ texture: any MTLTexture,
        level: Int = 0
    ) throws -> Data {
        let device = texture.device
        let width = max(1, texture.width >> level)
        let height = max(1, texture.height >> level)
        let format = try sceneFormat(texture.pixelFormat)
        let unalignedRowBytes = try unalignedBytesPerRow(format: format, width: width)
        let rowCount = blockOrPixelRows(format: format, height: height)
        let alignment = sceneTextureStagingAlignment(device: device, format: format)
        let alignedRowBytes = (unalignedRowBytes + alignment - 1) & ~(alignment - 1)
        let bytesPerImage = alignedRowBytes * rowCount
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder(),
              let buffer = device.makeBuffer(length: bytesPerImage, options: .storageModeShared) else {
            throw SceneTexturePipelineError.allocationFailed
        }

        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: level,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: width, height: height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: alignedRowBytes,
            destinationBytesPerImage: bytesPerImage
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw SceneTexturePipelineError.uploadFailed
        }

        var result = Data(count: unalignedRowBytes * rowCount)
        result.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress else {
                return
            }
            for row in 0..<rowCount {
                memcpy(
                    destinationBase.advanced(by: row * unalignedRowBytes),
                    buffer.contents().advanced(by: row * alignedRowBytes),
                    unalignedRowBytes
                )
            }
        }
        return result
    }

    private func sceneFormat(_ pixelFormat: MTLPixelFormat) throws -> SceneTextureGPUFormat {
        switch pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb:
            .rgba8Unorm
        case .rg8Unorm:
            .rg8Unorm
        case .r8Unorm:
            .r8Unorm
        case .bc1_rgba, .bc1_rgba_srgb:
            .bc1RGBA
        case .bc2_rgba, .bc2_rgba_srgb:
            .bc2RGBA
        case .bc3_rgba, .bc3_rgba_srgb:
            .bc3RGBA
        default:
            throw SceneTexturePipelineError.allocationFailed
        }
    }

    private func unalignedBytesPerRow(
        format: SceneTextureGPUFormat,
        width: Int
    ) throws -> Int {
        switch format {
        case .rgba8Unorm:
            width * 4
        case .rg8Unorm:
            width * 2
        case .r8Unorm:
            width
        case .bc1RGBA:
            ((width + 3) / 4) * 8
        case .bc2RGBA, .bc3RGBA:
            ((width + 3) / 4) * 16
        }
    }

    private func blockOrPixelRows(
        format: SceneTextureGPUFormat,
        height: Int
    ) -> Int {
        isBlockCompressed(format) ? (height + 3) / 4 : height
    }

    private func isBlockCompressed(_ format: SceneTextureGPUFormat) -> Bool {
        switch format {
        case .bc1RGBA, .bc2RGBA, .bc3RGBA:
            true
        case .rgba8Unorm, .rg8Unorm, .r8Unorm:
            false
        }
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class AllocationLifetimeToken: @unchecked Sendable {}

private final class WeakObjectReference: @unchecked Sendable {
    weak var value: AnyObject?

    func track(_ value: AnyObject) {
        self.value = value
    }
}

private enum DirectAllocatorTestError: Error {
    case allocationUnexpectedlySucceeded
}

private func runPreCancelledAllocation(
    device: any MTLDevice,
    plan: SceneTextureAllocationPlan,
    submission: SceneTextureSubmissionState,
    completion: VoidCallbackBox,
    commitCount: LockedInt,
    lifetime: WeakObjectReference
) async throws {
    let lifetimeToken = AllocationLifetimeToken()
    lifetime.track(lifetimeToken)

    var operations = DirectSceneTextureAllocatorOperations.live
    operations.addCompletedHandler = { _, callback in
        _ = lifetimeToken
        completion.store(callback)
    }
    operations.commit = { _ in commitCount.increment() }
    let allocator = try DirectSceneTextureAllocator(
        device: device,
        limits: .init(),
        operations: operations
    )

    do {
        _ = try await allocator.allocate(plan, submission: submission)
    } catch let error as SceneTexturePipelineError {
        guard error == .cancelled else {
            throw error
        }
        return
    }
    throw DirectAllocatorTestError.allocationUnexpectedlySucceeded
}

private struct ImmediateSleeper: SceneTextureSleeper {
    func sleep(for duration: Duration) async throws {}
}

private final class UploadCompletionBox: @unchecked Sendable {
    typealias Completion = @Sendable (Result<Void, Error>) -> Void

    private let lock = NSLock()
    private var completion: Completion?
    private var resolutions = 0

    var hasCompletion: Bool {
        lock.withLock { completion != nil }
    }

    var resolutionCount: Int {
        lock.withLock { resolutions }
    }

    func store(_ completion: @escaping Completion) {
        lock.withLock {
            self.completion = completion
        }
    }

    func resolve(_ result: Result<Void, Error>) {
        let callback = lock.withLock { () -> Completion? in
            guard let completion else {
                return nil
            }
            resolutions += 1
            return completion
        }
        callback?(result)
    }
}

private final class VoidCallbackBox: @unchecked Sendable {
    typealias Callback = @Sendable () -> Void

    private let lock = NSLock()
    private var callback: Callback?

    var hasCallback: Bool {
        lock.withLock { callback != nil }
    }

    func store(_ callback: @escaping Callback) {
        lock.withLock {
            self.callback = callback
        }
    }

    func invoke() {
        lock.withLock { callback }?()
    }
}

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func setTrue() {
        lock.withLock {
            storedValue = true
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}
