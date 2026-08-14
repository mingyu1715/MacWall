import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Metal
import XCTest
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTextures
@testable import MacWallSceneRenderer

final class SceneLocalFixtureRendererTests: XCTestCase {
    func testNoAvailableFixedFixtureIsAbsent() {
        XCTAssertEqual(
            localFixtureAvailability(availableIDs: []),
            .absent
        )
    }

    func testPartialAvailabilityReportsEveryMissingFixedIDSorted() {
        XCTAssertEqual(
            localFixtureAvailability(
                availableIDs: [.fixture3516106265]
            ),
            .partial(missingIDs: ["2174863503", "2834933421"])
        )
    }

    func testCatalogValidationRequiresExactFixedIDs() {
        let invalidIDs = [
            ["2174863503", "2174863503", "2834933421"],
            ["2174863503", "2834933421", "3516106265", "9999999999"],
            ["2174863503", "2834933421", "../3516106265"]
        ]

        for ids in invalidIDs {
            XCTAssertThrowsError(
                try validatedFixtures(in: makeCatalog(ids: ids)),
                ids.joined(separator: ",")
            )
        }
    }

    func testCanonicalCatalogContainsNoPathPayloadOrThumbnailNames() throws {
        let generatedBytes = try canonicalCatalogData(
            makeCatalog(ids: FixedWorkshopID.sorted.map(\.rawValue))
        )
        let trackedBytes = try Data(contentsOf: localCatalogURL)
        let forbidden = [
            "/Users/",
            repositoryRoot.path,
            "scene.pkg",
            "preview.gif",
            "preview.jpg",
            "thumbnail.jpg",
            "cover.png",
            "materials/example.tex",
            "fixture-payload-secret"
        ]

        for bytes in [generatedBytes, trackedBytes] {
            for value in forbidden {
                XCTAssertNil(
                    bytes.range(of: Data(value.utf8)),
                    "catalog leaked forbidden value: \(value)"
                )
            }
        }
    }

    func testLocalSceneRendererMatchesTrackedCatalog() async throws {
        if ProcessInfo.processInfo.environment[
            "MACWALL_UPDATE_SCENE_RENDERER_CATALOG"
        ] == "1" {
            try await writeLocalCatalog()
        }

        let trackedBytes = try Data(contentsOf: localCatalogURL)
        let catalog = try JSONDecoder().decode(
            LocalSceneRendererCatalog.self,
            from: trackedBytes
        )
        let trackedFixtures = try validatedFixtures(in: catalog)
        XCTAssertEqual(trackedBytes, try canonicalCatalogData(catalog))

        let activeFixtureIDs: [FixedWorkshopID]
        switch availableLocalFixtures() {
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
            XCTFail("The local renderer fixture gate requires a Metal device.")
            return
        }
        guard SceneMetalPipelines.hasPackagedDefaultLibrary else {
            throw XCTSkip(
                "Local renderer fixtures require swiftbuild so the metallib is packaged."
            )
        }

        let trackedByID = Dictionary(
            uniqueKeysWithValues: trackedFixtures.map {
                ($0.workshopID, $0.fixture)
            }
        )
        for workshopID in activeFixtureIDs {
            let before = try packageFingerprint(for: workshopID)
            let actual = try await renderLocalFixture(
                workshopID: workshopID,
                device: device
            )
            XCTAssertEqual(
                actual,
                trackedByID[workshopID],
                workshopID.rawValue
            )
            XCTAssertGreaterThan(actual.compiledDrawCount, 0)
            XCTAssertGreaterThan(actual.renderedDrawCount, 0)
            XCTAssertGreaterThan(actual.sampledNonTransparentPixelCount, 0)
            XCTAssertEqual(
                before,
                try packageFingerprint(for: workshopID),
                workshopID.rawValue
            )
        }
    }

