import Foundation
import MacWallSceneAssets

struct SceneGraphHierarchyResolver: Sendable {
    let limits: SceneGraphLimits

    func resolve(
        nodes: [SceneGraphNode],
        rawObjects: [SceneJSONValue],
        sourcePath: SceneVirtualPath
    ) -> SceneGraphResolvedHierarchy {
        var diagnostics: [SceneGraphParserDiagnostic] = []
        let sourceIDs = sourceIdentifierMultimap(nodes: nodes)
        diagnostics.append(contentsOf: duplicateDiagnostics(
            sourceIDs: sourceIDs,
            sourcePath: sourcePath
        ))

        var hierarchyEdges: [SceneHierarchyEdge] = []
        var instanceEdges: [SceneInstanceEdge] = []
        hierarchyEdges.reserveCapacity(nodes.count)
        instanceEdges.reserveCapacity(nodes.count)

        for (node, rawObject) in zip(nodes, rawObjects) {
            guard case let .object(fields) = rawObject else {
                continue
            }
            let overrideResult = fields["instanceoverride"].map {
                overrides(from: $0, node: node, sourcePath: sourcePath)
            }
            if let rawParent = fields["parent"] {
                if let parent = SceneSourceIdentifier(scalar: rawParent) {
                    let resolution = resolve(parent, in: sourceIDs)
                    hierarchyEdges.append(SceneHierarchyEdge(
                        childID: node.id,
                        requestedParent: parent,
                        resolution: resolution
                    ))
                    if let diagnostic = referenceDiagnostic(
                        resolution: resolution,
                        node: node,
                        sourcePath: sourcePath,
                        jsonPath: "objects[\(node.sourceOrder)].parent",
                        missingCode: "graph.missing-parent",
                        ambiguousCode: "graph.ambiguous-parent"
                    ) {
                        diagnostics.append(diagnostic)
                    }
                } else {
                    diagnostics.append(invalidProperty(
                        node: node,
                        sourcePath: sourcePath,
                        jsonPath: "objects[\(node.sourceOrder)].parent"
                    ))
                }
            }

            if let rawInstance = fields["instance"] {
                if let source = SceneSourceIdentifier(scalar: rawInstance) {
                    let resolution = resolve(source, in: sourceIDs)
                    instanceEdges.append(SceneInstanceEdge(
                        instanceID: node.id,
                        requestedSource: source,
                        resolution: resolution,
                        overrides: overrideResult?.overrides ?? []
                    ))
                    if let overrideResult {
                        diagnostics.append(contentsOf: overrideResult.diagnostics)
                    }
                    if let diagnostic = referenceDiagnostic(
                        resolution: resolution,
                        node: node,
                        sourcePath: sourcePath,
                        jsonPath: "objects[\(node.sourceOrder)].instance",
                        missingCode: "graph.missing-instance",
                        ambiguousCode: "graph.ambiguous-instance"
                    ) {
                        diagnostics.append(diagnostic)
                    }
                } else {
                    diagnostics.append(invalidProperty(
                        node: node,
                        sourcePath: sourcePath,
                        jsonPath: "objects[\(node.sourceOrder)].instance"
                    ))
                    appendUnrepresentedOverrideDiagnostics(
                        overrideResult,
                        node: node,
                        sourcePath: sourcePath,
                        to: &diagnostics
                    )
                }
            } else {
                appendUnrepresentedOverrideDiagnostics(
                    overrideResult,
                    node: node,
                    sourcePath: sourcePath,
                    to: &diagnostics
                )
            }
        }

        diagnostics.append(contentsOf: validate(
            nodes: nodes,
            adjacency: resolvedParentAdjacency(hierarchyEdges),
            sourcePath: sourcePath,
            edgeKind: .parent
        ))
        diagnostics.append(contentsOf: validate(
            nodes: nodes,
            adjacency: resolvedInstanceAdjacency(instanceEdges),
            sourcePath: sourcePath,
            edgeKind: .instance
        ))

        return SceneGraphResolvedHierarchy(
            hierarchyEdges: hierarchyEdges,
            instanceEdges: instanceEdges,
            diagnostics: diagnostics
        )
    }

