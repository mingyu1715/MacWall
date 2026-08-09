import CryptoKit
import Foundation
import Metal
import XCTest
@testable import MacWallSceneTextures
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport

final class SceneLocalFixtureTextureTests: XCTestCase {
    func testNoAvailableFixedFixtureIsAbsent() {
        XCTAssertEqual(
            localFixtureAvailability(availableIDs: []),
            .absent
        )
    }

    func testOneAvailableFixedFixtureReportsEveryMissingIDSorted() {
        XCTAssertEqual(
            localFixtureAvailability(
                availableIDs: [.fixture3516106265]
            ),
            .partial(missingIDs: ["2174863503", "2834933421"])
        )
    }

    func testTwoAvailableFixedFixturesReportMissingID() {
        XCTAssertEqual(
            localFixtureAvailability(
                availableIDs: [
                    .fixture3516106265,
                    .fixture2174863503
                ]
            ),
            .partial(missingIDs: ["2834933421"])
        )
    }

    func testAllAvailableFixedFixturesAreCompleteAndSorted() {
        XCTAssertEqual(
            localFixtureAvailability(
                availableIDs: Set(FixedWorkshopID.allCases)
            ),
            .complete(FixedWorkshopID.sorted)
        )
    }

    func testCatalogValidationRequiresSchemaOne() {
        XCTAssertThrowsError(
            try validatedFixtures(
                in: makeCatalog(
                    schemaVersion: 2,
                    ids: FixedWorkshopID.sorted.map(\.rawValue)
                )
            )
        )
    }

    func testCatalogValidationReturnsTheExactFixedSetSorted() throws {
        let validated = try validatedFixtures(
            in: makeCatalog(ids: FixedWorkshopID.sorted.reversed().map(\.rawValue))
        )

        XCTAssertEqual(
            validated.map(\.workshopID),
            FixedWorkshopID.sorted
        )
    }

    func testCatalogValidationRejectsDuplicateID() {
        XCTAssertThrowsError(
            try validatedFixtures(
                in: makeCatalog(ids: [
                    "2174863503",
                    "2174863503",
                    "2834933421"
                ])
            )
        )
    }

    func testCatalogValidationRejectsExtraID() {
        XCTAssertThrowsError(
            try validatedFixtures(
                in: makeCatalog(ids: [
                    "2174863503",
                    "2834933421",
                    "3516106265",
                    "9999999999"
                ])
            )
        )
    }

    func testCatalogValidationRejectsPathLikeID() {
        XCTAssertThrowsError(
            try validatedFixtures(
                in: makeCatalog(ids: [
                    "2174863503",
                    "2834933421",
                    "../3516106265"
                ])
            )
        )
    }

    func testCatalogValidationRejectsMissingID() {
        XCTAssertThrowsError(
            try validatedFixtures(
                in: makeCatalog(ids: [
                    "2174863503",
                    "2834933421"
                ])
            )
        )
    }

    func testCanonicalCatalogEncodingIsByteIdentical() throws {
        let catalog = makeCatalog(
            ids: FixedWorkshopID.sorted.reversed().map(\.rawValue)
        )

        let first = try canonicalCatalogData(catalog)
        let second = try canonicalCatalogData(catalog)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.last, 0x0A)
        XCTAssertNotEqual(first.dropLast().last, 0x0A)
    }

    func testCanonicalCatalogContainsNoPathOrPayloadData() throws {
        let bytes = try canonicalCatalogData(
            makeCatalog(ids: FixedWorkshopID.sorted.map(\.rawValue))
        )
        let forbidden = [
            "/Users/",
            repositoryRoot.path,
            ".tex",
            "materials/example.tex",
            "fixture-payload-secret"
        ]

        for (index, value) in forbidden.enumerated() {
            XCTAssertNil(
                bytes.range(of: Data(value.utf8)),
                "forbidden-value-index \(index)"
            )
        }
    }

    func testCatalogArithmeticRejectsUnclassifiedTextureResource() {
        XCTAssertThrowsError(
            try validateClassifiedTextureCount(
                workshopID: .fixture2174863503,
                textureResourceCount: 3,
                uploadPathCounts: ["directUncompressed": 1],
                unsupportedCounts: ["animation": 1],
                outcomeCount: 2
            )
        )
    }

    func testCatalogArithmeticAcceptsOnlySupportedAndTypedUnsupportedResources() throws {
        try validateClassifiedTextureCount(
            workshopID: .fixture2174863503,
            textureResourceCount: 3,
            uploadPathCounts: ["directUncompressed": 1, "encodedImageRGBA": 1],
            unsupportedCounts: ["animation": 1],
            outcomeCount: 3
        )
    }

    func testLocalSceneTexturesMatchTrackedAggregateCatalog() async throws {
        try await runLocalSceneTextureGate()
    }

    private func makeCatalog(
        schemaVersion: Int = 1,
        ids: [String]
    ) -> LocalSceneTextureCatalog {
        LocalSceneTextureCatalog(
            schemaVersion: schemaVersion,
            capabilityProfile: localCatalogCapabilityProfile,
            fixtures: ids.map { id in
                LocalSceneTextureFixture(
                    workshopID: id,
                    packageVersion: "PKGV0008",
                    textureResourceCount: 1,
                    formatCounts: ["0": 1],
                    containerCounts: ["TEXB0003": 1],
                    uploadPathCounts: ["directUncompressed": 1],
                    unsupportedCounts: [:],
                    logicalPayloadBytes: 4
                )
            }
        )
    }
}

