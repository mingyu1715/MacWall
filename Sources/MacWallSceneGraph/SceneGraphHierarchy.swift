import Foundation

public enum SceneNodeReferenceResolution: Equatable, Sendable {
    case resolved(SceneNodeID)
    case missing
    case ambiguous([SceneNodeID])
}

public struct SceneHierarchyEdge: Equatable, Sendable {
    public let childID: SceneNodeID
    public let requestedParent: SceneSourceIdentifier
    public let resolution: SceneNodeReferenceResolution

    public init(
        childID: SceneNodeID,
        requestedParent: SceneSourceIdentifier,
        resolution: SceneNodeReferenceResolution
    ) {
        self.childID = childID
        self.requestedParent = requestedParent
        self.resolution = resolution
    }
}

public struct ScenePropertyOverride: Equatable, Sendable {
    public let propertyPath: String
    public let value: SceneJSONValue

    public init(propertyPath: String, value: SceneJSONValue) {
        self.propertyPath = propertyPath
        self.value = value
    }
}

public struct SceneInstanceEdge: Equatable, Sendable {
    public let instanceID: SceneNodeID
    public let requestedSource: SceneSourceIdentifier
    public let resolution: SceneNodeReferenceResolution
    public let overrides: [ScenePropertyOverride]

    public init(
        instanceID: SceneNodeID,
        requestedSource: SceneSourceIdentifier,
        resolution: SceneNodeReferenceResolution,
        overrides: [ScenePropertyOverride]
    ) {
        self.instanceID = instanceID
        self.requestedSource = requestedSource
        self.resolution = resolution
        self.overrides = overrides
    }
}
