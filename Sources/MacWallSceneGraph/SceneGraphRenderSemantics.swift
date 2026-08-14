import Foundation

public enum SceneRenderableProperty: String, Codable, Sendable {
    case origin
    case position
    case scale
    case rotationZ
    case opacity
    case visibility
    case enabled
    case zOrder
}

public enum SceneTimelinePlaybackMode: String, Codable, Sendable {
    case loop
    case mirror
    case single
}

public enum SceneTimelineInterpolation: Equatable, Sendable {
    case linear
    case step
    case cubicBezier(SceneCubicBezierControlPoints)
}

public struct SceneCubicBezierControlPoints: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
}

public enum SceneTypedPropertyValue: Equatable, Sendable {
    case scalar(Double)
    case vector3(SceneGraphVector3)
    case boolean(Bool)
}

public struct SceneTypedAnimationKeyframe: Equatable, Sendable {
    public let timeSeconds: Double
    public let value: SceneTypedPropertyValue
    public let interpolation: SceneTimelineInterpolation

    public init(
        timeSeconds: Double,
        value: SceneTypedPropertyValue,
        interpolation: SceneTimelineInterpolation
    ) {
        self.timeSeconds = timeSeconds
        self.value = value
        self.interpolation = interpolation
    }
}

public struct SceneTypedAnimationTrack: Equatable, Sendable {
    public let property: SceneRenderableProperty
    public let playbackMode: SceneTimelinePlaybackMode
    public let durationSeconds: Double
    public let isRelative: Bool
    public let startsPaused: Bool
    public let keyframes: [SceneTypedAnimationKeyframe]

    public init(
        property: SceneRenderableProperty,
        playbackMode: SceneTimelinePlaybackMode,
        durationSeconds: Double,
        isRelative: Bool,
        startsPaused: Bool,
        keyframes: [SceneTypedAnimationKeyframe]
    ) {
        self.property = property
        self.playbackMode = playbackMode
        self.durationSeconds = durationSeconds
        self.isRelative = isRelative
        self.startsPaused = startsPaused
        self.keyframes = keyframes
    }
}

public struct SceneTypedPropertyOverride: Equatable, Sendable {
    public let property: SceneRenderableProperty
    public let value: SceneTypedPropertyValue

    public init(
        property: SceneRenderableProperty,
        value: SceneTypedPropertyValue
    ) {
        self.property = property
        self.value = value
    }
}

extension SceneAnimationTrack {
    public var typedTrack: SceneTypedAnimationTrack? {
        guard status == .exact,
              let property = SceneRenderableProperty(animationPath: propertyPath),
              let playbackMode,
              let fps,
              fps.isFinite,
              fps > 0,
              let lengthFrames,
              lengthFrames.isFinite,
              lengthFrames > 0 else {
            return nil
        }

        let durationSeconds = lengthFrames / fps
        guard durationSeconds.isFinite, durationSeconds > 0,
              let keyframes = typedKeyframes(
                  property: property,
                  fps: fps,
                  lengthFrames: lengthFrames
              ) else {
            return nil
        }

        return SceneTypedAnimationTrack(
            property: property,
            playbackMode: playbackMode,
            durationSeconds: durationSeconds,
            isRelative: isRelative ?? false,
            startsPaused: startsPaused,
            keyframes: keyframes
        )
    }

    private func typedKeyframes(
        property: SceneRenderableProperty,
        fps: Double,
        lengthFrames: Double
    ) -> [SceneTypedAnimationKeyframe]? {
        switch property {
        case .origin, .position, .scale:
            return typedVectorKeyframes(
                fps: fps,
                lengthFrames: lengthFrames
            )
        case .rotationZ:
            return typedRotationKeyframes(
                fps: fps,
                lengthFrames: lengthFrames
            )
        case .opacity, .zOrder:
            return typedScalarKeyframes(
                fps: fps,
                lengthFrames: lengthFrames
            )
        case .visibility, .enabled:
            return typedBooleanKeyframes(
                fps: fps,
                lengthFrames: lengthFrames
            )
        }
    }

    private func typedScalarKeyframes(
        fps: Double,
        lengthFrames: Double
    ) -> [SceneTypedAnimationKeyframe]? {
        guard channels.count == 1, channels[0].name == "c0",
              let keyframes = normalizedKeyframes(
                  channels[0],
                  fps: fps,
                  lengthFrames: lengthFrames
              ) else {
            return nil
        }
        var result: [SceneTypedAnimationKeyframe] = []
        result.reserveCapacity(keyframes.count)
        for keyframe in keyframes {
            guard let value = keyframe.value.renderFiniteNumber else {
                return nil
            }
            result.append(SceneTypedAnimationKeyframe(
                timeSeconds: keyframe.timeSeconds,
                value: .scalar(value),
                interpolation: keyframe.interpolation
            ))
        }
        return result
    }