private let localCatalogCapabilityProfile =
    "bc-compression=true;logical-bytes=unaligned;policy=1"
private let maximumPackageReadBytes: UInt64 = 64 * 1_024 * 1_024
private let packageHashReadBytes = 1 * 1_024 * 1_024

private var repositoryRoot: URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private var localCatalogURL: URL {
    repositoryRoot
        .appending(path: "Tests")
        .appending(path: "Fixtures")
        .appending(path: "SceneTextures")
        .appending(path: "local-scene-texture-catalog.json")
}

private enum FixedWorkshopID: String, CaseIterable {
    case fixture2174863503 = "2174863503"
    case fixture2834933421 = "2834933421"
    case fixture3516106265 = "3516106265"

    static let sorted = allCases.sorted { $0.rawValue < $1.rawValue }
}

private struct LocalSceneTextureCatalog: Codable, Equatable {
    let schemaVersion: Int
    let capabilityProfile: String
    let fixtures: [LocalSceneTextureFixture]
}

private struct LocalSceneTextureFixture: Codable, Equatable {
    let workshopID: String
    let packageVersion: String
    let textureResourceCount: Int
    let formatCounts: [String: Int]
    let containerCounts: [String: Int]
    let uploadPathCounts: [String: Int]
    let unsupportedCounts: [String: Int]
    let logicalPayloadBytes: Int
}

private struct ValidatedLocalSceneTextureFixture {
    let workshopID: FixedWorkshopID
    let fixture: LocalSceneTextureFixture
}

private enum LocalFixtureAvailability: Equatable {
    case absent
    case partial(missingIDs: [String])
    case complete([FixedWorkshopID])
}

private enum LocalFixtureCatalogError: Error, Equatable {
    case invalidSchemaVersion(Int)
    case invalidCapabilityProfile(String)
    case invalidFixtureIDs([String])
    case missingFixtures([String])
}

private enum LocalTextureGateError: Error {
    case missingGraphDocument(String)
    case unresolvedTexture(fixtureID: String, textureIndex: Int)
    case missingPlannedTexture(fixtureID: String, textureIndex: Int)
    case unexpectedPipelineError(
        fixtureID: String,
        textureIndex: Int,
        stage: String,
        category: String
    )
    case unexpectedFixtureOperation(
        fixtureID: String,
        textureIndex: Int?,
        stage: String
    )
    case unsupportedTextureAcquired(
        fixtureID: String,
        textureIndex: Int,
        category: String
    )
    case classifiedTextureCountMismatch(
        fixtureID: String,
        expected: Int,
        classified: Int,
        outcomes: Int
    )
    case logicalPayloadOverflow
    case packageReadExceededMaximum(UInt64)
    case packageReadCoveredEntireFile
    case previewPayloadRead(String)
    case packageByteCountChanged
    case packageFingerprintChanged(String)
    case catalogUpdateFailed
}

private struct PackageFingerprint: Equatable {
    let byteCount: UInt64
    let sha256: Data
}

private enum PlannedTextureOutcome {
    case supported(SceneTextureLoadPlan, mipmapLevelCount: Int)
    case unsupported(String)
}

private struct PlannedLocalFixture {
    let aggregate: LocalSceneTextureFixture
    let outcomes: [SceneResourceID: PlannedTextureOutcome]
    let textureEntryPaths: [String]
}

