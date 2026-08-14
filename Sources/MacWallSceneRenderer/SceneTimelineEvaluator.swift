import Foundation
import MacWallSceneGraph

struct SceneTimelineEvaluator: Sendable {
    func evaluate(
        program: SceneRenderProgram,
        mediaTimeSeconds: Double,
        into scratch: inout SceneEvaluationScratch
    ) throws {
        guard mediaTimeSeconds.isFinite, mediaTimeSeconds >= 0 else {
            throw SceneRenderError.invalidProgram
        }

        scratch.nodes.removeAll(keepingCapacity: true)
        scratch.nodes.reserveCapacity(program.nodeTemplates.count)
        for template in program.nodeTemplates {
            var properties = SceneEvaluatedNodeProperties(
                base: template.baseProperties
            )
            for (index, track) in template.animationBindings.enumerated() {
                guard !template.animationBindings[..<index].contains(where: {
                    $0.property == track.property
                }) else {
                    throw SceneRenderError.invalidProgram
                }
                let value = try evaluatedValue(
                    track,
                    mediaTimeSeconds: mediaTimeSeconds
                )
                try apply(value, property: track.property, to: &properties)
            }
            scratch.nodes.append(properties)
        }
    }

    private func evaluatedValue(
        _ track: SceneTypedAnimationTrack,
        mediaTimeSeconds: Double
    ) throws -> SceneTypedPropertyValue {
        guard !track.isRelative, !track.startsPaused else {
            throw SceneRenderError.unsupported
        }
        guard track.durationSeconds.isFinite,
              track.durationSeconds > 0,
              !track.keyframes.isEmpty else {
            throw SceneRenderError.invalidProgram
        }
        for (index, keyframe) in track.keyframes.enumerated() {
            guard keyframe.timeSeconds.isFinite,
                  keyframe.timeSeconds >= 0,
                  keyframe.timeSeconds <= track.durationSeconds,
                  value(keyframe.value, matches: track.property),
                  interpolationIsValid(keyframe.interpolation),
                  index == 0
                    || track.keyframes[index - 1].timeSeconds < keyframe.timeSeconds else {
                throw SceneRenderError.invalidProgram
            }
        }

        let timelineTime = try normalizedTime(
            mediaTimeSeconds,
            duration: track.durationSeconds,
            mode: track.playbackMode
        )
        guard let first = track.keyframes.first,
              let last = track.keyframes.last else {
            throw SceneRenderError.invalidProgram
        }
        if timelineTime <= first.timeSeconds {
            return first.value
        }
        if timelineTime >= last.timeSeconds {
            return last.value
        }

        let upperIndex = firstKeyframeIndex(
            after: timelineTime,
            keyframes: track.keyframes
        )
        let lower = track.keyframes[upperIndex - 1]
        let upper = track.keyframes[upperIndex]
        let duration = upper.timeSeconds - lower.timeSeconds
        guard duration.isFinite, duration > 0 else {
            throw SceneRenderError.invalidProgram
        }
        let progress = (timelineTime - lower.timeSeconds) / duration
        return try interpolate(
            from: lower.value,
            to: upper.value,
            progress: progress,
            interpolation: lower.interpolation
        )
    }

    private func normalizedTime(
        _ mediaTime: Double,
        duration: Double,
        mode: SceneTimelinePlaybackMode
    ) throws -> Double {
        let normalized: Double
        switch mode {
        case .loop:
            normalized = mediaTime.truncatingRemainder(dividingBy: duration)
        case .mirror:
            let period = duration * 2
            guard period.isFinite else {
                throw SceneRenderError.invalidProgram
            }
            let phase = mediaTime.truncatingRemainder(dividingBy: period)
            normalized = phase <= duration ? phase : period - phase
        case .single:
            normalized = min(mediaTime, duration)
        }
        guard normalized.isFinite else {
            throw SceneRenderError.invalidProgram
        }
        return normalized
    }

