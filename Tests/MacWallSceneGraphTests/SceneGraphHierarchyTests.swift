import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneGraphHierarchyTests: XCTestCase {
    func testBuildResolvesIntegerAndStringParentReferencesInSourceOrder() throws {
        let result = try build(#"""
        {"objects":[
          {"id":1,"fullscreen":true},
          {"id":"child","parent":1,"fullscreen":true},
          {"id":"leaf","parent":"child","fullscreen":true}
        ]}
        """#)

        let document = try XCTUnwrap(result.document)
        let nodes = document.nodes
        XCTAssertEqual(document.hierarchyEdges, [
            SceneHierarchyEdge(
                childID: nodes[1].id,
                requestedParent: .integer(1),
                resolution: .resolved(nodes[0].id)
            ),
            SceneHierarchyEdge(
                childID: nodes[2].id,
                requestedParent: .string("child"),
                resolution: .resolved(nodes[1].id)
            )
        ])
        XCTAssertEqual(result.status, .exact)
    }

    func testBuildRetainsMissingParentAndInstanceEdges() throws {
        let result = try build(#"""
        {"objects":[
          {"id":"parentless","parent":99,"fullscreen":true},
          {"id":"instance","instance":"absent","fullscreen":true}
        ]}
        """#)

        let document = try XCTUnwrap(result.document)
        XCTAssertEqual(document.hierarchyEdges, [
            .init(
                childID: document.nodes[0].id,
                requestedParent: .integer(99),
                resolution: .missing
            )
        ])
        XCTAssertEqual(document.instanceEdges, [
            .init(
                instanceID: document.nodes[1].id,
                requestedSource: .string("absent"),
                resolution: .missing,
                overrides: []
            )
        ])
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.missing-parent" })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.missing-instance" })
    }

    func testBuildDiagnosesDuplicateIdentifiersWithoutDeletingNodes() throws {
        let unreferenced = try build(#"""
        {"objects":[
          {"id":7,"fullscreen":true},
          {"id":7,"fullscreen":true}
        ]}
        """#)
        XCTAssertEqual(unreferenced.document?.nodes.count, 2)
        XCTAssertEqual(unreferenced.status, .degraded)
        XCTAssertEqual(
            unreferenced.diagnostics.filter { $0.code == "graph.duplicate-source-id" }.count,
            1
        )
        XCTAssertEqual(
            unreferenced.diagnostics.first { $0.code == "graph.duplicate-source-id" }?.arguments,
            unreferenced.document?.nodes.prefix(2).map(\.id.rawValue)
        )

        let referenced = try build(#"""
        {"objects":[
          {"id":7,"fullscreen":true},
          {"id":7,"fullscreen":true},
          {"id":"child","parent":7,"fullscreen":true}
        ]}
        """#)
        let document = try XCTUnwrap(referenced.document)
        XCTAssertEqual(document.nodes.count, 3)
        XCTAssertEqual(document.hierarchyEdges, [
            .init(
                childID: document.nodes[2].id,
                requestedParent: .integer(7),
                resolution: .ambiguous([document.nodes[0].id, document.nodes[1].id])
            )
        ])
        XCTAssertEqual(referenced.status, .unsupported)
        XCTAssertTrue(referenced.diagnostics.contains { $0.code == "graph.ambiguous-parent" })
    }

    func testBuildDiagnosesAmbiguousInstanceAndMalformedLinks() throws {
        let result = try build(#"""
        {"objects":[
          {"id":"source","fullscreen":true},
          {"id":"source","fullscreen":true},
          {"instance":"source","fullscreen":true},
          {"parent":false,"instance":1.5,"fullscreen":true}
        ]}
        """#)

        let document = try XCTUnwrap(result.document)
        XCTAssertEqual(document.instanceEdges, [
            .init(
                instanceID: document.nodes[2].id,
                requestedSource: .string("source"),
                resolution: .ambiguous([document.nodes[0].id, document.nodes[1].id]),
                overrides: []
            )
        ])
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(
            result.diagnostics.first { $0.code == "graph.ambiguous-instance" }?.arguments,
            [document.nodes[0].id.rawValue, document.nodes[1].id.rawValue]
        )
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.invalid-property" }
                .map(\.jsonPath),
            ["objects[3].instance", "objects[3].parent"]
        )
    }

    func testBuildRetainsUnrepresentedHierarchyMetadata() throws {
        let partialOverrides: SceneJSONValue = .array([
            .object(["property": .string("visible"), "value": .bool(true)]),
            .object(["property": .bool(false), "value": .integer(0)])
        ])
        let result = try build(#"""
        {"objects":[
          {"id":"source","fullscreen":true},
          {"parent":false,"fullscreen":true},
          {"instanceoverride":{"opacity":0.5},"fullscreen":true},
          {"instance":false,"instanceoverride":{"scale":2},"fullscreen":true},
          {"instance":"source","instanceoverride":[
            {"property":"visible","value":true},
            {"property":false,"value":0}
          ],"fullscreen":true}
        ]}
        """#)

        let document = try XCTUnwrap(result.document)
        XCTAssertEqual(document.nodes[1].unknownFields, ["parent": .bool(false)])
        XCTAssertEqual(document.nodes[2].unknownFields, [
            "instanceoverride": .object(["opacity": .number(0.5)])
        ])
        XCTAssertEqual(document.nodes[3].unknownFields, [
            "instance": .bool(false),
            "instanceoverride": .object(["scale": .integer(2)])
        ])
        XCTAssertEqual(document.nodes[4].unknownFields, [
            "instanceoverride": partialOverrides
        ])
        XCTAssertEqual(document.instanceEdges, [
            .init(
                instanceID: document.nodes[4].id,
                requestedSource: .string("source"),
                resolution: .resolved(document.nodes[0].id),
                overrides: [.init(propertyPath: "visible", value: .bool(true))]
            )
        ])
        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.invalid-property" }
                .map(\.jsonPath),
            [
                "objects[1].parent",
                "objects[2].instanceoverride",
                "objects[3].instance",
                "objects[3].instanceoverride",
                "objects[4].instanceoverride[1]"
            ]
        )
    }

    func testBuildPreservesObjectAndArrayInstanceOverrides() throws {
        let objectResult = try build(#"""
        {"objects":[
          {"id":"source","fullscreen":true},
          {"instance":"source","instanceoverride":{
            "z":3,
            "alpha":0.5
          },"fullscreen":true}
        ]}
        """#)
        XCTAssertEqual(objectResult.document?.instanceEdges.first?.overrides, [
            .init(propertyPath: "alpha", value: .number(0.5)),
            .init(propertyPath: "z", value: .integer(3))
        ])
        XCTAssertEqual(
            objectResult.document?.instanceEdges.first?.overrides.compactMap(\.typedOverride),
            [
                .init(property: .opacity, value: .scalar(0.5)),
                .init(property: .zOrder, value: .scalar(3))
            ]
        )

        let arrayResult = try build(#"""
        {"objects":[
          {"id":1,"fullscreen":true},
          {"instance":1,"instanceoverride":[
            {"property":"position.x","value":12},
            {"property":"visible","value":true},
            {"property":false,"value":0},
            {"property":"missing-value"}
          ],"fullscreen":true}
        ]}
        """#)
        XCTAssertEqual(arrayResult.document?.instanceEdges.first?.overrides, [
            .init(propertyPath: "position.x", value: .integer(12)),
            .init(propertyPath: "visible", value: .bool(true))
        ])
        XCTAssertEqual(arrayResult.status, .degraded)
        XCTAssertEqual(
            arrayResult.diagnostics.filter { $0.code == "graph.invalid-property" }.map(\.jsonPath),
            ["objects[1].instanceoverride[2]", "objects[1].instanceoverride[3]"]
        )
    }

    func testBuildCanonicalizesParentAndInstanceCycles() throws {
        let parent = try build(#"""
        {"objects":[
          {"id":"b","parent":"c","fullscreen":true},
          {"id":"c","parent":"a","fullscreen":true},
          {"id":"a","parent":"b","fullscreen":true}
        ]}
        """#)
        XCTAssertEqual(parent.status, .invalid)
        XCTAssertEqual(
            parent.diagnostics.first { $0.code == "graph.parent-cycle" }?.arguments,
            [
                "scene.json#objects[0]",
                "scene.json#objects[1]",
                "scene.json#objects[2]"
            ]
        )

        let selfCycle = try build(#"""
        {"objects":[{"id":"self","parent":"self","fullscreen":true}]}
        """#)
        XCTAssertEqual(selfCycle.status, .invalid)
        XCTAssertEqual(
            selfCycle.diagnostics.first { $0.code == "graph.parent-cycle" }?.arguments,
            ["scene.json#objects[0]"]
        )

        let instance = try build(#"""
        {"objects":[
          {"id":"first","instance":"second","fullscreen":true},
          {"id":"second","instance":"first","fullscreen":true}
        ]}
        """#)
        XCTAssertEqual(instance.status, .invalid)
        XCTAssertEqual(
            instance.diagnostics.first { $0.code == "graph.instance-cycle" }?.arguments,
            ["scene.json#objects[0]", "scene.json#objects[1]"]
        )
    }

    func testBuildCanonicalizesReverseParentCycleDirection() throws {
        let result = try build(#"""
        {"objects":[
          {"id":"a","parent":"c","fullscreen":true},
          {"id":"b","parent":"a","fullscreen":true},
          {"id":"c","parent":"b","fullscreen":true}
        ]}
        """#)

        XCTAssertEqual(result.status, .invalid)
        XCTAssertEqual(
            result.diagnostics.first { $0.code == "graph.parent-cycle" }?.arguments,
            [
                "scene.json#objects[0]",
                "scene.json#objects[1]",
                "scene.json#objects[2]"
            ]
        )
    }

    func testBuildRejectsHierarchyDepthOverflow() throws {
        let result = try build(
            #"""
            {"objects":[
              {"id":1,"fullscreen":true},
              {"id":2,"parent":1,"fullscreen":true},
              {"id":3,"parent":2,"fullscreen":true}
            ]}
            """#,
            limits: .init(maximumHierarchyDepth: 2)
        )

        XCTAssertEqual(result.status, .invalid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.resource-limit" })
    }

    func testBuildTraversesLongHierarchyIteratively() throws {
        let count = 10_000
        let objects = (0..<count).map { index in
            if index == 0 {
                return #"{"id":0,"fullscreen":true}"#
            }
            return #"{"id":\#(index),"parent":\#(index - 1),"fullscreen":true}"#
        }.joined(separator: ",")

        let result = try build(
            "{\"objects\":[\(objects)]}",
            limits: .init(maximumHierarchyDepth: count)
        )

        XCTAssertEqual(result.document?.hierarchyEdges.count, count - 1)
        XCTAssertEqual(result.status, .exact)
    }

    private func build(
        _ scene: String,
        limits: SceneGraphLimits = .init()
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: [
                    .init(path: "scene.json", data: Data(scene.utf8))
                ])
            )
        )
        return SceneGraphBuilder(limits: limits).build(resolver: resolver)
    }
}
