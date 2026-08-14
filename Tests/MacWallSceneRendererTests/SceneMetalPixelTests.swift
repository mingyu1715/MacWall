import Metal
import XCTest
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport
import MacWallSceneTextures
@testable import MacWallSceneRenderer

final class SceneMetalPixelTests: XCTestCase {
    func testClearOnlyFrameRendersRequestedLinearColor() async throws {
        let fixture = try makeRendererFixture(
            textureBytes: [255, 255, 255, 255],
            visible: false
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 2,
            outputHeight: 2,
            scalingMode: .stretch,
            clearColor: .init(red: 0, green: 1, blue: 0, alpha: 1)
        ))

        XCTAssertEqual(frame.drawCount, 0)
        XCTAssertEqual(frame.skippedDrawCount, 1)
        let pixels = try await readBGRA8(frame.texture)
        XCTAssertEqual(
            pixels,
            Data(repeating: [0, 255, 0, 255], count: 4)
        )
        frame.release()
        await session.invalidate()
    }

    func testOneQuadRendersExpectedPixels() async throws {
        let fixture = try makeRendererFixture(
            textureBytes: [255, 0, 0, 255]
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 2,
            outputHeight: 2,
            scalingMode: .stretch
        ))

        XCTAssertEqual(frame.status, .exact)
        XCTAssertEqual(frame.drawCount, 1)
        XCTAssertEqual(frame.skippedDrawCount, 0)
        XCTAssertNil(frame.snapshotPNG)
        let pixels = try await readBGRA8(frame.texture)
        XCTAssertEqual(
            pixels,
            Data(repeating: [0, 0, 255, 255], count: 4)
        )
        frame.release()
        await session.invalidate()
    }

    func testTopLeftTextureOrientationIsAppliedExactlyOnce() async throws {
        let fixture = try makeRendererFixture(
            textures: [.init(
                storageSize: (2, 2),
                contentSize: (2, 2),
                rgba: [
                    255, 0, 0, 255, 0, 255, 0, 255,
                    0, 0, 255, 255, 255, 255, 255, 255
                ]
            )],
            layers: [.init(textureIndex: 0)],
            canvasSize: (2, 2)
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 2,
            outputHeight: 2,
            scalingMode: .stretch
        ))
        let pixels = try await readBGRA8(frame.texture)

        XCTAssertEqual(Array(pixels), [
            0, 0, 255, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 255, 255, 255
        ])
        frame.release()
        await session.invalidate()
    }

    func testTextureContentExtentDefinesCenteredLocalQuad() async throws {
        let fixture = try makeRendererFixture(
            textures: [.init(
                storageSize: (2, 1),
                contentSize: (2, 1),
                rgba: [255, 0, 0, 255, 0, 255, 0, 255]
            )],
            layers: [.init(textureIndex: 0, origin: (1, 0.5))],
            canvasSize: (2, 1)
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 2,
            outputHeight: 1,
            scalingMode: .stretch
        ))
        let pixels = try await readBGRA8(frame.texture)

        XCTAssertEqual(Array(pixels), [0, 0, 255, 255, 0, 255, 0, 255])
        frame.release()
        await session.invalidate()
    }

    func testContentRectExcludesPhysicalPaddingFromFiltering() async throws {
        let fixture = try makeRendererFixture(
            textures: [.init(
                storageSize: (4, 2),
                contentSize: (2, 1),
                rgba: [
                    255, 0, 0, 255, 0, 255, 0, 255,
                    0, 0, 255, 255, 0, 0, 255, 255,
                    0, 0, 255, 255, 0, 0, 255, 255,
                    0, 0, 255, 255, 0, 0, 255, 255
                ]
            )],
            layers: [.init(textureIndex: 0)],
            canvasSize: (2, 1)
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 2,
            outputHeight: 1,
            scalingMode: .stretch
        ))
        let pixels = try await readBGRA8(frame.texture)

        XCTAssertEqual(Array(pixels), [0, 0, 255, 255, 0, 255, 0, 255])
        frame.release()
        await session.invalidate()
    }

    func testOverlappingStraightAlphaUsesStableSourceOverOrder() async throws {
        let fixture = try makeRendererFixture(
            textures: [
                .solid([0, 0, 255, 255]),
                .solid([255, 0, 0, 128])
            ],
            layers: [
                .init(textureIndex: 0),
                .init(textureIndex: 1)
            ]
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch
        ))
        let pixels = try await readBGRA8(frame.texture)

        assertPixel(pixels, equalsBGRA: [187, 0, 188, 255], tolerance: 2)
        XCTAssertEqual(frame.drawCount, 2)
        frame.release()
        await session.invalidate()
    }

    func testNodeOpacityIsAppliedInLinearPremultipliedSpace() async throws {
        let fixture = try makeRendererFixture(
            textures: [.solid([255, 0, 0, 255])],
            layers: [.init(textureIndex: 0, opacity: 0.25)]
        )
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch
        ))
        let pixels = try await readBGRA8(frame.texture)

        assertPixel(pixels, equalsBGRA: [0, 0, 137, 64], tolerance: 2)
        frame.release()
        await session.invalidate()
    }

    func testOwnedTargetIsReusedOnlyAfterCallerAndSessionReleaseIt() async throws {
        let fixture = try makeRendererFixture(textureBytes: [255, 0, 0, 255])
        let session = try await fixture.makeSession()
        let request = SceneRenderFrameRequest(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch
        )

        let first = try await session.render(request)
        let firstIdentity = ObjectIdentifier(first.texture)
        first.release()

        let second = try await session.render(request)
        let secondIdentity = ObjectIdentifier(second.texture)
        XCTAssertNotEqual(secondIdentity, firstIdentity)
        second.release()

        let third = try await session.render(request)
        XCTAssertEqual(ObjectIdentifier(third.texture), firstIdentity)

        third.release()
        await session.invalidate()
    }

    func testExternalTargetReceivesCompletedPixelsWithoutOwningPoolTarget() async throws {
        let fixture = try makeRendererFixture(textureBytes: [255, 0, 0, 255])
        let session = try await fixture.makeSession()
        let externalTexture = try makeExternalTarget(
            device: fixture.device,
            width: 1,
            height: 1
        )
        let externalLease = SceneExternalRenderTargetLease(texture: externalTexture)

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch,
            output: .external(externalLease)
        ))
        let pixels = try await readBGRA8(externalTexture)

        XCTAssertEqual(ObjectIdentifier(frame.texture), ObjectIdentifier(externalTexture))
        XCTAssertEqual(Array(pixels), [0, 0, 255, 255])
        frame.release()
        await session.invalidate()
    }

    func testExternalTargetReservationRejectsDuplicateUntilCompletion() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try makeExternalTarget(device: device, width: 1, height: 1)
        let lease = SceneExternalRenderTargetLease(texture: texture)
        var reservations = SceneExternalTargetReservations()

        let identifier = try reservations.reserve(lease)
        XCTAssertThrowsError(try reservations.reserve(lease)) { error in
            XCTAssertEqual(error as? SceneRenderError, .invalidTarget)
        }

        reservations.release(identifier)
        XCTAssertNoThrow(try reservations.reserve(lease))
    }

    func testInvalidationDuringRenderDoesNotPublishStaleCompletion() async throws {
        let fixture = try makeRendererFixture(textureBytes: [255, 0, 0, 255])
        let session = try await fixture.makeSession()
        let renderTask = Task { () -> Result<SceneRenderCompletedFrame, Error> in
            do {
                return .success(try await session.render(.init(
                    mediaTimeSeconds: 0,
                    outputWidth: 4_096,
                    outputHeight: 2_160,
                    scalingMode: .stretch
                )))
            } catch {
                return .failure(error)
            }
        }

        var observedPendingFrame = false
        for _ in 0..<1_000 {
            if await session.snapshot().pendingFrameCount == 1 {
                observedPendingFrame = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(observedPendingFrame)

        await session.invalidate()
        switch await renderTask.value {
        case .success(let frame):
            frame.release()
            XCTFail("Invalidated session published a stale frame")
        case .failure(let error):
            XCTAssertEqual(error as? SceneRenderError, .sessionInvalidated)
        }
        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.pendingFrameCount, 0)
        XCTAssertTrue(snapshot.isInvalidated)
    }

    func testSnapshotRequestReturnsPNGFromCompletedFrame() async throws {
        let fixture = try makeRendererFixture(textureBytes: [255, 0, 0, 255])
        let session = try await fixture.makeSession()

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch,
            requestsSnapshot: true
        ))

        let png = try XCTUnwrap(frame.snapshotPNG)
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertFalse(frame.diagnostics.contains {
            $0.code == "renderer.snapshot-failed"
        })
        frame.release()
        await session.invalidate()
    }

    func testSnapshotFailureKeepsCompletedFrameAndAddsSnapshotDiagnostic() async throws {
        let fixture = try makeRendererFixture(textureBytes: [255, 0, 0, 255])
        let session = try await fixture.makeSession(limits: .init(
            snapshotReadbackBudgetBytes: 3
        ))

        let frame = try await session.render(.init(
            mediaTimeSeconds: 0,
            outputWidth: 1,
            outputHeight: 1,
            scalingMode: .stretch,
            requestsSnapshot: true
        ))
        let pixels = try await readBGRA8(frame.texture)

        XCTAssertNil(frame.snapshotPNG)
        XCTAssertEqual(Array(pixels), [0, 0, 255, 255])
        XCTAssertEqual(frame.status, .exact)
        XCTAssertEqual(frame.diagnostics.last, .init(
            severity: .warning,
            code: "renderer.snapshot-failed",
            arguments: ["resourceLimit.snapshotReadbackBytes"]
        ))
        frame.release()
        await session.invalidate()
    }

    func testSyntheticGoldenMatrix() async throws {
        let golden = try loadSyntheticGolden()
        XCTAssertEqual(golden.schemaVersion, 1)
        XCTAssertEqual(golden.tolerance, 1)
        try assertInstancePolicy(golden.instancePolicy)

        for testCase in golden.cases {
            let fixture = try makeGoldenFixture(id: testCase.id)
            let session = try await fixture.makeSession()
            let scalingMode = try XCTUnwrap(
                SceneOutputScalingMode(rawValue: testCase.scalingMode)
            )
            let expectedStatus = try XCTUnwrap(
                SceneRenderStatus(rawValue: testCase.status)
            )
            let request = SceneRenderFrameRequest(
                mediaTimeSeconds: testCase.mediaTimeSeconds,
                outputWidth: testCase.width,
                outputHeight: testCase.height,
                scalingMode: scalingMode
            )

            let first = try await session.render(request)
            let firstPixels = try await readBGRA8(first.texture)
            XCTAssertEqual(first.texture.width, testCase.width, testCase.id)
            XCTAssertEqual(first.texture.height, testCase.height, testCase.id)
            XCTAssertEqual(first.status, expectedStatus, testCase.id)
            XCTAssertEqual(first.drawCount, testCase.drawCount, testCase.id)
            XCTAssertEqual(
                first.skippedDrawCount,
                testCase.skippedDrawCount,
                testCase.id
            )
            first.release()

            let second = try await session.render(request)
            let secondPixels = try await readBGRA8(second.texture)
            XCTAssertEqual(
                second.texture.width,
                first.texture.width,
                testCase.id
            )
            XCTAssertEqual(
                second.texture.height,
                first.texture.height,
                testCase.id
            )
            XCTAssertEqual(second.status, first.status, testCase.id)
            XCTAssertEqual(second.drawCount, first.drawCount, testCase.id)
            XCTAssertEqual(
                second.skippedDrawCount,
                first.skippedDrawCount,
                testCase.id
            )
            XCTAssertEqual(secondPixels, firstPixels, testCase.id)
            for sample in testCase.samples {
                assertSample(
                    pixels: secondPixels,
                    width: testCase.width,
                    height: testCase.height,
                    sample: sample,
                    tolerance: golden.tolerance,
                    caseID: testCase.id
                )
            }

            second.release()
            await session.invalidate()
        }
    }

    private func makeRendererFixture(
        textureBytes: [UInt8],
        visible: Bool = true
    ) throws -> RendererFixture {
        try makeRendererFixture(
            textures: [.solid(textureBytes)],
            layers: [.init(textureIndex: 0, visible: visible)]
        )
    }

    private func makeGoldenFixture(id: String) throws -> RendererFixture {
        switch id {
        case "order-alpha-srgb":
            return try makeRendererFixture(
                textures: [
                    .solid([0, 0, 255, 255]),
                    .solid([255, 0, 0, 128])
                ],
                layers: [.init(textureIndex: 0), .init(textureIndex: 1)]
            )
        case "content-rect-top-left":
            return try makeRendererFixture(
                textures: [.init(
                    storageSize: (4, 2),
                    contentSize: (2, 2),
                    rgba: [
                        255, 0, 0, 255, 0, 255, 0, 255,
                        255, 0, 255, 255, 255, 0, 255, 255,
                        0, 0, 255, 255, 255, 255, 255, 255,
                        255, 0, 255, 255, 255, 0, 255, 255
                    ]
                )],
                layers: [.init(textureIndex: 0)],
                canvasSize: (2, 2)
            )
        case "fit-letterbox", "stretch-full-frame":
            return try makeRendererFixture(
                textures: [.solid([255, 0, 0, 255])],
                layers: [.init(textureIndex: 0, localSize: (2, 1))],
                canvasSize: (2, 1)
            )
        case "fill-center-crop":
            return try makeRendererFixture(
                textures: [.init(
                    storageSize: (2, 1),
                    contentSize: (2, 1),
                    rgba: [255, 0, 0, 255, 0, 0, 255, 255]
                )],
                layers: [.init(textureIndex: 0)],
                canvasSize: (2, 1)
            )
        case "hierarchy-opacity":
            return try makeRendererFixture(
                textures: [
                    .solid([0, 0, 0, 0]),
                    .solid([255, 0, 0, 255])
                ],
                layers: [
                    .init(textureIndex: 0, origin: (0, 0), opacity: 0.5),
                    .init(textureIndex: 1, opacity: 0.5, parentIndex: 0)
                ]
            )
        case "fixed-time-opacity":
            return try makeRendererFixture(
                textures: [.solid([255, 0, 0, 255])],
                layers: [.init(
                    textureIndex: 0,
                    animationBindings: [.init(
                        property: .opacity,
                        playbackMode: .single,
                        durationSeconds: 1,
                        isRelative: false,
                        startsPaused: false,
                        keyframes: [
                            .init(
                                timeSeconds: 0,
                                value: .scalar(0),
                                interpolation: .linear
                            ),
                            .init(
                                timeSeconds: 1,
                                value: .scalar(1),
                                interpolation: .linear
                            )
                        ]
                    )]
                )]
            )
        default:
            throw GoldenTestError.unknownCase(id)
        }
    }

    private func loadSyntheticGolden() throws -> SyntheticGolden {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appending(path: "Tests")
            .appending(path: "Fixtures")
            .appending(path: "SceneRenderer")
            .appending(path: "synthetic-scene-golden.json")
        return try JSONDecoder().decode(
            SyntheticGolden.self,
            from: Data(contentsOf: url)
        )
    }

    private func assertInstancePolicy(
        _ expected: SyntheticInstancePolicy
    ) throws {
        let entries = [
            ScenePackageFixtureEntry(
                path: "scene.json",
                data: Data(
                    #"{"general":{"orthogonalprojection":{"width":1,"height":1}},"objects":[{"id":20,"image":"models/base.json"},{"id":10,"image":"models/base.json","instance":20}]}"#.utf8
                )
            ),
            ScenePackageFixtureEntry(
                path: "models/base.json",
                data: Data(#"{"material":"materials/base.json"}"#.utf8)
            ),
            ScenePackageFixtureEntry(
                path: "materials/base.json",
                data: Data(#"{"texture":"base"}"#.utf8)
            ),
            ScenePackageFixtureEntry(
                path: "materials/base.tex",
                data: Data([0x54, 0x45, 0x58])
            )
        ]
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(
                entries: entries
            ))
        )
        let result = SceneRenderCompiler().compile(
            SceneGraphBuilder().build(resolver: resolver)
        )

        XCTAssertEqual(result.status.rawValue, expected.status)
        XCTAssertEqual(result.program?.drawCount, expected.survivingDrawCount)
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == expected.diagnosticCode
        })
    }

    private func assertSample(
        pixels: Data,
        width: Int,
        height: Int,
        sample: SyntheticGoldenSample,
        tolerance: Int,
        caseID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            (0..<width).contains(sample.x),
            caseID,
            file: file,
            line: line
        )
        XCTAssertTrue(
            (0..<height).contains(sample.y),
            caseID,
            file: file,
            line: line
        )
        let offset = (sample.y * width + sample.x) * 4
        let actual = Array(pixels[offset..<(offset + 4)])
        XCTAssertEqual(
            actual.count,
            sample.bgra.count,
            caseID,
            file: file,
            line: line
        )
        for (actualByte, expectedByte) in zip(actual, sample.bgra) {
            XCTAssertLessThanOrEqual(
                abs(Int(actualByte) - Int(expectedByte)),
                tolerance,
                caseID,
                file: file,
                line: line
            )
        }
    }

    private func makeRendererFixture(
        textures: [PixelTexture],
        layers: [PixelLayer],
        canvasSize: (Double, Double) = (1, 1)
    ) throws -> RendererFixture {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        guard SceneMetalPipelines.hasPackagedDefaultLibrary else {
            throw XCTSkip(
                "Metal pixel tests require swiftbuild so the metallib is packaged"
            )
        }
        XCTAssertFalse(textures.isEmpty)
        XCTAssertFalse(layers.isEmpty)
        let paths = textures.indices.map { "materials/image-\($0).tex" }
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(
                entries: zip(paths, textures).map { path, texture in
                    .init(path: path, data: texture.fixtureData)
                }
            ))
        )
        let resources = try paths.map { path in
            let resolution = resolver.resolve(.init(
                requestedPath: path,
                ownerPath: nil,
                role: .texture,
                key: "texture"
            ))
            let selected = try XCTUnwrap(resolution.selected)
            return SceneTextureResource(
                id: .init(kind: .texture, path: selected.canonicalPath),
                path: selected.canonicalPath,
                resolution: resolution
            )
        }
        let documentPath = try SceneVirtualPath(canonicalPath: "scene.json")
        let identities = layers.indices.map {
            SceneRenderNodeIdentity(
                nodeID: SceneNodeID(documentPath: documentPath, objectIndex: $0),
                instancePath: []
            )
        }
        let program = SceneRenderProgram(
            canvas: .init(width: canvasSize.0, height: canvasSize.1),
            fingerprint: "metal-pixel-test",
            nodeTemplates: zip(identities, layers).map { identity, layer in
                let texture = textures[layer.textureIndex]
                let width = layer.localSize?.0 ?? Double(texture.contentSize.0)
                let height = layer.localSize?.1 ?? Double(texture.contentSize.1)
                let origin = layer.origin ?? (width * 0.5, height * 0.5)
                return .init(
                    identity: identity,
                    parentIndex: layer.parentIndex,
                    baseProperties: .init(
                        origin: .init(x: origin.0, y: origin.1, z: 0),
                        pivot: .init(x: 0, y: 0, z: 0),
                        position: .init(x: 0, y: 0, z: 0),
                        scale: .init(x: layer.scale.0, y: layer.scale.1, z: 1),
                        rotationZ: 0,
                        opacity: layer.opacity,
                        visible: layer.visible,
                        enabled: true,
                        color: .init(red: 255, green: 255, blue: 255, alpha: 255),
                        zOrder: 0
                    ),
                    animationBindings: layer.animationBindings,
                    isSupported: true
                )
            },
            drawTemplates: zip(identities, layers).enumerated().map {
                drawIndex, pair in
                .init(
                    identity: pair.0,
                    sourceOrder: drawIndex,
                    effectiveZ: 0,
                    evaluationNodeIndex: drawIndex,
                    textureManifestIndex: pair.1.textureIndex,
                    localSize: pair.1.localSize.map {
                        .init(width: $0.0, height: $0.1)
                    }
                )
            },
            textureManifest: resources.enumerated().map { textureIndex, resource in
                .init(
                    resource: resource,
                    imageIndex: 0,
                    colorIntent: .colorSRGB,
                    dependentDrawIndices: layers.indices.filter {
                        layers[$0].textureIndex == textureIndex
                    }
                )
            }
        )
        let packageID = SceneTexturePackageID()
        return RendererFixture(
            device: device,
            program: program,
            store: try SceneTextureStore(device: device),
            context: .init(packageID: packageID, resolver: resolver)
        )
    }

    private func assertPixel(
        _ actual: Data,
        equalsBGRA expected: [UInt8],
        tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualByte, expectedByte) in zip(actual, expected) {
            XCTAssertLessThanOrEqual(
                abs(Int(actualByte) - Int(expectedByte)),
                tolerance,
                file: file,
                line: line
            )
        }
    }

    private func makeExternalTarget(
        device: any MTLDevice,
        width: Int,
        height: Int
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    private func readBGRA8(_ texture: any MTLTexture) async throws -> Data {
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm_srgb)
        let byteCount = texture.width * texture.height * 4
        let device = texture.device
        let buffer = try XCTUnwrap(device.makeBuffer(
            length: byteCount,
            options: .storageModeShared
        ))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: texture.width * 4,
            destinationBytesPerImage: byteCount
        )
        blit.endEncoding()
        try await commitAndWait(commandBuffer)
        return Data(bytes: buffer.contents(), count: byteCount)
    }

    private func commitAndWait(_ commandBuffer: any MTLCommandBuffer) async throws {
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
}