    private func firstKeyframeIndex(
        after time: Double,
        keyframes: [SceneTypedAnimationKeyframe]
    ) -> Int {
        var lower = 0
        var upper = keyframes.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if keyframes[middle].timeSeconds <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func interpolate(
        from first: SceneTypedPropertyValue,
        to second: SceneTypedPropertyValue,
        progress: Double,
        interpolation: SceneTimelineInterpolation
    ) throws -> SceneTypedPropertyValue {
        let adjustedProgress: Double
        switch interpolation {
        case .step:
            return first
        case .linear:
            adjustedProgress = progress
        case let .cubicBezier(points):
            adjustedProgress = cubicBezierProgress(progress, points: points)
        }

        switch (first, second) {
        case let (.scalar(start), .scalar(end)):
            let value = linear(start, end, adjustedProgress)
            guard value.isFinite else {
                throw SceneRenderError.invalidProgram
            }
            return .scalar(value)
        case let (.vector3(start), .vector3(end)):
            let value = SceneGraphVector3(
                x: linear(start.x, end.x, adjustedProgress),
                y: linear(start.y, end.y, adjustedProgress),
                z: linear(start.z, end.z, adjustedProgress)
            )
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                throw SceneRenderError.invalidProgram
            }
            return .vector3(value)
        case (.boolean, .boolean):
            throw SceneRenderError.invalidProgram
        default:
            throw SceneRenderError.invalidProgram
        }
    }

    private func cubicBezierProgress(
        _ progress: Double,
        points: SceneCubicBezierControlPoints
    ) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }

        var lower = 0.0
        var upper = 1.0
        for _ in 0..<32 {
            let parameter = (lower + upper) * 0.5
            let x = cubicBezierCoordinate(
                parameter,
                firstControl: points.x1,
                secondControl: points.x2
            )
            if abs(x - progress) <= 1e-12 {
                return cubicBezierCoordinate(
                    parameter,
                    firstControl: points.y1,
                    secondControl: points.y2
                )
            }
            if x < progress {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return cubicBezierCoordinate(
            (lower + upper) * 0.5,
            firstControl: points.y1,
            secondControl: points.y2
        )
    }

    private func cubicBezierCoordinate(
        _ parameter: Double,
        firstControl: Double,
        secondControl: Double
    ) -> Double {
        let inverse = 1 - parameter
        return 3 * inverse * inverse * parameter * firstControl
            + 3 * inverse * parameter * parameter * secondControl
            + parameter * parameter * parameter
    }

    private func linear(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }

    private func value(
        _ value: SceneTypedPropertyValue,
        matches property: SceneRenderableProperty
    ) -> Bool {
        switch (property, value) {
        case let (.origin, .vector3(value)),
             let (.position, .vector3(value)),
             let (.scale, .vector3(value)):
            value.x.isFinite && value.y.isFinite && value.z.isFinite
        case let (.rotationZ, .scalar(value)),
             let (.opacity, .scalar(value)),
             let (.zOrder, .scalar(value)):
            value.isFinite
        case (.visibility, .boolean), (.enabled, .boolean):
            true
        default:
            false
        }
    }

    private func interpolationIsValid(
        _ interpolation: SceneTimelineInterpolation
    ) -> Bool {
        switch interpolation {
        case .linear, .step:
            true
        case let .cubicBezier(points):
            points.x1.isFinite && points.y1.isFinite
                && points.x2.isFinite && points.y2.isFinite
                && (0...1).contains(points.x1)
                && (0...1).contains(points.x2)
        }
    }

    private func apply(
        _ value: SceneTypedPropertyValue,
        property: SceneRenderableProperty,
        to properties: inout SceneEvaluatedNodeProperties
    ) throws {
        switch (property, value) {
        case let (.origin, .vector3(value)):
            properties.origin = value
        case let (.position, .vector3(value)):
            properties.position = value
        case let (.scale, .vector3(value)):
            properties.scale = .init(x: value.x, y: value.y, z: 1)
        case let (.rotationZ, .scalar(value)):
            properties.rotationZ = value
        case let (.opacity, .scalar(value)):
            properties.opacity = value
        case let (.visibility, .boolean(value)):
            properties.visible = value
        case let (.enabled, .boolean(value)):
            properties.enabled = value
        case let (.zOrder, .scalar(value)):
            properties.zOrder = value
        default:
            throw SceneRenderError.invalidProgram
        }
    }
}

struct SceneEvaluationScratch: Sendable {
    var nodes: [SceneEvaluatedNodeProperties]

    init(nodes: [SceneEvaluatedNodeProperties] = []) {
        self.nodes = nodes
    }
}

struct SceneEvaluatedNodeProperties: Equatable, Sendable {
    var origin: SceneGraphVector3
    var position: SceneGraphVector3
    var scale: SceneGraphVector3
    var rotationZ: Double
    var opacity: Double
    var visible: Bool
    var enabled: Bool
    var color: SceneGraphColor
    var zOrder: Double

    init(base: SceneRenderBaseProperties) {
        origin = base.origin
        position = base.position
        scale = base.scale
        rotationZ = base.rotationZ
        opacity = base.opacity
        visible = base.visible
        enabled = base.enabled
        color = base.color
        zOrder = base.zOrder
    }
}