    private func typedBooleanKeyframes(
        fps: Double,
        lengthFrames: Double
    ) -> [SceneTypedAnimationKeyframe]? {
        guard channels.count == 1, channels[0].name == "c0",
              let keyframes = normalizedKeyframes(
                  channels[0],
                  fps: fps,
                  lengthFrames: lengthFrames
              ) else {
            return nil
        }
        var result: [SceneTypedAnimationKeyframe] = []
        result.reserveCapacity(keyframes.count)
        for keyframe in keyframes {
            guard case let .bool(value) = keyframe.value else {
                return nil
            }
            result.append(.init(
                timeSeconds: keyframe.timeSeconds,
                value: .boolean(value),
                interpolation: keyframe.interpolation
            ))
        }
        return result
    }

    private func typedVectorKeyframes(
        fps: Double,
        lengthFrames: Double
    ) -> [SceneTypedAnimationKeyframe]? {
        guard channels.map(\.name) == ["c0", "c1", "c2"] else {
            return nil
        }
        let normalized = channels.map {
            normalizedKeyframes($0, fps: fps, lengthFrames: lengthFrames)
        }
        guard normalized.allSatisfy({ $0 != nil }),
              let first = normalized[0],
              let second = normalized[1],
              let third = normalized[2],
              first.count == second.count,
              first.count == third.count else {
            return nil
        }

        var result: [SceneTypedAnimationKeyframe] = []
        result.reserveCapacity(first.count)
        for index in first.indices {
            let components = [first[index], second[index], third[index]]
            guard components.allSatisfy({ $0.timeSeconds == first[index].timeSeconds }),
                  components.allSatisfy({ $0.interpolation == first[index].interpolation }),
                  let x = components[0].value.renderFiniteNumber,
                  let y = components[1].value.renderFiniteNumber,
                  let z = components[2].value.renderFiniteNumber else {
                return nil
            }
            result.append(.init(
                timeSeconds: first[index].timeSeconds,
                value: .vector3(.init(x: x, y: y, z: z)),
                interpolation: first[index].interpolation
            ))
        }
        return result
    }

    private func typedRotationKeyframes(
        fps: Double,
        lengthFrames: Double
    ) -> [SceneTypedAnimationKeyframe]? {
        guard propertyPath == "angles" else {
            return typedScalarKeyframes(fps: fps, lengthFrames: lengthFrames)
        }
        guard channels.map(\.name) == ["c0", "c1", "c2"] else {
            return nil
        }
        let normalized = channels.map {
            normalizedKeyframes($0, fps: fps, lengthFrames: lengthFrames)
        }
        guard normalized.allSatisfy({ $0 != nil }),
              let xValues = normalized[0],
              let yValues = normalized[1],
              let zValues = normalized[2],
              xValues.count == yValues.count,
              xValues.count == zValues.count else {
            return nil
        }

        var result: [SceneTypedAnimationKeyframe] = []
        result.reserveCapacity(zValues.count)
        for index in zValues.indices {
            guard xValues[index].timeSeconds == zValues[index].timeSeconds,
                  yValues[index].timeSeconds == zValues[index].timeSeconds,
                  xValues[index].interpolation == zValues[index].interpolation,
                  yValues[index].interpolation == zValues[index].interpolation,
                  xValues[index].value.renderFiniteNumber == 0,
                  yValues[index].value.renderFiniteNumber == 0,
                  let z = zValues[index].value.renderFiniteNumber else {
                return nil
            }
            result.append(.init(
                timeSeconds: zValues[index].timeSeconds,
                value: .scalar(z),
                interpolation: zValues[index].interpolation
            ))
        }
        return result
    }

    private func normalizedKeyframes(
        _ channel: SceneAnimationChannel,
        fps: Double,
        lengthFrames: Double
    ) -> [NormalizedRenderKeyframe]? {
        var result: [NormalizedRenderKeyframe] = []
        result.reserveCapacity(channel.keyframes.count)
        for keyframe in channel.keyframes {
            guard keyframe.explicitTime == nil,
                  let frame = keyframe.frame,
                  frame.isFinite,
                  frame >= 0,
                  frame <= lengthFrames,
                  let value = keyframe.value,
                  let interpolation = keyframe.interpolation?.renderInterpolation else {
                return nil
            }
            let seconds = frame / fps
            guard seconds.isFinite else {
                return nil
            }
            result.append(.init(
                timeSeconds: seconds,
                value: value,
                interpolation: interpolation
            ))
        }
        result.sort { $0.timeSeconds < $1.timeSeconds }
        guard !result.isEmpty,
              zip(result, result.dropFirst()).allSatisfy({ pair in
                  pair.0.timeSeconds < pair.1.timeSeconds
              }) else {
            return nil
        }
        return result
    }
}