private func localFixtureAvailability(
    availableIDs: Set<FixedWorkshopID>
) -> LocalFixtureAvailability {
    guard !availableIDs.isEmpty else {
        return .absent
    }
    let missingIDs = FixedWorkshopID.sorted.filter {
        !availableIDs.contains($0)
    }
    guard missingIDs.isEmpty else {
        return .partial(missingIDs: missingIDs.map(\.rawValue))
    }
    return .complete(FixedWorkshopID.sorted)
}

private func validatedFixtures(
    in catalog: LocalSceneTextureCatalog
) throws -> [ValidatedLocalSceneTextureFixture] {
    guard catalog.schemaVersion == 1 else {
        throw LocalFixtureCatalogError.invalidSchemaVersion(
            catalog.schemaVersion
        )
    }
    guard catalog.capabilityProfile == localCatalogCapabilityProfile else {
        throw LocalFixtureCatalogError.invalidCapabilityProfile(
            catalog.capabilityProfile
        )
    }

    let expectedIDs = FixedWorkshopID.sorted.map(\.rawValue)
    let actualIDs = catalog.fixtures.map(\.workshopID).sorted()
    guard actualIDs == expectedIDs else {
        throw LocalFixtureCatalogError.invalidFixtureIDs(actualIDs)
    }

    let fixturesByID = Dictionary(
        uniqueKeysWithValues: catalog.fixtures.map {
            ($0.workshopID, $0)
        }
    )
    return FixedWorkshopID.sorted.compactMap { workshopID in
        fixturesByID[workshopID.rawValue].map {
            ValidatedLocalSceneTextureFixture(
                workshopID: workshopID,
                fixture: $0
            )
        }
    }
}

