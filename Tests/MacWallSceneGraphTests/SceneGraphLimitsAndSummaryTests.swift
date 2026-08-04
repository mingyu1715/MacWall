import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneGraphLimitsAndSummaryTests: XCTestCase {
    func testRootLimitsReturnNilDocumentWithNamedResourceLimit() throws {
        let twoNodes = #"{"objects":[{"fullscreen":true},{"fullscreen":true}]}"#
        assertLimit(
            try build(twoNodes, limits: .init(maximumNodeCount: 1)),
            name: "maximumNodeCount",
            retainsDocument: false
        )

        let largerThan32Bytes = #"{"objects":[{"fullscreen":true}]}"#
        assertLimit(
            try build(largerThan32Bytes, limits: .init(maximumJSONEntryBytes: 32)),
            name: "maximumJSONEntryBytes",
            retainsDocument: false
        )

        let byteCount = UInt64(largerThan32Bytes.utf8.count)
        let exact = try build(
            largerThan32Bytes,
            limits: .init(
                maximumJSONEntryBytes: byteCount,
                maximumCumulativeJSONBytes: byteCount
            )
        )
        XCTAssertNotNil(exact.document)
        XCTAssertFalse(exact.diagnostics.contains { $0.code == "graph.resource-limit" })

        assertLimit(
            try build(
                largerThan32Bytes,
                limits: .init(
                    maximumJSONEntryBytes: byteCount,
                    maximumCumulativeJSONBytes: byteCount - 1
                )
            ),
            name: "maximumCumulativeJSONBytes",
            retainsDocument: false
        )

        assertLimit(
            try build(
                #"{"objects":[{"fullscreen":true}]}"#,
                limits: .init(maximumJSONDepth: 2)
            ),
            name: "maximumJSONDepth",
            retainsDocument: false
        )
    }

    func testGraphPhaseLimitsRetainPartialDocumentWithNamedResourceLimit() throws {
        let dependencies = try build(
            #"{"objects":[{"image":"missing-a.json"},{"image":"missing-b.json"}]}"#,
            limits: .init(maximumDependencyEdgeCount: 1)
        )
        assertLimit(
            dependencies,
            name: "maximumDependencyEdgeCount",
            retainsDocument: true
        )
        XCTAssertEqual(dependencies.document?.dependencies.count, 1)

        let keyframes = try build(
            #"{"objects":[{"fullscreen":true,"alpha":{"animation":{"c0":[{"frame":0,"value":0},{"frame":1,"value":1}]}}}]}"#,
            limits: .init(maximumAnimationKeyframeCount: 1)
        )
        assertLimit(
            keyframes,
            name: "maximumAnimationKeyframeCount",
            retainsDocument: true
        )
        XCTAssertEqual(
            keyframes.document?.animations.first?.channels.first?.keyframes.count,
            1
        )

        let hierarchy = try build(
            #"{"objects":[{"id":"a","fullscreen":true},{"id":"b","parent":"a","fullscreen":true},{"id":"c","parent":"b","fullscreen":true}]}"#,
            limits: .init(maximumHierarchyDepth: 2)
        )
        assertLimit(
            hierarchy,
            name: "maximumHierarchyDepth",
            retainsDocument: true
        )
        XCTAssertEqual(hierarchy.document?.hierarchyEdges.count, 2)

        let candidates = try build(
            #"{"objects":[{"image":"models/sub/model.json"}]}"#,
            entries: [
                entry("models/sub/model.json", #"{"material":"base"}"#)
            ],
            resolverLimits: .init(maximumCandidatesPerRequest: 1)
        )
        assertLimit(
            candidates,
            name: "maximumCandidatesPerRequest",
            retainsDocument: true
        )
    }

    func testStatusPolicyUsesRequiredEvidenceAndPrecedence() throws {
        XCTAssertEqual(
            try build(#"{"objects":[{"fullscreen":true,"futureProperty":1}]}"#).status,
            .degraded
        )
        XCTAssertEqual(
            try build(#"{"objects":[{"id":1,"fullscreen":true},{"id":1,"fullscreen":true}]}"#).status,
            .degraded
        )

        let ambiguity = try build(
            #"{"objects":[{"image":"models/model.json"}]}"#,
            entries: [
                entry("models/model.json", #"{"material":"shared.json"}"#),
                entry("shared.json", #"{"passes":[]}"#),
                entry("models/shared.json", #"{"passes":[]}"#)
            ]
        )
        XCTAssertEqual(ambiguity.status, .degraded)
        XCTAssertTrue(ambiguity.diagnostics.contains { $0.code == "asset.ambiguous-resolution" })

        XCTAssertEqual(try build(#"{"objects":[{"mystery":true}]}"#).status, .unsupported)
        XCTAssertEqual(
            try build(#"{"objects":[{"id":"child","parent":"missing","fullscreen":true}]}"#).status,
            .unsupported
        )
        XCTAssertEqual(
            try build(#"{"objects":[{"image":"models/util/missing.json"}]}"#).status,
            .unsupported
        )
        XCTAssertEqual(
            try build(
                #"{"objects":[{"image":"shared/missing.json"}]}"#,
                sourcePolicy: .init(
                    version: 99,
                    builtInPrefixes: [],
                    externalPrefixes: ["shared/"],
                    classifyBareShadersAsBuiltIn: false
                )
            ).status,
            .unsupported
        )
        XCTAssertEqual(
            try build(#"{"objects":[{"image":"missing.json"}]}"#).status,
            .unsupported
        )

        XCTAssertEqual(
            try build(#"{"objects":[{"fullscreen":true,"effect":"effects/custom.json"}]}"#, entries: [
                entry("effects/custom.json", "{}")
            ]).status,
            .unsupported
        )
        XCTAssertEqual(
            try build(#"{"objects":[{"fullscreen":true,"shader":"shaders/custom.frag"}]}"#, entries: [
                entry("shaders/custom.frag", "custom shader")
            ]).status,
            .unsupported
        )
        XCTAssertEqual(
            try build(#"{"script":"function update() {}","objects":[]}"#).status,
            .unsupported
        )

        let malformed = try build("[]")
        XCTAssertEqual(malformed.status, .invalid)
        XCTAssertNil(malformed.document)

        let pathEscape = try build(#"{"objects":[{"image":"../escape.json"}]}"#)
        XCTAssertEqual(pathEscape.status, .invalid)
        XCTAssertNotNil(pathEscape.document)
        XCTAssertEqual(
            pathEscape.diagnostics.first { $0.code == "asset.path-escape" }?.severity,
            .error
        )

        XCTAssertEqual(
            try build(
                #"{"objects":[{"fullscreen":true},{"fullscreen":true}]}"#,
                limits: .init(maximumNodeCount: 1)
            ).status,
            .invalid
        )
        XCTAssertEqual(
            try build(#"{"objects":[{"id":"self","parent":"self","fullscreen":true}]}"#).status,
            .invalid
        )
    }

    func testRetainedUnknownResourceFieldsDegradeWithoutNoisyDiagnostics() throws {
        let model = try build(
            #"{"objects":[{"image":"models/model.json"}]}"#,
            entries: [entry("models/model.json", #"{"futureModel":1}"#)]
        )
        XCTAssertEqual(model.status, .degraded)
        XCTAssertEqual(model.diagnostics, [])
        XCTAssertEqual(
            model.document?.resources.first?.model?.unknownFields,
            ["futureModel": .integer(1)]
        )

        let material = try build(
            #"{"objects":[{"image":"models/model.json"}]}"#,
            entries: [
                entry("models/model.json", #"{"material":"materials/material.json"}"#),
                entry("materials/material.json", #"{"passes":[],"futureMaterial":2}"#)
            ]
        )
        XCTAssertEqual(material.status, .degraded)
        XCTAssertEqual(material.diagnostics, [])
        XCTAssertEqual(
            material.document?.resources.first { $0.id.kind == .material }?.material?.unknownFields,
            ["futureMaterial": .integer(2)]
        )

        let pass = try build(
            #"{"objects":[{"image":"models/model.json"}]}"#,
            entries: [
                entry("models/model.json", #"{"material":"materials/material.json"}"#),
                entry("materials/material.json", #"{"passes":[{"futurePass":3}]}"#)
            ]
        )
        XCTAssertEqual(pass.status, .degraded)
        XCTAssertEqual(pass.diagnostics, [])
        XCTAssertEqual(
            pass.document?.resources.first { $0.id.kind == .material }?
                .material?.passes.first?.unknownFields,
            ["futurePass": .integer(3)]
        )

        let malformedKnown = try build(
            #"{"objects":[{"image":"models/model.json"}]}"#,
            entries: [entry("models/model.json", #"{"material":42}"#)]
        )
        XCTAssertEqual(malformedKnown.status, .unsupported)
        XCTAssertEqual(
            malformedKnown.diagnostics.map(\.code),
            ["graph.invalid-property"]
        )
    }

    func testDependencyLimitWinsBeforeCollidingCandidateLimit() throws {
        let result = try build(
            #"{"objects":[{"image":"./models/model.json"}]}"#,
            entries: [
                entry("models/model.json", #"{"material":"base"}"#)
            ],
            limits: .init(maximumDependencyEdgeCount: 1),
            resolverLimits: .init(maximumCandidatesPerRequest: 1)
        )

        assertLimit(
            result,
            name: "maximumDependencyEdgeCount",
            retainsDocument: true
        )
        XCTAssertEqual(result.document?.dependencies.count, 1)
        XCTAssertFalse(result.diagnostics.contains {
            $0.arguments == ["maximumCandidatesPerRequest"]
        })
    }

    func testStatusPrecedenceIsIndependentOfEvidenceOrder() throws {
        let result = try build(#"{"objects":[{"mystery":true,"futureProperty":1},{"id":"self","parent":"self","fullscreen":true}]}"#)
        XCTAssertEqual(result.status, .invalid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.unknown-node" })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.parent-cycle" })
    }

    func testCanonicalSummaryHasExactCountsOrderingAndEncoding() throws {
        let result = try build(summaryScene, entries: summaryEntries)
        let summary = SceneGraphSummarizer.summarize(result)

        XCTAssertEqual(summary, SceneGraphSummary(
            schemaVersion: 1,
            packageVersion: "PKGV0008",
            nodeKinds: [
                .init(name: "fullscreen", count: 1),
                .init(name: "image", count: 1),
                .init(name: "text", count: 1)
            ],
            hierarchyEdgeCount: 1,
            instanceEdgeCount: 1,
            overrideCount: 1,
            resourceKinds: [
                .init(name: "effect", count: 1),
                .init(name: "material", count: 1),
                .init(name: "model", count: 1),
                .init(name: "shader", count: 1),
                .init(name: "texture", count: 1)
            ],
            dependencyResolutions: [.init(name: "package", count: 5)],
            animationTrackCount: 1,
            animationKeyframeCount: 2,
            scriptCount: 1,
            diagnosticCodes: [
                .init(name: "graph.invalid-property", count: 1),
                .init(name: "graph.scenescript-preserved-not-executed", count: 1),
                .init(name: "graph.unsupported-effect", count: 1),
                .init(name: "graph.unsupported-shader", count: 1)
            ],
            status: .unsupported
        ))

        let data = try SceneGraphSummaryEncoder.encode(summary)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), expectedSummaryJSON)
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertNotEqual(data.dropLast().last, 0x0A)
    }

    func testCanonicalSummaryIsStableAcrossInsertionOrderAndRepeatedBuilds() throws {
        let first = try build(summaryScene, entries: summaryEntries)
        let repeated = try build(summaryScene, entries: summaryEntries)
        let reordered = try build(
            reorderedSummaryScene,
            entries: Array(summaryEntries.reversed())
        )

        let firstBytes = try SceneGraphSummaryEncoder.encode(SceneGraphSummarizer.summarize(first))
        let repeatedBytes = try SceneGraphSummaryEncoder.encode(SceneGraphSummarizer.summarize(repeated))
        let reorderedBytes = try SceneGraphSummaryEncoder.encode(SceneGraphSummarizer.summarize(reordered))
        XCTAssertEqual(firstBytes, repeatedBytes)
        XCTAssertEqual(firstBytes, reorderedBytes)

        let summary = SceneGraphSummarizer.summarize(first)
        let reversedCounts = SceneGraphSummary(
            schemaVersion: summary.schemaVersion,
            packageVersion: summary.packageVersion,
            nodeKinds: Array(summary.nodeKinds.reversed()),
            hierarchyEdgeCount: summary.hierarchyEdgeCount,
            instanceEdgeCount: summary.instanceEdgeCount,
            overrideCount: summary.overrideCount,
            resourceKinds: Array(summary.resourceKinds.reversed()),
            dependencyResolutions: Array(summary.dependencyResolutions.reversed()),
            animationTrackCount: summary.animationTrackCount,
            animationKeyframeCount: summary.animationKeyframeCount,
            scriptCount: summary.scriptCount,
            diagnosticCodes: Array(summary.diagnosticCodes.reversed()),
            status: summary.status
        )
        XCTAssertEqual(
            firstBytes,
            try SceneGraphSummaryEncoder.encode(reversedCounts)
        )
    }

    func testSummaryExcludesPrivateAndRetainedPayloadData() throws {
        let sensitive = "PRIVATE-WORKSHOP-HOST-PATH-RAW-SCRIPT-PAYLOAD"
        let result = try build("""
        {"title":"\(sensitive)","script":"function hidden() { return '\(sensitive)' }","objects":[{"name":"\(sensitive)","image":"private/\(sensitive)/model.json"}]}
        """, entries: [
            entry(
                "private/\(sensitive)/model.json",
                #"{"material":"missing.json"}"#
            )
        ])
        let encoded = try SceneGraphSummaryEncoder.encode(SceneGraphSummarizer.summarize(result))
        let string = String(decoding: encoded, as: UTF8.self)

        XCTAssertFalse(string.contains(sensitive))
        XCTAssertFalse(string.contains("scene.json"))
        XCTAssertFalse(string.contains("objects["))
    }

    func testCanonicalEncoderEscapesCountNamesAndEmitsExactlyOneLF() throws {
        let summary = SceneGraphSummary(
            schemaVersion: 1,
            packageVersion: nil,
            nodeKinds: [
                .init(name: "slash/name", count: 1),
                .init(name: "quote\"name", count: 1),
                .init(name: "back\\slash", count: 1),
                .init(name: "line\nbreak", count: 1)
            ],
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

        let first = try SceneGraphSummaryEncoder.encode(summary)
        let repeated = try SceneGraphSummaryEncoder.encode(summary)
        let string = String(decoding: first, as: UTF8.self)
        XCTAssertEqual(first, repeated)
        XCTAssertTrue(string.contains(#""name" : "slash/name""#))
        XCTAssertTrue(string.contains(#""name" : "quote\"name""#))
        XCTAssertTrue(string.contains(#""name" : "back\\slash""#))
        XCTAssertTrue(string.contains(#""name" : "line\nbreak""#))
        XCTAssertFalse(string.contains("line\nbreak"))
        XCTAssertEqual(first.last, 0x0A)
        XCTAssertNotEqual(first.dropLast().last, 0x0A)
    }

    private func assertLimit(
        _ result: SceneGraphBuildResult,
        name: String,
        retainsDocument: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.status, .invalid, file: file, line: line)
        XCTAssertEqual(result.document != nil, retainsDocument, file: file, line: line)
        let limits = result.diagnostics.filter { $0.code == "graph.resource-limit" }
        XCTAssertEqual(limits.count, 1, file: file, line: line)
        XCTAssertEqual(limits.first?.severity, .error, file: file, line: line)
        XCTAssertEqual(limits.first?.arguments, [name], file: file, line: line)
    }

    private func build(
        _ scene: String,
        entries: [ScenePackageFixtureEntry] = [],
        limits: SceneGraphLimits = .init(),
        resolverLimits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(data: ScenePackageFixtureBuilder.make(
                entries: [entry("scene.json", scene)] + entries
            )),
            limits: resolverLimits,
            sourcePolicy: sourcePolicy
        )
        return SceneGraphBuilder(limits: limits).build(resolver: resolver)
    }

    private func entry(_ path: String, _ contents: String) -> ScenePackageFixtureEntry {
        .init(path: path, data: Data(contents.utf8))
    }

    private var summaryEntries: [ScenePackageFixtureEntry] {
        [
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry("materials/material.json", #"{"passes":[{"shader":"shaders/custom.frag","texture":"summary"}]}"#),
            entry("shaders/custom.frag", "custom shader payload"),
            entry("materials/summary.tex", "texture payload"),
            entry("effects/custom.json", "{}")
        ]
    }

    private var summaryScene: String {
        #"{"script":"function update() {}","objects":[{"id":"root","fullscreen":true,"metadata":{"effect":"effects/custom.json"}},{"id":"image","parent":"root","image":"models/model.json","alpha":{"value":1,"animation":{"c0":[{"frame":0,"value":0},{"frame":1,"value":1}]}}},{"text":{"value":"hello"},"instance":"root","instanceoverride":{"visible":true}}]}"#
    }

    private var reorderedSummaryScene: String {
        #"{"objects":[{"metadata":{"effect":"effects/custom.json"},"fullscreen":true,"id":"root"},{"alpha":{"animation":{"c0":[{"value":0,"frame":0},{"value":1,"frame":1}]},"value":1},"image":"models/model.json","parent":"root","id":"image"},{"instanceoverride":{"visible":true},"instance":"root","text":{"value":"hello"}}],"script":"function update() {}"}"#
    }

    private var expectedSummaryJSON: String {
        """
        {
          "animationKeyframeCount" : 2,
          "animationTrackCount" : 1,
          "dependencyResolutions" : [
            {
              "count" : 5,
              "name" : "package"
            }
          ],
          "diagnosticCodes" : [
            {
              "count" : 1,
              "name" : "graph.invalid-property"
            },
            {
              "count" : 1,
              "name" : "graph.scenescript-preserved-not-executed"
            },
            {
              "count" : 1,
              "name" : "graph.unsupported-effect"
            },
            {
              "count" : 1,
              "name" : "graph.unsupported-shader"
            }
          ],
          "hierarchyEdgeCount" : 1,
          "instanceEdgeCount" : 1,
          "nodeKinds" : [
            {
              "count" : 1,
              "name" : "fullscreen"
            },
            {
              "count" : 1,
              "name" : "image"
            },
            {
              "count" : 1,
              "name" : "text"
            }
          ],
          "overrideCount" : 1,
          "packageVersion" : "PKGV0008",
          "resourceKinds" : [
            {
              "count" : 1,
              "name" : "effect"
            },
            {
              "count" : 1,
              "name" : "material"
            },
            {
              "count" : 1,
              "name" : "model"
            },
            {
              "count" : 1,
              "name" : "shader"
            },
            {
              "count" : 1,
              "name" : "texture"
            }
          ],
          "schemaVersion" : 1,
          "scriptCount" : 1,
          "status" : "unsupported"
        }

        """
    }
}

private extension SceneGraphResource {
    var model: SceneModelResource? {
        guard case let .model(value) = self else {
            return nil
        }
        return value
    }

    var material: SceneMaterialResource? {
        guard case let .material(value) = self else {
            return nil
        }
        return value
    }
}