private struct PixelTexture {
    let storageSize: (Int32, Int32)
    let contentSize: (Int32, Int32)
    let rgba: [UInt8]

    static func solid(_ rgba: [UInt8]) -> PixelTexture {
        PixelTexture(storageSize: (1, 1), contentSize: (1, 1), rgba: rgba)
    }

    var fixtureData: Data {
        SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: storageSize,
            imageSize: contentSize,
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [.init(
                width: storageSize.0,
                height: storageSize.1,
                payload: Data(rgba)
            )])]
        )
    }
}

private struct PixelLayer {
    let textureIndex: Int
    let origin: (Double, Double)?
    let scale: (Double, Double)
    let localSize: (Double, Double)?
    let opacity: Double
    let visible: Bool
    let parentIndex: Int?
    let animationBindings: [SceneTypedAnimationTrack]

    init(
        textureIndex: Int,
        origin: (Double, Double)? = nil,
        scale: (Double, Double) = (1, 1),
        localSize: (Double, Double)? = nil,
        opacity: Double = 1,
        visible: Bool = true,
        parentIndex: Int? = nil,
        animationBindings: [SceneTypedAnimationTrack] = []
    ) {
        self.textureIndex = textureIndex
        self.origin = origin
        self.scale = scale
        self.localSize = localSize
        self.opacity = opacity
        self.visible = visible
        self.parentIndex = parentIndex
        self.animationBindings = animationBindings
    }
}

