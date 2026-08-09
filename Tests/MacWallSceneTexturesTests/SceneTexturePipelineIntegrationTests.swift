import CoreGraphics
import Foundation
import ImageIO
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport
import Metal
import UniformTypeIdentifiers
import XCTest
@testable import MacWallSceneTextures

private typealias PipelineLimits = MacWallSceneTextures.SceneTextureLimits

final class SceneTexturePipelineIntegrationTests: XCTestCase {
    func testRejectsInvalidProductionLimitsDuringConstruction() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var invalidLimits: [PipelineLimits] = []

        var limits = PipelineLimits()
        limits.residentSoftBytes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.residentHardBytes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.stagingBytes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.decodedCPUBytes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.singlePayloadBytes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.maximumTextureDimension = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.maximumDecodedPixels = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.maximumConcurrentDecodes = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.maximumConcurrentUploads = 0
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.uploadTimeout = .zero
        invalidLimits.append(limits)
        limits = PipelineLimits()
        limits.residentSoftBytes = limits.residentHardBytes + 1
        invalidLimits.append(limits)

        for invalid in invalidLimits {
            XCTAssertThrowsError(try SceneTextureStore(device: device, limits: invalid)) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
            }
        }
    }

    func testRejectsResourceWhoseResolutionDoesNotMatchItsID() async throws {
        let fixture = try makePackageTextureFixture(
            texture: makeTexture(format: 0, width: 1, height: 1, payload: Data([1, 2, 3, 4])),
            path: "materials/a.tex"
        )
        let mismatchedPath = try SceneVirtualPath(canonicalPath: "materials/b.tex")
        let mismatched = SceneTextureResource(
            id: SceneResourceID(kind: .texture, path: mismatchedPath),
            path: mismatchedPath,
            resolution: fixture.resource.resolution
        )
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: mismatched,
                resolver: fixture.resolver,
                for: generation
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
        }
    }

    func testRejectsNonPackageResolutionAndResolverIdentityMismatch() async throws {
        let texture = makeTexture(
            format: 0,
            width: 1,
            height: 1,
            payload: Data([1, 2, 3, 4])
        )
        let fixture = try makePackageTextureFixture(texture: texture)
        let selected = try XCTUnwrap(fixture.resource.resolution.selected)
        let nonPackageSelected = SceneResolvedAsset(
            request: selected.request,
            canonicalPath: selected.canonicalPath,
            candidateOrigin: selected.candidateOrigin,
            provenance: .builtInCandidate(policyVersion: 1)
        )
        let nonPackageResource = SceneTextureResource(
            id: fixture.resource.id,
            path: fixture.resource.path,
            resolution: SceneAssetResolution(
                request: selected.request,
                candidates: fixture.resource.resolution.candidates,
                kind: .builtInCandidate,
                selected: nonPackageSelected,
                issues: []
            )
        )
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: nonPackageResource,
                resolver: fixture.resolver,
                for: generation
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
        }

        let other = try makePackageTextureFixture(
            texture: texture,
            precedingEntryBytes: 8
        )
        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: other.resolver,
                for: generation
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
        }
    }

    func testMapsUnsupportedDescriptorKindsWithoutLeakingMetadata() async throws {
        let cases: [(Data, SceneTexturePipelineError, String)] = [
            (
                makeTexture(
                    version: "TEXV9999",
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([0, 0, 0, 0])
                ),
                .unsupportedDescriptor(.outerVersion),
                "descriptor.outerVersion"
            ),
            (
                makeTexture(
                    infoVersion: "TEXI9999",
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([0, 0, 0, 0])
                ),
                .unsupportedDescriptor(.infoVersion),
                "descriptor.infoVersion"
            ),
            (
                makeTexture(
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([0, 0, 0, 0]),
                    container: .raw("TEXB9999")
                ),
                .unsupportedDescriptor(.container),
                "descriptor.container"
            ),
            (
                makeTexture(
                    format: 0,
                    flags: 4,
                    width: 1,
                    height: 1,
                    payload: Data([0, 0, 0, 0]),
                    animation: .init(
                        version: "TEXS9999",
                        frameCount: 0,
                        frameRecords: Data()
                    )
                ),
                .unsupportedAnimation,
                "animation"
            )
        ]

        for (texture, expectedError, category) in cases {
            let fixture = try makePackageTextureFixture(texture: texture)
            let store = try SceneTextureStore(device: try device())
            let generation = await store.makeGeneration()
            var captured: Error?

            await XCTAssertThrowsErrorAsync(
                try await store.acquire(
                    fixture.request(color: .dataLinear),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            ) { error in
                captured = error
                XCTAssertEqual(error as? SceneTexturePipelineError, expectedError)
            }

            let snapshot = await store.snapshot()
            XCTAssertEqual(snapshot.unsupportedCounts[category], 1)
            assertRedacted(String(describing: captured))
            assertRedacted(String(describing: snapshot))
        }
    }

    func testMapsParsedAnimationVideoMultiImageAndUnknownPixelFormat() async throws {
        let parsedAnimation = makeTexture(
            format: 0,
            flags: 4,
            width: 1,
            height: 1,
            payload: Data([0, 0, 0, 0]),
            animation: .init(
                version: "TEXS0001",
                frameCount: 1,
                frameRecords: Data(repeating: 0, count: 32)
            )
        )
        let video = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0004(imageFormatRawValue: 0, isVideoMP4: true),
            images: [.init(mipmaps: [.init(width: 1, height: 1, payload: Data([0]))])]
        )
        let multiImage = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [
                .init(mipmaps: [.init(width: 1, height: 1, payload: Data([0, 0, 0, 0]))]),
                .init(mipmaps: [.init(width: 1, height: 1, payload: Data([0, 0, 0, 0]))])
            ]
        )
        let unknown = makeTexture(
            format: 77,
            width: 1,
            height: 1,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let cases: [(Data, SceneTexturePipelineError)] = [
            (parsedAnimation, .unsupportedAnimation),
            (video, .unsupportedVideo),
            (multiImage, .unsupportedMultiImage),
            (unknown, .unsupportedPixelFormat(77))
        ]

        for (texture, expected) in cases {
            let fixture = try makePackageTextureFixture(texture: texture)
            let store = try SceneTextureStore(device: try device())
            let generation = await store.makeGeneration()
            await XCTAssertThrowsErrorAsync(
                try await store.acquire(
                    fixture.request(color: .dataLinear),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            ) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, expected)
            }
        }
    }

    func testMapsMalformedDescriptorAndRange() async throws {
        let malformedDescriptors = [
            Data("TEXV0005\0TEXI0001\0".utf8),
            makeTexture(
                format: 0,
                width: 1,
                height: 1,
                payload: Data([1, 2, 3]),
                declaredPayloadByteCount: 4
            )
        ]

        for texture in malformedDescriptors {
            let fixture = try makePackageTextureFixture(texture: texture)
            let store = try SceneTextureStore(device: try device())
            let generation = await store.makeGeneration()
            await XCTAssertThrowsErrorAsync(
                try await store.acquire(
                    fixture.request(color: .dataLinear),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            ) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, .malformedDescriptor)
            }
        }
    }

    func testMapsPayloadDimensionPixelAndMemoryLimitsExactly() async throws {
        let direct = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 2,
            height: 1,
            payload: Data(repeating: 1, count: 8)
        ))
        let png = try makePackageTextureFixture(texture: makeTexture(
            format: 77,
            width: 2,
            height: 1,
            payload: encodedPNG(
                width: 2,
                height: 1,
                premultipliedRGBA: [255, 0, 0, 255, 0, 255, 0, 255]
            )
        ))
        let device = try device()
        let cases: [(PackageTextureFixture, PipelineLimits, SceneTexturePipelineError)] = [
            (direct, .init(singlePayloadBytes: 7), .resourceLimit(.payloadBytes)),
            (direct, .init(maximumTextureDimension: 1), .resourceLimit(.textureDimension)),
            (png, .init(maximumDecodedPixels: 1), .resourceLimit(.decodedPixels)),
            (direct, .init(decodedCPUBytes: 7), .resourceLimit(.decodedCPUBytes)),
            (
                direct,
                .init(residentSoftBytes: 1, residentHardBytes: 7),
                .resourceLimit(.residentBytes)
            ),
            (direct, .init(stagingBytes: 7), .resourceLimit(.stagingBytes))
        ]

        for (fixture, limits, expected) in cases {
            let store = try SceneTextureStore(device: device, limits: limits)
            let generation = await store.makeGeneration()
            await XCTAssertThrowsErrorAsync(
                try await store.acquire(
                    fixture.request(color: .dataLinear),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            ) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, expected)
            }
            let snapshot = await store.snapshot()
            XCTAssertEqual(snapshot.readyEntries, 0)
            XCTAssertEqual(snapshot.residentBytes, 0)
            XCTAssertEqual(snapshot.stagingBytes, 0)
            XCTAssertEqual(snapshot.decodedCPUBytes, 0)
        }
    }

    func testPackageRGBAReachesPrivateTextureThroughPublicStore() async throws {
        let expected = Data([255, 0, 0, 255, 0, 255, 0, 128])
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 2,
            height: 1,
            payload: expected
        ))
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        let lease = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )

        XCTAssertEqual(lease.texture.storageMode, .private)
        XCTAssertEqual(lease.storageExtent, .init(width: 2, height: 1))
        XCTAssertEqual(lease.contentExtent, .init(width: 2, height: 1))
        XCTAssertEqual(try readBack(lease.texture), expected)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.cacheMisses, 1)
    }

    func testR8AndRG8DirectPathsRetainChannelFormats() async throws {
        let device = try device()
        let cases: [(Int32, Data, MTLPixelFormat)] = [
            (9, Data([1, 2]), .r8Unorm),
            (8, Data([1, 2, 3, 4]), .rg8Unorm)
        ]

        for (format, expected, pixelFormat) in cases {
            let fixture = try makePackageTextureFixture(texture: makeTexture(
                format: format,
                width: 2,
                height: 1,
                payload: expected
            ))
            let store = try SceneTextureStore(device: device)
            let generation = await store.makeGeneration()
            let lease = try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )

            XCTAssertEqual(lease.texture.pixelFormat, pixelFormat)
            XCTAssertEqual(try readBack(lease.texture), expected)
        }
    }

    func testBC1BC2AndBC3UseDirectPathOnCapableDevice() async throws {
        let device = try device()
        guard device.supportsBCTextureCompression else {
            throw XCTSkip("The active Metal device does not support BC textures")
        }
        let colorBlock = Data([0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0])
        let cases: [(Int32, Data, MTLPixelFormat)] = [
            (7, colorBlock, .bc1_rgba),
            (6, Data(repeating: 0xFF, count: 8) + colorBlock, .bc2_rgba),
            (
                4,
                Data([255, 0, 0, 0, 0, 0, 0, 0]) + colorBlock,
                .bc3_rgba
            )
        ]

        for (format, expected, pixelFormat) in cases {
            let fixture = try makePackageTextureFixture(texture: makeTexture(
                format: format,
                width: 4,
                height: 4,
                payload: expected
            ))
            let store = try SceneTextureStore(device: device)
            let generation = await store.makeGeneration()
            let lease = try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )

            XCTAssertEqual(lease.texture.pixelFormat, pixelFormat)
            XCTAssertEqual(try readBack(lease.texture), expected)
            let snapshot = await store.snapshot()
            XCTAssertEqual(
                snapshot.uploadPathCounts[.directBlockCompressed],
                1
            )
        }
    }

    func testUnsupportedBCDeviceUsesSoftwareRGBAThroughProductionLoader() async throws {
        let device = try device()
        let limits = PipelineLimits()
        let allocator = try DirectSceneTextureAllocator(device: device, limits: limits)
        let capabilities = SceneTextureDeviceCapabilities(
            supportsBCTextureCompression: false,
            linearTextureAlignment: [:]
        )
        let store = try SceneTextureStore(
            device: device,
            limits: limits,
            capabilities: capabilities,
            allocator: allocator
        )
        let block = Data([0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0])
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 7,
            width: 4,
            height: 4,
            payload: block
        ))
        let generation = await store.makeGeneration()

        let lease = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )

        XCTAssertEqual(lease.texture.pixelFormat, .rgba8Unorm_srgb)
        XCTAssertEqual(
            try readBack(lease.texture),
            repeatedPixel([255, 0, 0, 255], count: 16)
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.uploadPathCounts[.softwareRGBA], 1)
    }

    func testPNGBecomesStraightRGBA8PrivateTexture() async throws {
        let png = encodedPNG(
            width: 2,
            height: 1,
            premultipliedRGBA: [255, 0, 0, 255, 0, 128, 0, 128]
        )
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 77,
            width: 2,
            height: 1,
            payload: png
        ))
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        let lease = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )

        XCTAssertEqual(lease.texture.storageMode, .private)
        XCTAssertEqual(lease.texture.pixelFormat, .rgba8Unorm_srgb)
        XCTAssertEqual(
            try readBack(lease.texture),
            Data([255, 0, 0, 255, 0, 255, 0, 128])
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.uploadPathCounts[.encodedImageRGBA], 1)
    }

    func testEverySuppliedMipReachesPrivateTexture() async throws {
        let levelZero = repeatedPixel([255, 0, 0, 255], count: 4)
        let levelOne = Data([0, 0, 255, 255])
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 2, height: 2, payload: levelZero),
                .init(width: 1, height: 1, payload: levelOne)
            ])]
        )
        let fixture = try makePackageTextureFixture(texture: texture)
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        let lease = try await store.acquire(
            fixture.request(color: .dataLinear),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )

        XCTAssertEqual(lease.mipmapLevelCount, 2)
        XCTAssertEqual(try readBack(lease.texture, level: 0), levelZero)
        XCTAssertEqual(try readBack(lease.texture, level: 1), levelOne)
    }

    func testMalformedLaterMipPreventsAllCacheInstallation() async throws {
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 2, height: 2, payload: Data(repeating: 1, count: 16)),
                .init(width: 1, height: 1, payload: Data(repeating: 2, count: 3))
            ])]
        )
        let fixture = try makePackageTextureFixture(texture: texture)
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()

        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .malformedPayload)
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
        XCTAssertEqual(snapshot.decodedCPUBytes, 0)
    }

    func testSecondRequestIsCacheHitWithoutFurtherReadDecodeOrUpload() async throws {
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 77,
            width: 1,
            height: 1,
            payload: encodedPNG(
                width: 1,
                height: 1,
                premultipliedRGBA: [255, 0, 0, 255]
            )
        ))
        let store = try SceneTextureStore(device: try device())
        let firstGeneration = await store.makeGeneration()
        let secondGeneration = await store.makeGeneration()

        _ = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: firstGeneration
        )
        let readRangesAfterFirstLoad = fixture.recording.readRanges
        let firstSnapshot = await store.snapshot()

        _ = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: secondGeneration
        )

        let secondSnapshot = await store.snapshot()
        XCTAssertEqual(fixture.recording.readRanges, readRangesAfterFirstLoad)
        XCTAssertEqual(secondSnapshot.cacheHits, 1)
        XCTAssertEqual(secondSnapshot.cacheMisses, 1)
        XCTAssertEqual(secondSnapshot.uploadPathCounts, firstSnapshot.uploadPathCounts)
        XCTAssertEqual(secondSnapshot.uploadPathCounts[.encodedImageRGBA], 1)
    }

    func testAllocationAndUploadFailuresRollbackEveryReservation() async throws {
        let device = try device()
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 2,
            height: 1,
            payload: Data(repeating: 1, count: 8)
        ))

        for expected in [
            SceneTexturePipelineError.allocationFailed,
            SceneTexturePipelineError.uploadFailed
        ] {
            let store = try SceneTextureStore(
                device: device,
                limits: .init(),
                capabilities: .init(
                    supportsBCTextureCompression: device.supportsBCTextureCompression,
                    linearTextureAlignment: [:]
                ),
                allocator: ThrowingTextureAllocator(error: expected)
            )
            let generation = await store.makeGeneration()
            await XCTAssertThrowsErrorAsync(
                try await store.acquire(
                    fixture.request(color: .dataLinear),
                    resource: fixture.resource,
                    resolver: fixture.resolver,
                    for: generation
                )
            ) { error in
                XCTAssertEqual(error as? SceneTexturePipelineError, expected)
            }

            let snapshot = await store.snapshot()
            XCTAssertEqual(snapshot.readyEntries, 0)
            XCTAssertEqual(snapshot.loadingEntries, 0)
            XCTAssertEqual(snapshot.residentBytes, 0)
            XCTAssertEqual(snapshot.stagingBytes, 0)
            XCTAssertEqual(snapshot.decodedCPUBytes, 0)
        }
    }

    func testActualAllocatedBytesAreReconciledAndReleasedAfterGenerationTrim() async throws {
        let limits = PipelineLimits(residentSoftBytes: 1)
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 2,
            height: 1,
            payload: Data(repeating: 1, count: 8)
        ))
        let store = try SceneTextureStore(device: try device(), limits: limits)
        let generation = await store.makeGeneration()

        let lease = try await store.acquire(
            fixture.request(color: .dataLinear),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: generation
        )
        let loadedSnapshot = await store.snapshot()
        XCTAssertEqual(loadedSnapshot.residentBytes, lease.texture.allocatedSize)

        await store.releaseGeneration(generation)
        await store.trimToSoftBudget()

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
        XCTAssertEqual(snapshot.decodedCPUBytes, 0)
        XCTAssertEqual(snapshot.stagingBytes, 0)
    }

    func testWorkLimiterBoundsObservedConcurrencyWithoutSleepTiming() async throws {
        let limiter = SceneTextureWorkLimiter(limit: 2)
        let probe = LimiterProbe()
        let tasks = (1...3).map { id in
            Task {
                try await limiter.withPermit {
                    await probe.run(id: id)
                    return id
                }
            }
        }

        await probe.waitForStartedCount(2)
        let initialMaximum = await probe.maximumActive
        XCTAssertEqual(initialMaximum, 2)
        await probe.release(id: 1)
        await probe.waitForStartedCount(3)
        let finalMaximum = await probe.maximumActive
        XCTAssertEqual(finalMaximum, 2)
        await probe.release(id: 2)
        await probe.release(id: 3)
        let values = try await tasks.asyncValues()
        XCTAssertEqual(Set(values), Set([1, 2, 3]))
    }

    func testWorkLimiterPreservesFIFOAndRemovesCanceledWaiter() async throws {
        let limiter = SceneTextureWorkLimiter(limit: 1)
        let probe = LimiterProbe()
        let first = limiterTask(id: 1, limiter: limiter, probe: probe)
        await probe.waitForStartedCount(1)

        let second = limiterTask(id: 2, limiter: limiter, probe: probe)
        await waitForQueuedCount(1, limiter: limiter)
        let canceled = limiterTask(id: 3, limiter: limiter, probe: probe)
        await waitForQueuedCount(2, limiter: limiter)
        let fourth = limiterTask(id: 4, limiter: limiter, probe: probe)
        await waitForQueuedCount(3, limiter: limiter)
        canceled.cancel()
        await XCTAssertThrowsErrorAsync(try await canceled.value) { error in
            XCTAssertTrue(error is CancellationError)
        }

        await probe.release(id: 1)
        await probe.waitForStartedCount(2)
        await probe.release(id: 2)
        await probe.waitForStartedCount(3)
        await probe.release(id: 4)
        _ = try await (first.value, second.value, fourth.value)

        let order = await probe.startedIDs
        XCTAssertEqual(order, [1, 2, 4])
    }

    func testDetachedWorkReceivesParentCancellation() async {
        let probe = DetachedCancellationProbe()
        let task = Task {
            try await runSceneTextureDetachedWork {
                await probe.recordStarted()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await probe.recordCanceled()
                throw CancellationError()
            }
        }

        await probe.waitUntilStarted()
        task.cancel()
        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        await probe.waitUntilCanceled()
    }

    private func limiterTask(
        id: Int,
        limiter: SceneTextureWorkLimiter,
        probe: LimiterProbe
    ) -> Task<Int, Error> {
        Task {
            try await limiter.withPermit {
                await probe.run(id: id)
                return id
            }
        }
    }

    private func waitForQueuedCount(
        _ count: Int,
        limiter: SceneTextureWorkLimiter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if await limiter.queuedWaiterCount == count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) queued limiter operations", file: file, line: line)
    }

    private func device() throws -> any MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func assertRedacted(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(text.contains("/Users/"), file: file, line: line)
        XCTAssertFalse(text.contains("scene-s3-gpu-texture-pipeline"), file: file, line: line)
        XCTAssertFalse(text.contains("DEADBEEF"), file: file, line: line)
    }
}

