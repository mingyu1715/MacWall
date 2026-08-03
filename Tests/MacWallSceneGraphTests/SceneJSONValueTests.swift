import Foundation
import XCTest
@testable import MacWallSceneGraph

final class SceneJSONValueTests: XCTestCase {
    func testDocumentDecoderDistinguishesJSONValueTypes() throws {
        let value = try SceneJSONDocumentDecoder(
            maximumDepth: 8
        ).decode(Data(#"{"bool":true,"int":7,"double":7.5,"null":null}"#.utf8))

        XCTAssertEqual(
            value,
            .object([
                "bool": .bool(true),
                "int": .integer(7),
                "double": .number(7.5),
                "null": .null
            ])
        )
    }

    func testCodableRoundTripPreservesNestedValues() throws {
        let original: SceneJSONValue = .object([
            "array": .array([
                .null,
                .bool(false),
                .integer(-42),
                .number(1.25),
                .string("value")
            ]),
            "object": .object([
                "kind": .string("arbitrary object key"),
                "value": .string("arbitrary object key")
            ])
        ])

        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(SceneJSONValue.self, from: encoded), original)
    }

    func testCodableRoundTripPreservesIntegralValuedDouble() throws {
        let original: SceneJSONValue = .number(1.0)

        let encoded = try JSONEncoder().encode(original)

        XCTAssertEqual(
            try JSONDecoder().decode(SceneJSONValue.self, from: encoded),
            original
        )
    }

    func testJSONEncoderSortsObjectKeysWhenRequested() throws {
        let value: SceneJSONValue = .object([
            "z": .integer(1),
            "a": .integer(2)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        XCTAssertEqual(
            String(decoding: try encoder.encode(value), as: UTF8.self),
            #"{"kind":"object","value":{"a":{"kind":"integer","value":2},"z":{"kind":"integer","value":1}}}"#
        )
    }

    func testDocumentDecoderRejectsMalformedJSON() {
        XCTAssertThrowsError(
            try SceneJSONDocumentDecoder(maximumDepth: 8).decode(
                Data(#"{"key":]"#.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? SceneJSONDocumentError, .malformed)
        }
    }

    func testDocumentDecoderAcceptsRootFragment() throws {
        XCTAssertEqual(
            try SceneJSONDocumentDecoder(maximumDepth: 8).decode(Data("true".utf8)),
            .bool(true)
        )
    }

    func testDocumentDecoderRejectsValuesBeyondInjectedDepthLimit() {
        XCTAssertThrowsError(
            try SceneJSONDocumentDecoder(maximumDepth: 2).decode(
                Data(#"{"one":{"two":{"three":true}}}"#.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? SceneJSONDocumentError, .depthLimit(maximum: 2))
        }
    }

    func testGraphLimitsUseProductionDefaults() {
        XCTAssertEqual(
            SceneGraphLimits(),
            SceneGraphLimits(
                maximumJSONEntryBytes: 16 * 1_024 * 1_024,
                maximumCumulativeJSONBytes: 64 * 1_024 * 1_024,
                maximumNodeCount: 100_000,
                maximumDependencyEdgeCount: 500_000,
                maximumAnimationKeyframeCount: 1_000_000,
                maximumJSONDepth: 256,
                maximumHierarchyDepth: 4_096
            )
        )
    }
}
