import Foundation
import MacWallSceneAssets

public struct SceneScriptMetadata: Equatable, Sendable {
    public let ownerPath: SceneVirtualPath
    public let nodeID: SceneNodeID?
    public let jsonPath: String
    public let source: String
    public let handlerNames: [String]

    public init(
        ownerPath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String,
        source: String,
        handlerNames: [String]
    ) {
        self.ownerPath = ownerPath
        self.nodeID = nodeID
        self.jsonPath = jsonPath
        self.source = source
        self.handlerNames = handlerNames
    }
}

public struct SceneGraphDocument: Equatable, Sendable {
    public let package: SceneAssetPackageMetadata
    public let sourcePath: SceneVirtualPath
    public let canvas: SceneGraphCanvas?
    public let sceneMetadata: [String: SceneJSONValue]
    public let nodes: [SceneGraphNode]
    public let hierarchyEdges: [SceneHierarchyEdge]
    public let instanceEdges: [SceneInstanceEdge]
    public let resources: [SceneGraphResource]
    public let dependencies: [SceneDependencyEdge]
    public let animations: [SceneAnimationTrack]
    public let scripts: [SceneScriptMetadata]

    public init(
        package: SceneAssetPackageMetadata,
        sourcePath: SceneVirtualPath,
        canvas: SceneGraphCanvas?,
        sceneMetadata: [String: SceneJSONValue],
        nodes: [SceneGraphNode],
        hierarchyEdges: [SceneHierarchyEdge],
        instanceEdges: [SceneInstanceEdge],
        resources: [SceneGraphResource],
        dependencies: [SceneDependencyEdge],
        animations: [SceneAnimationTrack],
        scripts: [SceneScriptMetadata]
    ) {
        self.package = package
        self.sourcePath = sourcePath
        self.canvas = canvas
        self.sceneMetadata = sceneMetadata
        self.nodes = nodes
        self.hierarchyEdges = hierarchyEdges
        self.instanceEdges = instanceEdges
        self.resources = resources
        self.dependencies = dependencies
        self.animations = animations
        self.scripts = scripts
    }
}

public struct SceneGraphBuildResult: Equatable, Sendable {
    public let document: SceneGraphDocument?
    public let status: SceneGraphStatus
    public let diagnostics: [SceneGraphDiagnostic]

    public init(
        document: SceneGraphDocument?,
        status: SceneGraphStatus,
        diagnostics: [SceneGraphDiagnostic]
    ) {
        self.document = document
        self.status = status
        self.diagnostics = diagnostics
    }
}
