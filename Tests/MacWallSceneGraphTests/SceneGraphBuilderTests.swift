import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneGraphBuilderTests: XCTestCase {
    func testBuildPreservesSourceOrderAndClassifiesTypedNodes() throws {
        let result = try build("""
        {
          "objects": [
            {"image":"images/a.json"},
            {"text":{"value":"hello"}},
            {"particle":"particles/snow.json"},
            {"sound":"sounds/rain.json"},
            {"model":"models/mesh.json"},
            {"composition":"compositions/child.json"},
            {"fullscreen":true},
            {"mystery":"kept"}
          ]
        }
        """)

        XCTAssertEqual(
            result.document?.nodes.map(\.id.rawValue),
            (0..<8).map { "scene.json#objects[\($0)]" }
        )
        XCTAssertEqual(
            result.document?.nodes.map(\.payload.kind),
            [
                .image, .text, .particle, .sound,
                .model, .composition, .fullscreen, .unknown(nil)
            ]
        )
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.unknown-node" })
    }

    func testBuildPreservesIdentifiersAndCommonTypedProperties() throws {
        let result = try build("""
        {
          "general":{"orthogonalprojection":{"width":1920,"height":1080}},
          "objects":[
            {
              "id":7,
              "name":"first",
              "image":"images/one.json",
              "visible":{"value":true,"animation":{"ignored":true}},
              "enabled":false,
              "origin":"1, 2 3",
              "pivot":"4 5 6",
              "position":[7,8,9],
              "scale":{"value":"10,11,12"},
              "angles":"13 14 15",
              "size":"640, 480",
              "alpha":{"value":0.5},
              "color":[1,0.5,0.25,1],
              "zindex":3,
              "custom":{"retained":true}
            },
            {"id":"second","fullscreen":true},
            {"fullscreen":true}
          ]
        }
        """)

        let document = try XCTUnwrap(result.document)
        let first = try XCTUnwrap(document.nodes.first)
        XCTAssertEqual(document.canvas, SceneGraphCanvas(width: 1920, height: 1080))
        XCTAssertEqual(first.sourceIdentifier, .integer(7))
        XCTAssertEqual(first.name, "first")
        XCTAssertEqual(first.visible, true)
        XCTAssertEqual(first.enabled, false)
        XCTAssertEqual(first.origin, SceneGraphVector3(x: 1, y: 2, z: 3))
        XCTAssertEqual(first.pivot, SceneGraphVector3(x: 4, y: 5, z: 6))
        XCTAssertEqual(first.position, SceneGraphVector3(x: 7, y: 8, z: 9))
        XCTAssertEqual(first.scale, SceneGraphVector3(x: 10, y: 11, z: 12))
        XCTAssertEqual(first.angles, SceneGraphVector3(x: 13, y: 14, z: 15))
        XCTAssertEqual(first.size, SceneGraphSize(width: 640, height: 480))
        XCTAssertEqual(first.opacity, 0.5)
        XCTAssertEqual(first.color, SceneGraphColor(red: 1, green: 0.5, blue: 0.25, alpha: 1))
        XCTAssertEqual(first.zOrder, 3)
        XCTAssertEqual(first.unknownFields, ["custom": .object(["retained": .bool(true)])])
        XCTAssertEqual(document.nodes[1].sourceIdentifier, .string("second"))
        XCTAssertNil(document.nodes[2].sourceIdentifier)
        XCTAssertEqual(result.status, .degraded)
    }

    func testBuildUsesExactPayloadClassificationOrderAndLowercaseTypes() throws {
        let result = try build(#"""
        {
          "objects":[
            {"type":"image"},
            {"type":"text"},
            {"type":"particle"},
            {"type":"sound"},
            {"type":"model"},
            {"type":"composition"},
            {"type":"fullscreen"},
            {"type":"Fullscreen"},
            {"image":"first","text":"second","type":"sound"}
          ]
        }
        """#)

        let nodes = try XCTUnwrap(result.document?.nodes)
        XCTAssertEqual(nodes.map(\.payload.kind), [
            .image, .text, .particle, .sound, .model, .composition,
            .fullscreen, .unknown("Fullscreen"), .image
        ])
        XCTAssertEqual(nodes.last?.unknownFields, [
            "text": .string("second"),
            "type": .string("sound")
        ])
        XCTAssertEqual(result.status, .unsupported)
    }

    func testBuildDoesNotApplyHistoricalNodeCountCap() throws {
        let objects = (0..<17).map {
            "{\"fullscreen\":true,\"id\":\($0)}"
        }.joined(separator: ",")
        let result = try build("{\"objects\":[\(objects)]}")

        XCTAssertEqual(result.document?.nodes.count, 17)
        XCTAssertEqual(result.document?.nodes.last?.sourceOrder, 16)
        XCTAssertEqual(result.status, .exact)
    }

    func testBuildRetainsUnknownNodeAndMalformedIdentifier() throws {
        let result = try build(#"""
        {
          "objects":[
            {"id":true,"type":"future-node","visible":"yes","custom":[1,2]},
            {"type":9}
          ]
        }
        """#)

        let node = try XCTUnwrap(result.document?.nodes.first)
        XCTAssertEqual(node.payload, .unknown(typeName: "future-node", rawValue: .object([
            "id": .bool(true),
            "type": .string("future-node"),
            "visible": .string("yes"),
            "custom": .array([.integer(1), .integer(2)])
        ])))
        XCTAssertEqual(node.unknownFields["id"], .bool(true))
        XCTAssertEqual(node.unknownFields["visible"], .string("yes"))
        XCTAssertEqual(node.unknownFields["custom"], .array([.integer(1), .integer(2)]))
        XCTAssertEqual(result.document?.nodes[1].unknownFields["type"], .integer(9))
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.invalid-property" })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.unknown-node" })
    }

    func testBuildTreatsMissingObjectsAsEmptyExactDocument() throws {
        let result = try build(#"""
        {
          "title":"Empty",
          "general":{"orthogonalprojection":{"width":0,"height":100}}
        }
        """#)

        XCTAssertEqual(result.document?.nodes, [])
        XCTAssertEqual(result.document?.sceneMetadata["title"], .string("Empty"))
        XCTAssertNil(result.document?.canvas)
        XCTAssertEqual(result.status, .exact)
    }

    func testBuildRejectsInvalidRootShapesAndPreservesObjectIndices() throws {
        let nonArray = try build(#"{"objects":{}}"#)
        XCTAssertNil(nonArray.document)
        XCTAssertEqual(nonArray.status, .invalid)
        XCTAssertEqual(nonArray.diagnostics.map(\.code), ["graph.malformed-scene-json"])

        let nonObject = try build(#"{"objects":["not-an-object",{"fullscreen":true}]}"#)
        XCTAssertEqual(nonObject.document?.nodes.map(\.id.rawValue), [
            "scene.json#objects[0]", "scene.json#objects[1]"
        ])
        XCTAssertEqual(nonObject.document?.nodes.first?.payload, .unknown(
            typeName: nil,
            rawValue: .string("not-an-object")
        ))
        XCTAssertEqual(nonObject.status, .unsupported)
        XCTAssertTrue(nonObject.diagnostics.contains { $0.code == "graph.invalid-property" })
    }

    func testBuildReportsMalformedMissingOversizedAndInvalidPackages() throws {
        let malformed = try build(#"{"objects":]"#)
        XCTAssertNil(malformed.document)
        XCTAssertEqual(malformed.status, .invalid)
        XCTAssertEqual(malformed.diagnostics.map(\.code), ["graph.malformed-scene-json"])

        let missing = try buildPackage(entries: [])
        XCTAssertNil(missing.document)
        XCTAssertEqual(missing.status, .invalid)
        XCTAssertEqual(missing.diagnostics.map(\.code), ["graph.malformed-scene-json"])

        let oversized = try build(
            #"{"objects":[]}"#,
            limits: SceneGraphLimits(maximumJSONEntryBytes: 1)
        )
        XCTAssertNil(oversized.document)
        XCTAssertEqual(oversized.status, .invalid)
        XCTAssertEqual(oversized.diagnostics.map(\.code), ["graph.resource-limit"])

        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try Data("not-a-package".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let invalid = SceneGraphBuilder().build(url: url)
        XCTAssertNil(invalid.document)
        XCTAssertEqual(invalid.status, .invalid)
        XCTAssertEqual(invalid.diagnostics.map(\.code), ["graph.invalid-package"])
    }

    func testBuildEnforcesRootNodeCumulativeAndDepthBounds() throws {
        let scene = #"{"objects":[{"fullscreen":true},{"fullscreen":true}]}"#
        let byteCount = UInt64(scene.utf8.count)
        let exact = try build(
            scene,
            limits: SceneGraphLimits(
                maximumJSONEntryBytes: byteCount,
                maximumCumulativeJSONBytes: byteCount,
                maximumNodeCount: 2,
                maximumJSONDepth: 3
            )
        )
        XCTAssertEqual(exact.document?.nodes.count, 2)
        XCTAssertEqual(exact.status, .exact)

        let cumulative = try build(
            scene,
            limits: SceneGraphLimits(
                maximumJSONEntryBytes: byteCount,
                maximumCumulativeJSONBytes: byteCount - 1
            )
        )
        XCTAssertNil(cumulative.document)
        XCTAssertEqual(cumulative.diagnostics.map(\.code), ["graph.resource-limit"])

        let nodes = try build(
            scene,
            limits: SceneGraphLimits(maximumNodeCount: 1)
        )
        XCTAssertNil(nodes.document)
        XCTAssertEqual(nodes.diagnostics.map(\.code), ["graph.resource-limit"])

        let depth = try build(
            scene,
            limits: SceneGraphLimits(maximumJSONDepth: 2)
        )
        XCTAssertNil(depth.document)
        XCTAssertEqual(depth.diagnostics.map(\.code), ["graph.malformed-scene-json"])

        let nonObjectRoot = try build("[]")
        XCTAssertNil(nonObjectRoot.document)
        XCTAssertEqual(
            nonObjectRoot.diagnostics.map(\.code),
            ["graph.malformed-scene-json"]
        )
    }

    func testBuildConvertsPackageIssuesAndSortsDiagnostics() throws {
        let scene = Data(#"{"objects":[{"mystery":true}]}"#.utf8)
        let result = try buildPackage(
            version: "PKGV0099",
            entries: [
                .init(
                    path: "scene.json",
                    data: scene,
                    tableOffset: 0,
                    tableLength: Int32(scene.count)
                ),
                .init(
                    path: "other.json",
                    data: scene,
                    tableOffset: 0,
                    tableLength: Int32(scene.count)
                )
            ]
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.diagnostics.map(\.code), [
            "package.unverified-version",
            "package.overlapping-entry-range",
            "graph.unknown-node",
            "graph.invalid-property"
        ])
        XCTAssertEqual(result.diagnostics.map(\.severity), [
            .warning, .warning, .warning, .warning
        ])
    }

    private func build(
        _ scene: String,
        limits: SceneGraphLimits = .init()
    ) throws -> SceneGraphBuildResult {
        try buildPackage(entries: [
            .init(path: "scene.json", data: Data(scene.utf8))
        ], limits: limits)
    }

    private func buildPackage(
        version: String = "PKGV0008",
        entries: [ScenePackageFixtureEntry],
        limits: SceneGraphLimits = .init()
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(version: version, entries: entries)
            )
        )
        return SceneGraphBuilder(limits: limits).build(resolver: resolver)
    }
}
