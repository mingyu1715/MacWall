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

        for value in forbidden {
            XCTAssertNil(
                bytes.range(of: Data(value.utf8)),
                value
            )
        }
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
    case unresolvedTexture(String)
    case missingPlannedTexture(String)
    case logicalPayloadOverflow
    case packageReadExceededMaximum(UInt64)
    case packageReadCoveredEntireFile
    case previewPayloadRead(String)
    case packageByteCountChanged
}

private struct PackageFingerprint: Equatable {
    let byteCount: UInt64
    let sha256: Data
}

private enum PlannedTextureOutcome {
    case supported(SceneTextureLoadPlan, mipmapLevelCount: Int)
    case unsupported(String)
    case failed(SceneTexturePipelineError)
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
        let url = packageURL(for: workshopID)
        let before = try packageFingerprint(url: url)
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
        XCTAssertEqual(
            try packageFingerprint(url: url),
            before,
            workshopID.rawValue
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

    let catalog = LocalSceneTextureCatalog(
        schemaVersion: 1,
        capabilityProfile: localCatalogCapabilityProfile,
        fixtures: try FixedWorkshopID.sorted.map { workshopID in
            let fingerprint = try packageFingerprint(
                url: packageURL(for: workshopID)
            )
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
}

private func planLocalFixture(
    workshopID: FixedWorkshopID,
    expectedPackageByteCount: UInt64
) throws -> PlannedLocalFixture {
    let url = packageURL(for: workshopID)
    let previewRanges = try previewPayloadRanges(packageURL: url)
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

    for resource in textureResources {
        guard resource.resolution.kind == .package,
              let selected = resource.resolution.selected else {
            throw LocalTextureGateError.unresolvedTexture(
                resource.id.rawValue
            )
        }
        let path = selected.canonicalPath.rawValue
        entryPaths.append(path)
        let source = try resolver.source(for: selected)
        let inspection = try SceneTextureFormatReader().inspect(
            source: source,
            path: path
        )

        switch inspection {
        case let .unsupported(metadata):
            let category = unsupportedCategory(for: metadata)
            unsupportedCounts[category, default: 0] += 1
            outcomes[resource.id] = .unsupported(category)

        case let .parsed(descriptor):
            formatCounts[String(descriptor.formatRawValue), default: 0] += 1
            containerCounts[descriptor.declaredContainer, default: 0] += 1
            do {
                let plan = try planner.makePlan(
                    descriptor: descriptor,
                    imageIndex: 0,
                    colorIntent: .dataLinear
                )
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
                    outcomes[resource.id] = .failed(error)
                }
            }
        }
    }

    try validateReadPolicy(
        recording,
        previewRanges: previewRanges,
        textureEntryPaths: entryPaths
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
    let previewRanges = try previewPayloadRanges(packageURL: url)
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
        for resource in resources {
            guard let outcome = expected.outcomes[resource.id] else {
                throw LocalTextureGateError.missingPlannedTexture(
                    resource.id.rawValue
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
                let lease = try await store.acquire(
                    request,
                    resource: resource,
                    resolver: resolver,
                    for: generation
                )
                XCTAssertEqual(
                    lease.texture.storageMode,
                    .private,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.texture.mipmapLevelCount,
                    mipmapLevelCount,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.mipmapLevelCount,
                    mipmapLevelCount,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.texture.width,
                    plan.storageExtent.width,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.texture.height,
                    plan.storageExtent.height,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.storageExtent,
                    plan.storageExtent,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.contentExtent,
                    plan.contentExtent,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    lease.contentRect,
                    plan.contentRect,
                    resource.id.rawValue
                )
                XCTAssertGreaterThan(
                    lease.residentBytes,
                    0,
                    resource.id.rawValue
                )

            case let .unsupported(expectedCategory):
                let before = await store.snapshot()
                do {
                    _ = try await store.acquire(
                        request,
                        resource: resource,
                        resolver: resolver,
                        for: generation
                    )
                    XCTFail(
                        "Unsupported texture became ready: \(resource.id.rawValue)"
                    )
                } catch let error as SceneTexturePipelineError {
                    XCTAssertEqual(
                        unsupportedCategory(for: error),
                        expectedCategory,
                        resource.id.rawValue
                    )
                }
                let after = await store.snapshot()
                XCTAssertEqual(
                    after.readyEntries,
                    before.readyEntries,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    after.loadingEntries,
                    0,
                    resource.id.rawValue
                )

            case let .failed(expectedError):
                let before = await store.snapshot()
                do {
                    _ = try await store.acquire(
                        request,
                        resource: resource,
                        resolver: resolver,
                        for: generation
                    )
                    XCTFail(
                        "Failed texture became ready: \(resource.id.rawValue)"
                    )
                } catch let error as SceneTexturePipelineError {
                    XCTAssertEqual(
                        error,
                        expectedError,
                        resource.id.rawValue
                    )
                }
                let after = await store.snapshot()
                XCTAssertEqual(
                    after.readyEntries,
                    before.readyEntries,
                    resource.id.rawValue
                )
                XCTAssertEqual(
                    after.loadingEntries,
                    0,
                    resource.id.rawValue
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
        textureEntryPaths: expected.textureEntryPaths
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

private func previewPayloadRanges(
    packageURL: URL
) throws -> [Range<UInt64>] {
    let recording = RecordingSceneByteSource(
        base: try SceneFileByteSource(url: packageURL)
    )
    let archive = try ScenePackageArchiveReader().read(source: recording)
    try validateReadPolicy(
        recording,
        previewRanges: [],
        textureEntryPaths: []
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
    textureEntryPaths: [String]
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
                textureEntryPaths.joined(separator: ",")
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
    for value in forbidden {
        XCTAssertNil(
            data.range(of: Data(value.utf8)),
            "\(workshopID): \(value)"
        )
    }
}
