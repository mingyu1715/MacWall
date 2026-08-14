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

    func testLZ4DirectReservesSelectedAndExpandedOverlapAcrossMipChain() async throws {
        let levelZero = Data(repeating: 0x11, count: 16)
        let levelOneRGBA = Data([0x21, 0x22, 0x23, 0x24])
        let levelOneLZ4 = Data([0x40]) + levelOneRGBA
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 2, height: 2, payload: levelZero),
                .init(
                    width: 1,
                    height: 1,
                    isLZ4Compressed: true,
                    decompressedByteCount: 4,
                    payload: levelOneLZ4
                )
            ])]
        )
        let fixture = try makePackageTextureFixture(texture: texture)

        try await assertDecodedFootprintBoundary(
            fixture: fixture,
            expectedMaximum: 16 + levelOneLZ4.count + levelOneRGBA.count
        )
    }

    func testSoftwareBCReservesInputDecodeCropAndPaddingOverlapAcrossMipChain() async throws {
        let block = Data([0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0])
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 7,
            textureSize: (4, 4),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 7),
            images: [.init(mipmaps: [
                .init(width: 4, height: 4, payload: block),
                .init(width: 2, height: 2, payload: block)
            ])]
        )
        let fixture = try makePackageTextureFixture(texture: texture)

        try await assertDecodedFootprintBoundary(
            fixture: fixture,
            expectedMaximum: 64 + block.count + block.count + 16 + 4,
            supportsBCTextureCompression: false
        )
    }

    func testImageIOReservesEncodedLogicalAndPaddedTransparencyOverlapAcrossMipChain() async throws {
        let levelZeroPNG = encodedPNG(
            width: 2,
            height: 2,
            premultipliedRGBA: [
                64, 32, 0, 64, 0, 0, 0, 0,
                255, 0, 0, 255, 0, 255, 0, 255
            ]
        )
        let levelOnePNG = encodedPNG(
            width: 1,
            height: 1,
            premultipliedRGBA: [0, 0, 128, 128]
        )
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 77,
            textureSize: (4, 4),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 77),
            images: [.init(mipmaps: [
                .init(width: 4, height: 4, payload: levelZeroPNG),
                .init(width: 2, height: 2, payload: levelOnePNG)
            ])]
        )
        let fixture = try makePackageTextureFixture(texture: texture)
        let encodedChainBytes = levelZeroPNG.count + levelOnePNG.count

        try await assertDecodedFootprintBoundary(
            fixture: fixture,
            expectedMaximum: encodedChainBytes + 64 + 4 + 16
        )
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

    func testPackageContextAcquireHidesResolverFromRendererCallSite() async throws {
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 2,
            height: 1,
            payload: Data([255, 0, 0, 255, 0, 255, 0, 255])
        ))
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()
        let context = SceneTexturePackageContext(
            packageID: fixture.packageID,
            resolver: fixture.resolver
        )

        let lease = try await store.acquire(
            fixture.request(color: .colorSRGB),
            resource: fixture.resource,
            context: context,
            for: generation
        )

        XCTAssertEqual(lease.contentExtent, .init(width: 2, height: 1))
        XCTAssertEqual(lease.mipContentRegions.count, 1)
        XCTAssertEqual(lease.mipContentRegions[0].contentRect, lease.contentRect)
    }

    func testPackageContextAcquireRejectsUnknownGeneration() async throws {
        let fixture = try makePackageTextureFixture(texture: makeTexture(
            format: 0,
            width: 1,
            height: 1,
            payload: Data([255, 255, 255, 255])
        ))
        let store = try SceneTextureStore(device: try device())
        let context = SceneTexturePackageContext(
            packageID: fixture.packageID,
            resolver: fixture.resolver
        )

        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .colorSRGB),
                resource: fixture.resource,
                context: context,
                for: SceneTextureGenerationID()
            )
        ) { error in
            XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
        }
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

    func testFormatZeroCompactPNGBecomesPaddedPrivateTexture() async throws {
        let png = encodedPNG(
            width: 2,
            height: 1,
            premultipliedRGBA: [255, 0, 0, 255, 0, 255, 0, 255]
        )
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (4, 2),
            imageSize: (2, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 2, height: 1, payload: png)
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

        XCTAssertEqual(lease.texture.storageMode, .private)
        XCTAssertEqual(lease.storageExtent, .init(width: 4, height: 2))
        XCTAssertEqual(lease.contentExtent, .init(width: 2, height: 1))
        XCTAssertEqual(
            try readBack(lease.texture),
            Data([
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ])
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
        XCTAssertEqual(lease.mipContentRegions.map(\.level), [0, 1])
        XCTAssertEqual(
            lease.mipContentRegions.map(\.contentExtent),
            [.init(width: 2, height: 2), .init(width: 1, height: 1)]
        )
        XCTAssertEqual(try readBack(lease.texture, level: 0), levelZero)
        XCTAssertEqual(try readBack(lease.texture, level: 1), levelOne)
    }

    func testMalformedLaterMipPreventsAllCacheInstallation() async throws {
        let payloadMarker = "TASK9_PAYLOAD_SECRET_7F3A"
        let malformedPayload = Data(payloadMarker.utf8)
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (2, 2),
            imageSize: (2, 2),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [
                .init(width: 2, height: 2, payload: Data(repeating: 1, count: 16)),
                .init(width: 1, height: 1, payload: malformedPayload)
            ])]
        )
        XCTAssertNotNil(texture.range(of: malformedPayload))
        let fixture = try makePackageTextureFixture(texture: texture)
        let store = try SceneTextureStore(device: try device())
        let generation = await store.makeGeneration()
        var capturedError: SceneTexturePipelineError?

        await XCTAssertThrowsErrorAsync(
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )
        ) { error in
            capturedError = error as? SceneTexturePipelineError
            XCTAssertEqual(capturedError, .malformedPayload)
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.readyEntries, 0)
        XCTAssertEqual(snapshot.residentBytes, 0)
        XCTAssertEqual(snapshot.decodedCPUBytes, 0)
        for text in [
            String(describing: capturedError),
            String(reflecting: capturedError),
            String(describing: snapshot),
            String(reflecting: snapshot)
        ] {
            assertRedacted(text, payloadMarker: payloadMarker)
        }
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

    func testDefaultLoaderUsesConfiguredDecodeLimiterAndFIFO() async throws {
        let device = try device()
        let limits = PipelineLimits(
            maximumConcurrentDecodes: 2,
            maximumConcurrentUploads: 1
        )
        let probe = PipelineStageProbe(blocking: [.decode])
        let budget = SceneTextureMemoryBudget(limits: limits)
        let loader = try makeDefaultLoader(
            device: device,
            limits: limits,
            memoryBudget: budget,
            observer: probe
        )
        let fixtures = try (1...4).map { id in
            try makePackageTextureFixture(
                texture: makeTexture(
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([UInt8(id), 0, 0, 255])
                ),
                path: "materials/\(id).tex"
            )
        }
        let inputs = try fixtures.map { try pipelineInput(for: $0, device: device) }

        let first = Task { try await loader.prepare(inputs[0]) }
        await probe.waitForStartedCount(1, stage: .decode)
        let second = Task { try await loader.prepare(inputs[1]) }
        await probe.waitForStartedCount(2, stage: .decode)
        let third = Task { try await loader.prepare(inputs[2]) }
        await waitForQueuedDecodeCount(1, loader: loader)
        let fourth = Task { try await loader.prepare(inputs[3]) }
        await waitForQueuedDecodeCount(2, loader: loader)

        let maximumDecodeConcurrency = await probe.maximumActive(for: .decode)
        XCTAssertEqual(maximumDecodeConcurrency, 2)
        await probe.release(id: 1, stage: .decode)
        await probe.waitForStartedCount(3, stage: .decode)
        await probe.release(id: 2, stage: .decode)
        await probe.waitForStartedCount(4, stage: .decode)
        await probe.release(id: 3, stage: .decode)
        await probe.release(id: 4, stage: .decode)

        let prepared = try await [first.value, second.value, third.value, fourth.value]
        let decodeOrder = await probe.startedIDs(for: .decode)
        XCTAssertEqual(decodeOrder, [1, 2, 3, 4])
        for load in prepared {
            try budget.release(try XCTUnwrap(load.decodedReservation))
        }
    }

    func testDefaultLoaderUsesSeparateConfiguredUploadLimiterAndFIFO() async throws {
        let device = try device()
        let limits = PipelineLimits(
            maximumConcurrentDecodes: 3,
            maximumConcurrentUploads: 1
        )
        let probe = PipelineStageProbe(blocking: [.upload])
        let budget = SceneTextureMemoryBudget(limits: limits)
        let loader = try makeDefaultLoader(
            device: device,
            limits: limits,
            memoryBudget: budget,
            observer: probe
        )
        let fixtures = try (1...3).map { id in
            try makePackageTextureFixture(
                texture: makeTexture(
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([UInt8(id), 0, 0, 255])
                ),
                path: "materials/upload-\(id).tex"
            )
        }
        let prepared = try await fixtures.asyncMap {
            try await loader.prepare(try pipelineInput(for: $0, device: device))
        }

        let first = Task {
            try await loader.allocate(prepared[0], submission: SceneTextureSubmissionState())
        }
        await probe.waitForStartedCount(1, stage: .upload)
        let second = Task {
            try await loader.allocate(prepared[1], submission: SceneTextureSubmissionState())
        }
        await waitForQueuedUploadCount(1, loader: loader)
        let third = Task {
            try await loader.allocate(prepared[2], submission: SceneTextureSubmissionState())
        }
        await waitForQueuedUploadCount(2, loader: loader)

        let maximumUploadConcurrency = await probe.maximumActive(for: .upload)
        XCTAssertEqual(maximumUploadConcurrency, 1)
        await probe.release(id: 1, stage: .upload)
        await probe.waitForStartedCount(2, stage: .upload)
        await probe.release(id: 2, stage: .upload)
        await probe.waitForStartedCount(3, stage: .upload)
        await probe.release(id: 3, stage: .upload)
        _ = try await (first.value, second.value, third.value)

        let uploadOrder = await probe.startedIDs(for: .upload)
        XCTAssertEqual(uploadOrder, [1, 2, 3])
        let snapshot = budget.snapshot()
        XCTAssertEqual(snapshot.decodedCPUBytes, 0)
        XCTAssertEqual(snapshot.stagingBytes, 0)
    }

    func testProductionCancellationAfterPreparationRollsBackExactly() async throws {
        let device = try device()
        let limits = PipelineLimits()
        let probe = PipelineStageProbe(blocking: [.prepared])
        let fixture = try makePackageTextureFixture(
            texture: makeTexture(
                format: 0,
                width: 1,
                height: 1,
                payload: Data([41, 0, 0, 255])
            ),
            path: "materials/cancel-prepared-41.tex"
        )
        let (store, _) = try makeObservedProductionStore(
            device: device,
            limits: limits,
            observer: probe
        )
        let generation = await store.makeGeneration()

        let acquisition = Task {
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )
        }
        await probe.waitForStartedCount(1, stage: .prepared)
        let preparedSnapshot = await store.snapshot()
        XCTAssertGreaterThan(preparedSnapshot.decodedCPUBytes, 0)
        XCTAssertEqual(preparedSnapshot.stagingBytes, 0)
        XCTAssertEqual(preparedSnapshot.residentBytes, 0)

        acquisition.cancel()
        await assertCancelled(acquisition)
        await assertStoreRolledBack(store)
    }

    func testProductionCancellationWhileQueuedForUploadRollsBackExactly() async throws {
        let device = try device()
        let limits = PipelineLimits(maximumConcurrentUploads: 1)
        let probe = PipelineStageProbe(blocking: [.upload])
        let fixtures = try [51, 52].map { id in
            try makePackageTextureFixture(
                texture: makeTexture(
                    format: 0,
                    width: 1,
                    height: 1,
                    payload: Data([UInt8(id), 0, 0, 255])
                ),
                path: "materials/cancel-queued-\(id).tex"
            )
        }
        let (store, loader) = try makeObservedProductionStore(
            device: device,
            limits: limits,
            observer: probe
        )
        let generation = await store.makeGeneration()
        let first = acquisitionTask(store: store, fixture: fixtures[0], generation: generation)
        await probe.waitForStartedCount(1, stage: .upload)
        let second = acquisitionTask(store: store, fixture: fixtures[1], generation: generation)
        await waitForQueuedUploadCount(1, loader: loader)

        let queuedSnapshot = await store.snapshot()
        XCTAssertGreaterThan(queuedSnapshot.decodedCPUBytes, 0)
        XCTAssertGreaterThan(queuedSnapshot.stagingBytes, 0)
        XCTAssertGreaterThan(queuedSnapshot.residentBytes, 0)

        second.cancel()
        await assertCancelled(second)
        first.cancel()
        await assertCancelled(first)
        await assertStoreRolledBack(store)
    }

    func testProductionCancellationBeforeSubmissionRollsBackExactly() async throws {
        let device = try device()
        let limits = PipelineLimits(maximumConcurrentUploads: 1)
        let probe = PipelineStageProbe(blocking: [.upload])
        let fixture = try makePackageTextureFixture(
            texture: makeTexture(
                format: 0,
                width: 1,
                height: 1,
                payload: Data([61, 0, 0, 255])
            ),
            path: "materials/cancel-before-submit-61.tex"
        )
        let (store, _) = try makeObservedProductionStore(
            device: device,
            limits: limits,
            observer: probe
        )
        let generation = await store.makeGeneration()
        let acquisition = acquisitionTask(
            store: store,
            fixture: fixture,
            generation: generation
        )
        await probe.waitForStartedCount(1, stage: .upload)

        let beforeSubmission = await store.snapshot()
        XCTAssertGreaterThan(beforeSubmission.decodedCPUBytes, 0)
        XCTAssertGreaterThan(beforeSubmission.stagingBytes, 0)
        XCTAssertGreaterThan(beforeSubmission.residentBytes, 0)

        acquisition.cancel()
        await assertCancelled(acquisition)
        await assertStoreRolledBack(store)
    }

    func testTimedOutSubmittedUploadKeepsMemoryReservedUntilGPUCompletion() async throws {
        let device = try device()
        let limits = PipelineLimits()
        let memoryBudget = SceneTextureMemoryBudget(limits: limits)
        let completion = PipelineCompletionBox()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.addCompletedHandler = { _, callback in
            completion.store(callback)
        }
        operations.commandBufferStatus = { _ in .completed }
        operations.commit = { _ in }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: limits,
            executor: SceneTextureUploadExecutor(
                sleeper: ImmediatePipelineSleeper()
            ),
            operations: operations
        )
        let loader = try DefaultSceneTexturePipelineLoader(
            device: device,
            capabilities: .init(
                supportsBCTextureCompression: device.supportsBCTextureCompression,
                linearTextureAlignment: [:]
            ),
            limits: limits,
            memoryBudget: memoryBudget,
            allocator: allocator
        )
        let store = SceneTextureStore(
            testPipeline: loader,
            limits: limits,
            memoryBudget: memoryBudget,
            deviceRegistryID: device.registryID
        )
        let fixture = try makePackageTextureFixture(
            texture: makeTexture(
                format: 0,
                width: 1,
                height: 1,
                payload: Data([71, 0, 0, 255])
            ),
            path: "materials/timeout-submitted-71.tex"
        )
        let generation = await store.makeGeneration()
        let acquisition = acquisitionTask(
            store: store,
            fixture: fixture,
            generation: generation
        )

        await XCTAssertThrowsErrorAsync(try await acquisition.value) { error in
            XCTAssertEqual(
                error as? SceneTexturePipelineError,
                .uploadTimedOut
            )
        }
        XCTAssertTrue(completion.hasCallback)
        let timedOutSnapshot = await store.snapshot()
        XCTAssertGreaterThan(timedOutSnapshot.decodedCPUBytes, 0)
        XCTAssertGreaterThan(timedOutSnapshot.stagingBytes, 0)
        XCTAssertGreaterThan(timedOutSnapshot.residentBytes, 0)

        completion.invoke()
        await assertStoreRolledBack(store)
    }

    func testCancelledSubmittedUploadKeepsMemoryReservedUntilGPUCompletion() async throws {
        let device = try device()
        let limits = PipelineLimits()
        let memoryBudget = SceneTextureMemoryBudget(limits: limits)
        let completion = PipelineCompletionBox()
        var operations = DirectSceneTextureAllocatorOperations.live
        operations.addCompletedHandler = { _, callback in
            completion.store(callback)
        }
        operations.commandBufferStatus = { _ in .completed }
        operations.commit = { _ in }
        let allocator = try DirectSceneTextureAllocator(
            device: device,
            limits: limits,
            operations: operations
        )
        let loader = try DefaultSceneTexturePipelineLoader(
            device: device,
            capabilities: .init(
                supportsBCTextureCompression: device.supportsBCTextureCompression,
                linearTextureAlignment: [:]
            ),
            limits: limits,
            memoryBudget: memoryBudget,
            allocator: allocator
        )
        let store = SceneTextureStore(
            testPipeline: loader,
            limits: limits,
            memoryBudget: memoryBudget,
            deviceRegistryID: device.registryID
        )
        let fixture = try makePackageTextureFixture(
            texture: makeTexture(
                format: 0,
                width: 1,
                height: 1,
                payload: Data([72, 0, 0, 255])
            ),
            path: "materials/cancel-submitted-72.tex"
        )
        let generation = await store.makeGeneration()
        let acquisition = acquisitionTask(
            store: store,
            fixture: fixture,
            generation: generation
        )

        for _ in 0..<10_000 where !completion.hasCallback {
            await Task.yield()
        }
        XCTAssertTrue(completion.hasCallback)
        acquisition.cancel()
        await assertCancelled(acquisition)
        let cancelledSnapshot = await store.snapshot()
        XCTAssertGreaterThan(cancelledSnapshot.decodedCPUBytes, 0)
        XCTAssertGreaterThan(cancelledSnapshot.stagingBytes, 0)
        XCTAssertGreaterThan(cancelledSnapshot.residentBytes, 0)

        completion.invoke()
        await assertStoreRolledBack(store)
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

    private func waitForQueuedDecodeCount(
        _ count: Int,
        loader: DefaultSceneTexturePipelineLoader,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if await loader.queuedDecodeCount() == count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) queued decodes", file: file, line: line)
    }

    private func waitForQueuedUploadCount(
        _ count: Int,
        loader: DefaultSceneTexturePipelineLoader,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if await loader.queuedUploadCount() == count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) queued uploads", file: file, line: line)
    }

    private func makeDefaultLoader(
        device: any MTLDevice,
        limits: PipelineLimits,
        memoryBudget: SceneTextureMemoryBudget,
        observer: any SceneTexturePipelineObserving
    ) throws -> DefaultSceneTexturePipelineLoader {
        try DefaultSceneTexturePipelineLoader(
            device: device,
            capabilities: .init(
                supportsBCTextureCompression: device.supportsBCTextureCompression,
                linearTextureAlignment: [:]
            ),
            limits: limits,
            memoryBudget: memoryBudget,
            allocator: DirectSceneTextureAllocator(device: device, limits: limits),
            observer: observer
        )
    }

    private func makeObservedProductionStore(
        device: any MTLDevice,
        limits: PipelineLimits,
        observer: any SceneTexturePipelineObserving & SceneTextureStoreLoadObserving
    ) throws -> (SceneTextureStore, DefaultSceneTexturePipelineLoader) {
        let budget = SceneTextureMemoryBudget(limits: limits)
        let loader = try makeDefaultLoader(
            device: device,
            limits: limits,
            memoryBudget: budget,
            observer: observer
        )
        let store = SceneTextureStore(
            testPipeline: loader,
            limits: limits,
            memoryBudget: budget,
            loadObserver: observer,
            deviceRegistryID: device.registryID
        )
        return (store, loader)
    }

    private func acquisitionTask(
        store: SceneTextureStore,
        fixture: PackageTextureFixture,
        generation: SceneTextureGenerationID
    ) -> Task<SceneTextureLease, Error> {
        Task {
            try await store.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: generation
            )
        }
    }

    private func assertCancelled(
        _ task: Task<SceneTextureLease, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertEqual(
                error as? SceneTexturePipelineError,
                .cancelled,
                file: file,
                line: line
            )
        }
    }

    private func assertStoreRolledBack(
        _ store: SceneTextureStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            let snapshot = await store.snapshot()
            if snapshot.loadingEntries == 0,
               snapshot.decodedCPUBytes == 0,
               snapshot.stagingBytes == 0,
               snapshot.residentBytes == 0 {
                XCTAssertEqual(snapshot.readyEntries, 0, file: file, line: line)
                return
            }
            await Task.yield()
        }
        let snapshot = await store.snapshot()
        XCTFail("Store did not roll back exactly: \(snapshot)", file: file, line: line)
    }

    private func pipelineInput(
        for fixture: PackageTextureFixture,
        device: any MTLDevice
    ) throws -> SceneTexturePipelineInput {
        let selected = try XCTUnwrap(fixture.resource.resolution.selected)
        guard case let .package(identity) = selected.provenance else {
            throw SceneTexturePipelineError.invalidRequest
        }
        let request = fixture.request(color: .dataLinear)
        return SceneTexturePipelineInput(
            request: request,
            resource: fixture.resource,
            resolver: fixture.resolver,
            storageKey: SceneTextureStorageKey(
                packageID: request.packageID,
                canonicalPath: selected.canonicalPath.rawValue,
                entryRelativeOffset: identity.relativeOffset,
                entryByteCount: identity.byteCount,
                imageIndex: request.imageIndex,
                uploadPolicyVersion: 1,
                deviceRegistryID: device.registryID
            )
        )
    }

    private func device() throws -> any MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func assertDecodedFootprintBoundary(
        fixture: PackageTextureFixture,
        expectedMaximum: Int,
        supportsBCTextureCompression: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let device = try device()
        let rejectedLimits = PipelineLimits(decodedCPUBytes: expectedMaximum - 1)
        let rejectedStore = try makeProductionStore(
            device: device,
            limits: rejectedLimits,
            supportsBCTextureCompression: supportsBCTextureCompression
        )
        let rejectedGeneration = await rejectedStore.makeGeneration()
        await XCTAssertThrowsErrorAsync(
            try await rejectedStore.acquire(
                fixture.request(color: .dataLinear),
                resource: fixture.resource,
                resolver: fixture.resolver,
                for: rejectedGeneration
            )
        ) { error in
            XCTAssertEqual(
                error as? SceneTexturePipelineError,
                .resourceLimit(.decodedCPUBytes),
                file: file,
                line: line
            )
        }

        let acceptedLimits = PipelineLimits(decodedCPUBytes: expectedMaximum)
        let acceptedStore = try makeProductionStore(
            device: device,
            limits: acceptedLimits,
            supportsBCTextureCompression: supportsBCTextureCompression
        )
        let acceptedGeneration = await acceptedStore.makeGeneration()
        _ = try await acceptedStore.acquire(
            fixture.request(color: .dataLinear),
            resource: fixture.resource,
            resolver: fixture.resolver,
            for: acceptedGeneration
        )
        let snapshot = await acceptedStore.snapshot()
        XCTAssertEqual(snapshot.peakDecodedCPUBytes, expectedMaximum, file: file, line: line)
        XCTAssertEqual(snapshot.decodedCPUBytes, 0, file: file, line: line)
    }

    private func makeProductionStore(
        device: any MTLDevice,
        limits: PipelineLimits,
        supportsBCTextureCompression: Bool?
    ) throws -> SceneTextureStore {
        guard let supportsBCTextureCompression else {
            return try SceneTextureStore(device: device, limits: limits)
        }
        return try SceneTextureStore(
            device: device,
            limits: limits,
            capabilities: .init(
                supportsBCTextureCompression: supportsBCTextureCompression,
                linearTextureAlignment: [:]
            ),
            allocator: DirectSceneTextureAllocator(device: device, limits: limits)
        )
    }

    private func assertRedacted(
        _ text: String,
        payloadMarker: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let forbidden = [
            payloadMarker,
            "/Users/",
            "/Users/mingyu/workspace/01_projects/app/wallpaper",
            "scene-s3-gpu-texture-pipeline",
            NSUserName()
        ].compactMap { $0 }.filter { !$0.isEmpty }
        for value in forbidden {
            XCTAssertFalse(text.contains(value), file: file, line: line)
        }
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

private struct ImmediatePipelineSleeper: SceneTextureSleeper {
    func sleep(for duration: Duration) async throws {}
}

private final class PipelineCompletionBox: @unchecked Sendable {
    typealias Callback = @Sendable () -> Void

    private let lock = NSLock()
    private var callback: Callback?

    var hasCallback: Bool {
        lock.withLock { callback != nil }
    }

    func store(_ callback: @escaping Callback) {
        lock.withLock { self.callback = callback }
    }

    func invoke() {
        lock.withLock { callback }?()
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

private actor PipelineStageProbe: SceneTexturePipelineObserving,
    SceneTextureStoreLoadObserving {
    enum Stage: Hashable {
        case decode
        case prepared
        case upload
    }

    private struct Key: Hashable {
        let stage: Stage
        let id: Int
    }

    private let blocking: Set<Stage>
    private var order: [Stage: [Int]] = [:]
    private var active: [Stage: Int] = [:]
    private var maxima: [Stage: Int] = [:]
    private var blockers: [Key: CheckedContinuation<Void, any Error>] = [:]
    private var startWaiters: [Stage: [(Int, CheckedContinuation<Void, Never>)]] = [:]

    init(blocking: Set<Stage>) {
        self.blocking = blocking
    }

    func decodeStarted(_ input: SceneTexturePipelineInput) async throws {
        let component = input.resource.path.rawValue.split(separator: "/").last ?? ""
        let digits = component.filter(\.isNumber)
        try await enter(id: Int(digits) ?? 0, stage: .decode)
    }

    func preparationFinished(_ prepared: SceneTexturePreparedLoad) async throws {
        try await enter(id: try preparedID(prepared), stage: .prepared)
    }

    func uploadStarted(_ prepared: SceneTexturePreparedLoad) async throws {
        try await enter(id: try preparedID(prepared), stage: .upload)
    }

    func waitForStartedCount(_ count: Int, stage: Stage) async {
        guard order[stage, default: []].count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[stage, default: []].append((count, continuation))
        }
    }

    func release(id: Int, stage: Stage) {
        blockers.removeValue(forKey: Key(stage: stage, id: id))?.resume()
    }

    func maximumActive(for stage: Stage) -> Int {
        maxima[stage, default: 0]
    }

    func startedIDs(for stage: Stage) -> [Int] {
        order[stage, default: []]
    }

    private func enter(id: Int, stage: Stage) async throws {
        order[stage, default: []].append(id)
        active[stage, default: 0] += 1
        maxima[stage] = max(maxima[stage, default: 0], active[stage, default: 0])
        resumeStartWaiters(for: stage)
        defer { active[stage, default: 0] -= 1 }

        guard blocking.contains(stage) else {
            return
        }
        let key = Key(stage: stage, id: id)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    blockers[key] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(key) }
        }
    }

    private func cancel(_ key: Key) {
        blockers.removeValue(forKey: key)?.resume(throwing: CancellationError())
    }

    private func resumeStartWaiters(for stage: Stage) {
        let startedCount = order[stage, default: []].count
        let ready = startWaiters[stage, default: []].filter { $0.0 <= startedCount }
        startWaiters[stage]?.removeAll(where: { $0.0 <= startedCount })
        ready.forEach { $0.1.resume() }
    }

    private func preparedID(_ prepared: SceneTexturePreparedLoad) throws -> Int {
        Int(try XCTUnwrap(prepared.allocationPlan.mips.first?.bytes.first))
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

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
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
