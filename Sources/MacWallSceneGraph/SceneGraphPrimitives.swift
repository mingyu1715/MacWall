import Foundation

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