    private func makeCatalog(ids: [String]) -> LocalSceneRendererCatalog {
        LocalSceneRendererCatalog(
            schemaVersion: rendererCatalogSchemaVersion,
            configuration: rendererCatalogConfiguration,
            fixtures: ids.map { id in
                LocalSceneRendererFixture(
                    workshopID: id,
                    status: SceneRenderStatus.degraded.rawValue,
                    compiledDrawCount: 1,
                    renderedDrawCount: 1,
                    skippedDrawCount: 0,
                    diagnosticCounts: ["renderer.synthetic": 1],
                    sampledNonTransparentPixelCount: 1,
                    semanticSampleHash: String(repeating: "0", count: 64)
                )
            }
        )
    }
}

private let rendererCatalogSchemaVersion = 1
private let rendererOutputWidth = 320
private let rendererOutputHeight = 180
private let rendererMediaTimeSeconds = 0.5
private let rendererScalingMode = SceneOutputScalingMode.fit
private let semanticSampleSchemaVersion = 1
private let localFixtureTextureLimits = SceneTextureLimits(
    residentSoftBytes: 768 * 1_024 * 1_024,
    residentHardBytes: 1_024 * 1_024 * 1_024,
    stagingBytes: 512 * 1_024 * 1_024,
    decodedCPUBytes: 512 * 1_024 * 1_024,
    singlePayloadBytes: 256 * 1_024 * 1_024,
    maximumTextureDimension: 16_384,
    maximumDecodedPixels: 64_000_000,
    maximumConcurrentDecodes: 2,
    maximumConcurrentUploads: 2,
    uploadTimeout: .seconds(30)
)

private let rendererCatalogConfiguration = LocalSceneRendererConfiguration(
    width: rendererOutputWidth,
    height: rendererOutputHeight,
    mediaTimeSeconds: rendererMediaTimeSeconds,
    scalingMode: rendererScalingMode.rawValue,
    semanticSampleSchemaVersion: semanticSampleSchemaVersion
)

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
        .appending(path: "SceneRenderer")
        .appending(path: "local-scene-renderer-catalog.json")
}

private var debugOutputDirectoryURL: URL {
    URL(filePath: "/tmp/macwall-scene-renderer-local-fixtures")
}

private enum FixedWorkshopID: String, CaseIterable {
    case fixture2174863503 = "2174863503"
    case fixture2834933421 = "2834933421"
    case fixture3516106265 = "3516106265"

    static let sorted = allCases.sorted { $0.rawValue < $1.rawValue }
}

private struct LocalSceneRendererCatalog: Codable, Equatable {
    let schemaVersion: Int
    let configuration: LocalSceneRendererConfiguration
    let fixtures: [LocalSceneRendererFixture]
}

private struct LocalSceneRendererConfiguration: Codable, Equatable {
    let width: Int
    let height: Int
    let mediaTimeSeconds: Double
    let scalingMode: String
    let semanticSampleSchemaVersion: Int
}

private struct LocalSceneRendererFixture: Codable, Equatable {
    let workshopID: String
    let status: String
    let compiledDrawCount: Int
    let renderedDrawCount: Int
    let skippedDrawCount: Int
    let diagnosticCounts: [String: Int]
    let sampledNonTransparentPixelCount: Int
    let semanticSampleHash: String
}

private struct ValidatedLocalSceneRendererFixture {
    let workshopID: FixedWorkshopID
    let fixture: LocalSceneRendererFixture
}

private struct PackageFingerprint: Equatable {
    let byteCount: UInt64
    let sha256: String
}

private struct SemanticSampleResult: Equatable {
    let hash: String
    let nonTransparentPixelCount: Int
}

private struct DecodedPNG {
    let width: Int
    let height: Int
    let straightRGBA: [UInt8]
}

private enum LocalFixtureAvailability: Equatable {
    case absent
    case partial(missingIDs: [String])
    case complete([FixedWorkshopID])
}

