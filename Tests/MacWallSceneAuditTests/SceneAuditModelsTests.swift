import Foundation
import XCTest
@testable import MacWallSceneAudit

final class SceneAuditModelsTests: XCTestCase {
    func testEmptyReportUsesSchemaVersionTwo() {
        let report = SceneAuditReport.empty(status: .exact)

        XCTAssertEqual(SceneAuditReport.currentSchemaVersion, 2)
        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(
            report.package,
            SceneAuditPackageSummary(version: nil, entryCount: 0)
        )
        XCTAssertNil(report.canvas)
        XCTAssertTrue(report.textures.isEmpty)
        XCTAssertEqual(report.status, .exact)
    }

    func testTextureSummaryPreservesPartialOptionalEvidence() throws {
        let summary = SceneAuditTextureSummary(
            path: "materials/unknown.tex",
            status: .unsupportedContainer,
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: 777,
            flagsRawValue: nil,
            textureWidth: nil,
            textureHeight: nil,
            imageWidth: nil,
            imageHeight: nil,
            declaredContainer: "TEXB9999",
            mipmapLayout: nil,
            imageFormatRawValue: nil,
            isVideoMP4: nil,
            imageCount: nil,
            mipmapCounts: nil,
            animationVersion: nil,
            animationFrameCount: nil,
            trailingByteCount: nil
        )
        let report = SceneAuditReport(
            package: .init(version: "PKGV0008", entryCount: 1),
            canvas: nil,
            entryKinds: [],
            objectKinds: [],
            textures: [summary],
            dependencies: [],
            scriptHandlers: [],
            features: [],
            diagnostics: [],
            status: .unsupported
        )

        let encoded = try SceneAuditReportEncoder.encode(report)
        let string = String(decoding: encoded, as: UTF8.self)

        XCTAssertTrue(string.contains(#""status" : "unsupportedContainer""#))
        XCTAssertTrue(string.contains(#""declaredContainer" : "TEXB9999""#))
        XCTAssertFalse(string.contains(#""flagsRawValue""#))
        XCTAssertFalse(string.contains(#""imageCount""#))
    }

    func testS1SupportPolicyUsesStableSeverityPrecedence() {
        let exact = [
            SceneAuditFeatureObservation(
                key: .packageIndex,
                count: 1,
                support: .exact
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: exact,
                diagnostics: []
            ),
            .exact
        )

        let degraded = exact + [
            SceneAuditFeatureObservation(
                key: .imageLayer,
                count: 1,
                support: .degraded
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: degraded,
                diagnostics: []
            ),
            .degraded
        )
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: exact,
                diagnostics: [
                    diagnostic(severity: .warning)
                ]
            ),
            .degraded
        )

        let unsupported = degraded + [
            SceneAuditFeatureObservation(
                key: .particleSystem,
                count: 1,
                support: .unsupported
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: unsupported,
                diagnostics: []
            ),
            .unsupported
        )
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: [
                    SceneAuditFeatureObservation(
                        key: .unknownObject,
                        count: 1,
                        support: .unknown
                    )
                ],
                diagnostics: []
            ),
            .unsupported
        )
        XCTAssertEqual(
            SceneAuditSupportPolicy.s1.evaluate(
                features: unsupported,
                diagnostics: [
                    diagnostic(severity: .error)
                ]
            ),
            .invalid
        )
    }

    func testCanonicalEncoderSortsSemanticArraysAndIsStable() throws {
        let report = SceneAuditReport(
            package: .init(version: "PKGV0008", entryCount: 2),
            canvas: .init(width: 1_920, height: 1_080),
            entryKinds: [
                .init(name: "texture", count: 1),
                .init(name: "json", count: 1)
            ],
            objectKinds: [
                .init(name: "text", count: 1),
                .init(name: "image", count: 1)
            ],
            textures: [
                texture(path: "z.tex"),
                texture(path: "a.tex")
            ],
            dependencies: [
                .init(
                    ownerPath: "z.json",
                    key: "texture",
                    requestedPath: "z.tex",
                    resolvedPath: nil,
                    resolution: .unresolved
                ),
                .init(
                    ownerPath: "a.json",
                    key: "texture",
                    requestedPath: "a.tex",
                    resolvedPath: "a.tex",
                    resolution: .package
                )
            ],
            scriptHandlers: [
                .init(name: "update", count: 1),
                .init(name: "init", count: 1)
            ],
            features: [
                .init(
                    key: .textLayer,
                    count: 1,
                    support: .degraded
                ),
                .init(
                    key: .imageLayer,
                    count: 1,
                    support: .degraded
                )
            ],
            diagnostics: [
                .init(
                    severity: .warning,
                    code: "z.code",
                    path: "z.json",
                    message: "z"
                ),
                .init(
                    severity: .info,
                    code: "a.code",
                    path: nil,
                    message: "a"
                )
            ],
            status: .degraded
        )

        XCTAssertEqual(report.entryKinds.map(\.name), ["json", "texture"])
        XCTAssertEqual(report.objectKinds.map(\.name), ["image", "text"])
        XCTAssertEqual(report.textures.map(\.path), ["a.tex", "z.tex"])
        XCTAssertEqual(
            report.dependencies.map(\.ownerPath),
            ["a.json", "z.json"]
        )
        XCTAssertEqual(
            report.features.map(\.key),
            [.imageLayer, .textLayer]
        )

        let first = try SceneAuditReportEncoder.encode(report)
        let second = try SceneAuditReportEncoder.encode(report)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.last, 0x0A)
        XCTAssertNotEqual(first.dropLast().last, 0x0A)
        XCTAssertFalse(
            String(decoding: first, as: UTF8.self)
                .contains("/Users/")
        )
    }

    private func diagnostic(
        severity: SceneAuditDiagnosticSeverity
    ) -> SceneAuditDiagnostic {
        SceneAuditDiagnostic(
            severity: severity,
            code: "test.code",
            path: nil,
            message: "Test diagnostic."
        )
    }

    private func texture(path: String) -> SceneAuditTextureSummary {
        SceneAuditTextureSummary(
            path: path,
            status: .parsed,
            version: "TEXV0005",
            infoVersion: "TEXI0001",
            formatRawValue: 13,
            flagsRawValue: 0,
            textureWidth: 1,
            textureHeight: 1,
            imageWidth: 1,
            imageHeight: 1,
            declaredContainer: "TEXB0003",
            mipmapLayout: "b0002OrB0003",
            imageFormatRawValue: 13,
            isVideoMP4: false,
            imageCount: 1,
            mipmapCounts: [1],
            animationVersion: nil,
            animationFrameCount: nil,
            trailingByteCount: nil
        )
    }
}