private struct PackageTextureFixture: Sendable {
    let resolver: ScenePackageAssetResolver
    let resource: SceneTextureResource
    let recording: RecordingSceneByteSource
    let packageID: SceneTexturePackageID

    func request(color: SceneTextureColorIntent) -> SceneTextureRequest {
        SceneTextureRequest(
            packageID: packageID,
            resourceID: resource.id,
            imageIndex: 0,
            colorIntent: color
        )
    }
}

private func makePackageTextureFixture(
    texture: Data,
    path: String = "materials/test.tex",
    precedingEntryBytes: Int = 0
) throws -> PackageTextureFixture {
    var entries: [ScenePackageFixtureEntry] = []
    if precedingEntryBytes > 0 {
        entries.append(.init(
            path: "padding.bin",
            data: Data(repeating: 0, count: precedingEntryBytes)
        ))
    }
    entries.append(.init(path: path, data: texture))
    let recording = RecordingSceneByteSource(
        base: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(entries: entries))
    )
    let resolver = try ScenePackageAssetResolver.open(source: recording)
    let resolution = resolver.resolve(SceneAssetRequest(
        requestedPath: path,
        ownerPath: nil,
        role: .texture,
        key: "texture"
    ))
    let selected = try XCTUnwrap(resolution.selected)
    let id = SceneResourceID(kind: .texture, path: selected.canonicalPath)
    return PackageTextureFixture(
        resolver: resolver,
        resource: SceneTextureResource(
            id: id,
            path: selected.canonicalPath,
            resolution: resolution
        ),
        recording: recording,
        packageID: SceneTexturePackageID()
    )
}