private enum LocalRendererCatalogError: Error, Equatable {
    case invalidSchemaVersion(Int)
    case invalidConfiguration
    case invalidFixtureIDs([String])
    case missingFixtures([String])
    case missingCompiledProgram(
        fixtureID: String,
        status: String,
        diagnosticCounts: [String: Int]
    )
    case noCompiledDraws(String)
    case noRenderedDraws(String)
    case nondeterministicFrame(String)
    case missingSnapshot(String)
    case invalidSnapshotDimensions(String)
    case noSampledContent(String)
    case textureGenerationNotReleased(String)
    case packageByteCountOverflow
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

private func availableLocalFixtures() -> LocalFixtureAvailability {
    localFixtureAvailability(availableIDs: Set(FixedWorkshopID.sorted.filter {
        FileManager.default.fileExists(atPath: packageURL(for: $0).path)
    }))
}

private func validatedFixtures(
    in catalog: LocalSceneRendererCatalog
) throws -> [ValidatedLocalSceneRendererFixture] {
    guard catalog.schemaVersion == rendererCatalogSchemaVersion else {
        throw LocalRendererCatalogError.invalidSchemaVersion(
            catalog.schemaVersion
        )
    }
    guard catalog.configuration == rendererCatalogConfiguration else {
        throw LocalRendererCatalogError.invalidConfiguration
    }

    let expectedIDs = FixedWorkshopID.sorted.map(\.rawValue)
    let actualIDs = catalog.fixtures.map(\.workshopID).sorted()
    guard actualIDs == expectedIDs else {
        throw LocalRendererCatalogError.invalidFixtureIDs(actualIDs)
    }

    let fixturesByID = Dictionary(
        uniqueKeysWithValues: catalog.fixtures.map {
            ($0.workshopID, $0)
        }
    )
    return FixedWorkshopID.sorted.compactMap { workshopID in
        fixturesByID[workshopID.rawValue].map {
            ValidatedLocalSceneRendererFixture(
                workshopID: workshopID,
                fixture: $0
            )
        }
    }
}

private func canonicalCatalogData(
    _ catalog: LocalSceneRendererCatalog
) throws -> Data {
    let normalized = LocalSceneRendererCatalog(
        schemaVersion: catalog.schemaVersion,
        configuration: catalog.configuration,
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

private func writeLocalCatalog() async throws {
    let missingIDs = FixedWorkshopID.sorted.filter {
        !FileManager.default.fileExists(atPath: packageURL(for: $0).path)
    }
    guard missingIDs.isEmpty else {
        throw LocalRendererCatalogError.missingFixtures(
            missingIDs.map(\.rawValue)
        )
    }
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw XCTSkip("The local renderer catalog requires a Metal device.")
    }
    guard SceneMetalPipelines.hasPackagedDefaultLibrary else {
        throw XCTSkip(
            "Local renderer catalog requires swiftbuild so the metallib is packaged."
        )
    }

    let before = try fixedPackageFingerprints()
    var fixtures: [LocalSceneRendererFixture] = []
    fixtures.reserveCapacity(FixedWorkshopID.sorted.count)
    for workshopID in FixedWorkshopID.sorted {
        fixtures.append(try await renderLocalFixture(
            workshopID: workshopID,
            device: device
        ))
    }
    let catalog = LocalSceneRendererCatalog(
        schemaVersion: rendererCatalogSchemaVersion,
        configuration: rendererCatalogConfiguration,
        fixtures: fixtures
    )
    try FileManager.default.createDirectory(
        at: localCatalogURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try canonicalCatalogData(catalog).write(
        to: localCatalogURL,
        options: .atomic
    )
    guard before == (try fixedPackageFingerprints()) else {
        throw LocalRendererCatalogError.nondeterministicFrame(
            "fixture-package-mutated"
        )
    }
}

private func renderLocalFixture(
    workshopID: FixedWorkshopID,
    device: any MTLDevice
) async throws -> LocalSceneRendererFixture {
    let resolver = try ScenePackageAssetResolver.open(
        source: try SceneFileByteSource(url: packageURL(for: workshopID))
    )
    let graphResult = SceneGraphBuilder().build(resolver: resolver)
    let compileResult = SceneRenderCompiler().compile(graphResult)
    guard let program = compileResult.program else {
        throw LocalRendererCatalogError.missingCompiledProgram(
            fixtureID: workshopID.rawValue,
            status: compileResult.status.rawValue,
            diagnosticCounts: diagnosticCounts(compileResult.diagnostics)
        )
    }
    guard program.drawCount > 0 else {
        throw LocalRendererCatalogError.noCompiledDraws(workshopID.rawValue)
    }

    let store = try SceneTextureStore(
        device: device,
        limits: localFixtureTextureLimits
    )
    let session = try await SceneRenderSession.prepare(
        program: program,
        device: device,
        textureStore: store,
        textureContext: .init(
            packageID: SceneTexturePackageID(),
            resolver: resolver
        )
    )
    let request = SceneRenderFrameRequest(
        mediaTimeSeconds: rendererMediaTimeSeconds,
        outputWidth: rendererOutputWidth,
        outputHeight: rendererOutputHeight,
        scalingMode: rendererScalingMode,
        requestsSnapshot: true
    )

    do {
        let first = try await session.render(request)
        guard first.drawCount > 0 else {
            first.release()
            throw LocalRendererCatalogError.noRenderedDraws(
                workshopID.rawValue
            )
        }
        let firstPNG = try snapshotPNG(
            from: first,
            workshopID: workshopID
        )
        let firstSamples = try semanticSamples(
            png: firstPNG,
            workshopID: workshopID
        )
        try writeDebugPNG(firstPNG, workshopID: workshopID)

        let second = try await session.render(request)
        let secondPNG = try snapshotPNG(
            from: second,
            workshopID: workshopID
        )
        let secondSamples = try semanticSamples(
            png: secondPNG,
            workshopID: workshopID
        )
        guard first.status == second.status,
              first.drawCount == second.drawCount,
              first.skippedDrawCount == second.skippedDrawCount,
              first.diagnostics == second.diagnostics,
              firstSamples == secondSamples else {
            first.release()
            second.release()
            throw LocalRendererCatalogError.nondeterministicFrame(
                workshopID.rawValue
            )
        }
        guard firstSamples.nonTransparentPixelCount > 0 else {
            first.release()
            second.release()
            throw LocalRendererCatalogError.noSampledContent(
                workshopID.rawValue
            )
        }

        let renderedDrawCount = first.drawCount
        let skippedDrawCount = program.drawCount - renderedDrawCount
        let status = combinedStatus(compileResult.status, first.status)
        let diagnostics = compileResult.diagnostics + first.diagnostics
        first.release()
        second.release()
        await session.invalidate()

        let storeSnapshot = await store.snapshot()
        guard storeSnapshot.loadingEntries == 0,
              storeSnapshot.readyEntries == storeSnapshot.unownedEntries else {
            throw LocalRendererCatalogError.textureGenerationNotReleased(
                workshopID.rawValue
            )
        }
        return LocalSceneRendererFixture(
            workshopID: workshopID.rawValue,
            status: status.rawValue,
            compiledDrawCount: program.drawCount,
            renderedDrawCount: renderedDrawCount,
            skippedDrawCount: skippedDrawCount,
            diagnosticCounts: diagnosticCounts(diagnostics),
            sampledNonTransparentPixelCount:
                firstSamples.nonTransparentPixelCount,
            semanticSampleHash: firstSamples.hash
        )
    } catch {
        await session.invalidate()
        throw error
    }
}

private func snapshotPNG(
    from frame: SceneRenderCompletedFrame,
    workshopID: FixedWorkshopID
) throws -> Data {
    guard let png = frame.snapshotPNG else {
        throw LocalRendererCatalogError.missingSnapshot(workshopID.rawValue)
    }
    return png
}

private func semanticSamples(
    png: Data,
    workshopID: FixedWorkshopID
) throws -> SemanticSampleResult {
    let decoded = try decodePNG(png)
    guard decoded.width == rendererOutputWidth,
          decoded.height == rendererOutputHeight else {
        throw LocalRendererCatalogError.invalidSnapshotDimensions(
            workshopID.rawValue
        )
    }

    var sampleBytes = Data()
    var nonTransparentPixelCount = 0
    for row in 0...8 {
        let y = row * (decoded.height - 1) / 8
        for column in 0...16 {
            let x = column * (decoded.width - 1) / 16
            let offset = (y * decoded.width + x) * 4
            let pixel = decoded.straightRGBA[offset..<(offset + 4)]
            sampleBytes.append(contentsOf: pixel)
            if pixel[pixel.index(pixel.startIndex, offsetBy: 3)] > 0 {
                nonTransparentPixelCount += 1
            }
        }
    }
    return SemanticSampleResult(
        hash: SHA256.hash(data: sampleBytes).hexString,
        nonTransparentPixelCount: nonTransparentPixelCount
    )
}

private func decodePNG(_ data: Data) throws -> DecodedPNG {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw LocalRendererCatalogError.invalidSnapshotDimensions(
            "png-decode"
        )
    }
    var premultipliedRGBA = Data(count: image.width * image.height * 4)
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )
    try premultipliedRGBA.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw LocalRendererCatalogError.invalidSnapshotDimensions(
                "png-context"
            )
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }

