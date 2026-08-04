import Foundation
import MacWallSceneAssets

public struct SceneNodeID: Codable, Comparable, Hashable, Sendable {
    public let documentPath: SceneVirtualPath
    public let objectIndex: Int
    public var rawValue: String {
        "\(documentPath.rawValue)#objects[\(objectIndex)]"
    }

    public init(documentPath: SceneVirtualPath, objectIndex: Int) {
        self.documentPath = documentPath
        self.objectIndex = objectIndex
    }

    public static func < (lhs: SceneNodeID, rhs: SceneNodeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SceneSourceIdentifier: Codable, Equatable, Hashable, Sendable {
    case integer(Int64)
    case string(String)

    init?(scalar value: SceneJSONValue) {
        switch value {
        case let .integer(identifier):
            self = .integer(identifier)
        case let .string(identifier):
            self = .string(identifier)
        default:
            return nil
        }
    }
}

public enum SceneNodePayload: Equatable, Sendable {
    case image(reference: String)
    case text(SceneJSONValue)
    case particle(reference: String)
    case sound(reference: String)
    case model(reference: String)
    case composition(reference: String?)
    case fullscreen
    case unknown(typeName: String?, rawValue: SceneJSONValue)
}

public enum SceneNodeKind: Equatable, Sendable {
    case image
    case text
    case particle
    case sound
    case model
    case composition
    case fullscreen
    case unknown(String?)
}

extension SceneNodePayload {
    public var kind: SceneNodeKind {
        switch self {
        case .image:
            .image
        case .text:
            .text
        case .particle:
            .particle
        case .sound:
            .sound
        case .model:
            .model
        case .composition:
            .composition
        case .fullscreen:
            .fullscreen
        case let .unknown(typeName, _):
            .unknown(typeName)
        }
    }
}

public struct SceneGraphNode: Equatable, Sendable {
    public let id: SceneNodeID
    public let sourceIdentifier: SceneSourceIdentifier?
    public let sourceOrder: Int
    public let name: String?
    public let payload: SceneNodePayload
    public let visible: Bool?
    public let enabled: Bool?
    public let zOrder: Double?
    public let origin: SceneGraphVector3?
    public let pivot: SceneGraphVector3?
    public let position: SceneGraphVector3?
    public let scale: SceneGraphVector3?
    public let angles: SceneGraphVector3?
    public let size: SceneGraphSize?
    public let opacity: Double?
    public let color: SceneGraphColor?
    public let unknownFields: [String: SceneJSONValue]

    public init(
        id: SceneNodeID,
        sourceIdentifier: SceneSourceIdentifier?,
        sourceOrder: Int,
        name: String?,
        payload: SceneNodePayload,
        visible: Bool?,
        enabled: Bool?,
        zOrder: Double?,
        origin: SceneGraphVector3?,
        pivot: SceneGraphVector3?,
        position: SceneGraphVector3?,
        scale: SceneGraphVector3?,
        angles: SceneGraphVector3?,
        size: SceneGraphSize?,
        opacity: Double?,
        color: SceneGraphColor?,
        unknownFields: [String: SceneJSONValue]
    ) {
        self.id = id
        self.sourceIdentifier = sourceIdentifier
        self.sourceOrder = sourceOrder
        self.name = name
        self.payload = payload
        self.visible = visible
        self.enabled = enabled
        self.zOrder = zOrder
        self.origin = origin
        self.pivot = pivot
        self.position = position
        self.scale = scale
        self.angles = angles
        self.size = size
        self.opacity = opacity
        self.color = color
        self.unknownFields = unknownFields
    }
}
