import Foundation

public enum SceneAnimationValueKind: String, Codable, Equatable, Sendable {
    case scalar
    case vector2
    case vector3
    case raw
}

public enum SceneAnimationTrackStatus: String, Codable, Equatable, Sendable {
    case exact
    case degraded
}

public struct SceneAnimationKeyframe: Equatable, Sendable {
    public let frame: Double?
    public let time: Double?
    public let value: SceneJSONValue?
    public let interpolation: SceneJSONValue?
    public let unknownFields: [String: SceneJSONValue]

    public init(
        frame: Double?,
        time: Double?,
        value: SceneJSONValue?,
        interpolation: SceneJSONValue?,
        unknownFields: [String: SceneJSONValue]
    ) {
        self.frame = frame
        self.time = time
        self.value = value
        self.interpolation = interpolation
        self.unknownFields = unknownFields
    }
}

public struct SceneAnimationChannel: Equatable, Sendable {
    public let name: String
    public let keyframes: [SceneAnimationKeyframe]
    public let rawValue: SceneJSONValue

    public init(name: String, keyframes: [SceneAnimationKeyframe], rawValue: SceneJSONValue) {
        self.name = name
        self.keyframes = keyframes
        self.rawValue = rawValue
    }
}

public struct SceneAnimationTrack: Equatable, Sendable {
    public let nodeID: SceneNodeID
    public let propertyPath: String
    public let valueKind: SceneAnimationValueKind
    public let fps: Double?
    public let duration: Double?
    public let isRelative: Bool?
    public let channels: [SceneAnimationChannel]
    public let status: SceneAnimationTrackStatus
    public let rawValue: SceneJSONValue

    public init(
        nodeID: SceneNodeID,
        propertyPath: String,
        valueKind: SceneAnimationValueKind,
        fps: Double?,
        duration: Double?,
        isRelative: Bool?,
        channels: [SceneAnimationChannel],
        status: SceneAnimationTrackStatus,
        rawValue: SceneJSONValue
    ) {
        self.nodeID = nodeID
        self.propertyPath = propertyPath
        self.valueKind = valueKind
        self.fps = fps
        self.duration = duration
        self.isRelative = isRelative
        self.channels = channels
        self.status = status
        self.rawValue = rawValue
    }
}
