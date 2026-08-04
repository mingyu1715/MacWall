import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneLocalFixtureGraphTests: XCTestCase {
    func testReadRangesCoverPackageAcrossAdjacentReads() {
        XCTAssertTrue(
            readRangesCoverPackage(
                [0..<8, 8..<16],
                byteCount: 16
            )
        )
    }

    func testReadRangesDoNotCoverPackageWhenTheyHaveGap() {
        XCTAssertFalse(
            readRangesCoverPackage(
                [0..<7, 8..<16],
                byteCount: 16
            )
        )
    }

    func testValidatedFixturesRejectUnexpectedCatalogID() {
        let catalog = LocalSceneGraphCatalog(
            schemaVersion: 1,
            fixtures: [
                LocalSceneGraphFixture(
                    workshopID: "../unexpected",
                    summary: emptySummary
                )
            ]
        )

        XCTAssertThrowsError(try validatedFixtures(in: catalog))
    }

    func testLocalSceneFixturesMatchTrackedAggregateCatalog() throws {
        if ProcessInfo.processInfo.environment[
            "MACWALL_UPDATE_LOCAL_SCENE_GRAPH_CATALOG"
        ] == "1" {
            try writeLocalCatalog()
        }

        let catalog = try JSONDecoder().decode(
            LocalSceneGraphCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        let fixtures = try validatedFixtures(in: catalog)

        let availableFixtures = fixtures.filter {
            FileManager.default.fileExists(
                atPath: packageURL(for: $0.workshopID).path
            )
        }
        guard !availableFixtures.isEmpty else {
            throw XCTSkip(
                "Local Workshop scene fixtures are not available."
            )
        }

        for fixture in availableFixtures {
            let first = try buildFixture(for: fixture.workshopID)
            XCTAssertEqual(
                first.summary,
                fixture.fixture.summary,
                fixture.workshopID.rawValue
            )
            XCTAssertEqual(
                nodeCount(in: first.summary),
                fixture.workshopID.objectCount,
                fixture.workshopID.rawValue
            )

            let second = try buildFixture(for: fixture.workshopID)
            XCTAssertEqual(
                first.summaryBytes,
                second.summaryBytes,
                fixture.workshopID.rawValue
            )
        }
    }

    private var catalogURL: URL {
        repositoryRoot
            .appending(path: "Tests")
            .appending(path: "Fixtures")
            .appending(path: "SceneGraph")
            .appending(path: "local-scene-graph-catalog.json")
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var emptySummary: SceneGraphSummary {
        SceneGraphSummary(
            schemaVersion: 1,
            packageVersion: nil,
            nodeKinds: [],
            hierarchyEdgeCount: 0,
            instanceEdgeCount: 0,
            overrideCount: 0,
            resourceKinds: [],
            dependencyResolutions: [],
            animationTrackCount: 0,
            animationKeyframeCount: 0,
            scriptCount: 0,
            diagnosticCodes: [],
            status: .exact
        )
    }

    private func packageURL(for workshopID: FixedWorkshopID) -> URL {
        repositoryRoot
            .appending(path: "test")
            .appending(path: workshopID.rawValue)
            .appending(path: "scene.pkg")
    }

    private func buildFixture(
        for workshopID: FixedWorkshopID
    ) throws -> BuiltFixture {
        let packageURL = packageURL(for: workshopID)
        let excludedPayloadRanges = try excludedPayloadRanges(
            in: packageURL,
            workshopID: workshopID.rawValue
        )
        let recording = RecordingSceneByteSource(
            base: try SceneFileByteSource(url: packageURL)
        )
        let resolver = try ScenePackageAssetResolver.open(source: recording)
        let result = SceneGraphBuilder().build(resolver: resolver)
        let summary = SceneGraphSummarizer.summarize(result)

        assertReadPolicy(recording, workshopID: workshopID.rawValue)
        for range in recording.readRanges {
            XCTAssertFalse(
                excludedPayloadRanges.contains { rangesOverlap(range, $0) },
                workshopID.rawValue
            )
        }
        for diagnostic in result.diagnostics {
            for argument in diagnostic.arguments {
                XCTAssertFalse(
                    argument.contains(repositoryRoot.path),
                    workshopID.rawValue
                )
                XCTAssertFalse(argument.contains("/Users/"), workshopID.rawValue)
            }
        }

        return BuiltFixture(
            summary: summary,
            summaryBytes: try SceneGraphSummaryEncoder.encode(summary)
        )
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

        let catalog = LocalSceneGraphCatalog(
            schemaVersion: 1,
            fixtures: try FixedWorkshopID.sorted.map { workshopID in
                LocalSceneGraphFixture(
                    workshopID: workshopID.rawValue,
                    summary: try buildFixture(for: workshopID).summary
                )
            }
        )
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try catalogData(catalog).write(to: catalogURL, options: .atomic)
    }

    private func excludedPayloadRanges(
        in packageURL: URL,
        workshopID: String
    ) throws -> [Range<UInt64>] {
        let recording = RecordingSceneByteSource(
            base: try SceneFileByteSource(url: packageURL)
        )
        let archive = try ScenePackageArchiveReader().read(
            source: recording
        )
        assertReadPolicy(recording, workshopID: workshopID)
        return archive.entries.compactMap { entry in
            let filename = URL(filePath: entry.path).lastPathComponent.lowercased()
            let isPreview = [
                "preview.gif",
                "preview.jpg",
                "thumbnail.jpg",
                "cover.png"
            ].contains(filename)
            let isTexture = URL(filePath: entry.path)
                .pathExtension
                .lowercased() == "tex"
            return isPreview || isTexture ? entry.payloadRange : nil
        }
    }

    private func assertReadPolicy(
        _ recording: RecordingSceneByteSource,
        workshopID: String
    ) {
        XCTAssertLessThanOrEqual(
            recording.maximumReadByteCount,
            16 * 1_024 * 1_024,
            workshopID
        )
        XCTAssertFalse(
            readRangesCoverPackage(
                recording.readRanges,
                byteCount: recording.byteCount
            ),
            workshopID
        )
    }

    private func nodeCount(in summary: SceneGraphSummary) -> Int {
        summary.nodeKinds.reduce(into: 0) { count, kind in
            count += kind.count
        }
    }

    private func catalogData(
        _ catalog: LocalSceneGraphCatalog
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        var data = try encoder.encode(catalog)
        while data.last == 0x0A || data.last == 0x0D {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }

    private func rangesOverlap(
        _ first: Range<UInt64>,
        _ second: Range<UInt64>
    ) -> Bool {
        first.lowerBound < second.upperBound
            && second.lowerBound < first.upperBound
    }
}

private struct LocalSceneGraphCatalog: Codable {
    let schemaVersion: Int
    let fixtures: [LocalSceneGraphFixture]
}

private struct LocalSceneGraphFixture: Codable {
    let workshopID: String
    let summary: SceneGraphSummary
}

private enum FixedWorkshopID: String, CaseIterable {
    case fixture2174863503 = "2174863503"
    case fixture2834933421 = "2834933421"
    case fixture3516106265 = "3516106265"

    static let sorted = allCases.sorted { $0.rawValue < $1.rawValue }

    var objectCount: Int {
        switch self {
        case .fixture2174863503:
            28
        case .fixture2834933421:
            98
        case .fixture3516106265:
            69
        }
    }
}

private struct ValidatedLocalSceneGraphFixture {
    let workshopID: FixedWorkshopID
    let fixture: LocalSceneGraphFixture
}

private enum LocalFixtureCatalogError: Error {
    case invalidSchemaVersion(Int)
    case invalidFixtureIDs([String])
    case missingFixtures([String])
}

private struct BuiltFixture {
    let summary: SceneGraphSummary
    let summaryBytes: Data
}

private func validatedFixtures(
    in catalog: LocalSceneGraphCatalog
) throws -> [ValidatedLocalSceneGraphFixture] {
    guard catalog.schemaVersion == 1 else {
        throw LocalFixtureCatalogError.invalidSchemaVersion(
            catalog.schemaVersion
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
            ValidatedLocalSceneGraphFixture(
                workshopID: workshopID,
                fixture: $0
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
    return mergedRange.lowerBound == 0 && mergedRange.upperBound >= byteCount
}
