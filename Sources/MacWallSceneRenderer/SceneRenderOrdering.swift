import MacWallSceneGraph

enum SceneRenderOrdering {
    static func ordered(
        _ templates: [SceneRenderUnboundDrawTemplate]
    ) -> [SceneRenderUnboundDrawTemplate] {
        templates.sorted { first, second in
            if first.effectiveZ != second.effectiveZ {
                return first.effectiveZ < second.effectiveZ
            }
            if first.sourceOrder != second.sourceOrder {
                return first.sourceOrder < second.sourceOrder
            }
            return first.identity < second.identity
        }
    }

    static func evaluationOrder(
        nodes: [SceneGraphNode],
        hierarchyEdges: [SceneHierarchyEdge]
    ) -> [SceneRenderNodeIdentity]? {
        let orderedNodes = nodes.sorted(by: nodePrecedes)
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var children: [SceneNodeID: [SceneNodeID]] = [:]

        for edge in hierarchyEdges {
            guard case let .resolved(parentID) = edge.resolution,
                  nodeByID[parentID] != nil,
                  nodeByID[edge.childID] != nil else {
                continue
            }
            indegree[edge.childID, default: 0] += 1
            children[parentID, default: []].append(edge.childID)
        }
        for key in children.keys {
            children[key]?.sort { first, second in
                guard let firstNode = nodeByID[first],
                      let secondNode = nodeByID[second] else {
                    return first < second
                }
                return nodePrecedes(firstNode, secondNode)
            }
        }

        var ready = SceneRenderNodeHeap(
            orderedNodes.filter { indegree[$0.id] == 0 }
        )
        var result: [SceneRenderNodeIdentity] = []
        result.reserveCapacity(nodes.count)
        while let node = ready.removeMinimum() {
            result.append(.init(nodeID: node.id, instancePath: []))
            for childID in children[node.id] ?? [] {
                guard let current = indegree[childID] else {
                    continue
                }
                let next = current - 1
                indegree[childID] = next
                if next == 0, let child = nodeByID[childID] {
                    ready.insert(child)
                }
            }
        }

        return result.count == nodes.count ? result : nil
    }

    static func parentIndices(
        evaluationOrder: [SceneRenderNodeIdentity],
        hierarchyEdges: [SceneHierarchyEdge]
    ) -> [Int?]? {
        let indexByNode = Dictionary(uniqueKeysWithValues:
            evaluationOrder.enumerated().map { ($0.element.nodeID, $0.offset) }
        )
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]
        for edge in hierarchyEdges {
            guard case let .resolved(parentID) = edge.resolution else {
                continue
            }
            guard parentByChild.updateValue(parentID, forKey: edge.childID) == nil else {
                return nil
            }
        }
        return evaluationOrder.enumerated().map { childIndex, identity in
            guard let parentID = parentByChild[identity.nodeID],
                  let parentIndex = indexByNode[parentID],
                  parentIndex < childIndex else {
                return nil
            }
            return parentIndex
        }
    }

    private static func nodePrecedes(
        _ first: SceneGraphNode,
        _ second: SceneGraphNode
    ) -> Bool {
        if first.sourceOrder != second.sourceOrder {
            return first.sourceOrder < second.sourceOrder
        }
        return first.id < second.id
    }
}

private struct SceneRenderNodeHeap {
    private var elements: [SceneGraphNode] = []

    init(_ nodes: [SceneGraphNode]) {
        elements.reserveCapacity(nodes.count)
        for node in nodes {
            insert(node)
        }
    }

    mutating func insert(_ node: SceneGraphNode) {
        elements.append(node)
        var child = elements.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.precedes(elements[child], elements[parent]) else {
                break
            }
            elements.swapAt(child, parent)
            child = parent
        }
    }

    mutating func removeMinimum() -> SceneGraphNode? {
        guard !elements.isEmpty else {
            return nil
        }
        if elements.count == 1 {
            return elements.removeLast()
        }

        let minimum = elements[0]
        elements[0] = elements.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < elements.count else {
                break
            }
            let right = left + 1
            let child: Int
            if right < elements.count,
               Self.precedes(elements[right], elements[left]) {
                child = right
            } else {
                child = left
            }
            guard Self.precedes(elements[child], elements[parent]) else {
                break
            }
            elements.swapAt(parent, child)
            parent = child
        }
        return minimum
    }

    private static func precedes(
        _ first: SceneGraphNode,
        _ second: SceneGraphNode
    ) -> Bool {
        if first.sourceOrder != second.sourceOrder {
            return first.sourceOrder < second.sourceOrder
        }
        return first.id < second.id
    }
}
