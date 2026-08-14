import Metal
import XCTest
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport
import MacWallSceneTextures
@testable import MacWallSceneRenderer

final class SceneRenderSessionTests: XCTestCase {
    func testPrepareAcquiresEveryManifestTextureAndReleasesGenerationExactlyOnce() async throws {
        let device = try systemDevice()
        let fixture = try makeFixture(
            device: device,
            textureEntries: [
                ("materials/a.tex", texture(red: 255, green: 0, blue: 0)),
                ("materials/b.tex", texture(red: 0, green: 255, blue: 0))
            ]
        )
        let program = try makeProgram(resources: fixture.resources)

        let session = try await SceneRenderSession.prepare(
            program: program,
            device: device,
            textureStore: fixture.store,
            textureContext: fixture.context
        )

        var snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.status, .exact)
        XCTAssertEqual(snapshot.survivingDrawIndices, [0, 1])
        XCTAssertEqual(snapshot.textureLeaseCount, 2)
        XCTAssertEqual(snapshot.deviceRegistryID, device.registryID)
        XCTAssertFalse(snapshot.isInvalidated)
        XCTAssertTrue(snapshot.diagnostics.isEmpty)

        let firstLease = try await session.textureLease(atManifestIndex: 0)
        XCTAssertEqual(firstLease.texture.device.registryID, device.registryID)
        XCTAssertEqual(firstLease.mipContentRegions, [
            .init(
                level: 0,
                storageExtent: .init(width: 1, height: 1),
                contentExtent: .init(width: 1, height: 1),
                contentRect: .init(u: 0, v: 0, width: 1, height: 1)
            )
        ])

