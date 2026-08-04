import Foundation

public struct SceneGraphCount: Codable, Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct SceneGraphSummary: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let packageVersion: String?
    public let nodeKinds: [SceneGraphCount]
    public let hierarchyEdgeCount: Int
    public let instanceEdgeCount: Int
    public let overrideCount: Int
    public let resourceKinds: [SceneGraphCount]
    public let dependencyResolutions: [SceneGraphCount]
    public let animationTrackCount: Int
    public let animationKeyframeCount: Int
    public let scriptCount: Int
    public let diagnosticCodes: [SceneGraphCount]
    public let status: SceneGraphStatus

    public init(
        schemaVersion: Int,
        packageVersion: String?,
        nodeKinds: [SceneGraphCount],
        hierarchyEdgeCount: Int,
        instanceEdgeCount: Int,
        overrideCount: Int,
        resourceKinds: [SceneGraphCount],
        dependencyResolutions: [SceneGraphCount],
        animationTrackCount: Int,
        animationKeyframeCount: Int,
        scriptCount: Int,
        diagnosticCodes: [SceneGraphCount],
        status: SceneGraphStatus
    ) {
        self.schemaVersion = schemaVersion
        self.packageVersion = packageVersion
        self.nodeKinds = nodeKinds
        self.hierarchyEdgeCount = hierarchyEdgeCount
        self.instanceEdgeCount = instanceEdgeCount
        self.overrideCount = overrideCount
        self.resourceKinds = resourceKinds
        self.dependencyResolutions = dependencyResolutions
        self.animationTrackCount = animationTrackCount
        self.animationKeyframeCount = animationKeyframeCount
        self.scriptCount = scriptCount
        self.diagnosticCodes = diagnosticCodes
        self.status = status
    }
}

public enum SceneGraphSummarizer {
    public static func summarize(
        _ result: SceneGraphBuildResult
    ) -> SceneGraphSummary {
        guard let document = result.document else {
            return SceneGraphSummary(
                schemaVersion: 1,
                packageVersion: nil,
                nodeKinds: [],
                hierarchyEdgeCount: 0,
                instanceEdgeCount: 0,
                overrideCount: 0,
                resourceKinds: [],
                dependencyResolutions: [],
                animationTrackCount: 0,
                animationKeyframeCount: 0,
                scriptCount: 0,
                diagnosticCodes: counts(result.diagnostics.map(\.code)),
                status: result.status
            )
        }

        return SceneGraphSummary(
            schemaVersion: 1,
            packageVersion: document.package.version,
            nodeKinds: counts(document.nodes.map { nodeKindName($0.payload.kind) }),
            hierarchyEdgeCount: document.hierarchyEdges.count,
            instanceEdgeCount: document.instanceEdges.count,
            overrideCount: overrideCount(document.instanceEdges),
            resourceKinds: counts(document.resources.map { $0.id.kind.rawValue }),
            dependencyResolutions: counts(
                document.dependencies.map { $0.resolution.kind.rawValue }
            ),
            animationTrackCount: document.animations.count,
            animationKeyframeCount: animationKeyframeCount(document.animations),
            scriptCount: document.scripts.count,
            diagnosticCodes: counts(result.diagnostics.map(\.code)),
            status: result.status
        )
    }

    private static func nodeKindName(_ kind: SceneNodeKind) -> String {
        switch kind {
        case .image:
            "image"
        case .text:
            "text"
        case .particle:
            "particle"
        case .sound:
            "sound"
        case .model:
            "model"
        case .composition:
            "composition"
        case .fullscreen:
            "fullscreen"
        case .unknown:
            "unknown"
        }
    }

    private static func counts(_ names: [String]) -> [SceneGraphCount] {
        var values: [String: Int] = [:]
        for name in names {
            let current = values[name, default: 0]
            let (next, overflow) = current.addingReportingOverflow(1)
            values[name] = overflow ? Int.max : next
        }
        return values.keys.sorted().map {
            SceneGraphCount(name: $0, count: values[$0] ?? 0)
        }
    }

    private static func overrideCount(_ edges: [SceneInstanceEdge]) -> Int {
        var total = 0
        for edge in edges {
            let (next, overflow) = total.addingReportingOverflow(edge.overrides.count)
            if overflow {
                return Int.max
            }
            total = next
        }
        return total
    }

    private static func animationKeyframeCount(
        _ tracks: [SceneAnimationTrack]
    ) -> Int {
        var total = 0
        for track in tracks {
            for channel in track.channels {
                let (next, overflow) = total.addingReportingOverflow(
                    channel.keyframes.count
                )
                if overflow {
                    return Int.max
                }
                total = next
            }
        }
        return total
    }
}

public enum SceneGraphSummaryEncoder {
    public static func encode(
        _ summary: SceneGraphSummary
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        let canonical = SceneGraphSummary(
            schemaVersion: summary.schemaVersion,
            packageVersion: summary.packageVersion,
            nodeKinds: summary.nodeKinds.sorted(by: countPrecedes),
            hierarchyEdgeCount: summary.hierarchyEdgeCount,
            instanceEdgeCount: summary.instanceEdgeCount,
            overrideCount: summary.overrideCount,
            resourceKinds: summary.resourceKinds.sorted(by: countPrecedes),
            dependencyResolutions: summary.dependencyResolutions.sorted(by: countPrecedes),
            animationTrackCount: summary.animationTrackCount,
            animationKeyframeCount: summary.animationKeyframeCount,
            scriptCount: summary.scriptCount,
            diagnosticCodes: summary.diagnosticCodes.sorted(by: countPrecedes),
            status: summary.status
        )
        var data = try encoder.encode(canonical)
        while data.last == 0x0A || data.last == 0x0D {
            data.removeLast()
        }
        data.append(0x0A)
        return data
    }

    private static func countPrecedes(
        _ first: SceneGraphCount,
        _ second: SceneGraphCount
    ) -> Bool {
        if first.name != second.name {
            return first.name < second.name
        }
        return first.count < second.count
    }
}
