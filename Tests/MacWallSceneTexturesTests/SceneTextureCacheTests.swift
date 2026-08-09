import Foundation
import MacWallSceneAssets
import MacWallSceneGraph
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureCacheTests: XCTestCase {
    func testCacheKeyIncludesEveryStorageIdentityFieldButNotColorIntent() throws {
        let base = key(
            package: packageA,
            path: "materials/a.tex",
            offset: 10,
            bytes: 20,
            imageIndex: 0,
            policyVersion: 1,
            deviceRegistryID: 99
        )
        XCTAssertEqual(
            base,
            key(
                package: packageA,
                path: "materials/a.tex",
                offset: 10,
                bytes: 20,
                imageIndex: 0,
                policyVersion: 1,
                deviceRegistryID: 99
            )
        )

        XCTAssertNotEqual(base, key(package: packageB, path: "materials/a.tex"))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/b.tex"))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/a.tex", offset: 11))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/a.tex", bytes: 21))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/a.tex", imageIndex: 1))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/a.tex", policyVersion: 2))
        XCTAssertNotEqual(base, key(package: packageA, path: "materials/a.tex", deviceRegistryID: 100))

        let resourceID = SceneResourceID(
            kind: .texture,
            path: try SceneVirtualPath(canonicalPath: "materials/a.tex")
        )
        let colorRequest = SceneTextureRequest(
            packageID: packageA,
            resourceID: resourceID,
            imageIndex: 0,
            colorIntent: .colorSRGB
        )
        let dataRequest = SceneTextureRequest(
            packageID: packageA,
            resourceID: resourceID,
            imageIndex: 0,
            colorIntent: .dataLinear
        )
        XCTAssertEqual(
            key(
                package: colorRequest.packageID,
                path: colorRequest.resourceID.path.rawValue,
                offset: 10,
                bytes: 20,
                imageIndex: colorRequest.imageIndex,
                policyVersion: 1,
                deviceRegistryID: 99
            ),
            key(
                package: dataRequest.packageID,
                path: dataRequest.resourceID.path.rawValue,
                offset: 10,
                bytes: 20,
                imageIndex: dataRequest.imageIndex,
                policyVersion: 1,
                deviceRegistryID: 99
            )
        )
    }

    func testOwnedEntryCannotBeEvictedUntilGenerationRelease() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(
            textureValue(bytes: 100),
            residentBytes: 100,
            uploadPath: .directUncompressed,
            for: keyA,
            owner: generationA
        )

        XCTAssertTrue(cache.trimUnowned(toResidentBytes: 0).isEmpty)

        cache.releaseGeneration(generationA)
        XCTAssertEqual(
            cache.trimUnowned(toResidentBytes: 0).map(\.key),
            [keyA]
        )
    }

    func testSameKeyAddsGenerationOwnersWithoutDuplicateResidentBytes() {
        var cache = SceneTextureCache<FakeTextureValue>()
        let first = textureValue(bytes: 100)
        cache.install(
            first,
            residentBytes: 100,
            uploadPath: .softwareRGBA,
            for: keyA,
            owner: generationA
        )
        cache.install(
            textureValue(bytes: 200),
            residentBytes: 200,
            uploadPath: .encodedImageRGBA,
            for: keyA,
            owner: generationB
        )

        XCTAssertEqual(cache.value(for: keyA, owner: generationB), first)
        XCTAssertEqual(cache.snapshot().readyEntries, 1)
        XCTAssertEqual(cache.snapshot().residentBytes, 100)

        cache.releaseGeneration(generationA)
        XCTAssertTrue(cache.trimUnowned(toResidentBytes: 0).isEmpty)
        cache.releaseGeneration(generationB)
        XCTAssertEqual(cache.trimUnowned(toResidentBytes: 0).map(\.key), [keyA])
    }

    func testReleaseRemovesOnlyRequestedGenerationOwner() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(
            textureValue(bytes: 100),
            residentBytes: 100,
            uploadPath: .directUncompressed,
            for: keyA,
            owner: generationA
        )
        cache.install(
            textureValue(bytes: 200),
            residentBytes: 200,
            uploadPath: .directUncompressed,
            for: keyB,
            owner: generationB
        )

        cache.releaseGeneration(generationA)

        XCTAssertEqual(cache.trimUnowned(toResidentBytes: 100).map(\.key), [keyA])
        XCTAssertEqual(cache.value(for: keyB, owner: generationB), textureValue(bytes: 200))
    }

    func testTrimUsesMonotonicAccessOrdinals() {
        var cache = SceneTextureCache<FakeTextureValue>()
        let alpha = key(package: packageA, path: "materials/a.tex")
        let beta = key(package: packageA, path: "materials/b.tex")
        let gamma = key(package: packageA, path: "materials/c.tex")

        cache.install(textureValue(bytes: 10), residentBytes: 10, uploadPath: .directUncompressed, for: beta, owner: generationA)
        cache.install(textureValue(bytes: 10), residentBytes: 10, uploadPath: .directUncompressed, for: alpha, owner: generationA)
        cache.install(textureValue(bytes: 10), residentBytes: 10, uploadPath: .directUncompressed, for: gamma, owner: generationA)
        XCTAssertEqual(cache.value(for: gamma, owner: generationA), textureValue(bytes: 10))
        cache.releaseGeneration(generationA)

        XCTAssertEqual(
            cache.trimUnowned(toResidentBytes: 0).map(\.key),
            [beta, alpha, gamma]
        )
    }

    func testNewInstallIsMoreRecentThanAnOlderCacheHit() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(
            textureValue(bytes: 10),
            residentBytes: 10,
            uploadPath: .directUncompressed,
            for: keyA,
            owner: generationA
        )
        XCTAssertEqual(
            cache.value(for: keyA, owner: generationA),
            textureValue(bytes: 10)
        )
        cache.install(
            textureValue(bytes: 10),
            residentBytes: 10,
            uploadPath: .directUncompressed,
            for: keyB,
            owner: generationB
        )
        cache.releaseGeneration(generationA)
        cache.releaseGeneration(generationB)

        XCTAssertEqual(
            cache.trimUnowned(toResidentBytes: 10).map(\.key),
            [keyA]
        )
    }

    func testSaturatedOrdinalRebasesBeforeRecordingNewAccess() {
        var cache = SceneTextureCache<FakeTextureValue>(
            initialAccessOrdinal: UInt64.max - 2
        )
        cache.install(
            textureValue(bytes: 10),
            residentBytes: 10,
            uploadPath: .directUncompressed,
            for: keyA,
            owner: generationA
        )
        cache.install(
            textureValue(bytes: 10),
            residentBytes: 10,
            uploadPath: .directUncompressed,
            for: keyB,
            owner: generationB
        )
        XCTAssertEqual(
            cache.value(for: keyA, owner: generationA),
            textureValue(bytes: 10)
        )
        cache.releaseGeneration(generationA)
        cache.releaseGeneration(generationB)

        XCTAssertEqual(
            cache.trimUnowned(toResidentBytes: 10).map(\.key),
            [keyB]
        )
    }

    func testSoftTrimEvictsOnlyUnownedEntries() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(textureValue(bytes: 100), residentBytes: 100, uploadPath: .directUncompressed, for: keyA, owner: generationA)
        cache.install(textureValue(bytes: 50), residentBytes: 50, uploadPath: .directUncompressed, for: keyB, owner: generationB)
        cache.install(textureValue(bytes: 70), residentBytes: 70, uploadPath: .directUncompressed, for: keyC, owner: generationC)
        cache.releaseGeneration(generationB)
        cache.releaseGeneration(generationC)

        XCTAssertEqual(cache.trimUnowned(toResidentBytes: 170).map(\.key), [keyB])
        XCTAssertEqual(cache.snapshot().residentBytes, 170)
        XCTAssertEqual(cache.snapshot().unownedEntries, 1)
        XCTAssertEqual(cache.value(for: keyA, owner: generationA), textureValue(bytes: 100))
    }

    func testActiveGenerationSurvivesStagedInstallationFailure() {
        var cache = SceneTextureCache<FakeTextureValue>()
        let activeValue = textureValue(bytes: 100)
        cache.install(activeValue, residentBytes: 100, uploadPath: .directUncompressed, for: keyA, owner: generationA)

        let stagedValue: Result<FakeTextureValue, SceneTexturePipelineError> = .failure(.uploadFailed)
        if case let .success(value) = stagedValue {
            cache.install(value, residentBytes: 200, uploadPath: .directUncompressed, for: keyB, owner: generationB)
        }

        XCTAssertEqual(cache.value(for: keyA, owner: generationA), activeValue)
        XCTAssertNil(cache.value(for: keyB, owner: generationB))
        XCTAssertEqual(cache.snapshot().readyEntries, 1)
    }

    func testCacheHitUpdatesAccessAndCounters() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(textureValue(bytes: 100), residentBytes: 100, uploadPath: .directUncompressed, for: keyA, owner: generationA)

        XCTAssertEqual(cache.value(for: keyA, owner: generationB), textureValue(bytes: 100))
        XCTAssertNil(cache.value(for: keyB, owner: generationB))

        let snapshot = cache.snapshot()
        XCTAssertEqual(snapshot.cacheHits, 1)
        XCTAssertEqual(snapshot.cacheMisses, 1)
        XCTAssertEqual(snapshot.lastAccessOrdinal, 2)
    }

    func testSnapshotValuesAreDeterministicAfterEviction() {
        var cache = SceneTextureCache<FakeTextureValue>()
        cache.install(textureValue(bytes: 100), residentBytes: 100, uploadPath: .directUncompressed, for: keyA, owner: generationA)
        cache.install(textureValue(bytes: 50), residentBytes: 50, uploadPath: .directUncompressed, for: keyB, owner: generationB)
        cache.releaseGeneration(generationB)
        XCTAssertEqual(cache.trimUnowned(toResidentBytes: 100).map(\.key), [keyB])

        XCTAssertEqual(
            cache.snapshot(),
            SceneTextureCacheSnapshot(
                cacheHits: 0,
                cacheMisses: 0,
                readyEntries: 1,
                unownedEntries: 0,
                residentBytes: 100,
                evictions: 1,
                lastAccessOrdinal: 2
            )
        )
    }
}

private struct FakeTextureValue: Equatable, Sendable {
    let bytes: Int
}

private let packageA = SceneTexturePackageID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
)
private let packageB = SceneTexturePackageID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
)
private let generationA = SceneTextureGenerationID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
)
private let generationB = SceneTextureGenerationID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
)
private let generationC = SceneTextureGenerationID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
)

private let keyA = key(package: packageA, path: "materials/a.tex")
private let keyB = key(package: packageA, path: "materials/b.tex")
private let keyC = key(package: packageA, path: "materials/c.tex")

private func textureValue(bytes: Int) -> FakeTextureValue {
    FakeTextureValue(bytes: bytes)
}

private func key(
    package: SceneTexturePackageID,
    path: String,
    offset: UInt64 = 10,
    bytes: UInt64 = 20,
    imageIndex: Int = 0,
    policyVersion: Int = 1,
    deviceRegistryID: UInt64 = 99
) -> SceneTextureStorageKey {
    SceneTextureStorageKey(
        packageID: package,
        canonicalPath: path,
        entryRelativeOffset: offset,
        entryByteCount: bytes,
        imageIndex: imageIndex,
        uploadPolicyVersion: policyVersion,
        deviceRegistryID: deviceRegistryID
    )
}
