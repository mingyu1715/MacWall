import Foundation
import XCTest
@testable import MacWallCore

final class SceneAuditModelsTests: XCTestCase {
    func testS0SupportPolicyUsesStableSeverityPrecedence() {
        let exact = [
            SceneAuditFeatureObservation(
                key: .packageIndex,
                count: 1,
                support: .exact
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
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
            SceneAuditSupportPolicy.s0.evaluate(
                features: degraded,
                diagnostics: []
            ),
            .degraded
        )

        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: exact,
                diagnostics: [
                    SceneAuditDiagnostic(
                        severity: .warning,
                        code: "texture.unknown-format",
                        path: "materials/unknown.tex",
                        message: "Unknown texture format"
                    )
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
            SceneAuditSupportPolicy.s0.evaluate(
                features: unsupported,
                diagnostics: []
            ),
            .unsupported
        )

        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: exact,
                diagnostics: [
                    SceneAuditDiagnostic(
                        severity: .error,
                        code: "package.invalid",
                        path: nil,
                        message: "invalid"
                    )
                ]
            ),
            .invalid
        )
    }

    func testCanonicalEncoderIsStableAndContainsNoAbsolutePath() throws {
        let report = SceneAuditReport(
            package: SceneAuditPackageSummary(
                version: "PKGV0008",
                entryCount: 2
            ),
            canvas: SceneAuditCanvas(width: 1920, height: 1080),
            entryKinds: [
                SceneAuditCount(name: "texture", count: 1),
                SceneAuditCount(name: "json", count: 1)
            ],
            objectKinds: [
                SceneAuditCount(name: "image", count: 1)
            ],
            textures: [],
            dependencies: [],
            scriptHandlers: [],
            features: [
                SceneAuditFeatureObservation(
                    key: .imageLayer,
                    count: 1,
                    support: .degraded
                )
            ],
            diagnostics: [],
            status: .degraded
        )

        let first = try SceneAuditReportEncoder.encode(report)
        let second = try SceneAuditReportEncoder.encode(report)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.last, 0x0A)
        let string = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertFalse(string.contains("/Users/"))
        XCTAssertLessThan(
            try XCTUnwrap(string.range(of: #""json""#)?.lowerBound),
            try XCTUnwrap(string.range(of: #""texture""#)?.lowerBound)
        )
    }
}