    private func sourceIdentifierMultimap(
        nodes: [SceneGraphNode]
    ) -> [SceneSourceIdentifier: [SceneNodeID]] {
        var result: [SceneSourceIdentifier: [SceneNodeID]] = [:]
        for node in nodes {
            guard let identifier = node.sourceIdentifier else {
                continue
            }
            result[identifier, default: []].append(node.id)
        }
        return result
    }

    private func duplicateDiagnostics(
        sourceIDs: [SceneSourceIdentifier: [SceneNodeID]],
        sourcePath: SceneVirtualPath
    ) -> [SceneGraphParserDiagnostic] {
        sourceIDs.values.compactMap { candidates in
            guard candidates.count > 1 else {
                return nil
            }
            return .init(
                severity: .warning,
                code: "graph.duplicate-source-id",
                sourcePath: sourcePath,
                nodeID: nil,
                jsonPath: nil,
                arguments: candidates.sorted().map(\.rawValue),
                status: .degraded
            )
        }
    }

    private func resolve(
        _ identifier: SceneSourceIdentifier,
        in sourceIDs: [SceneSourceIdentifier: [SceneNodeID]]
    ) -> SceneNodeReferenceResolution {
        guard let candidates = sourceIDs[identifier] else {
            return .missing
        }
        if candidates.count == 1, let candidate = candidates.first {
            return .resolved(candidate)
        }
        return .ambiguous(candidates.sorted())
    }

    private func referenceDiagnostic(
        resolution: SceneNodeReferenceResolution,
        node: SceneGraphNode,
        sourcePath: SceneVirtualPath,
        jsonPath: String,
        missingCode: String,
        ambiguousCode: String
    ) -> SceneGraphParserDiagnostic? {
        switch resolution {
        case .resolved:
            nil
        case .missing:
            .init(
                severity: .warning,
                code: missingCode,
                sourcePath: sourcePath,
                nodeID: node.id,
                jsonPath: jsonPath,
                arguments: [],
                status: .unsupported
            )
        case let .ambiguous(candidates):
            .init(
                severity: .warning,
                code: ambiguousCode,
                sourcePath: sourcePath,
                nodeID: node.id,
                jsonPath: jsonPath,
                arguments: candidates.sorted().map(\.rawValue),
                status: .unsupported
            )
        }
    }

    private func overrides(
        from rawValue: SceneJSONValue,
        node: SceneGraphNode,
        sourcePath: SceneVirtualPath
    ) -> SceneGraphOverrideParseResult {
        let parsed = SceneGraphInstanceOverrideParser.parse(rawValue)
        let diagnostics: [SceneGraphParserDiagnostic]
        if parsed.hasInvalidShape {
            diagnostics = [invalidProperty(
                node: node,
                sourcePath: sourcePath,
                jsonPath: "objects[\(node.sourceOrder)].instanceoverride"
            )]
        } else {
            diagnostics = parsed.invalidRecordIndices.map { index in
                invalidProperty(
                    node: node,
                    sourcePath: sourcePath,
                    jsonPath: "objects[\(node.sourceOrder)].instanceoverride[\(index)]"
                )
            }
        }
        return .init(
            overrides: parsed.overrides,
            diagnostics: diagnostics,
            isComplete: parsed.isComplete
        )
    }

    private func appendUnrepresentedOverrideDiagnostics(
        _ overrideResult: SceneGraphOverrideParseResult?,
        node: SceneGraphNode,
        sourcePath: SceneVirtualPath,
        to diagnostics: inout [SceneGraphParserDiagnostic]
    ) {
        guard let overrideResult else {
            return
        }
        if overrideResult.isComplete {
            diagnostics.append(invalidProperty(
                node: node,
                sourcePath: sourcePath,
                jsonPath: "objects[\(node.sourceOrder)].instanceoverride"
            ))
        } else {
            diagnostics.append(contentsOf: overrideResult.diagnostics)
        }
    }

    private func resolvedParentAdjacency(
        _ edges: [SceneHierarchyEdge]
    ) -> [SceneNodeID: SceneNodeID] {
        var adjacency: [SceneNodeID: SceneNodeID] = [:]
        for edge in edges {
            guard case let .resolved(parent) = edge.resolution else {
                continue
            }
            adjacency[edge.childID] = parent
        }
        return adjacency
    }