extension ScenePropertyOverride {
    public var typedOverride: SceneTypedPropertyOverride? {
        switch propertyPath {
        case "origin":
            return typedVectorOverride(.origin)
        case "position":
            return typedVectorOverride(.position)
        case "scale":
            return typedVectorOverride(.scale)
        case "angles.z":
            return typedScalarOverride(.rotationZ)
        case "angles":
            guard let vector = value.renderVector3,
                  vector.x == 0,
                  vector.y == 0 else {
                return nil
            }
            return .init(property: .rotationZ, value: .scalar(vector.z))
        case "alpha", "opacity":
            return typedScalarOverride(.opacity)
        case "visible":
            return typedBooleanOverride(.visibility)
        case "enabled":
            return typedBooleanOverride(.enabled)
        case "z", "zorder", "zindex":
            return typedScalarOverride(.zOrder)
        default:
            return nil
        }
    }

    private func typedVectorOverride(
        _ property: SceneRenderableProperty
    ) -> SceneTypedPropertyOverride? {
        guard let vector = value.renderVector3 else {
            return nil
        }
        return .init(property: property, value: .vector3(vector))
    }

    private func typedScalarOverride(
        _ property: SceneRenderableProperty
    ) -> SceneTypedPropertyOverride? {
        guard let number = value.renderFiniteNumber else {
            return nil
        }
        return .init(property: property, value: .scalar(number))
    }

    private func typedBooleanOverride(
        _ property: SceneRenderableProperty
    ) -> SceneTypedPropertyOverride? {
        guard case let .bool(boolean) = value else {
            return nil
        }
        return .init(property: property, value: .boolean(boolean))
    }
}

private struct NormalizedRenderKeyframe {
    let timeSeconds: Double
    let value: SceneJSONValue
    let interpolation: SceneTimelineInterpolation
}

private extension SceneRenderableProperty {
    init?(animationPath: String) {
        switch animationPath {
        case "origin": self = .origin
        case "position": self = .position
        case "scale": self = .scale
        case "angles", "angles.z": self = .rotationZ
        case "alpha", "opacity": self = .opacity
        case "visible": self = .visibility
        case "enabled": self = .enabled
        case "z", "zorder", "zindex": self = .zOrder
        default: return nil
        }
    }
}

private extension SceneJSONValue {
    var renderFiniteNumber: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .number(value) where value.isFinite:
            return value
        default:
            return nil
        }
    }

    var renderVector3: SceneGraphVector3? {
        let components: [Double]
        switch self {
        case let .string(value):
            let tokens = value.split {
                $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n"
            }
            guard tokens.count == 3 else {
                return nil
            }
            var parsed: [Double] = []
            parsed.reserveCapacity(3)
            for token in tokens {
                guard let component = Double(token), component.isFinite else {
                    return nil
                }
                parsed.append(component)
            }
            components = parsed
        case let .array(values):
            guard values.count == 3 else {
                return nil
            }
            var parsed: [Double] = []
            parsed.reserveCapacity(3)
            for value in values {
                guard let component = value.renderFiniteNumber else {
                    return nil
                }
                parsed.append(component)
            }
            components = parsed
        case let .object(values):
            guard let x = values["x"]?.renderFiniteNumber,
                  let y = values["y"]?.renderFiniteNumber,
                  let z = values["z"]?.renderFiniteNumber else {
                return nil
            }
            components = [x, y, z]
        default:
            return nil
        }
        guard components.count == 3,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return .init(x: components[0], y: components[1], z: components[2])
    }

    var renderInterpolation: SceneTimelineInterpolation? {
        switch self {
        case let .string(value):
            switch value {
            case "linear": return .linear
            case "step": return .step
            default: return nil
            }
        case let .object(values):
            guard let x1 = values["x1"]?.renderFiniteNumber,
                  let y1 = values["y1"]?.renderFiniteNumber,
                  let x2 = values["x2"]?.renderFiniteNumber,
                  let y2 = values["y2"]?.renderFiniteNumber,
                  (0...1).contains(x1),
                  (0...1).contains(x2) else {
                return nil
            }
            return .cubicBezier(.init(x1: x1, y1: y1, x2: x2, y2: y2))
        default:
            return nil
        }
    }
}
