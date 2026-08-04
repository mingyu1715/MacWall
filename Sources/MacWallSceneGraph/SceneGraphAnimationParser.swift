import Foundation
import MacWallSceneAssets

struct SceneGraphAnimationParseResult: Sendable {
    let animations: [SceneAnimationTrack]
    let diagnostics: [SceneGraphParserDiagnostic]
}

struct SceneGraphAnimationParser: Sendable {
    let limits: SceneGraphLimits
    let sourcePath: SceneVirtualPath

    func parse(
        nodes: [SceneGraphNode],
        rawObjects: [SceneJSONValue]
    ) -> SceneGraphAnimationParseResult {
        var state = SceneGraphAnimationParseState(
            limits: limits,
            sourcePath: sourcePath
        )

        for (node, rawObject) in zip(nodes, rawObjects) {
            guard !state.stopped,
                  case let .object(properties) = rawObject else {
                continue
            }
            for propertyPath in properties.keys.sorted() {
                guard !state.stopped,
                      case let .object(wrapper)? = properties[propertyPath],
                      case let .object(animation)? = wrapper["animation"] else {
                    continue
                }
                state.appendTrack(
                    node: node,
                    propertyPath: propertyPath,
                    animation: animation
                )
            }
        }

        return SceneGraphAnimationParseResult(
            animations: state.animations.sorted(by: Self.trackPrecedes),
            diagnostics: state.diagnostics
        )
    }

    private static func trackPrecedes(
        _ first: SceneAnimationTrack,
        _ second: SceneAnimationTrack
    ) -> Bool {
        if first.nodeID != second.nodeID {
            return first.nodeID < second.nodeID
        }
        return first.propertyPath < second.propertyPath
    }
}

private struct SceneGraphAnimationParseState {
    let limits: SceneGraphLimits
    let sourcePath: SceneVirtualPath
    var animations: [SceneAnimationTrack] = []
    var diagnostics: [SceneGraphParserDiagnostic] = []
    var keyframeCount = 0
    var stopped = false

    mutating func appendTrack(
        node: SceneGraphNode,
        propertyPath: String,
        animation: [String: SceneJSONValue]
    ) {
        let basePath = "objects[\(node.sourceOrder)].\(propertyPath).animation"
        let options = parsedOptions(
            animation["options"],
            node: node,
            basePath: basePath
        )
        var status: SceneAnimationTrackStatus = options.isValid ? .exact : .degraded
        var channels: [SceneAnimationChannel] = []
        let names = animation.keys.filter { $0 != "options" }.sorted(
            by: channelPrecedes
        )
        channels.reserveCapacity(names.count)

        for name in names {
            guard let rawChannel = animation[name] else {
                continue
            }
            let parsed = parsedChannel(
                rawChannel,
                name: name,
                node: node,
                basePath: basePath,
                fps: options.fps
            )
            channels.append(parsed.channel)
            if !parsed.isValid {
                status = .degraded
            }
        }

        if stopped {
            status = .degraded
        }
        animations.append(
            SceneAnimationTrack(
                nodeID: node.id,
                propertyPath: propertyPath,
                valueKind: valueKind(channels: channels),
                fps: options.fps,
                duration: options.duration,
                isRelative: options.isRelative,
                channels: channels,
                status: status,
                rawValue: .object(animation)
            )
        )
    }

    private mutating func parsedOptions(
        _ rawValue: SceneJSONValue?,
        node: SceneGraphNode,
        basePath: String
    ) -> SceneGraphAnimationOptions {
        guard let rawValue else {
            return .init(fps: nil, duration: nil, isRelative: nil, isValid: true)
        }
        guard case let .object(values) = rawValue else {
            appendInvalidProperty(node: node, jsonPath: "\(basePath).options")
            return .init(fps: nil, duration: nil, isRelative: nil, isValid: false)
        }

        var isValid = true
        let fps: Double?
        if let value = values["fps"] {
            fps = value.finiteNumber
            if fps == nil || fps! <= 0 {
                isValid = false
                appendInvalidProperty(node: node, jsonPath: "\(basePath).options.fps")
            }
        } else {
            fps = nil
        }
        let duration: Double?
        if let value = values["length"] {
            duration = value.finiteNumber
            if duration == nil {
                isValid = false
                appendInvalidProperty(node: node, jsonPath: "\(basePath).options.length")
            }
        } else {
            duration = nil
        }
        let isRelative: Bool?
        if let value = values["relative"] {
            if case let .bool(parsed) = value {
                isRelative = parsed
            } else {
                isRelative = nil
                isValid = false
                appendInvalidProperty(
                    node: node,
                    jsonPath: "\(basePath).options.relative"
                )
            }
        } else {
            isRelative = nil
        }
        return .init(
            fps: fps,
            duration: duration,
            isRelative: isRelative,
            isValid: isValid
        )
    }

