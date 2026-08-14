import Foundation
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneGraph
import MacWallSceneTestSupport
import MacWallSceneTextures
import XCTest
@testable import MacWallSceneRenderer

final class SceneRenderCompilerTests: XCTestCase {
    func testRejectsMissingDocumentAndPreservesUpstreamDiagnostics() throws {
        let sourcePath = try SceneVirtualPath(canonicalPath: "scene.json")
        let graphDiagnostic = SceneGraphDiagnostic(
            severity: .error,
            code: "graph.invalid-package",
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: "$",
            dependencyPath: [],
            arguments: ["second", "first"]
        )

        let result = SceneRenderCompiler().compile(.init(
            document: nil,
            status: .invalid,
            diagnostics: [graphDiagnostic]
        ))

        XCTAssertNil(result.program)
        XCTAssertEqual(result.status, .invalid)
        XCTAssertEqual(result.diagnostics, [
            .init(
                severity: .error,
                code: "graph.invalid-package",
                arguments: ["second", "first"]
            ),
            .init(severity: .error, code: "renderer.missing-document")
        ])
    }

    func testCompilesExactImageChainIntoImmutableProgram() throws {
        let graph = try build(entries: exactEntries(
            scene: scene(objects: [
                #"{"image":"models/base.json","origin":"100 200 0","scale":"2 3 1","angles":"0 0 45","alpha":0.75}"#
            ])
        ))

        let result = SceneRenderCompiler().compile(graph)
        let program = try XCTUnwrap(result.program)

        XCTAssertEqual(result.status, .exact)
        XCTAssertEqual(result.diagnostics, [])
        XCTAssertEqual(program.canvas, .init(width: 1_920, height: 1_080))
        XCTAssertEqual(program.drawCount, 1)
        XCTAssertEqual(program.drawTemplates.map(\.sourceOrder), [0])
        XCTAssertEqual(program.evaluationOrder.map(\.nodeID.objectIndex), [0])
        XCTAssertEqual(program.textureManifest.count, 1)
        XCTAssertEqual(program.textureManifest[0].resource.path.rawValue, "materials/base.tex")
        XCTAssertEqual(program.textureManifest[0].imageIndex, 0)
        XCTAssertEqual(program.textureManifest[0].colorIntent, .colorSRGB)
        XCTAssertEqual(program.textureManifest[0].dependentDrawIndices, [0])
        XCTAssertEqual(program.drawTemplates[0].baseProperties, .init(
            origin: .init(x: 100, y: 200, z: 0),
            pivot: .init(x: 0, y: 0, z: 0),
            position: .init(x: 0, y: 0, z: 0),
            scale: .init(x: 2, y: 3, z: 1),
            rotationZ: 45,
            opacity: 0.75,
            visible: true,
            enabled: true,
            color: .init(red: 255, green: 255, blue: 255, alpha: 255),
            zOrder: 0
        ))
        XCTAssertTrue(program.drawTemplates[0].animationBindings.isEmpty)
        XCTAssertEqual(program.fingerprint.count, 64)
        XCTAssertNotNil(program.fingerprint.range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
        ))
    }

    func testKeepsStableDrawOrderWithoutTextureGrouping() throws {
        let graph = try build(entries: sharedTextureEntries())
        let program = try XCTUnwrap(SceneRenderCompiler().compile(graph).program)

        XCTAssertEqual(program.drawTemplates.map(\.identity.nodeID.objectIndex), [0, 1, 2])
        XCTAssertEqual(program.drawTemplates.map(\.textureManifestIndex), [0, 1, 0])
        XCTAssertEqual(program.textureManifest.map(\.dependentDrawIndices), [[0, 2], [1]])
    }

    func testStoresParentIndicesAndIncludesHierarchyInFingerprint() throws {
        let parented = try XCTUnwrap(SceneRenderCompiler().compile(try build(
            entries: exactEntries(scene: scene(objects: [
                #"{"id":"child","image":"models/base.json","parent":"parent"}"#,
                #"{"id":"parent","fullscreen":true}"#
            ]))
        )).program)
        let unparented = try XCTUnwrap(SceneRenderCompiler().compile(try build(
            entries: exactEntries(scene: scene(objects: [
                #"{"id":"child","image":"models/base.json"}"#,
                #"{"id":"parent","fullscreen":true}"#
            ]))
        )).program)

        XCTAssertEqual(parented.evaluationOrder.map(\.nodeID.objectIndex), [1, 0])
        XCTAssertEqual(parented.evaluationParentIndices, [nil, 0])
        XCTAssertNotEqual(parented.fingerprint, unparented.fingerprint)
    }

    func testDegradesKnownBaseImageWhenBuiltInShaderAndEffectAreOmitted() throws {
        let graph = try build(entries: [
            entry("scene.json", scene(objects: [#"{"image":"models/base.json"}"#])),
            entry("models/base.json", #"{"material":"materials/base.json"}"#),
            entry(
                "materials/base.json",
                #"{"passes":[{"shader":"genericimage4","texture":"base","effect":"effects/probe.json"}]}"#
            ),
            entry("effects/probe.json", "{}"),
            texture("materials/base.tex")
        ])

        let result = SceneRenderCompiler().compile(graph)

        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(result.program?.drawCount, 1)
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "renderer.builtin-shader-emulated"
        })
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "renderer.base-effect-omitted"
        })
    }

    func testSkipsCustomShaderLayerAndKeepsExistingRenderableLayer() throws {
        let graph = try build(entries: [
            entry("scene.json", scene(objects: [
                #"{"image":"models/base.json"}"#,
                #"{"image":"models/custom.json"}"#
            ])),
            entry("models/base.json", #"{"material":"materials/base.json"}"#),
            entry("materials/base.json", #"{"texture":"base"}"#),
            entry("models/custom.json", #"{"material":"materials/custom.json"}"#),
            entry(
                "materials/custom.json",
                #"{"passes":[{"shader":"shaders/custom.glsl","texture":"custom"}]}"#
            ),
            entry("shaders/custom.glsl", "fragment custom"),
            texture("materials/base.tex"),
            texture("materials/custom.tex")
        ])

        let result = SceneRenderCompiler().compile(graph)

        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(result.program?.drawTemplates.map(\.identity.nodeID.objectIndex), [0])
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "renderer.custom-shader" && $0.nodeID?.objectIndex == 1
        })
    }

    func testSkipsPassWithUnprovenGeometryOrUVMetadata() throws {
        let graph = try build(entries: [
            entry("scene.json", scene(objects: [
                #"{"image":"models/base.json"}"#,
                #"{"image":"models/warped.json"}"#
            ])),
            entry("models/base.json", #"{"material":"materials/base.json"}"#),
            entry("materials/base.json", #"{"texture":"base"}"#),
            entry("models/warped.json", #"{"material":"materials/warped.json"}"#),
            entry(
                "materials/warped.json",
                #"{"passes":[{"texture":"warped","uvtransform":"custom"}]}"#
            ),
            texture("materials/base.tex"),
            texture("materials/warped.tex")
        ])

        let result = SceneRenderCompiler().compile(graph)

        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(result.program?.drawTemplates.map(\.identity.nodeID.objectIndex), [0])
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "renderer.unsupported-material" && $0.nodeID?.objectIndex == 1
        })
    }

    func testReturnsUnsupportedForEmptyOrUnresolvedRenderableSet() throws {
        let empty = SceneRenderCompiler().compile(try build(entries: [
            entry("scene.json", scene(objects: []))
        ]))
        XCTAssertNil(empty.program)
        XCTAssertEqual(empty.status, .unsupported)
        XCTAssertTrue(empty.diagnostics.contains {
            $0.code == "renderer.no-renderable-images"
        })

        let missing = SceneRenderCompiler().compile(try build(entries: [
            entry("scene.json", scene(objects: [#"{"image":"missing.json"}"#]))
        ]))
        XCTAssertNil(missing.program)
        XCTAssertEqual(missing.status, .unsupported)
        XCTAssertTrue(missing.diagnostics.contains {
            $0.code == "renderer.missing-model"
        })
    }

    func testKeepsBaseValueForUnsupportedAnimationAndProperties() throws {
        let animatedObject = #"{"image":"models/base.json","alpha":{"value":0.5,"animation":{"options":{"fps":30,"length":30,"relative":true},"c0":[{"frame":0,"value":0.25,"interpolation":"linear"}]}},"color":"255 255 255 255"}"#
        let graph = try build(entries: exactEntries(
            scene: scene(objects: [animatedObject])
        ))

        let result = SceneRenderCompiler().compile(graph)
        let draw = try XCTUnwrap(result.program?.drawTemplates.first)

        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(draw.baseProperties.opacity, 0.5)
        XCTAssertTrue(draw.animationBindings.isEmpty)
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "renderer.unsupported-animation"
                && $0.arguments == ["opacity", "relative"]
        })
    }

    func testFingerprintIgnoresJSONDictionaryOrderAndRuntimeIdentity() throws {
        let firstScene = #"{"general":{"orthogonalprojection":{"width":1920,"height":1080}},"objects":[{"image":"models/base.json","origin":"10 20 0","alpha":1}]}"#
        let secondScene = #"{"objects":[{"alpha":1,"origin":"10 20 0","image":"models/base.json"}],"general":{"orthogonalprojection":{"height":1080,"width":1920}}}"#
        let first = try XCTUnwrap(SceneRenderCompiler().compile(try build(
            entries: exactEntries(scene: firstScene)
        )).program)
        let second = try XCTUnwrap(SceneRenderCompiler().compile(try build(
            entries: exactEntries(scene: secondScene)
        )).program)

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        let labels = Set(Mirror(reflecting: first).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("resolver"))
        XCTAssertFalse(labels.contains("url"))
        XCTAssertFalse(labels.contains("device"))
        XCTAssertFalse(labels.contains("packageID"))
    }

    func testEnforcesCanvasAndDrawCountLimits() throws {
        let invalidCanvas = SceneRenderCompiler(limits: .init(
            maximumDimension: 1_000
        )).compile(try build(entries: exactEntries(
            scene: scene(objects: [#"{"image":"models/base.json"}"#])
        )))
        XCTAssertNil(invalidCanvas.program)
        XCTAssertEqual(invalidCanvas.status, .invalid)
        XCTAssertTrue(invalidCanvas.diagnostics.contains {
            $0.code == "renderer.resource-limit"
                && $0.arguments == ["outputDimension"]
        })

        let drawLimit = SceneRenderCompiler(limits: .init(
            maximumDrawItemCount: 0
        )).compile(try build(entries: exactEntries(
            scene: scene(objects: [#"{"image":"models/base.json"}"#])
        )))
        XCTAssertNil(drawLimit.program)
        XCTAssertEqual(drawLimit.status, .invalid)
        XCTAssertTrue(drawLimit.diagnostics.contains {
            $0.code == "renderer.resource-limit"
                && $0.arguments == ["drawItems"]
        })
    }

    private func exactEntries(scene: String) -> [ScenePackageFixtureEntry] {
        [
            entry("scene.json", scene),
            entry("models/base.json", #"{"material":"materials/base.json"}"#),
            entry("materials/base.json", #"{"texture":"base"}"#),
            texture("materials/base.tex")
        ]
    }

    private func sharedTextureEntries() -> [ScenePackageFixtureEntry] {
        [
            entry("scene.json", scene(objects: [
                #"{"image":"models/a.json"}"#,
                #"{"image":"models/b.json"}"#,
                #"{"image":"models/a.json"}"#
            ])),
            entry("models/a.json", #"{"material":"materials/a.json"}"#),
            entry("models/b.json", #"{"material":"materials/b.json"}"#),
            entry("materials/a.json", #"{"texture":"a"}"#),
            entry("materials/b.json", #"{"texture":"b"}"#),
            texture("materials/a.tex"),
            texture("materials/b.tex")
        ]
    }

    private func scene(objects: [String]) -> String {
        #"{"general":{"orthogonalprojection":{"width":1920,"height":1080}},"objects":["#
            + objects.joined(separator: ",")
            + "]}"
    }

    private func build(
        entries: [ScenePackageFixtureEntry]
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: entries)
            )
        )
        return SceneGraphBuilder().build(resolver: resolver)
    }

    private func entry(_ path: String, _ contents: String) -> ScenePackageFixtureEntry {
        .init(path: path, data: Data(contents.utf8))
    }

    private func texture(_ path: String) -> ScenePackageFixtureEntry {
        .init(path: path, data: Data([0x54, 0x45, 0x58]))
    }
}
