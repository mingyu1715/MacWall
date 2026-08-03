import Foundation
import XCTest
@testable import MacWallSceneAudit
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneAuditorTests: XCTestCase {
    func testAuditsObjectsTexturesDependenciesAndScripts() {
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 4,
            flagsRawValue: 2,
            textureSize: (4, 4),
            imageSize: (4, 4),
            container: .b0003(imageFormatRawValue: 4),
            images: [.init(mipmaps: [
                .init(
                    width: 4,
                    height: 4,
                    payload: Data(repeating: 0, count: 16)
                )
            ])]
        )
        let scene = """
        {
          "general": {
            "orthogonalprojection": {
              "width": 1920,
              "height": 1080
            }
          },
          "objects": [
            {
              "id": 1,
              "image": "models/background.json",
              "effects": [
                {"file": "effects/missing/effect.json"}
              ]
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
        let report = audit(entries: [
            .init(path: "scene.json", data: Data(scene.utf8)),
            .init(
                path: "models/background.json",
                data: Data(
                    #"{"material":"materials/background.json"}"#.utf8
                )
            ),
            .init(
                path: "materials/background.json",
                data: Data(
                    #"{"passes":[{"shader":"genericimage4","textures":["background"]}]}"#.utf8
                )
            ),
            .init(
                path: "materials/background.tex",
                data: texture
            )
        ])

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.package.version, "PKGV0008")
        XCTAssertEqual(report.package.entryCount, 4)
        XCTAssertEqual(
            report.canvas,
            SceneAuditCanvas(width: 1_920, height: 1_080)
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: report.objectKinds.map {
                    ($0.name, $0.count)
                }
            ),
            ["image": 1, "particle": 1, "unknown": 1]
        )
        XCTAssertEqual(report.textures.map(\.status), [.parsed])
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
            $0.requestedPath
                == "effects/missing/effect.json"
                && $0.resolution == .unresolved
        })
        XCTAssertEqual(report.status, .unsupported)
    }

    func testResolvesOwnerRelativeDocumentDependency() {
        let report = audit(entries: [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            jsonEntry(
                "models/sub/model.json",
                #"{"material":"../materials/base.json"}"#
            ),
            jsonEntry("models/materials/base.json", #"{}"#)
        ])

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertTrue(report.dependencies.contains {
            $0.ownerPath == "models/sub/model.json"
                && $0.requestedPath == "../materials/base.json"
                && $0.resolvedPath == "models/materials/base.json"
                && $0.resolution == .package
        })
    }

    func testMalformedPackageReturnsInvalidReportWithoutThrowing() {
        let report = SceneAuditor().audit(
            source: SceneDataByteSource(
                data: Data("not-a-package".utf8)
            )
        )

        XCTAssertEqual(report.status, .invalid)
        XCTAssertNil(report.package.version)
        XCTAssertEqual(report.package.entryCount, 0)
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["package.invalid-index"]
        )
        XCTAssertEqual(report.diagnostics.first?.severity, .error)
    }

    func testDuplicatePathUsesStableDiagnostic() {
        let report = audit(entries: [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            jsonEntry("scene.json", #"{"objects":[]}"#)
        ])

        XCTAssertEqual(report.status, .invalid)
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["package.duplicate-entry-path"]
        )
    }

    func testPackageIssuesBecomeSortedWarnings() {
        let shared = Data(#"{"objects":[]}"#.utf8)
        let report = audit(
            version: "PKGV0099",
            entries: [
                .init(
                    path: "scene.json",
                    data: shared,
                    tableOffset: 0,
                    tableLength: Int32(shared.count)
                ),
                .init(
                    path: "a.json",
                    data: shared,
                    tableOffset: 0,
                    tableLength: Int32(shared.count)
                )
            ]
        )

        XCTAssertEqual(
            Set(report.diagnostics.map(\.code)),
            Set([
                "package.unverified-version",
                "package.overlapping-entry-range"
            ])
        )
        XCTAssertTrue(
            report.diagnostics.allSatisfy {
                $0.severity == .warning
            }
        )
        XCTAssertEqual(report.status, .degraded)
    }

    func testUnknownTextureLayoutsKeepPartialEvidence() {
        let cases: [
            (
                bytes: Data,
                status: SceneAuditTextureStatus,
                code: String
            )
        ] = [
            (
                SceneTextureFixtureBuilder.make(
                    version: "TEXV0006",
                    formatRawValue: 0,
                    textureSize: (1, 1),
                    imageSize: (1, 1),
                    container: .b0001,
                    images: []
                ),
                .unsupportedVersion,
                "texture.unsupported-version"
            ),
            (
                SceneTextureFixtureBuilder.make(
                    infoVersion: "TEXI0002",
                    formatRawValue: 0,
                    textureSize: (1, 1),
                    imageSize: (1, 1),
                    container: .b0001,
                    images: []
                ),
                .unsupportedInfoVersion,
                "texture.unsupported-info-version"
            ),
            (
                SceneTextureFixtureBuilder.make(
                    formatRawValue: 0,
                    textureSize: (1, 1),
                    imageSize: (1, 1),
                    container: .raw("TEXB9999"),
                    images: []
                ),
                .unsupportedContainer,
                "texture.unsupported-container"
            )
        ]

        for (bytes, status, code) in cases {
            let report = audit(entries: [
                jsonEntry("scene.json", #"{"objects":[]}"#),
                .init(path: "materials/test.tex", data: bytes)
            ])

            XCTAssertEqual(report.textures.map(\.status), [status])
            XCTAssertEqual(report.diagnostics.map(\.code), [code])
            XCTAssertEqual(report.status, .unsupported)
        }
    }

    func testInvalidTextureMetadataUsesStableDiagnostic() {
        let report = audit(entries: [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            .init(
                path: "materials/bad.tex",
                data: Data("bad".utf8)
            )
        ])

        XCTAssertEqual(report.textures.map(\.status), [.invalid])
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["texture.invalid-metadata"]
        )
        XCTAssertEqual(report.status, .unsupported)
    }

    func testTrailingTextureBytesBecomeWarning() {
        let texture = SceneTextureFixtureBuilder.make(
            formatRawValue: 13,
            textureSize: (1, 1),
            imageSize: (1, 1),
            container: .b0003(imageFormatRawValue: 13),
            images: [.init(mipmaps: [
                .init(width: 1, height: 1, payload: Data([1]))
            ])],
            trailingBytes: Data([9, 8])
        )
        let report = audit(entries: [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            .init(path: "materials/trailing.tex", data: texture)
        ])

        XCTAssertEqual(
            report.textures.first?.trailingByteCount,
            2
        )
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["texture.trailing-bytes"]
        )
        XCTAssertEqual(report.status, .degraded)
    }

    func testJSONLimitsUseProductionDefaultsAndSkipAuxiliary() {
        let defaults = SceneAuditLimits()
        XCTAssertEqual(
            defaults.maximumJSONEntryBytes,
            16 * 1_024 * 1_024
        )
        XCTAssertEqual(
            defaults.maximumCumulativeJSONBytes,
            64 * 1_024 * 1_024
        )

        let report = audit(
            entries: [
                jsonEntry("scene.json", #"{"objects":[]}"#),
                jsonEntry(
                    "materials/oversized.json",
                    #"{"padding":"12345678901234567890"}"#
                )
            ],
            limits: .init(
                maximumJSONEntryBytes: 24,
                maximumCumulativeJSONBytes: 100
            )
        )

        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["resource.limit-exceeded"]
        )
        XCTAssertEqual(
            report.diagnostics.first?.path,
            "materials/oversized.json"
        )
        XCTAssertEqual(report.status, .degraded)
    }

    func testOversizedSceneJSONMakesReportInvalid() {
        let report = audit(
            entries: [
                jsonEntry("scene.json", #"{"objects":[]}"#)
            ],
            limits: .init(
                maximumJSONEntryBytes: 5,
                maximumCumulativeJSONBytes: 100
            )
        )

        XCTAssertEqual(report.status, .invalid)
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["resource.limit-exceeded"]
        )
        XCTAssertEqual(report.diagnostics.first?.severity, .error)
    }

    func testCumulativeJSONLimitSkipsAuxiliaryInPathOrder() {
        let entries = [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            jsonEntry("z.json", #"{"z":1234}"#),
            jsonEntry("a.json", #"{"a":1234}"#)
        ]
        let limits = SceneAuditLimits(
            maximumJSONEntryBytes: 100,
            maximumCumulativeJSONBytes: 30
        )
        let first = audit(entries: entries, limits: limits)
        let second = audit(
            entries: [entries[2], entries[0], entries[1]],
            limits: limits
        )

        XCTAssertEqual(
            first.diagnostics.filter {
                $0.code == "resource.limit-exceeded"
            }.map(\.path),
            ["z.json"]
        )
        XCTAssertEqual(
            try? SceneAuditReportEncoder.encode(first),
            try? SceneAuditReportEncoder.encode(second)
        )
    }

    func testReportOrderingDoesNotDependOnEntryOrder() {
        let entries = [
            jsonEntry("scene.json", #"{"objects":[]}"#),
            jsonEntry("materials/z.json", #"{"passes":[]}"#),
            jsonEntry("materials/a.json", #"{"passes":[]}"#)
        ]
        let first = audit(entries: entries)
        let second = audit(entries: Array(entries.reversed()))

        XCTAssertEqual(
            try? SceneAuditReportEncoder.encode(first),
            try? SceneAuditReportEncoder.encode(second)
        )
    }

    func testURLFailureDiagnosticDoesNotLeakInputPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        let packageURL = directory.appending(path: "missing.pkg")

        let report = SceneAuditor().audit(url: packageURL)
        let encoded = try SceneAuditReportEncoder.encode(report)
        let string = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(report.status, .invalid)
        XCTAssertFalse(string.contains(directory.path))
        XCTAssertFalse(string.contains("/Users/"))
    }

    private func audit(
        version: String = "PKGV0008",
        entries: [ScenePackageFixtureEntry],
        limits: SceneAuditLimits = .init()
    ) -> SceneAuditReport {
        let bytes = ScenePackageFixtureBuilder.make(
            version: version,
            entries: entries
        )
        return SceneAuditor(limits: limits).audit(
            source: SceneDataByteSource(data: bytes)
        )
    }

    private func jsonEntry(
        _ path: String,
        _ json: String
    ) -> ScenePackageFixtureEntry {
        ScenePackageFixtureEntry(
            path: path,
            data: Data(json.utf8)
        )
    }
}