    private mutating func parsedChannel(
        _ rawValue: SceneJSONValue,
        name: String,
        node: SceneGraphNode,
        basePath: String,
        fps: Double?
    ) -> SceneGraphParsedAnimationChannel {
        guard case let .array(rawKeyframes) = rawValue else {
            appendInvalidProperty(node: node, jsonPath: "\(basePath).\(name)")
            return .init(
                channel: SceneAnimationChannel(
                    name: name,
                    keyframes: [],
                    rawValue: rawValue
                ),
                isValid: false
            )
        }

        var keyframes: [SceneAnimationKeyframe] = []
        let remainingKeyframes = remainingKeyframeCapacity
        keyframes.reserveCapacity(min(rawKeyframes.count, remainingKeyframes))
        var isValid = true
        for (index, rawKeyframe) in rawKeyframes.enumerated() {
            guard canAppendKeyframe(
                node: node,
                jsonPath: "\(basePath).\(name)[\(index)]"
            ) else {
                isValid = false
                break
            }
            let parsed = parsedKeyframe(
                rawKeyframe,
                node: node,
                jsonPath: "\(basePath).\(name)[\(index)]",
                fps: fps
            )
            keyframes.append(parsed.keyframe)
            if !parsed.isValid {
                isValid = false
            }
        }

        return .init(
            channel: SceneAnimationChannel(
                name: name,
                keyframes: keyframes,
                rawValue: rawValue
            ),
            isValid: isValid
        )
    }

    private mutating func parsedKeyframe(
        _ rawValue: SceneJSONValue,
        node: SceneGraphNode,
        jsonPath: String,
        fps: Double?
    ) -> SceneGraphParsedAnimationKeyframe {
        guard case let .object(rawFields) = rawValue else {
            appendInvalidProperty(node: node, jsonPath: jsonPath)
            return .init(
                keyframe: SceneAnimationKeyframe(
                    frame: nil,
                    time: nil,
                    value: nil,
                    interpolation: nil,
                    unknownFields: [:]
                ),
                isValid: false
            )
        }

        var fields = rawFields
        let frame = parsedNumber(
            key: "frame",
            fields: &fields,
            node: node,
            jsonPath: jsonPath
        )
        let explicitTimePresent = fields["time"] != nil
        let time = parsedNumber(
            key: "time",
            fields: &fields,
            node: node,
            jsonPath: jsonPath
        )
        let value = fields.removeValue(forKey: "value")
        var isValid = frame.isValid && time.isValid
        if value == nil {
            isValid = false
            appendInvalidProperty(node: node, jsonPath: "\(jsonPath).value")
        }

        let interpolation: SceneJSONValue?
        if let value = fields.removeValue(forKey: "interpolation") {
            interpolation = value
        } else {
            interpolation = fields.removeValue(forKey: "easing")
        }

        let resolvedTime: Double?
        if explicitTimePresent {
            resolvedTime = time.value
        } else if let frame = frame.value,
                  let fps,
                  fps.isFinite,
                  fps > 0 {
            let derived = frame / fps
            resolvedTime = derived.isFinite ? derived : nil
        } else {
            resolvedTime = nil
        }

        return .init(
            keyframe: SceneAnimationKeyframe(
                frame: frame.value,
                time: resolvedTime,
                value: value,
                interpolation: interpolation,
                unknownFields: fields
            ),
            isValid: isValid
        )
    }