    private func resolvedInstanceAdjacency(
        _ edges: [SceneInstanceEdge]
    ) -> [SceneNodeID: SceneNodeID] {
        var adjacency: [SceneNodeID: SceneNodeID] = [:]
        for edge in edges {
            guard case let .resolved(source) = edge.resolution else {
                continue
            }
            adjacency[edge.instanceID] = source
        }
        return adjacency
    }

    private func validate(
        nodes: [SceneGraphNode],
        adjacency: [SceneNodeID: SceneNodeID],
        sourcePath: SceneVirtualPath,
        edgeKind: SceneGraphHierarchyEdgeKind
    ) -> [SceneGraphParserDiagnostic] {
        var colors: [SceneNodeID: SceneGraphTraversalColor] = [:]
        var depths: [SceneNodeID: Int] = [:]
        var diagnostics: [SceneGraphParserDiagnostic] = []
        var reportedDepthLimit = false

        for node in nodes where colors[node.id] == nil {
            var stack: [SceneGraphTraversalFrame] = [.visit(node.id, depth: 1)]
            while let frame = stack.popLast() {
                switch frame {
                case let .visit(current, depth):
                    if colors[current] != nil {
                        continue
                    }
                    colors[current] = .gray
                    guard let next = adjacency[current] else {
                        colors[current] = .black
                        depths[current] = 1
                        continue
                    }
                    switch colors[next] {
                    case .gray:
                        let cycle = cyclePath(from: stack, endingAt: current, target: next)
                        diagnostics.append(cycleDiagnostic(
                            cycle: cycle,
                            sourcePath: sourcePath,
                            edgeKind: edgeKind
                        ))
                        colors[current] = .black
                        depths[current] = 1
                    case .black:
                        let depth = (depths[next] ?? 0) + 1
                        if depth > limits.maximumHierarchyDepth,
                           !reportedDepthLimit {
                            diagnostics.append(depthDiagnostic(
                                nodeID: current,
                                sourcePath: sourcePath,
                                edgeKind: edgeKind
                            ))
                            reportedDepthLimit = true
                        }
                        colors[current] = .black
                        depths[current] = depth
                    case nil:
                        if depth >= limits.maximumHierarchyDepth {
                            if !reportedDepthLimit {
                                diagnostics.append(depthDiagnostic(
                                    nodeID: current,
                                    sourcePath: sourcePath,
                                    edgeKind: edgeKind
                                ))
                                reportedDepthLimit = true
                            }
                            colors[current] = .black
                            depths[current] = limits.maximumHierarchyDepth + 1
                        } else {
                            stack.append(.finish(current, next: next))
                            stack.append(.visit(next, depth: depth + 1))
                        }
                    }
                case let .finish(current, next):
                    let depth = (depths[next] ?? 0) + 1
                    if depth > limits.maximumHierarchyDepth,
                       !reportedDepthLimit {
                        diagnostics.append(depthDiagnostic(
                            nodeID: current,
                            sourcePath: sourcePath,
                            edgeKind: edgeKind
                        ))
                        reportedDepthLimit = true
                    }
                    colors[current] = .black
                    depths[current] = depth
                }
            }
        }
        return diagnostics
    }

    private func cyclePath(
        from stack: [SceneGraphTraversalFrame],
        endingAt current: SceneNodeID,
        target: SceneNodeID
    ) -> [SceneNodeID] {
        let path = stack.compactMap(\.node) + [current]
        guard let start = path.firstIndex(of: target) else {
            return [current]
        }
        return canonicalCycle(Array(path[start...]))
    }

    private func canonicalCycle(_ cycle: [SceneNodeID]) -> [SceneNodeID] {
        guard !cycle.isEmpty else {
            return cycle
        }
        let forward = rotateCycleToSmallestNodeID(cycle)
        let reversed = rotateCycleToSmallestNodeID(Array(cycle.reversed()))
        return reversed.lexicographicallyPrecedes(forward) ? reversed : forward
    }

    private func rotateCycleToSmallestNodeID(
        _ cycle: [SceneNodeID]
    ) -> [SceneNodeID] {
        guard let smallest = cycle.indices.min(by: { cycle[$0] < cycle[$1] }) else {
            return cycle
        }
        return Array(cycle[smallest...]) + Array(cycle[..<smallest])
    }