        await session.invalidate()
        await session.invalidate()
        snapshot = await session.snapshot()
        XCTAssertTrue(snapshot.isInvalidated)
        XCTAssertEqual(snapshot.textureLeaseCount, 0)
        let storeSnapshot = await fixture.store.snapshot()
        XCTAssertEqual(storeSnapshot.readyEntries, 2)
        XCTAssertEqual(storeSnapshot.unownedEntries, 2)
    }

    func testPrepareDropsOnlyDrawsDependingOnMalformedTexture() async throws {
        let device = try systemDevice()
        let fixture = try makeFixture(
            device: device,
            textureEntries: [
                ("materials/good.tex", texture(red: 30, green: 60, blue: 90)),
                ("materials/bad.tex", malformedTexture())
            ]
        )
        let program = try makeProgram(resources: fixture.resources)

        let session = try await SceneRenderSession.prepare(
            program: program,
            device: device,
            textureStore: fixture.store,
            textureContext: fixture.context
        )

        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.status, .degraded)
        XCTAssertEqual(snapshot.survivingDrawIndices, [0])
        XCTAssertEqual(snapshot.textureLeaseCount, 1)
        XCTAssertEqual(snapshot.diagnostics, [
            .init(
                severity: .warning,
                code: "renderer.texture-load-failed",
                resourceID: fixture.resources[1].id,
                arguments: ["malformedDescriptor"]
            )
        ])
        await session.invalidate()
    }

    func testPrepareReturnsUnsupportedAndReleasesGenerationWhenEveryTextureFails() async throws {
        let device = try systemDevice()
        let fixture = try makeFixture(
            device: device,
            textureEntries: [
                ("materials/a.tex", malformedTexture()),
                ("materials/b.tex", malformedTexture())
            ]
        )
        let program = try makeProgram(resources: fixture.resources)

        let session = try await SceneRenderSession.prepare(
            program: program,
            device: device,
            textureStore: fixture.store,
            textureContext: fixture.context
        )

        let snapshot = await session.snapshot()
        XCTAssertEqual(snapshot.status, .unsupported)
        XCTAssertTrue(snapshot.survivingDrawIndices.isEmpty)
        XCTAssertEqual(snapshot.textureLeaseCount, 0)
        XCTAssertEqual(snapshot.diagnostics.map(\.resourceID), fixture.resources.map(\.id))
        let storeSnapshot = await fixture.store.snapshot()
        XCTAssertEqual(storeSnapshot.readyEntries, 0)
        XCTAssertEqual(storeSnapshot.unownedEntries, 0)
        await session.invalidate()
    }

    func testPrepareMapsCancellationWithoutPublishingPartialSession() async throws {
        let device = try systemDevice()
        let fixture = try makeFixture(
            device: device,
            textureEntries: [
                ("materials/a.tex", texture(red: 255, green: 255, blue: 255))
            ]
        )
        let program = try makeProgram(resources: fixture.resources)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SceneRenderSession.prepare(
                program: program,
                device: device,
                textureStore: fixture.store,
                textureContext: fixture.context
            )
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? SceneRenderError, .cancelled)
        }
        let storeSnapshot = await fixture.store.snapshot()
        XCTAssertEqual(storeSnapshot.readyEntries, 0)
        XCTAssertEqual(storeSnapshot.loadingEntries, 0)
    }

    func testPrepareTreatsTextureResourceLimitAsFatal() async throws {
        let device = try systemDevice()
        var textureLimits = MacWallSceneTextures.SceneTextureLimits()
        textureLimits.singlePayloadBytes = 1
        let fixture = try makeFixture(
            device: device,
            textureEntries: [
                ("materials/a.tex", texture(red: 255, green: 255, blue: 255))
            ],
            limits: textureLimits
        )
        let program = try makeProgram(resources: fixture.resources)

        do {
            _ = try await SceneRenderSession.prepare(
                program: program,
                device: device,
                textureStore: fixture.store,
                textureContext: fixture.context
            )
            XCTFail("Expected texture resource limit")
        } catch {
            XCTAssertEqual(
                error as? SceneRenderError,
                .texturePipeline(.resourceLimit(.payloadBytes))
            )
        }
        let storeSnapshot = await fixture.store.snapshot()
        XCTAssertEqual(storeSnapshot.loadingEntries, 0)
        XCTAssertEqual(storeSnapshot.readyEntries, 0)
    }

    func testPrepareRejectsTextureStoreCreatedForAnotherMetalDevice() async throws {
        let devices = MTLCopyAllDevices()
        guard devices.count > 1 else {
            throw XCTSkip("Cross-device validation requires at least two Metal devices")
        }
        let fixture = try makeFixture(
            device: devices[0],
            textureEntries: [
                ("materials/a.tex", texture(red: 255, green: 255, blue: 255))
            ]
        )
        let program = try makeProgram(resources: fixture.resources)

        do {
            _ = try await SceneRenderSession.prepare(
                program: program,
                device: devices[1],
                textureStore: fixture.store,
                textureContext: fixture.context
            )
            XCTFail("Expected incompatible device")
        } catch {
            XCTAssertEqual(error as? SceneRenderError, .incompatibleDevice)
        }
    }

    private func systemDevice() throws -> any MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makeFixture(
        device: any MTLDevice,
        textureEntries: [(String, Data)],
        limits: MacWallSceneTextures.SceneTextureLimits = .init()
    ) throws -> SessionTextureFixture {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(
                entries: textureEntries.map {
                    ScenePackageFixtureEntry(path: $0.0, data: $0.1)
                }
            ))
        )
        let resources = try textureEntries.map { path, _ in
            let resolution = resolver.resolve(SceneAssetRequest(
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
        let packageID = SceneTexturePackageID()
        return SessionTextureFixture(
            store: try SceneTextureStore(device: device, limits: limits),
            context: SceneTexturePackageContext(
                packageID: packageID,
                resolver: resolver
            ),
            resources: resources
        )
    }

    private func makeProgram(
        resources: [SceneTextureResource]
    ) throws -> SceneRenderProgram {
        let documentPath = try SceneVirtualPath(canonicalPath: "scene.json")
        let nodes = resources.indices.map { index in
            SceneRenderNodeTemplate(
                identity: .init(
                    nodeID: .init(documentPath: documentPath, objectIndex: index),
                    instancePath: []
                ),
                parentIndex: nil,
                baseProperties: .identity,
                animationBindings: [],
                isSupported: true
            )
        }
        let draws = nodes.indices.map { index in
            SceneRenderDrawTemplate(
                identity: nodes[index].identity,
                sourceOrder: index,
                effectiveZ: Double(index),
                evaluationNodeIndex: index,
                textureManifestIndex: index
            )
        }
        let manifest = resources.indices.map { index in
            SceneRenderTextureManifestEntry(
                resource: resources[index],
                imageIndex: 0,
                colorIntent: .colorSRGB,
                dependentDrawIndices: [index]
            )
        }
        return SceneRenderProgram(
            canvas: .init(width: 1920, height: 1080),
            fingerprint: "session-test",
            nodeTemplates: nodes,
            drawTemplates: draws,
            textureManifest: manifest
        )
    }

    private func texture(red: UInt8, green: UInt8, blue: UInt8) -> Data {
        SceneTextureFixtureBuilder.make(
            formatRawValue: 0,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 0),
            images: [.init(mipmaps: [.init(
                width: 1,
                height: 1,
                payload: Data([red, green, blue, 255])
            )])]
        )
    }

    private func malformedTexture() -> Data {
        Data("TEXV0005\0TEXI0001\0".utf8)
    }
}

private struct SessionTextureFixture {
    let store: SceneTextureStore
    let context: SceneTexturePackageContext
    let resources: [SceneTextureResource]
}