private struct SyntheticGolden: Decodable {
    let schemaVersion: Int
    let tolerance: Int
    let instancePolicy: SyntheticInstancePolicy
    let cases: [SyntheticGoldenCase]
}

private struct SyntheticInstancePolicy: Decodable {
    let diagnosticCode: String
    let status: String
    let survivingDrawCount: Int
}

private struct SyntheticGoldenCase: Decodable {
    let id: String
    let width: Int
    let height: Int
    let scalingMode: String
    let mediaTimeSeconds: Double
    let status: String
    let drawCount: Int
    let skippedDrawCount: Int
    let samples: [SyntheticGoldenSample]
}

private struct SyntheticGoldenSample: Decodable {
    let x: Int
    let y: Int
    let bgra: [UInt8]
}

private enum GoldenTestError: Error {
    case unknownCase(String)
}

private struct RendererFixture {
    let device: any MTLDevice
    let program: SceneRenderProgram
    let store: SceneTextureStore
    let context: SceneTexturePackageContext

    func makeSession(
        limits: SceneRenderLimits = .init()
    ) async throws -> SceneRenderSession {
        try await SceneRenderSession.prepare(
            program: program,
            device: device,
            textureStore: store,
            textureContext: context,
            limits: limits
        )
    }
}

private extension Data {
    init(repeating bytes: [UInt8], count: Int) {
        self.init((0..<count).flatMap { _ in bytes })
    }
}