    var straightRGBA = [UInt8](repeating: 0, count: premultipliedRGBA.count)
    for pixelIndex in 0..<(image.width * image.height) {
        let offset = pixelIndex * 4
        let alpha = Int(premultipliedRGBA[offset + 3])
        straightRGBA[offset + 3] = UInt8(alpha)
        guard alpha > 0 else { continue }
        for channel in 0..<3 {
            straightRGBA[offset + channel] = UInt8(min(
                255,
                (Int(premultipliedRGBA[offset + channel]) * 255 + alpha / 2)
                    / alpha
            ))
        }
    }
    return DecodedPNG(
        width: image.width,
        height: image.height,
        straightRGBA: straightRGBA
    )
}

private func combinedStatus(
    _ first: SceneRenderStatus,
    _ second: SceneRenderStatus
) -> SceneRenderStatus {
    let rank: [SceneRenderStatus: Int] = [
        .exact: 0,
        .degraded: 1,
        .unsupported: 2,
        .invalid: 3
    ]
    return rank[first, default: 3] >= rank[second, default: 3]
        ? first
        : second
}

private func diagnosticCounts(
    _ diagnostics: [SceneRenderDiagnostic]
) -> [String: Int] {
    diagnostics.reduce(into: [:]) { counts, diagnostic in
        counts[diagnostic.code, default: 0] += 1
    }
}