private func makeTexture(
    version: String = "TEXV0005",
    infoVersion: String = "TEXI0001",
    format: Int32,
    flags: Int32 = 0,
    width: Int32,
    height: Int32,
    payload: Data,
    container: SceneTextureFixtureContainer? = nil,
    declaredPayloadByteCount: Int32? = nil,
    animation: SceneTextureFixtureAnimation? = nil
) -> Data {
    SceneTextureFixtureBuilder.make(
        version: version,
        infoVersion: infoVersion,
        formatRawValue: format,
        flagsRawValue: flags,
        textureSize: (width, height),
        imageSize: (width, height),
        container: container ?? .b0003(imageFormatRawValue: format),
        images: [.init(mipmaps: [.init(
            width: width,
            height: height,
            payload: payload,
            declaredPayloadByteCount: declaredPayloadByteCount
        )])],
        animation: animation
    )
}

private func encodedPNG(
    width: Int,
    height: Int,
    premultipliedRGBA: [UInt8]
) -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )
    let provider = CGDataProvider(data: Data(premultipliedRGBA) as CFData)!
    let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

private func repeatedPixel(_ pixel: [UInt8], count: Int) -> Data {
    Data((0..<count).flatMap { _ in pixel })
}

private func readBack(
    _ texture: any MTLTexture,
    level: Int = 0
) throws -> Data {
    let device = texture.device
    let width = max(1, texture.width >> level)
    let height = max(1, texture.height >> level)
    let format = try sceneFormat(texture.pixelFormat)
    let rowBytes = unalignedBytesPerRow(format: format, width: width)
    let rowCount = blockOrPixelRows(format: format, height: height)
    let alignment = sceneTextureStagingAlignment(device: device, format: format)
    let alignedRowBytes = (rowBytes + alignment - 1) & ~(alignment - 1)
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

    var result = Data(count: rowBytes * rowCount)
    result.withUnsafeMutableBytes { destination in
        guard let base = destination.baseAddress else {
            return
        }
        for row in 0..<rowCount {
            memcpy(
                base.advanced(by: row * rowBytes),
                buffer.contents().advanced(by: row * alignedRowBytes),
                rowBytes
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
) -> Int {
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
    switch format {
    case .rgba8Unorm, .rg8Unorm, .r8Unorm:
        height
    case .bc1RGBA, .bc2RGBA, .bc3RGBA:
        (height + 3) / 4
    }
}

private struct ThrowingTextureAllocator: SceneTextureAllocator {
    let error: SceneTexturePipelineError

    func allocate(
        _ plan: SceneTextureAllocationPlan,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture {
        throw error
    }
}

private actor LimiterProbe {
    private(set) var startedIDs: [Int] = []
    private(set) var maximumActive = 0
    private var active = 0
    private var blockers: [Int: CheckedContinuation<Void, Never>] = [:]
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func run(id: Int) async {
        active += 1
        maximumActive = max(maximumActive, active)
        startedIDs.append(id)
        resumeCountWaiters()
        await withCheckedContinuation { continuation in
            blockers[id] = continuation
        }
        active -= 1
    }

    func release(id: Int) {
        blockers.removeValue(forKey: id)?.resume()
    }

    func waitForStartedCount(_ count: Int) async {
        guard startedIDs.count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    private func resumeCountWaiters() {
        let ready = countWaiters.filter { $0.0 <= startedIDs.count }
        countWaiters.removeAll(where: { $0.0 <= startedIDs.count })
        ready.forEach { $0.1.resume() }
    }
}

private actor DetachedCancellationProbe {
    private var started = false
    private var canceled = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var canceledWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStarted() {
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
    }

    func recordCanceled() {
        canceled = true
        canceledWaiters.forEach { $0.resume() }
        canceledWaiters.removeAll()
    }

    func waitUntilStarted() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func waitUntilCanceled() async {
        guard !canceled else {
            return
        }
        await withCheckedContinuation { canceledWaiters.append($0) }
    }
}

private extension Array where Element == Task<Int, Error> {
    func asyncValues() async throws -> [Int] {
        var values: [Int] = []
        for task in self {
            values.append(try await task.value)
        }
        return values
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
