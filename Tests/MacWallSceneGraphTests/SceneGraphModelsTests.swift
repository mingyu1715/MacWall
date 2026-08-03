import XCTest
import MacWallSceneAssets
import MacWallSceneGraph

final class SceneGraphModelsTests: XCTestCase {
    func testConstructedDocumentPreservesTypedGraphValues() throws {
        let scenePath = try SceneVirtualPath(canonicalPath: "scene.json")
        let materialPath = try SceneVirtualPath(canonicalPath: "materials/metal.json")
        let texturePath = try SceneVirtualPath(canonicalPath: "textures/albedo.tex")
        let nodeID = SceneNodeID(documentPath: scenePath, objectIndex: 0)
        let materialID = SceneResourceID(kind: .material, path: materialPath)
        let textureID = SceneResourceID(kind: .texture, path: texturePath)
        let request = SceneAssetRequest(
            requestedPath: "textures/albedo.tex",
            ownerPath: materialPath,
            role: .texture,
            key: "albedo"
        )
        let resolution = SceneAssetResolution(
            request: request,
            candidates: [
                SceneAssetCandidate(path: texturePath, origin: .ownerRelative)
            ],
            kind: .package,
            selected: SceneResolvedAsset(
                request: request,
                canonicalPath: texturePath,
                candidateOrigin: .ownerRelative,
                provenance: .package(
                    SceneAssetEntryIdentity(relativeOffset: 0, byteCount: 128)
                )
            ),
            issues: []
        )
        let dependency = SceneDependencyEdge(
            owner: .materialPass(material: materialID, index: 0),
            key: "albedo",
            request: request,
            resolution: resolution
        )
        let node = SceneGraphNode(
            id: nodeID,
            sourceIdentifier: .integer(7),
            sourceOrder: 0,
            name: "Hero",
            payload: .image(reference: "textures/albedo.tex"),
            visible: true,
            enabled: true,
            zOrder: 3,
            origin: SceneGraphVector3(x: 0, y: 0, z: 0),
            pivot: SceneGraphVector3(x: 0.5, y: 0.5, z: 0),
            position: SceneGraphVector3(x: 10, y: 20, z: 0),
            scale: SceneGraphVector3(x: 1, y: 1, z: 1),
            angles: SceneGraphVector3(x: 0, y: 0, z: 0),
            size: SceneGraphSize(width: 1920, height: 1080),
            opacity: 0.75,
            color: SceneGraphColor(red: 1, green: 0.5, blue: 0.25, alpha: 1),
            unknownFields: ["custom": .bool(true)]
        )
        let material = SceneMaterialResource(
            id: materialID,
            path: materialPath,
            passes: [
                SceneMaterialPass(
                    index: 0,
                    sourcePath: materialPath,
                    documentDependency: nil,
                    shaderDependency: nil,
                    textureBindings: [
                        SceneTextureBinding(
                            slot: "albedo",
                            rawValue: .string("textures/albedo.tex"),
                            dependency: dependency
                        )
                    ],
                    effectDependencies: [],
                    rawValue: .object(["name": .string("base")]),
                    unknownFields: [:]
                )
            ],
            unknownFields: [:]
        )
        let animation = SceneAnimationTrack(
            nodeID: nodeID,
            propertyPath: "position.x",
            valueKind: .scalar,
            fps: 60,
            duration: 1,
            isRelative: false,
            channels: [
                SceneAnimationChannel(
                    name: "x",
                    keyframes: [
                        SceneAnimationKeyframe(
                            frame: 0,
                            time: 0,
                            value: .integer(10),
                            interpolation: nil,
                            unknownFields: [:]
                        )
                    ],
                    rawValue: .object([:])
                )
            ],
            status: .exact,
            rawValue: .object([:])
        )
        let script = SceneScriptMetadata(
            ownerPath: scenePath,
            nodeID: nodeID,
            jsonPath: "objects[0].script",
            source: "update = function() {}",
            handlerNames: ["update"]
        )
        let document = SceneGraphDocument(
            package: SceneAssetPackageMetadata(
                version: "1",
                isVerifiedVersion: true,
                entryCount: 3
            ),
            sourcePath: scenePath,
            canvas: SceneGraphCanvas(width: 1920, height: 1080),
            sceneMetadata: ["title": .string("Example")],
            nodes: [node],
            hierarchyEdges: [
                SceneHierarchyEdge(
                    childID: nodeID,
                    requestedParent: .string("root"),
                    resolution: .missing
                )
            ],
            instanceEdges: [],
            resources: [.material(material), .texture(SceneTextureResource(
                id: textureID,
                path: texturePath,
                resolution: resolution
            ))],
            dependencies: [dependency],
            animations: [animation],
            scripts: [script]
        )

        XCTAssertEqual(
            document,
            SceneGraphDocument(
                package: SceneAssetPackageMetadata(
                    version: "1",
                    isVerifiedVersion: true,
                    entryCount: 3
                ),
                sourcePath: scenePath,
                canvas: SceneGraphCanvas(width: 1920, height: 1080),
                sceneMetadata: ["title": .string("Example")],
                nodes: [node],
                hierarchyEdges: [
                    SceneHierarchyEdge(
                        childID: nodeID,
                        requestedParent: .string("root"),
                        resolution: .missing
                    )
                ],
                instanceEdges: [],
                resources: [.material(material), .texture(SceneTextureResource(
                    id: textureID,
                    path: texturePath,
                    resolution: resolution
                ))],
                dependencies: [dependency],
                animations: [animation],
                scripts: [script]
            )
        )
        XCTAssertEqual(nodeID.rawValue, "scene.json#objects[0]")
        XCTAssertEqual(materialID.rawValue, "material:materials/metal.json")
        XCTAssertEqual(SceneNodePayload.fullscreen.kind, .fullscreen)
        XCTAssertEqual(SceneGraphResource.texture(
            SceneTextureResource(id: textureID, path: texturePath, resolution: resolution)
        ).id, textureID)
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    func testPublicGraphValuesAreSendable() {
        requireSendable(SceneGraphDocument.self)
        requireSendable(SceneGraphBuildResult.self)
        requireSendable(SceneGraphNode.self)
        requireSendable(SceneGraphResource.self)
        requireSendable(SceneAnimationTrack.self)
    }
}
