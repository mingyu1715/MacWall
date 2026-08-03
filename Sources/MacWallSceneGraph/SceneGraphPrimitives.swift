import Foundation
import MacWallSceneAssets

public enum SceneGraphStatus: String, Codable, Equatable, Sendable {
    case exact
    case degraded
    case unsupported
    case invalid
}

public enum SceneGraphDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct SceneGraphDiagnostic: Equatable, Sendable {
    public let severity: SceneGraphDiagnosticSeverity
    public let code: String
    public let sourcePath: SceneVirtualPath?
    public let nodeID: SceneNodeID?
    public let jsonPath: String?
    public let dependencyPath: [SceneVirtualPath]
    public let arguments: [String]

    public init(
        severity: SceneGraphDiagnosticSeverity,
        code: String,
        sourcePath: SceneVirtualPath?,
        nodeID: SceneNodeID?,
        jsonPath: String?,
        dependencyPath: [SceneVirtualPath],
        arguments: [String]
    ) {
        self.severity = severity
        self.code = code
        self.sourcePath = sourcePath
        self.nodeID = nodeID
        self.jsonPath = jsonPath
        self.dependencyPath = dependencyPath
        self.arguments = arguments
    }
}

public struct SceneGraphCanvas: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct SceneGraphVector3: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SceneGraphSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct SceneGraphColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct SceneGraphLimits: Equatable, Sendable {
    public var maximumJSONEntryBytes: UInt64
    public var maximumCumulativeJSONBytes: UInt64
    public var maximumNodeCount: Int
    public var maximumDependencyEdgeCount: Int
    public var maximumAnimationKeyframeCount: Int
    public var maximumJSONDepth: Int
    public var maximumHierarchyDepth: Int

    public init(
        maximumJSONEntryBytes: UInt64 = 16 * 1_024 * 1_024,
        maximumCumulativeJSONBytes: UInt64 = 64 * 1_024 * 1_024,
        maximumNodeCount: Int = 100_000,
        maximumDependencyEdgeCount: Int = 500_000,
        maximumAnimationKeyframeCount: Int = 1_000_000,
        maximumJSONDepth: Int = 256,
        maximumHierarchyDepth: Int = 4_096
    ) {
        self.maximumJSONEntryBytes = maximumJSONEntryBytes
        self.maximumCumulativeJSONBytes = maximumCumulativeJSONBytes
        self.maximumNodeCount = maximumNodeCount
        self.maximumDependencyEdgeCount = maximumDependencyEdgeCount
        self.maximumAnimationKeyframeCount = maximumAnimationKeyframeCount
        self.maximumJSONDepth = maximumJSONDepth
        self.maximumHierarchyDepth = maximumHierarchyDepth
    }
}
