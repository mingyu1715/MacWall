import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneLocalFixtureGraphTests: XCTestCase {
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
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(
            catalog.fixtures.map(\.workshopID).sorted(),
            expectedObjectCounts.keys.sorted()
        )

        let availableFixtures = catalog.fixtures.filter {
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
            XCTAssertEqual(first.summary, fixture.summary, fixture.workshopID)
            XCTAssertEqual(
                nodeCount(in: first.summary),
                expectedObjectCounts[fixture.workshopID],
                fixture.workshopID
            )

            let second = try buildFixture(for: fixture.workshopID)
            XCTAssertEqual(
                first.summaryBytes,
                second.summaryBytes,
                fixture.workshopID
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

    private var expectedObjectCounts: [String: Int] {
        [
            "2174863503": 28,
            "2834933421": 98,
            "3516106265": 69
        ]
    }

    private func packageURL(for workshopID: String) -> URL {
        repositoryRoot
            .appending(path: "test")
            .appending(path: workshopID)
            .appending(path: "scene.pkg")
    }

    private func buildFixture(
        for workshopID: String
    ) throws -> BuiltFixture {
        let packageURL = packageURL(for: workshopID)
        let excludedPayloadRanges = try excludedPayloadRanges(
            in: packageURL
        )
        let recording = RecordingSceneByteSource(
            base: try SceneFileByteSource(url: packageURL)
        )
        let resolver = try ScenePackageAssetResolver.open(source: recording)
        let result = SceneGraphBuilder().build(resolver: resolver)
        let summary = SceneGraphSummarizer.summarize(result)

        XCTAssertFalse(
            recording.readRanges.contains(0..<recording.byteCount),
            workshopID
        )
        XCTAssertLessThanOrEqual(
            recording.maximumReadByteCount,
            16 * 1_024 * 1_024,
            workshopID
        )
        for range in recording.readRanges {
            XCTAssertFalse(
                excludedPayloadRanges.contains { rangesOverlap(range, $0) },
                workshopID
            )
        }
        for diagnostic in result.diagnostics {
            for argument in diagnostic.arguments {
                XCTAssertFalse(
                    argument.contains(repositoryRoot.path),
                    workshopID
                )
                XCTAssertFalse(argument.contains("/Users/"), workshopID)
            }
        }

        return BuiltFixture(
            summary: summary,
            summaryBytes: try SceneGraphSummaryEncoder.encode(summary)
        )
    }

    private func writeLocalCatalog() throws {
        let workshopIDs = [
            "2174863503",
            "2834933421",
            "3516106265"
        ]
        let missingIDs = workshopIDs.filter {
            !FileManager.default.fileExists(
                atPath: packageURL(for: $0).path
            )
        }
        XCTAssertTrue(missingIDs.isEmpty, missingIDs.joined(separator: ", "))
        guard missingIDs.isEmpty else { return }

        let catalog = LocalSceneGraphCatalog(
            schemaVersion: 1,
            fixtures: try workshopIDs.sorted().map { workshopID in
                LocalSceneGraphFixture(
                    workshopID: workshopID,
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
        in packageURL: URL
    ) throws -> [Range<UInt64>] {
        let archive = try ScenePackageArchiveReader().read(
            source: try SceneFileByteSource(url: packageURL)
        )
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

private struct BuiltFixture {
    let summary: SceneGraphSummary
    let summaryBytes: Data
}