private func writeDebugPNG(
    _ data: Data,
    workshopID: FixedWorkshopID
) throws {
    try FileManager.default.createDirectory(
        at: debugOutputDirectoryURL,
        withIntermediateDirectories: true
    )
    try data.write(
        to: debugOutputDirectoryURL.appending(
            path: "\(workshopID.rawValue).png"
        ),
        options: .atomic
    )
}

private func packageURL(for workshopID: FixedWorkshopID) -> URL {
    repositoryRoot
        .appending(path: "test")
        .appending(path: workshopID.rawValue)
        .appending(path: "scene.pkg")
}

private func packageFingerprint(
    for workshopID: FixedWorkshopID
) throws -> PackageFingerprint {
    let url = packageURL(for: workshopID)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    var byteCount: UInt64 = 0
    while let chunk = try handle.read(upToCount: 1_024 * 1_024),
          !chunk.isEmpty {
        let (sum, overflow) = byteCount.addingReportingOverflow(
            UInt64(chunk.count)
        )
        guard !overflow else {
            throw LocalRendererCatalogError.packageByteCountOverflow
        }
        byteCount = sum
        hasher.update(data: chunk)
    }
    return PackageFingerprint(
        byteCount: byteCount,
        sha256: hasher.finalize().hexString
    )
}

private func fixedPackageFingerprints()
    throws -> [FixedWorkshopID: PackageFingerprint] {
    try Dictionary(uniqueKeysWithValues: FixedWorkshopID.sorted.map {
        ($0, try packageFingerprint(for: $0))
    })
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
