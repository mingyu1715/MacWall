import Foundation
import XCTest
@testable import MacWallCore

final class SceneAuditorTests: XCTestCase {
    func testAuditsObjectsTexturesDependenciesAndScripts() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        let texture = Fixture.texData(
            format: 4,
            flags: 2,
            width: 4,
            height: 4,
            images: [TextureImageFixture(mipmaps: [Data(repeating: 0, count: 16)])]
        )
        let sceneJSON = """
        {
          "general": {
            "orthogonalprojection": { "width": 1920, "height": 1080 }
          },
          "objects": [
            {
              "id": 1,
              "name": "background",
              "image": "models/background.json",
              "effects": [{"file": "effects/missing/effect.json"}]
            },
            {
              "id": 2,
              "parent": 1,
              "particle": "particles/snow.json",
              "script": "export function update() {}"
            },
            {
              "id": 3,
              "instance": 1,
              "mystery": "unknown"
            }
          ]
        }
        """
        try Fixture.writeScenePackage(
            to: packageURL,
            sceneJSON: sceneJSON,
            extraEntries: [
                (
                    path: "models/background.json",
                    data: Data(#"{"material":"materials/background.json"}"#.utf8)
                ),
                (
                    path: "materials/background.json",
                    data: Data(
                        #"{"passes":[{"shader":"genericimage4","textures":["background"]}]}"#.utf8
                    )
                ),
                (path: "materials/background.tex", data: texture),
            ]
        )

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.package.version, "PKGV0007")
        XCTAssertEqual(report.package.entryCount, 4)
        XCTAssertEqual(report.canvas, SceneAuditCanvas(width: 1920, height: 1080))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: report.objectKinds.map {
                ($0.name, $0.count)
            }),
            ["image": 1, "particle": 1, "unknown": 1]
        )
        XCTAssertEqual(report.textures.map(\.formatRawValue), [4])
        XCTAssertTrue(report.features.contains {
            $0.key == .parentGraph && $0.count == 1
        })
        XCTAssertTrue(report.features.contains {
            $0.key == .instance && $0.count == 1
        })
        XCTAssertEqual(
            report.scriptHandlers,
            [SceneAuditCount(name: "update", count: 1)]
        )
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "models/background.json"
                && $0.resolution == .package
        })
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "genericimage4"
                && $0.resolution == .builtInCandidate
        })
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "effects/missing/effect.json"
                && $0.resolution == .unresolved
        })
        XCTAssertEqual(report.status, .unsupported)
    }

    func testInvalidPackageReturnsInvalidReportInsteadOfThrowing() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        try Data("not-a-package".utf8).write(to: packageURL)

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.status, .invalid)
        XCTAssertNil(report.package.version)
        XCTAssertEqual(report.package.entryCount, 0)
        XCTAssertEqual(report.diagnostics.first?.severity, .error)
        XCTAssertEqual(
            report.diagnostics.first?.code,
            "package.invalid-string-length"
        )
        XCTAssertFalse(
            report.diagnostics.first?.message.contains(root.path) ?? true
        )
    }

    func testUnsafeEntryPathBecomesStableInvalidDiagnostic() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        try Fixture.scenePackageData(entries: [
            (path: "../escape.json", data: Data())
        ]).write(to: packageURL)

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.status, .invalid)
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["package.unsafe-entry-path"]
        )
        XCTAssertFalse(
            report.diagnostics[0].message.contains("../escape.json")
        )
    }

    func testAuditJSONIsIndependentOfPackageEntryOrdering() throws {
        let root = try Fixture.makeTempDirectory()
        let firstURL = root.appending(path: "first.pkg")
        let secondURL = root.appending(path: "second.pkg")
        let scene = Data(#"{"objects":[]}"#.utf8)
        let material = Data(#"{"passes":[]}"#.utf8)
        try Fixture.scenePackageData(entries: [
            (path: "scene.json", data: scene),
            (path: "materials/a.json", data: material),
        ]).write(to: firstURL)
        try Fixture.scenePackageData(entries: [
            (path: "materials/a.json", data: material),
            (path: "scene.json", data: scene),
        ]).write(to: secondURL)

        let first = try SceneAuditReportEncoder.encode(
            SceneAuditor().audit(url: firstURL)
        )
        let second = try SceneAuditReportEncoder.encode(
            SceneAuditor().audit(url: secondURL)
        )

        XCTAssertEqual(first, second)
    }
}
