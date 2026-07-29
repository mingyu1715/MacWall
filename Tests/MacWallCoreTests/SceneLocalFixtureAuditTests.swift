import Foundation
import XCTest
@testable import MacWallCore

final class SceneLocalFixtureAuditTests: XCTestCase {
    func testLocalSceneFixturesMatchTrackedAggregateCatalog() throws {
        let catalogURL = repositoryRoot
            .appending(path: "Tests")
            .appending(path: "Fixtures")
            .appending(path: "SceneAudit")
            .appending(path: "local-scene-catalog.json")
        let catalog = try JSONDecoder().decode(
            LocalSceneCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        XCTAssertEqual(catalog.schemaVersion, 1)

        let availableFixtures = catalog.fixtures.filter {
            FileManager.default.fileExists(
                atPath: packageURL(for: $0).path
            )
        }
        guard !availableFixtures.isEmpty else {
            throw XCTSkip("Local Workshop scene fixtures are not available.")
        }

        for fixture in availableFixtures {
            let report = SceneAuditor().audit(url: packageURL(for: fixture))

            XCTAssertEqual(
                report.package.version,
                fixture.packageVersion,
                fixture.workshopID
            )
            XCTAssertEqual(
                report.package.entryCount,
                fixture.entryCount,
                fixture.workshopID
            )
            XCTAssertEqual(
                counts(report.objectKinds),
                fixture.objectKinds,
                fixture.workshopID
            )
            XCTAssertEqual(
                counted(report.textures.map(\.formatRawValue)),
                fixture.textureFormats,
                fixture.workshopID
            )
            XCTAssertEqual(
                counted(report.textures.map(\.flagsRawValue)),
                fixture.textureFlags,
                fixture.workshopID
            )
            XCTAssertEqual(
                counted(report.textures.map(\.declaredContainer)),
                fixture.textureContainers,
                fixture.workshopID
            )

            let features = Dictionary(uniqueKeysWithValues: report.features.map {
                ($0.key.rawValue, $0.count)
            })
            for (key, expectedCount) in fixture.features {
                XCTAssertEqual(
                    features[key, default: 0],
                    expectedCount,
                    "\(fixture.workshopID): \(key)"
                )
            }

            for diagnostic in report.diagnostics {
                XCTAssertFalse(
                    diagnostic.message.contains(repositoryRoot.path),
                    fixture.workshopID
                )
                XCTAssertFalse(
                    diagnostic.message.contains("/Users/"),
                    fixture.workshopID
                )
            }

            let first = try SceneAuditReportEncoder.encode(report)
            let second = try SceneAuditReportEncoder.encode(report)
            XCTAssertEqual(first, second, fixture.workshopID)
        }
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func packageURL(for fixture: LocalSceneFixture) -> URL {
        repositoryRoot
            .appending(path: "test")
            .appending(path: fixture.workshopID)
            .appending(path: "scene.pkg")
    }
}

private struct LocalSceneCatalog: Codable {
    let schemaVersion: Int
    let fixtures: [LocalSceneFixture]
}

private struct LocalSceneFixture: Codable {
    let workshopID: String
    let packageVersion: String
    let entryCount: Int
    let objectKinds: [String: Int]
    let textureFormats: [String: Int]
    let textureFlags: [String: Int]
    let textureContainers: [String: Int]
    let features: [String: Int]
}

private func counts(_ values: [SceneAuditCount]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0.count) })
}

private func counted<T: Hashable>(_ values: [T]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for value in values {
        counts[String(describing: value), default: 0] += 1
    }
    return counts
}
