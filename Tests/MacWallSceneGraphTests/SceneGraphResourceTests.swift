import Foundation
import XCTest
@testable import MacWallSceneGraph
import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneGraphResourceTests: XCTestCase {
    func testBuildsModelMaterialPassShaderTextureChain() throws {
        let result = try build(entries: standardChainEntries())
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.resources.map(\.id.rawValue), [
            "material:materials/background.json",
            "model:models/background.json",
            "shader:genericimage4",
            "texture:materials/background.tex"
        ])
        XCTAssertEqual(
            document.dependencies.map(\.resolution.kind),
            [.package, .package, .builtInCandidate, .package]
        )
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "asset.builtin-candidate" }.count,
            1
        )

        let model = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneModelResource? in
            guard case let .model(model) = resource else { return nil }
            return model
        }.first)
        let material = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)
        XCTAssertEqual(model.unknownFields, ["mesh": .string("quad")])
        XCTAssertEqual(material.unknownFields, ["blend": .string("normal")])
        XCTAssertEqual(material.passes.count, 1)
        XCTAssertEqual(material.passes[0].shaderDependency?.request.role, .shader)
        XCTAssertEqual(material.passes[0].textureBindings.count, 1)
        XCTAssertEqual(material.passes[0].unknownFields, ["depth": .bool(false)])
    }

    func testSharedChainMemoizesResourcesAndKeepsSeparateNodeEdges() throws {
        var entries = standardChainEntries()
        entries[0] = entry(
            "scene.json",
            #"{"objects":[{"image":"models/background.json"},{"image":"models/background.json"}]}"#
        )

        let document = try XCTUnwrap(try build(entries: entries).document)

        XCTAssertEqual(document.resources.map(\.id.rawValue), [
            "material:materials/background.json",
            "model:models/background.json",
            "shader:genericimage4",
            "texture:materials/background.tex"
        ])
        XCTAssertEqual(document.dependencies.count, 5)
        XCTAssertEqual(document.dependencies.compactMap { edge -> SceneNodeID? in
            guard case let .node(nodeID) = edge.owner else { return nil }
            return nodeID
        }.map(\.objectIndex), [0, 1])
    }

    func testResolvesOwnerRelativeDocumentsAndReportsRootOwnerAmbiguity() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"./models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"shared.json"}"#),
            entry("shared.json", #"{"passes":[]}"#),
            entry("models/shared.json", #"{"passes":[]}"#)
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.resources.map(\.id.rawValue), [
            "material:shared.json",
            "model:models/model.json"
        ])
        let nodeEdge = try XCTUnwrap(document.dependencies.first {
            if case .node = $0.owner { return true }
            return false
        })
        let materialEdge = try XCTUnwrap(document.dependencies.first {
            $0.request.role == .material
        })
        XCTAssertEqual(nodeEdge.request.ownerPath?.rawValue, "scene.json")
        XCTAssertEqual(nodeEdge.resolution.selected?.candidateOrigin, .ownerRelative)
        XCTAssertEqual(materialEdge.resolution.selected?.canonicalPath.rawValue, "shared.json")
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "asset.ambiguous-resolution" }.count,
            1
        )
        XCTAssertEqual(result.status, .degraded)
    }

    func testParsesTopLevelTexturesInlineAndReferencedPassesInSourceOrder() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"texture":"top","textures":[{"slot":"normal","texture":"normal"}],"passes":[{"textures":["base",{"slot":"albedo","texture":"detail"}]},"passes/extra.json"]}"#
            ),
            entry("passes/extra.json", #"{"texture":{"slot":"mask","file":"mask"},"kept":1}"#),
            texture("materials/top.tex"),
            texture("materials/normal.tex"),
            texture("materials/base.tex"),
            texture("materials/detail.tex"),
            texture("materials/mask.tex")
        ])
        let document = try XCTUnwrap(result.document)
        let material = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertEqual(material.passes.map(\.index), [0, 1, 2])
        XCTAssertEqual(material.passes[0].textureBindings.map(\.slot), [nil, "albedo"])
        XCTAssertEqual(material.passes[0].textureBindings.map {
            $0.dependency.request.requestedPath
        }, ["base", "detail"])
        XCTAssertEqual(material.passes[1].sourcePath?.rawValue, "passes/extra.json")
        XCTAssertEqual(material.passes[1].documentDependency?.request.role, .pass)
        XCTAssertEqual(material.passes[1].textureBindings.map(\.slot), ["mask"])
        XCTAssertEqual(material.passes[1].unknownFields, ["kept": .integer(1)])
        XCTAssertEqual(material.passes[2].textureBindings.map(\.slot), [nil, "normal"])
        XCTAssertEqual(material.passes[2].textureBindings.map {
            $0.dependency.request.requestedPath
        }, ["top", "normal"])
        XCTAssertEqual(document.resources.filter {
            if case .texture = $0 { return true }
            return false
        }.count, 5)
    }

    func testMissingModelMaterialAndTextureAreStableUnsupportedDiagnostics() throws {
        let result = try build(entries: [
            entry(
                "scene.json",
                #"{"objects":[{"image":"missing-model.json"},{"image":"models/no-material.json"},{"image":"models/no-texture.json"}]}"#
            ),
            entry("models/no-material.json", #"{"material":"missing-material.json"}"#),
            entry("models/no-texture.json", #"{"material":"materials/no-texture.json"}"#),
            entry("materials/no-texture.json", #"{"texture":"missing-texture"}"#)
        ])

        XCTAssertNotNil(result.document)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "asset.unresolved" }.count,
            3
        )
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.unresolved-material" }.count,
            1
        )
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.unresolved-texture" }.count,
            1
        )
    }

    func testMalformedAuxiliaryJSONRetainsNodeAndReturnsUnsupported() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/broken.json"}]}"#),
            entry("models/broken.json", #"{"material":]"#)
        ])

        XCTAssertEqual(result.document?.nodes.count, 1)
        XCTAssertTrue(result.document?.resources.isEmpty == true)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.invalid-property" })
    }

    func testAuxiliaryJSONEntryAndCumulativeLimitsRetainDocumentAsInvalid() throws {
        let scene = #"{"objects":[{"image":"models/model.json"}]}"#
        let model = #"{"material":"materials/material.json","padding":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}"#
        let material = #"{"passes":[]}"#
        let entries = [
            entry("scene.json", scene),
            entry("models/model.json", model),
            entry("materials/material.json", material)
        ]

        let entryLimited = try build(
            entries: entries,
            limits: SceneGraphLimits(maximumJSONEntryBytes: UInt64(scene.utf8.count))
        )
        XCTAssertNotNil(entryLimited.document)
        XCTAssertEqual(entryLimited.status, .invalid)
        XCTAssertEqual(entryLimited.diagnostics.last?.code, "graph.resource-limit")

        let cumulativeLimit = UInt64(scene.utf8.count + model.utf8.count)
        let cumulative = try build(
            entries: entries,
            limits: SceneGraphLimits(
                maximumJSONEntryBytes: 1_024,
                maximumCumulativeJSONBytes: cumulativeLimit
            )
        )
        XCTAssertNotNil(cumulative.document)
        XCTAssertEqual(cumulative.status, .invalid)
        XCTAssertEqual(cumulative.document?.resources.map(\.id.rawValue), [
            "model:models/model.json"
        ])
        XCTAssertTrue(cumulative.diagnostics.contains { $0.code == "graph.resource-limit" })
    }

    func testDependencyEdgeLimitStopsBeforeOverflow() throws {
        let result = try build(
            entries: standardChainEntries(),
            limits: SceneGraphLimits(maximumDependencyEdgeCount: 2)
        )

        XCTAssertEqual(result.document?.dependencies.count, 2)
        XCTAssertEqual(result.status, .invalid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.resource-limit" })
    }

    func testTraversalIsOnDemandAndDoesNotReadTexturePayload() throws {
        var entries = standardChainEntries()
        entries.removeAll { $0.path == "materials/background.tex" }
        entries.append(contentsOf: [
            entry("unused/broken.json", #"{"broken":]"#),
            .init(path: "materials/background.tex", data: Data(repeating: 7, count: 4_096))
        ])
        let packageData = ScenePackageFixtureBuilder.make(entries: entries)
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: packageData)
        )
        let resolver = try ScenePackageAssetResolver.open(source: recording)
        recording.resetReadRanges()

        let result = SceneGraphBuilder().build(resolver: resolver)

        XCTAssertNotNil(result.document)
        XCTAssertTrue(result.document?.resources.contains {
            $0.id.rawValue == "texture:materials/background.tex"
        } == true)
        XCTAssertLessThan(recording.maximumReadByteCount, 4_096)
    }

    func testMapsNonModelNodePayloadsToProvenanceEdgesWithoutReadingThem() throws {
        let result = try build(entries: [
            entry(
                "scene.json",
                #"{"objects":[{"particle":"particles/smoke.json"},{"sound":"audio/music.ogg"},{"composition":"scenes/child.json"}]}"#
            ),
            .init(path: "particles/smoke.json", data: Data([1, 2, 3])),
            .init(path: "audio/music.ogg", data: Data(repeating: 4, count: 2_048)),
            .init(path: "scenes/child.json", data: Data([5, 6, 7]))
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.resources, [])
        XCTAssertEqual(document.dependencies.map(\.request.role), [
            .particle,
            .sound,
            .document
        ])
        XCTAssertEqual(document.dependencies.map(\.resolution.kind), [
            .package,
            .package,
            .package
        ])
        XCTAssertEqual(result.status, .exact)
    }

    func testPreservesSceneDocumentMetadataDependenciesWithProvenance() throws {
        let result = try build(entries: [
            entry(
                "scene.json",
                #"{"effect":"effects/root.json","file":"documents/root.json","model":"models/root.json","objects":[],"shader":"shaders/root.glsl","texture":"textures/root.tex"}"#
            ),
            entry("effects/root.json", "{}"),
            entry("documents/root.json", "{}"),
            entry("models/root.json", "{}"),
            .init(path: "shaders/root.glsl", data: Data([0x53])),
            texture("textures/root.tex")
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.dependencies.map(\.request.role), [
            .effect,
            .document,
            .model,
            .shader,
            .texture
        ])
        XCTAssertEqual(
            document.dependencies.map(\.resolution.kind),
            Array(repeating: .package, count: 5)
        )
        XCTAssertTrue(document.dependencies.allSatisfy { dependency in
            guard dependency.request.ownerPath?.rawValue == "scene.json",
                  case .package? = dependency.resolution.selected?.provenance,
                  case let .document(ownerPath) = dependency.owner else {
                return false
            }
            return ownerPath.rawValue == "scene.json"
        })
        XCTAssertEqual(document.resources.map(\.id.rawValue), [
            "effect:effects/root.json",
            "model:models/root.json",
            "shader:shaders/root.glsl",
            "texture:textures/root.tex"
        ])
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(
            Set(result.diagnostics.map(\.code)),
            ["graph.unsupported-effect", "graph.unsupported-shader"]
        )
    }

    func testPreservesInvalidPathEscapeAndExternalResolverStates() throws {
        let entries = [
            entry(
                "scene.json",
                #"{"objects":[{"image":"../outside.json"},{"image":"invalid\\path.json"},{"image":"models/model.json"}]}"#
            ),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"shader":"external/custom"}]}"#
            )
        ]
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: entries)
            ),
            sourcePolicy: SceneAssetSourcePolicy(
                version: 7,
                builtInPrefixes: [],
                externalPrefixes: ["external/"],
                classifyBareShadersAsBuiltIn: false
            )
        )

        let result = SceneGraphBuilder().build(resolver: resolver)
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.dependencies.map(\.resolution.kind), [
            .invalid,
            .invalid,
            .package,
            .package,
            .externalCandidate
        ])
        XCTAssertEqual(
            Set(result.diagnostics.map(\.code)),
            [
                "asset.external-candidate",
                "asset.invalid-reference",
                "asset.path-escape"
            ]
        )
        XCTAssertEqual(result.status, .invalid)
    }

    func testRecordsPassEffectsAsUnsupportedMetadataResources() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"effect":"effects/one.json","effects":["effects/two.json"],"kept":true}]}"#
            ),
            entry("effects/one.json", #"{"strength":1}"#),
            entry("effects/two.json", #"{"strength":2}"#)
        ])
        let document = try XCTUnwrap(result.document)
        let material = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertEqual(material.passes[0].effectDependencies.map(\.request.requestedPath), [
            "effects/one.json",
            "effects/two.json"
        ])
        XCTAssertEqual(material.passes[0].unknownFields, ["kept": .bool(true)])
        XCTAssertEqual(document.resources.filter {
            if case .effect = $0 { return true }
            return false
        }.map(\.id.rawValue), ["effect:effects/one.json", "effect:effects/two.json"])
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.unsupported-effect" }.count,
            2
        )
        XCTAssertEqual(result.status, .unsupported)
    }

    func testPreservesEffectShaderAndSceneScriptMetadataWithoutExecution() throws {
        let sceneScript = """
        // function ignoredFromLineComment() {}
        function update() {}
        function init() {}
        /* function ignoredFromBlockComment() {} */
        let text = \"function ignoredFromString() {}\";
        function update() {}
        """
        let nodeScript = "function init() {}"
        let materialScript = "function applyUserProperties() {}"
        let effectScript = "function arbitraryHandler() {}"
        let result = try build(entries: [
            entry(
                "scene.json",
                "{\"script\":\"\(escaped(sceneScript))\",\"objects\":[{\"image\":\"models/background.json\",\"script\":\"\(escaped(nodeScript))\"}]}"
            ),
            entry("models/background.json", #"{"material":"materials/background.json"}"#),
            entry(
                "materials/background.json",
                "{\"script\":\"\(escaped(materialScript))\",\"passes\":[{\"shader\":\"shaders/custom.glsl\",\"effect\":\"effects/glow/effect.json\"},{\"shader\":\"genericimage4\"}]}"
            ),
            entry(
                "effects/glow/effect.json",
                "{\"script\":\"\(escaped(effectScript))\",\"texture\":\"textures/glow.tex\"}"
            ),
            .init(path: "shaders/custom.glsl", data: Data(repeating: 1, count: 4_096)),
            texture("effects/glow/textures/glow.tex")
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(document.scripts.count, 4)
        XCTAssertTrue(document.scripts.contains {
            $0.ownerPath.rawValue == "scene.json" && $0.jsonPath == "$.script"
        })
        XCTAssertTrue(document.scripts.contains {
            $0.ownerPath.rawValue == "scene.json" && $0.jsonPath == "$.objects[0].script"
        })
        XCTAssertTrue(document.scripts.contains {
            $0.ownerPath.rawValue == "materials/background.json" && $0.jsonPath == "$.script"
        })
        XCTAssertTrue(document.scripts.contains {
            $0.ownerPath.rawValue == "effects/glow/effect.json" && $0.jsonPath == "$.script"
        })
        XCTAssertEqual(
            document.scripts.first {
                $0.ownerPath.rawValue == "scene.json" && $0.jsonPath == "$.script"
            }?.source,
            sceneScript
        )
        XCTAssertEqual(
            document.scripts.first {
                $0.ownerPath.rawValue == "scene.json" && $0.jsonPath == "$.script"
            }?.handlerNames,
            ["init", "update"]
        )
        XCTAssertEqual(
            document.scripts.first { $0.jsonPath == "$.objects[0].script" }?.handlerNames,
            ["init"]
        )
        XCTAssertEqual(
            document.scripts.first { $0.ownerPath.rawValue == "materials/background.json" }?.handlerNames,
            ["applyUserProperties"]
        )
        XCTAssertEqual(
            document.scripts.first { $0.ownerPath.rawValue == "effects/glow/effect.json" }?.handlerNames,
            ["arbitraryHandler"]
        )
        XCTAssertTrue(document.resources.contains {
            if case let .effect(effect) = $0 {
                return effect.path.rawValue == "effects/glow/effect.json"
                    && effect.dependencies.contains {
                        $0.request.role == .texture
                            && $0.request.requestedPath == "textures/glow.tex"
                    }
            }
            return false
        })
        XCTAssertEqual(document.resources.filter {
            if case .shader = $0 { return true }
            return false
        }.map(\.id.rawValue), ["shader:genericimage4", "shader:shaders/custom.glsl"])
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "graph.scenescript-preserved-not-executed"
        })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.unsupported-effect" })
        XCTAssertEqual(result.status, .unsupported)
    }

    func testStructuredEffectTextureBindingCreatesOneEdgeAndDiagnosticSet() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"effect":"effects/effect.json"}]}"#
            ),
            entry("effects/effect.json", #"{"texture":{"file":"missing-texture"}}"#)
        ])
        let document = try XCTUnwrap(result.document)
        let effect = try XCTUnwrap(document.resources.compactMap { resource -> SceneEffectResource? in
            guard case let .effect(effect) = resource else { return nil }
            return effect
        }.first)

        XCTAssertEqual(effect.dependencies.count, 1)
        XCTAssertEqual(effect.dependencies[0].request.role, .texture)
        XCTAssertEqual(effect.dependencies[0].request.requestedPath, "missing-texture")
        XCTAssertEqual(
            document.dependencies.filter { $0.request.requestedPath == "missing-texture" }.count,
            1
        )
        XCTAssertEqual(
            result.diagnostics.filter {
                $0.code == "asset.unresolved" && $0.arguments == ["missing-texture"]
            }.count,
            1
        )
    }

    func testMetadataKeysWithPathDelimitersDoNotCollide() throws {
        let result = try build(entries: [
            entry(
                "scene.json",
                #"{"a":{"b":{"texture":"missing.tex"}},"a.b":{"texture":"missing.tex"},"items":[{"texture":"missing.tex"}],"items[0]":{"texture":"missing.tex"},"objects":[]}"#
            )
        ])
        let document = try XCTUnwrap(result.document)
        let missingDependencies = document.dependencies.filter {
            $0.request.requestedPath == "missing.tex"
        }
        let missingDiagnostics = result.diagnostics.filter {
            $0.code == "asset.unresolved"
                && $0.arguments == ["missing.tex"]
        }

        XCTAssertEqual(missingDependencies.count, 4)
        XCTAssertTrue(missingDependencies.allSatisfy {
            guard case .document = $0.owner else { return false }
            return $0.request.role == .texture
        })
        XCTAssertEqual(Set(missingDiagnostics.compactMap(\.jsonPath)), [
            "$.a.b.texture",
            #"$["a.b"].texture"#,
            "$.items[0].texture",
            #"$["items[0]"].texture"#
        ])
        XCTAssertEqual(result.status, .unsupported)
    }

    func testStructuredTextureBindingRetainsNestedShaderAndScriptMetadata() throws {
        let nestedScript = "function nested() {}"
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"effect":"effects/effect.json"}]}"#
            ),
            entry(
                "effects/effect.json",
                "{\"texture\":{\"file\":\"missing-texture\",\"shader\":\"shaders/nested.glsl\",\"script\":\"\(escaped(nestedScript))\"}}"
            ),
            .init(path: "effects/shaders/nested.glsl", data: Data(repeating: 1, count: 4_096))
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(
            document.dependencies.filter { $0.request.requestedPath == "missing-texture" }.count,
            1
        )
        XCTAssertEqual(
            result.diagnostics.filter {
                $0.code == "asset.unresolved" && $0.arguments == ["missing-texture"]
            }.count,
            1
        )
        XCTAssertTrue(document.resources.contains {
            $0.id.rawValue == "shader:effects/shaders/nested.glsl"
        })
        XCTAssertEqual(document.scripts.first {
            $0.ownerPath.rawValue == "effects/effect.json"
                && $0.jsonPath == "$.texture.script"
        }?.source, nestedScript)
    }

    func testConsumedTextureStringRetainsStructuredFileMetadata() throws {
        let nestedScript = "function retainedFromFile() {}"
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry("materials/material.json", #"{"passes":[{"effect":"effects/effect.json"}]}"#),
            entry(
                "effects/effect.json",
                "{\"texture\":{\"texture\":\"missing-texture\",\"file\":{\"shader\":\"shaders/from-file.glsl\",\"script\":\"\(escaped(nestedScript))\"}}}"
            ),
            .init(path: "effects/shaders/from-file.glsl", data: Data(repeating: 1, count: 4_096))
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(
            document.dependencies.filter { $0.request.requestedPath == "missing-texture" }.count,
            1
        )
        XCTAssertEqual(
            result.diagnostics.filter {
                $0.code == "asset.unresolved" && $0.arguments == ["missing-texture"]
            }.count,
            1
        )
        XCTAssertTrue(document.resources.contains {
            $0.id.rawValue == "shader:effects/shaders/from-file.glsl"
        })
        XCTAssertEqual(document.scripts.first {
            $0.ownerPath.rawValue == "effects/effect.json"
                && $0.jsonPath == "$.texture.file.script"
        }?.source, nestedScript)
    }

    func testConsumedFileStringRetainsStructuredTextureMetadata() throws {
        let nestedScript = "function retainedFromTexture() {}"
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry("materials/material.json", #"{"passes":[{"effect":"effects/effect.json"}]}"#),
            entry(
                "effects/effect.json",
                "{\"texture\":{\"file\":\"missing-file\",\"texture\":{\"shader\":\"shaders/from-texture.glsl\",\"script\":\"\(escaped(nestedScript))\"}}}"
            ),
            .init(path: "effects/shaders/from-texture.glsl", data: Data(repeating: 1, count: 4_096))
        ])
        let document = try XCTUnwrap(result.document)

        XCTAssertEqual(
            document.dependencies.filter { $0.request.requestedPath == "missing-file" }.count,
            1
        )
        XCTAssertEqual(
            result.diagnostics.filter {
                $0.code == "asset.unresolved" && $0.arguments == ["missing-file"]
            }.count,
            1
        )
        XCTAssertTrue(document.resources.contains {
            $0.id.rawValue == "shader:effects/shaders/from-texture.glsl"
        })
        XCTAssertEqual(document.scripts.first {
            $0.ownerPath.rawValue == "effects/effect.json"
                && $0.jsonPath == "$.texture.texture.script"
        }?.source, nestedScript)
    }

    func testScriptHandlerScannerPreservesDollarIdentifiersAndGenerators() throws {
        let source = """
        function update$() {}
        function* generator() {}
        function $update() {}
        function update$() {}
        """
        let result = try build(entries: [
            entry("scene.json", "{\"script\":\"\(escaped(source))\"}")
        ])
        let script = try XCTUnwrap(result.document?.scripts.first)

        XCTAssertEqual(script.handlerNames, ["$update", "generator", "update$"])
    }

    func testMemoizesReferencedPassDocumentsWithinCumulativeLimit() throws {
        let scene = #"{"objects":[{"image":"models/model.json"}]}"#
        let model = #"{"material":"materials/material.json"}"#
        let material = #"{"passes":["passes/shared.json","passes/shared.json"]}"#
        let pass = #"{"shader":"genericimage4"}"#
        let entries = [
            entry("scene.json", scene),
            entry("models/model.json", model),
            entry("materials/material.json", material),
            entry("passes/shared.json", pass)
        ]

        let result = try build(
            entries: entries,
            limits: SceneGraphLimits(
                maximumJSONEntryBytes: 1_024,
                maximumCumulativeJSONBytes: UInt64(
                    scene.utf8.count + model.utf8.count + material.utf8.count + pass.utf8.count
                )
            )
        )
        let materialResource = try XCTUnwrap(result.document?.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertEqual(materialResource.passes.count, 2)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertFalse(result.diagnostics.contains { $0.code == "graph.resource-limit" })
    }

    func testRetainsMalformedKnownMetadataAndContinuesTopLevelTextures() throws {
        let result = try build(entries: [
            entry(
                "scene.json",
                #"{"objects":[{"image":"models/invalid.json"},{"image":"models/material.json"}]}"#
            ),
            entry("models/invalid.json", #"{"material":7,"mesh":"quad"}"#),
            entry("models/material.json", #"{"material":"materials/bad-passes.json"}"#),
            entry(
                "materials/bad-passes.json",
                #"{"passes":false,"texture":"base","kept":"metadata"}"#
            ),
            texture("materials/base.tex")
        ])
        let document = try XCTUnwrap(result.document)
        let models = document.resources.compactMap { resource -> SceneModelResource? in
            guard case let .model(model) = resource else { return nil }
            return model
        }
        let material = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertEqual(models.first { $0.path.rawValue == "models/invalid.json" }?.unknownFields, [
            "material": .integer(7),
            "mesh": .string("quad")
        ])
        XCTAssertEqual(material.unknownFields, [
            "kept": .string("metadata"),
            "passes": .bool(false)
        ])
        let topLevelPass = try XCTUnwrap(material.passes.first)
        XCTAssertEqual(material.passes.count, 1)
        XCTAssertEqual(topLevelPass.textureBindings.first?.dependency.resolution.kind, .package)
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.invalid-property" }.map(\.jsonPath),
            ["passes", "material"]
        )
    }

    func testPreservesPassSourceOffsetsAfterMalformedEntries() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[false,{"texture":"base"},"passes/referenced.json",42],"texture":"top"}"#
            ),
            entry("passes/referenced.json", #"{"shader":"genericimage4"}"#),
            texture("materials/base.tex"),
            texture("materials/top.tex")
        ])
        let document = try XCTUnwrap(result.document)
        let material = try XCTUnwrap(document.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertEqual(material.passes.map(\.index), [1, 2, 4])
        XCTAssertEqual(material.passes[1].documentDependency?.owner, .materialPass(
            material: material.id,
            index: 2
        ))
        XCTAssertEqual(
            result.diagnostics.filter { $0.code == "graph.invalid-property" }.map(\.jsonPath),
            ["passes[0]", "passes[3]"]
        )
    }

    func testReservesFailedJSONReadsAndMemoizesTheirFailure() throws {
        let scene = #"{"objects":[{"image":"models/fails.json"},{"image":"models/fails.json"},{"image":"models/later.json"}]}"#
        let failedModel = #"{"material":"materials/unused.json"}"#
        let laterModel = #"{"material":"materials/later.json"}"#
        let packageData = ScenePackageFixtureBuilder.make(entries: [
            entry("scene.json", scene),
            entry("models/fails.json", failedModel),
            entry("models/later.json", laterModel)
        ])
        let archive = try ScenePackageArchiveReader().read(
            source: SceneDataByteSource(data: packageData)
        )
        let failedRange = try XCTUnwrap(archive.entry(named: "models/fails.json")).payloadRange
        let laterRange = try XCTUnwrap(archive.entry(named: "models/later.json")).payloadRange
        let source = FailingRangeSceneByteSource(
            data: packageData,
            failingRange: failedRange
        )
        let resolver = try ScenePackageAssetResolver.open(source: source)
        source.resetReadRanges()

        let result = SceneGraphBuilder(limits: SceneGraphLimits(
            maximumJSONEntryBytes: 1_024,
            maximumCumulativeJSONBytes: UInt64(scene.utf8.count + failedModel.utf8.count)
        )).build(resolver: resolver)

        XCTAssertEqual(source.readRanges.filter { $0.overlaps(failedRange) }.count, 1)
        XCTAssertFalse(source.readRanges.contains { $0.overlaps(laterRange) })
        XCTAssertEqual(result.status, .invalid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "graph.resource-limit" })
    }

    func testDiagnosesMalformedTextureBindingSlotWithoutDroppingRawBinding() throws {
        let result = try build(entries: [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"textures":[{"slot":7,"texture":"base"}]}]}"#
            ),
            texture("materials/base.tex")
        ])
        let material = try XCTUnwrap(result.document?.resources.compactMap {
            resource -> SceneMaterialResource? in
            guard case let .material(material) = resource else { return nil }
            return material
        }.first)

        XCTAssertNil(material.passes[0].textureBindings[0].slot)
        XCTAssertEqual(material.passes[0].textureBindings[0].rawValue, .object([
            "slot": .integer(7),
            "texture": .string("base")
        ]))
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "graph.invalid-property" && $0.jsonPath == "textures[0].slot"
        })
        XCTAssertEqual(result.status, .unsupported)
    }

    func testDoesNotReadPackageTextureOrShaderPayloadRanges() throws {
        let entries = [
            entry("scene.json", #"{"objects":[{"image":"models/model.json"}]}"#),
            entry("models/model.json", #"{"material":"materials/material.json"}"#),
            entry(
                "materials/material.json",
                #"{"passes":[{"shader":"shaders/custom.glsl","texture":"base","effect":"effects/custom.json"}]}"#
            ),
            .init(path: "shaders/custom.glsl", data: Data(repeating: 1, count: 4_096)),
            texture("materials/base.tex"),
            entry("effects/custom.json", #"{"texture":"base"}"#)
        ]
        let packageData = ScenePackageFixtureBuilder.make(entries: entries)
        let archive = try ScenePackageArchiveReader().read(
            source: SceneDataByteSource(data: packageData)
        )
        let protectedRanges = try [
            "materials/base.tex",
            "shaders/custom.glsl"
        ].map { path in
            try XCTUnwrap(archive.entry(named: path)).payloadRange
        }
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: packageData)
        )
        let resolver = try ScenePackageAssetResolver.open(source: recording)
        recording.resetReadRanges()

        let result = SceneGraphBuilder().build(resolver: resolver)

        XCTAssertNotNil(result.document)
        XCTAssertFalse(recording.readRanges.contains { readRange in
            protectedRanges.contains { readRange.overlaps($0) }
        })
    }

    private func standardChainEntries() -> [ScenePackageFixtureEntry] {
        [
            entry("scene.json", #"{"objects":[{"image":"models/background.json"}]}"#),
            entry(
                "models/background.json",
                #"{"material":"materials/background.json","mesh":"quad"}"#
            ),
            entry(
                "materials/background.json",
                #"{"passes":[{"shader":"genericimage4","textures":["background"],"depth":false}],"blend":"normal"}"#
            ),
            texture("materials/background.tex")
        ]
    }

    private func build(
        entries: [ScenePackageFixtureEntry],
        limits: SceneGraphLimits = .init()
    ) throws -> SceneGraphBuildResult {
        let resolver = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: entries)
            )
        )
        return SceneGraphBuilder(limits: limits).build(resolver: resolver)
    }

    private func entry(_ path: String, _ json: String) -> ScenePackageFixtureEntry {
        .init(path: path, data: Data(json.utf8))
    }

    private func texture(_ path: String) -> ScenePackageFixtureEntry {
        .init(path: path, data: Data([0x54, 0x45, 0x58]))
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private final class FailingRangeSceneByteSource: SceneByteSource, @unchecked Sendable {
    private let base: SceneDataByteSource
    private let failingRange: Range<UInt64>
    private var ranges: [Range<UInt64>] = []

    var byteCount: UInt64 { base.byteCount }
    var readRanges: [Range<UInt64>] { ranges }

    init(data: Data, failingRange: Range<UInt64>) {
        base = SceneDataByteSource(data: data)
        self.failingRange = failingRange
    }

    func resetReadRanges() {
        ranges.removeAll(keepingCapacity: true)
    }

    func read(range: Range<UInt64>) throws -> Data {
        ranges.append(range)
        guard !range.overlaps(failingRange) else {
            throw SceneFormatError.outOfBounds
        }
        return try base.read(range: range)
    }
}