    private func cycleDiagnostic(
        cycle: [SceneNodeID],
        sourcePath: SceneVirtualPath,
        edgeKind: SceneGraphHierarchyEdgeKind
    ) -> SceneGraphParserDiagnostic {
        .init(
            severity: .error,
            code: edgeKind.cycleCode,
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: nil,
            arguments: cycle.map(\.rawValue),
            status: .invalid
        )
    }

    private func depthDiagnostic(
        nodeID: SceneNodeID,
        sourcePath: SceneVirtualPath,
        edgeKind: SceneGraphHierarchyEdgeKind
    ) -> SceneGraphParserDiagnostic {
        .init(
            severity: .error,
            code: "graph.resource-limit",
            sourcePath: sourcePath,
            nodeID: nodeID,
            jsonPath: "objects[\(nodeID.objectIndex)].\(edgeKind.key)",
            arguments: [],
            status: .invalid
        )
    }

    private func invalidProperty(
        node: SceneGraphNode,
        sourcePath: SceneVirtualPath,
        jsonPath: String
    ) -> SceneGraphParserDiagnostic {
        .init(
            severity: .warning,
            code: "graph.invalid-property",
            sourcePath: sourcePath,
            nodeID: node.id,
            jsonPath: jsonPath,
            arguments: [],
            status: .degraded
        )
    }
}

struct SceneGraphResolvedHierarchy: Sendable {
    let hierarchyEdges: [SceneHierarchyEdge]
    let instanceEdges: [SceneInstanceEdge]
    let diagnostics: [SceneGraphParserDiagnostic]
}

private struct SceneGraphOverrideParseResult: Sendable {
    let overrides: [ScenePropertyOverride]
    let diagnostics: [SceneGraphParserDiagnostic]
    let isComplete: Bool
}

struct SceneGraphParsedInstanceOverrides: Sendable {
    let overrides: [ScenePropertyOverride]
    let invalidRecordIndices: [Int]
    let hasInvalidShape: Bool

    var isComplete: Bool {
        !hasInvalidShape && invalidRecordIndices.isEmpty
    }
}

enum SceneGraphInstanceOverrideParser {
    static func parse(
        _ rawValue: SceneJSONValue
    ) -> SceneGraphParsedInstanceOverrides {
        switch rawValue {
        case let .object(values):
            return .init(
                overrides: values.keys.sorted().compactMap { property in
                    values[property].map {
                        ScenePropertyOverride(propertyPath: property, value: $0)
                    }
                },
                invalidRecordIndices: [],
                hasInvalidShape: false
            )
        case let .array(records):
            var overrides: [ScenePropertyOverride] = []
            var invalidRecordIndices: [Int] = []
            overrides.reserveCapacity(records.count)
            for (index, record) in records.enumerated() {
                guard case let .object(fields) = record,
                      case let .string(property)? = fields["property"],
                      let value = fields["value"] else {
                    invalidRecordIndices.append(index)
                    continue
                }
                overrides.append(ScenePropertyOverride(
                    propertyPath: property,
                    value: value
                ))
            }
            return .init(
                overrides: overrides,
                invalidRecordIndices: invalidRecordIndices,
                hasInvalidShape: false
            )
        default:
            return .init(
                overrides: [],
                invalidRecordIndices: [],
                hasInvalidShape: true
            )
        }
    }
}

private enum SceneGraphHierarchyEdgeKind: Sendable {
    case parent
    case instance

    var key: String {
        switch self {
        case .parent:
            "parent"
        case .instance:
            "instance"
        }
    }

    var cycleCode: String {
        switch self {
        case .parent:
            "graph.parent-cycle"
        case .instance:
            "graph.instance-cycle"
        }
    }
}

private enum SceneGraphTraversalColor: Sendable {
    case gray
    case black
}

private enum SceneGraphTraversalFrame: Sendable {
    case visit(SceneNodeID, depth: Int)
    case finish(SceneNodeID, next: SceneNodeID)

    var node: SceneNodeID? {
        switch self {
        case let .visit(node, _), let .finish(node, _):
            node
        }
    }
}