    private mutating func parsedNumber(
        key: String,
        fields: inout [String: SceneJSONValue],
        node: SceneGraphNode,
        jsonPath: String
    ) -> SceneGraphParsedAnimationNumber {
        guard let rawValue = fields[key] else {
            return .init(value: nil, isValid: true)
        }
        guard let value = rawValue.finiteNumber else {
            appendInvalidProperty(node: node, jsonPath: "\(jsonPath).\(key)")
            return .init(value: nil, isValid: false)
        }
        fields.removeValue(forKey: key)
        return .init(value: value, isValid: true)
    }

    private mutating func canAppendKeyframe(
        node: SceneGraphNode,
        jsonPath: String
    ) -> Bool {
        let (nextCount, overflow) = keyframeCount.addingReportingOverflow(1)
        guard !overflow, nextCount <= limits.maximumAnimationKeyframeCount else {
            appendResourceLimit(node: node, jsonPath: jsonPath)
            return false
        }
        keyframeCount = nextCount
        return true
    }

    private var remainingKeyframeCapacity: Int {
        guard limits.maximumAnimationKeyframeCount > keyframeCount else {
            return 0
        }
        return limits.maximumAnimationKeyframeCount - keyframeCount
    }

    private func valueKind(
        channels: [SceneAnimationChannel]
    ) -> SceneAnimationValueKind {
        guard (1...3).contains(channels.count),
              channels.enumerated().allSatisfy({
                  $0.element.name == "c\($0.offset)"
                      && !$0.element.keyframes.isEmpty
                      && $0.element.keyframes.allSatisfy {
                          $0.value?.finiteNumber != nil
                      }
              }) else {
            return .raw
        }
        switch channels.count {
        case 1:
            return .scalar
        case 2:
            return .vector2
        case 3:
            return .vector3
        default:
            return .raw
        }
    }

    private func channelPrecedes(_ first: String, _ second: String) -> Bool {
        switch (numericChannelSuffix(first), numericChannelSuffix(second)) {
        case let (.some(firstSuffix), .some(secondSuffix)):
            if firstSuffix.count != secondSuffix.count {
                return firstSuffix.count < secondSuffix.count
            }
            if firstSuffix != secondSuffix {
                return firstSuffix < secondSuffix
            }
            return first < second
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return first < second
        }
    }

    private func numericChannelSuffix(_ name: String) -> String? {
        guard name.first == "c" else {
            return nil
        }
        let suffix = name.dropFirst()
        guard !suffix.isEmpty,
              suffix.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        let normalized = suffix.drop { $0 == "0" }
        return normalized.isEmpty ? "0" : String(normalized)
    }

    private mutating func appendInvalidProperty(
        node: SceneGraphNode,
        jsonPath: String
    ) {
        diagnostics.append(
            SceneGraphParserDiagnostic(
                severity: .warning,
                code: "graph.invalid-property",
                sourcePath: sourcePath,
                nodeID: node.id,
                jsonPath: jsonPath,
                arguments: [],
                evidence: .degraded
            )
        )
    }

    private mutating func appendResourceLimit(
        node: SceneGraphNode,
        jsonPath: String
    ) {
        guard !stopped else {
            return
        }
        stopped = true
        diagnostics.append(
            SceneGraphParserDiagnostic(
                severity: .error,
                code: "graph.resource-limit",
                sourcePath: sourcePath,
                nodeID: node.id,
                jsonPath: jsonPath,
                arguments: ["maximumAnimationKeyframeCount"],
                evidence: .invalid
            )
        )
    }
}

private struct SceneGraphAnimationOptions {
    let fps: Double?
    let duration: Double?
    let isRelative: Bool?
    let isValid: Bool
}

private struct SceneGraphParsedAnimationChannel {
    let channel: SceneAnimationChannel
    let isValid: Bool
}

private struct SceneGraphParsedAnimationKeyframe {
    let keyframe: SceneAnimationKeyframe
    let isValid: Bool
}

private struct SceneGraphParsedAnimationNumber {
    let value: Double?
    let isValid: Bool
}

private extension SceneJSONValue {
    var finiteNumber: Double? {
        switch self {
        case let .integer(value):
            Double(value)
        case let .number(value) where value.isFinite:
            value
        default:
            nil
        }
    }
}
