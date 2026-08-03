import Foundation
import MacWallSceneAssets

public enum SceneResourceKind: String, Codable, Equatable, Hashable, Sendable {
    case model
    case material
    case effect
    case shader
    case texture
}

public struct SceneResourceID: Codable, Comparable, Hashable, Sendable {
    public let kind: SceneResourceKind
    public let path: SceneVirtualPath
    public var rawValue: String {
        "\(kind.rawValue):\(path.rawValue)"
    }

    public init(kind: SceneResourceKind, path: SceneVirtualPath) {
        self.kind = kind
        self.path = path
    }

    public static func < (lhs: SceneResourceID, rhs: SceneResourceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SceneDependencyOwner: Equatable, Sendable {
    case node(SceneNodeID)
    case resource(SceneResourceID)
    case materialPass(material: SceneResourceID, index: Int)
}

public struct SceneDependencyEdge: Equatable, Sendable {
    public let owner: SceneDependencyOwner
    public let key: String
    public let request: SceneAssetRequest
    public let resolution: SceneAssetResolution

    public init(
        owner: SceneDependencyOwner,
        key: String,
        request: SceneAssetRequest,
        resolution: SceneAssetResolution
    ) {
        self.owner = owner
        self.key = key
        self.request = request
        self.resolution = resolution
    }
}

public struct SceneModelResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let materialDependency: SceneDependencyEdge?
    public let unknownFields: [String: SceneJSONValue]

    public init(
        id: SceneResourceID,
        path: SceneVirtualPath,
        materialDependency: SceneDependencyEdge?,
        unknownFields: [String: SceneJSONValue]
    ) {
        self.id = id
        self.path = path
        self.materialDependency = materialDependency
        self.unknownFields = unknownFields
    }
}

public struct SceneMaterialResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let passes: [SceneMaterialPass]
    public let unknownFields: [String: SceneJSONValue]

    public init(
        id: SceneResourceID,
        path: SceneVirtualPath,
        passes: [SceneMaterialPass],
        unknownFields: [String: SceneJSONValue]
    ) {
        self.id = id
        self.path = path
        self.passes = passes
        self.unknownFields = unknownFields
    }
}

public struct SceneMaterialPass: Equatable, Sendable {
    public let index: Int
    public let sourcePath: SceneVirtualPath?
    public let documentDependency: SceneDependencyEdge?
    public let shaderDependency: SceneDependencyEdge?
    public let textureBindings: [SceneTextureBinding]
    public let effectDependencies: [SceneDependencyEdge]
    public let rawValue: SceneJSONValue
    public let unknownFields: [String: SceneJSONValue]

    public init(
        index: Int,
        sourcePath: SceneVirtualPath?,
        documentDependency: SceneDependencyEdge?,
        shaderDependency: SceneDependencyEdge?,
        textureBindings: [SceneTextureBinding],
        effectDependencies: [SceneDependencyEdge],
        rawValue: SceneJSONValue,
        unknownFields: [String: SceneJSONValue]
    ) {
        self.index = index
        self.sourcePath = sourcePath
        self.documentDependency = documentDependency
        self.shaderDependency = shaderDependency
        self.textureBindings = textureBindings
        self.effectDependencies = effectDependencies
        self.rawValue = rawValue
        self.unknownFields = unknownFields
    }
}

public struct SceneTextureBinding: Equatable, Sendable {
    public let slot: String?
    public let rawValue: SceneJSONValue
    public let dependency: SceneDependencyEdge

    public init(slot: String?, rawValue: SceneJSONValue, dependency: SceneDependencyEdge) {
        self.slot = slot
        self.rawValue = rawValue
        self.dependency = dependency
    }
}

public struct SceneEffectResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let dependencies: [SceneDependencyEdge]
    public let unknownFields: [String: SceneJSONValue]

    public init(
        id: SceneResourceID,
        path: SceneVirtualPath,
        dependencies: [SceneDependencyEdge],
        unknownFields: [String: SceneJSONValue]
    ) {
        self.id = id
        self.path = path
        self.dependencies = dependencies
        self.unknownFields = unknownFields
    }
}

public struct SceneShaderResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let resolution: SceneAssetResolution

    public init(id: SceneResourceID, path: SceneVirtualPath, resolution: SceneAssetResolution) {
        self.id = id
        self.path = path
        self.resolution = resolution
    }
}

public struct SceneTextureResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let resolution: SceneAssetResolution

    public init(id: SceneResourceID, path: SceneVirtualPath, resolution: SceneAssetResolution) {
        self.id = id
        self.path = path
        self.resolution = resolution
    }
}

public enum SceneGraphResource: Equatable, Sendable {
    case model(SceneModelResource)
    case material(SceneMaterialResource)
    case effect(SceneEffectResource)
    case shader(SceneShaderResource)
    case texture(SceneTextureResource)

    public var id: SceneResourceID {
        switch self {
        case let .model(resource):
            resource.id
        case let .material(resource):
            resource.id
        case let .effect(resource):
            resource.id
        case let .shader(resource):
            resource.id
        case let .texture(resource):
            resource.id
        }
    }
}