private func canonicalCatalogData(
    _ catalog: LocalSceneTextureCatalog
) throws -> Data {
    let normalized = LocalSceneTextureCatalog(
        schemaVersion: catalog.schemaVersion,
        capabilityProfile: catalog.capabilityProfile,
        fixtures: catalog.fixtures.sorted {
            $0.workshopID < $1.workshopID
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [
        .prettyPrinted,
        .sortedKeys,
        .withoutEscapingSlashes
    ]
    var data = try encoder.encode(normalized)
    while data.last == 0x0A || data.last == 0x0D {
        data.removeLast()
    }
    data.append(0x0A)
    return data
}

private func runLocalSceneTextureGate() async throws {
    if ProcessInfo.processInfo.environment[
        "MACWALL_UPDATE_LOCAL_SCENE_TEXTURE_CATALOG"
    ] == "1" {
        try writeLocalCatalog()
    }

    let trackedBytes = try Data(contentsOf: localCatalogURL)
    let catalog = try JSONDecoder().decode(
        LocalSceneTextureCatalog.self,
        from: trackedBytes
    )
    let trackedFixtures = try validatedFixtures(in: catalog)
    XCTAssertEqual(trackedBytes, try canonicalCatalogData(catalog))

    let availableIDs = Set(FixedWorkshopID.sorted.filter {
        FileManager.default.fileExists(
            atPath: packageURL(for: $0).path
        )
    })
    let activeFixtureIDs: [FixedWorkshopID]
    switch localFixtureAvailability(availableIDs: availableIDs) {
    case .absent:
        throw XCTSkip("Local Workshop scene fixtures are not available.")
    case let .partial(missingIDs):
        XCTFail(
            "Local Workshop scene fixtures are partially available; "
                + "missing fixed fixture IDs: "
                + missingIDs.joined(separator: ", ")
        )
        return
    case let .complete(workshopIDs):
        activeFixtureIDs = workshopIDs
    }

    guard let device = MTLCreateSystemDefaultDevice() else {
        XCTFail("The local fixture GPU gate requires a default Metal device.")
        return
    }

    let trackedByID = Dictionary(
        uniqueKeysWithValues: trackedFixtures.map {
            ($0.workshopID, $0.fixture)
        }
    )
    for workshopID in activeFixtureIDs {
        let before = try packageFingerprint(for: workshopID)
        let first = try planLocalFixture(
            workshopID: workshopID,
            expectedPackageByteCount: before.byteCount
        )
        try await validateActualGPUTextures(
            workshopID: workshopID,
            device: device,
            expected: first,
            expectedPackageByteCount: before.byteCount
        )
        let second = try planLocalFixture(
            workshopID: workshopID,
            expectedPackageByteCount: before.byteCount
        )

        XCTAssertEqual(
            first.aggregate,
            trackedByID[workshopID],
            workshopID.rawValue
        )
        XCTAssertEqual(
            try canonicalFixtureData(first.aggregate),
            try canonicalFixtureData(second.aggregate),
            workshopID.rawValue
        )
        assertCatalogRedaction(
            trackedBytes,
            textureEntryPaths: first.textureEntryPaths,
            workshopID: workshopID.rawValue
        )
        try validateUnchangedPackageFingerprint(
            before: before,
            after: packageFingerprint(for: workshopID),
            workshopID: workshopID
        )
    }
}

private func writeLocalCatalog() throws {
    let missingIDs = FixedWorkshopID.sorted.filter {
        !FileManager.default.fileExists(
            atPath: packageURL(for: $0).path
        )
    }
    guard missingIDs.isEmpty else {
        throw LocalFixtureCatalogError.missingFixtures(
            missingIDs.map(\.rawValue)
        )
    }

    let beforeFingerprints = try fixedPackageFingerprints()
    let updateResult: Result<Void, LocalTextureGateError>
    do {
        let catalog = LocalSceneTextureCatalog(
            schemaVersion: 1,
            capabilityProfile: localCatalogCapabilityProfile,
            fixtures: try FixedWorkshopID.sorted.map { workshopID in
                guard let fingerprint = beforeFingerprints[workshopID] else {
                    throw LocalTextureGateError.catalogUpdateFailed
                }
                return try planLocalFixture(
                    workshopID: workshopID,
                    expectedPackageByteCount: fingerprint.byteCount
                ).aggregate
            }
        )
        try FileManager.default.createDirectory(
            at: localCatalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try canonicalCatalogData(catalog).write(
            to: localCatalogURL,
            options: .atomic
        )
        updateResult = .success(())
    } catch let error as LocalTextureGateError {
        updateResult = .failure(error)
    } catch {
        updateResult = .failure(.catalogUpdateFailed)
    }

    let afterFingerprints = try fixedPackageFingerprints()
    for workshopID in FixedWorkshopID.sorted {
        guard let before = beforeFingerprints[workshopID],
              let after = afterFingerprints[workshopID] else {
            throw LocalTextureGateError.catalogUpdateFailed
        }
        try validateUnchangedPackageFingerprint(
            before: before,
            after: after,
            workshopID: workshopID
        )
    }
    try updateResult.get()
}

private func planLocalFixture(
    workshopID: FixedWorkshopID,
    expectedPackageByteCount: UInt64
) throws -> PlannedLocalFixture {
    let url = packageURL(for: workshopID)
    let previewRanges = try previewPayloadRanges(
        packageURL: url,
        workshopID: workshopID
    )
    let recording = RecordingSceneByteSource(
        base: try SceneFileByteSource(url: url)
    )
    guard recording.byteCount == expectedPackageByteCount else {
        throw LocalTextureGateError.packageByteCountChanged
    }
    let resolver = try ScenePackageAssetResolver.open(source: recording)
    let graphResult = SceneGraphBuilder().build(resolver: resolver)
    guard let document = graphResult.document else {
        throw LocalTextureGateError.missingGraphDocument(
            workshopID.rawValue
        )
    }
    let textureResources = document.resources.compactMap {
        resource -> SceneTextureResource? in
        guard case let .texture(texture) = resource else {
            return nil
        }
        return texture
    }.sorted { $0.id < $1.id }

    let limits = MacWallSceneTextures.SceneTextureLimits()
    let planner = SceneTextureLoadPlanner(
        capabilities: fixedCatalogCapabilities,
        limits: limits
    )
    var formatCounts: [String: Int] = [:]
    var containerCounts: [String: Int] = [:]
    var uploadPathCounts: [String: Int] = [:]
    var unsupportedCounts: [String: Int] = [:]
    var logicalPayloadBytes = 0
    var outcomes: [SceneResourceID: PlannedTextureOutcome] = [:]
    var entryPaths: [String] = []

    for (textureIndex, resource) in textureResources.enumerated() {
        guard resource.resolution.kind == .package,
              let selected = resource.resolution.selected else {
            throw LocalTextureGateError.unresolvedTexture(
                fixtureID: workshopID.rawValue,
                textureIndex: textureIndex
            )
        }
        let path = selected.canonicalPath.rawValue
        entryPaths.append(path)
        let source: any SceneByteSource
        let inspection: SceneTextureInspection
        do {
            source = try resolver.source(for: selected)
            inspection = try SceneTextureFormatReader().inspect(
                source: source,
                path: path
            )
        } catch {
            throw LocalTextureGateError.unexpectedFixtureOperation(
                fixtureID: workshopID.rawValue,
                textureIndex: textureIndex,
                stage: "inspect"
            )
        }

        switch inspection {
        case let .unsupported(metadata):
            let category = unsupportedCategory(for: metadata)
            unsupportedCounts[category, default: 0] += 1
            outcomes[resource.id] = .unsupported(category)

        case let .parsed(descriptor):
            formatCounts[String(descriptor.formatRawValue), default: 0] += 1
            containerCounts[descriptor.declaredContainer, default: 0] += 1
            let plan: SceneTextureLoadPlan
            do {
                plan = try planner.makePlan(
                    descriptor: descriptor,
                    imageIndex: 0,
                    colorIntent: .dataLinear
                )
            } catch let error as SceneTexturePipelineError {
                if let category = unsupportedCategory(for: error) {
                    unsupportedCounts[category, default: 0] += 1
                    outcomes[resource.id] = .unsupported(category)
                } else {
                    throw LocalTextureGateError.unexpectedPipelineError(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        stage: "plan",
                        category: stablePipelineErrorCategory(error)
                    )
                }
                continue
            } catch {
                throw LocalTextureGateError.unexpectedFixtureOperation(
                    fixtureID: workshopID.rawValue,
                    textureIndex: textureIndex,
                    stage: "plan"
                )
            }

            do {
                let prepared = try preparedUpload(
                    plan: plan,
                    descriptor: descriptor,
                    source: source,
                    limits: limits
                )
                uploadPathCounts[prepared.uploadPath.rawValue, default: 0] += 1
                logicalPayloadBytes = try checkedLogicalPayloadSum(
                    logicalPayloadBytes,
                    prepared.mips.map { $0.bytes.count }
                )
                outcomes[resource.id] = .supported(
                    plan,
                    mipmapLevelCount: descriptor.images[0].mipmaps.count
                )
            } catch let error as SceneTexturePipelineError {
                if let category = unsupportedCategory(for: error) {
                    unsupportedCounts[category, default: 0] += 1
                    outcomes[resource.id] = .unsupported(category)
                } else {
                    throw LocalTextureGateError.unexpectedPipelineError(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        stage: "prepare",
                        category: stablePipelineErrorCategory(error)
                    )
                }
            } catch {
                throw LocalTextureGateError.unexpectedFixtureOperation(
                    fixtureID: workshopID.rawValue,
                    textureIndex: textureIndex,
                    stage: "prepare"
                )
            }
        }
    }

    try validateClassifiedTextureCount(
        workshopID: workshopID,
        textureResourceCount: textureResources.count,
        uploadPathCounts: uploadPathCounts,
        unsupportedCounts: unsupportedCounts,
        outcomeCount: outcomes.count
    )

    try validateReadPolicy(
        recording,
        previewRanges: previewRanges,
        workshopID: workshopID
    )
    return PlannedLocalFixture(
        aggregate: LocalSceneTextureFixture(
            workshopID: workshopID.rawValue,
            packageVersion: document.package.version,
            textureResourceCount: textureResources.count,
            formatCounts: formatCounts,
            containerCounts: containerCounts,
            uploadPathCounts: uploadPathCounts,
            unsupportedCounts: unsupportedCounts,
            logicalPayloadBytes: logicalPayloadBytes
        ),
        outcomes: outcomes,
        textureEntryPaths: entryPaths
    )
}

private func stablePipelineErrorCategory(
    _ error: SceneTexturePipelineError
) -> String {
    switch error {
    case .invalidRequest:
        "invalidRequest"
    case let .unsupportedDescriptor(kind):
        "unsupportedDescriptor.\(kind.rawValue)"
    case .unsupportedAnimation:
        "unsupportedAnimation"
    case .unsupportedVideo:
        "unsupportedVideo"
    case .unsupportedMultiImage:
        "unsupportedMultiImage"
    case let .unsupportedPixelFormat(rawValue):
        "unsupportedPixelFormat.\(rawValue)"
    case .malformedDescriptor:
        "malformedDescriptor"
    case .malformedPayload:
        "malformedPayload"
    case let .resourceLimit(limit):
        "resourceLimit.\(limit.rawValue)"
    case .decodeFailed:
        "decodeFailed"
    case .allocationFailed:
        "allocationFailed"
    case .uploadFailed:
        "uploadFailed"
    case .uploadTimedOut:
        "uploadTimedOut"
    case .cancelled:
        "cancelled"
    }
}

private func preparedUpload(
    plan: SceneTextureLoadPlan,
    descriptor: SceneTextureDescriptor,
    source: any SceneByteSource,
    limits: MacWallSceneTextures.SceneTextureLimits
) throws -> SceneTexturePreparedSource {
    let prepared = try SceneTexturePayloadLoader().prepare(
        plan: plan,
        descriptor: descriptor,
        source: source,
        limits: limits
    )
    switch prepared {
    case .upload:
        return prepared
    case let .encodedImages(encodedMips):
        return try SceneTextureImageDecoder().decode(
            encodedMips: encodedMips,
            expectedContentExtents: plan.mips.map(\.contentExtent),
            storageExtents: plan.mips.map(\.storageExtent),
            limits: limits
        )
    }
}

private func validateActualGPUTextures(
    workshopID: FixedWorkshopID,
    device: any MTLDevice,
    expected: PlannedLocalFixture,
    expectedPackageByteCount: UInt64
) async throws {
    let url = packageURL(for: workshopID)
    let previewRanges = try previewPayloadRanges(
        packageURL: url,
        workshopID: workshopID
    )
    let recording = RecordingSceneByteSource(
        base: try SceneFileByteSource(url: url)
    )
    guard recording.byteCount == expectedPackageByteCount else {
        throw LocalTextureGateError.packageByteCountChanged
    }
    let resolver = try ScenePackageAssetResolver.open(source: recording)
    let graphResult = SceneGraphBuilder().build(resolver: resolver)
    guard let document = graphResult.document else {
        throw LocalTextureGateError.missingGraphDocument(
            workshopID.rawValue
        )
    }
    let resources = document.resources.compactMap {
        resource -> SceneTextureResource? in
        guard case let .texture(texture) = resource else {
            return nil
        }
        return texture
    }.sorted { $0.id < $1.id }
    let store = try SceneTextureStore(device: device)
    let generation = await store.makeGeneration()
    let packageID = SceneTexturePackageID()

    do {
        for (textureIndex, resource) in resources.enumerated() {
            let diagnostic = "fixture \(workshopID.rawValue) "
                + "texture-index \(textureIndex)"
            guard let outcome = expected.outcomes[resource.id] else {
                throw LocalTextureGateError.missingPlannedTexture(
                    fixtureID: workshopID.rawValue,
                    textureIndex: textureIndex
                )
            }
            let request = SceneTextureRequest(
                packageID: packageID,
                resourceID: resource.id,
                imageIndex: 0,
                colorIntent: .dataLinear
            )
            switch outcome {
            case let .supported(plan, mipmapLevelCount):
                let lease: SceneTextureLease
                do {
                    lease = try await store.acquire(
                        request,
                        resource: resource,
                        resolver: resolver,
                        for: generation
                    )
                } catch let error as SceneTexturePipelineError {
                    throw LocalTextureGateError.unexpectedPipelineError(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        stage: "gpu-acquire",
                        category: stablePipelineErrorCategory(error)
                    )
                } catch {
                    throw LocalTextureGateError.unexpectedFixtureOperation(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        stage: "gpu-acquire"
                    )
                }
                XCTAssertEqual(
                    lease.texture.storageMode,
                    .private,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.texture.mipmapLevelCount,
                    mipmapLevelCount,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.mipmapLevelCount,
                    mipmapLevelCount,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.texture.width,
                    plan.storageExtent.width,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.texture.height,
                    plan.storageExtent.height,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.storageExtent,
                    plan.storageExtent,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.contentExtent,
                    plan.contentExtent,
                    diagnostic
                )
                XCTAssertEqual(
                    lease.contentRect,
                    plan.contentRect,
                    diagnostic
                )
                XCTAssertGreaterThan(
                    lease.residentBytes,
                    0,
                    diagnostic
                )

            case let .unsupported(expectedCategory):
                let before = await store.snapshot()
                let acquisition: Result<SceneTextureLease, Error>
                do {
                    acquisition = .success(try await store.acquire(
                        request,
                        resource: resource,
                        resolver: resolver,
                        for: generation
                    ))
                } catch {
                    acquisition = .failure(error)
                }
                switch acquisition {
                case .success:
                    throw LocalTextureGateError.unsupportedTextureAcquired(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        category: expectedCategory
                    )
                case let .failure(error as SceneTexturePipelineError):
                    guard let actualCategory = unsupportedCategory(for: error) else {
                        throw LocalTextureGateError.unexpectedPipelineError(
                            fixtureID: workshopID.rawValue,
                            textureIndex: textureIndex,
                            stage: "gpu-unsupported",
                            category: stablePipelineErrorCategory(error)
                        )
                    }
                    XCTAssertEqual(
                        actualCategory,
                        expectedCategory,
                        diagnostic
                    )
                case .failure:
                    throw LocalTextureGateError.unexpectedFixtureOperation(
                        fixtureID: workshopID.rawValue,
                        textureIndex: textureIndex,
                        stage: "gpu-unsupported"
                    )
                }
                let after = await store.snapshot()
                XCTAssertEqual(
                    after.readyEntries,
                    before.readyEntries,
                    diagnostic
                )
                XCTAssertEqual(
                    after.loadingEntries,
                    0,
                    diagnostic
                )
            }
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(
            snapshot.unsupportedCounts,
            expected.aggregate.unsupportedCounts,
            workshopID.rawValue
        )
        XCTAssertEqual(snapshot.loadingEntries, 0, workshopID.rawValue)
        await store.releaseGeneration(generation)
    } catch {
        await store.releaseGeneration(generation)
        throw error
    }

    try validateReadPolicy(
        recording,
        previewRanges: previewRanges,
        workshopID: workshopID
    )
}

private var fixedCatalogCapabilities: SceneTextureDeviceCapabilities {
    SceneTextureDeviceCapabilities(
        supportsBCTextureCompression: true,
        linearTextureAlignment: Dictionary(
            uniqueKeysWithValues: SceneTextureGPUFormat.allCases.map {
                ($0, 1)
            }
        )
    )
}

private func unsupportedCategory(
    for metadata: SceneTextureUnsupportedMetadata
) -> String {
    if metadata.kind == .animationVersion {
        return "animation"
    }
    return "descriptor.\(metadata.kind.rawValue)"
}

private func unsupportedCategory(
    for error: SceneTexturePipelineError
) -> String? {
    switch error {
    case let .unsupportedDescriptor(kind):
        return "descriptor.\(kind.rawValue)"
    case .unsupportedAnimation:
        return "animation"
    case .unsupportedVideo:
        return "video"
    case .unsupportedMultiImage:
        return "multiImage"
    case .unsupportedPixelFormat:
        return "pixelFormat"
    default:
        return nil
    }
}

private func checkedLogicalPayloadSum(
    _ current: Int,
    _ values: [Int]
) throws -> Int {
    try values.reduce(current) { result, value in
        let (sum, overflow) = result.addingReportingOverflow(value)
        guard !overflow else {
            throw LocalTextureGateError.logicalPayloadOverflow
        }
        return sum
    }
}

private func validateClassifiedTextureCount(
    workshopID: FixedWorkshopID,
    textureResourceCount: Int,
    uploadPathCounts: [String: Int],
    unsupportedCounts: [String: Int],
    outcomeCount: Int
) throws {
    let classifiedCount = uploadPathCounts.values.reduce(0, +)
        + unsupportedCounts.values.reduce(0, +)
    guard classifiedCount == textureResourceCount,
          outcomeCount == textureResourceCount else {
        throw LocalTextureGateError.classifiedTextureCountMismatch(
            fixtureID: workshopID.rawValue,
            expected: textureResourceCount,
            classified: classifiedCount,
            outcomes: outcomeCount
        )
    }
}

private func packageURL(for workshopID: FixedWorkshopID) -> URL {
    repositoryRoot
        .appending(path: "test")
        .appending(path: workshopID.rawValue)
        .appending(path: "scene.pkg")
}

private func packageFingerprint(url: URL) throws -> PackageFingerprint {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let fileSize = values.fileSize,
          let byteCount = UInt64(exactly: fileSize) else {
        throw LocalTextureGateError.packageByteCountChanged
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: packageHashReadBytes),
          !data.isEmpty {
        hasher.update(data: data)
    }
    return PackageFingerprint(
        byteCount: byteCount,
        sha256: Data(hasher.finalize())
    )
}

private func packageFingerprint(
    for workshopID: FixedWorkshopID
) throws -> PackageFingerprint {
    do {
        return try packageFingerprint(url: packageURL(for: workshopID))
    } catch let error as LocalTextureGateError {
        throw error
    } catch {
        throw LocalTextureGateError.unexpectedFixtureOperation(
            fixtureID: workshopID.rawValue,
            textureIndex: nil,
            stage: "fingerprint"
        )
    }
}

private func fixedPackageFingerprints() throws -> [
    FixedWorkshopID: PackageFingerprint
] {
    try Dictionary(uniqueKeysWithValues: FixedWorkshopID.sorted.map {
        ($0, try packageFingerprint(for: $0))
    })
}

private func validateUnchangedPackageFingerprint(
    before: PackageFingerprint,
    after: PackageFingerprint,
    workshopID: FixedWorkshopID
) throws {
    guard before == after else {
        throw LocalTextureGateError.packageFingerprintChanged(
            workshopID.rawValue
        )
    }
}

private func previewPayloadRanges(
    packageURL: URL,
    workshopID: FixedWorkshopID
) throws -> [Range<UInt64>] {
    let recording = RecordingSceneByteSource(
        base: try SceneFileByteSource(url: packageURL)
    )
    let archive = try ScenePackageArchiveReader().read(source: recording)
    try validateReadPolicy(
        recording,
        previewRanges: [],
        workshopID: workshopID
    )
    return archive.entries.compactMap { entry in
        let filename = URL(filePath: entry.path)
            .lastPathComponent
            .lowercased()
        return [
            "preview.gif",
            "preview.jpg",
            "thumbnail.jpg",
            "cover.png"
        ].contains(filename) ? entry.payloadRange : nil
    }
}

private func validateReadPolicy(
    _ recording: RecordingSceneByteSource,
    previewRanges: [Range<UInt64>],
    workshopID: FixedWorkshopID
) throws {
    guard recording.maximumReadByteCount <= maximumPackageReadBytes else {
        throw LocalTextureGateError.packageReadExceededMaximum(
            recording.maximumReadByteCount
        )
    }
    guard !readRangesCoverPackage(
        recording.readRanges,
        byteCount: recording.byteCount
    ) else {
        throw LocalTextureGateError.packageReadCoveredEntireFile
    }
    for range in recording.readRanges {
        if previewRanges.contains(where: { rangesOverlap(range, $0) }) {
            throw LocalTextureGateError.previewPayloadRead(
                workshopID.rawValue
            )
        }
    }
}

private func readRangesCoverPackage(
    _ ranges: [Range<UInt64>],
    byteCount: UInt64
) -> Bool {
    guard byteCount > 0 else { return false }
    let sortedRanges = ranges.sorted {
        if $0.lowerBound != $1.lowerBound {
            return $0.lowerBound < $1.lowerBound
        }
        return $0.upperBound < $1.upperBound
    }
    guard var mergedRange = sortedRanges.first else { return false }

    for range in sortedRanges.dropFirst() {
        if range.lowerBound <= mergedRange.upperBound {
            mergedRange = mergedRange.lowerBound..<max(
                mergedRange.upperBound,
                range.upperBound
            )
        } else if mergedRange.lowerBound == 0,
                  mergedRange.upperBound >= byteCount {
            return true
        } else {
            mergedRange = range
        }
    }
    return mergedRange.lowerBound == 0
        && mergedRange.upperBound >= byteCount
}

private func rangesOverlap(
    _ first: Range<UInt64>,
    _ second: Range<UInt64>
) -> Bool {
    first.lowerBound < second.upperBound
        && second.lowerBound < first.upperBound
}

private func canonicalFixtureData(
    _ fixture: LocalSceneTextureFixture
) throws -> Data {
    try canonicalCatalogData(
        LocalSceneTextureCatalog(
            schemaVersion: 1,
            capabilityProfile: localCatalogCapabilityProfile,
            fixtures: [fixture]
        )
    )
}

private func assertCatalogRedaction(
    _ data: Data,
    textureEntryPaths: [String],
    workshopID: String
) {
    let forbidden = [
        "/Users/",
        repositoryRoot.path,
        ".tex",
        "scene.pkg"
    ] + textureEntryPaths
    for (index, value) in forbidden.enumerated() {
        XCTAssertNil(
            data.range(of: Data(value.utf8)),
            "\(workshopID): forbidden-value-index \(index)"
        )
    }
}
