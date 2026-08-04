import Foundation
import MacWallSceneAssets

public struct SceneGraphBuilder: Sendable {
    private let limits: SceneGraphLimits

    public init(limits: SceneGraphLimits = .init()) {
        self.limits = limits
    }

    public func build(url: URL) -> SceneGraphBuildResult {
        do {
            return build(
                resolver: try ScenePackageAssetResolver.open(url: url)
            )
        } catch {
            return SceneGraphBuildResult(
                document: nil,
                status: .invalid,
                diagnostics: [
                    SceneGraphDiagnostic(
                        severity: .error,
                        code: "graph.invalid-package",
                        sourcePath: nil,
                        nodeID: nil,
                        jsonPath: nil,
                        dependencyPath: [],
                        arguments: []
                    )
                ]
            )
        }
    }

    public func build(
        resolver: ScenePackageAssetResolver
    ) -> SceneGraphBuildResult {
        var accumulator = SceneGraphStatusAccumulator()
        appendPackageDiagnostics(
            resolver.packageIssues,
            to: &accumulator
        )

        let request = SceneAssetRequest(
            requestedPath: "scene.json",
            ownerPath: nil,
            role: .scene,
            key: nil
        )
        let resolution = resolver.resolve(request)
        guard resolution.kind == .package,
              let asset = resolution.selected else {
            return accumulator.invalidResult(
                code: "graph.malformed-scene-json",
                sourcePath: nil
            )
        }

        guard case let .package(identity) = asset.provenance else {
            return accumulator.invalidResult(
                code: "graph.malformed-scene-json",
                sourcePath: asset.canonicalPath
            )
        }
        if let limitName = exceededRootLimit(byteCount: identity.byteCount) {
            return accumulator.invalidResult(
                code: "graph.resource-limit",
                sourcePath: asset.canonicalPath,
                arguments: [limitName]
            )
        }

        let data: Data
        do {
            data = try resolver.read(
                asset,
                maximumBytes: limits.maximumJSONEntryBytes
            )
        } catch {
            return accumulator.invalidResult(
                code: "graph.malformed-scene-json",
                sourcePath: asset.canonicalPath
            )
        }

        let root: [String: SceneJSONValue]
        do {
            guard case let .object(value) = try SceneJSONDocumentDecoder(
                maximumDepth: limits.maximumJSONDepth
            ).decode(data) else {
                return accumulator.invalidResult(
                    code: "graph.malformed-scene-json",
                    sourcePath: asset.canonicalPath
                )
            }
            root = value
        } catch SceneJSONDocumentError.depthLimit {
            return accumulator.invalidResult(
                code: "graph.resource-limit",
                sourcePath: asset.canonicalPath,
                arguments: ["maximumJSONDepth"]
            )
        } catch {
            return accumulator.invalidResult(
                code: "graph.malformed-scene-json",
                sourcePath: asset.canonicalPath
            )
        }

        let rawObjects: [SceneJSONValue]
        if let objects = root["objects"] {
            guard case let .array(values) = objects else {
                return accumulator.invalidResult(
                    code: "graph.malformed-scene-json",
                    sourcePath: asset.canonicalPath
                )
            }
            rawObjects = values
        } else {
            rawObjects = []
        }

        guard rawObjects.count <= limits.maximumNodeCount else {
            return accumulator.invalidResult(
                code: "graph.resource-limit",
                sourcePath: asset.canonicalPath,
                arguments: ["maximumNodeCount"]
            )
        }

        let phaseState = SceneGraphBuildPhaseState(
            rawObjects: rawObjects
        )
        var nodes: [SceneGraphNode] = []
        nodes.reserveCapacity(phaseState.rawObjects.count)
        let parser = SceneGraphNodeParser(sourcePath: asset.canonicalPath)
        for (index, rawObject) in phaseState.rawObjects.enumerated() {
            let parsed = parser.parse(rawObject, at: index)
            nodes.append(parsed.node)
            accumulator.append(contentsOf: parsed.diagnostics)
            if !parsed.node.unknownFields.isEmpty {
                accumulator.record(.degraded)
            }
        }
        let hierarchy = SceneGraphHierarchyResolver(limits: limits).resolve(
            nodes: nodes,
            rawObjects: phaseState.rawObjects,
            sourcePath: asset.canonicalPath
        )
        accumulator.append(contentsOf: hierarchy.diagnostics)

        var resourceParser = SceneGraphResourceParser(
            resolver: resolver,
            limits: limits,
            initialCumulativeJSONBytes: identity.byteCount
        )
        let resourceGraph = resourceParser.parse(
            root: root,
            sourcePath: asset.canonicalPath,
            nodes: nodes
        )
        accumulator.append(contentsOf: resourceGraph.diagnostics)
        for evidence in resourceGraph.evidence {
            accumulator.record(evidence)
        }

        let animationGraph = SceneGraphAnimationParser(
            limits: limits,
            sourcePath: asset.canonicalPath
        ).parse(
            nodes: nodes,
            rawObjects: phaseState.rawObjects
        )
        accumulator.append(contentsOf: animationGraph.diagnostics)

        var sceneMetadata = root
        sceneMetadata.removeValue(forKey: "objects")
        let document = SceneGraphDocument(
            package: resolver.package,
            sourcePath: asset.canonicalPath,
            canvas: canvas(from: root),
            sceneMetadata: sceneMetadata,
            nodes: nodes,
            hierarchyEdges: hierarchy.hierarchyEdges,
            instanceEdges: hierarchy.instanceEdges,
            resources: resourceGraph.resources,
            dependencies: resourceGraph.dependencies,
            animations: animationGraph.animations,
            scripts: resourceGraph.scripts
        )
        return SceneGraphBuildResult(
            document: document,
            status: accumulator.status,
            diagnostics: accumulator.sortedDiagnostics
        )
    }

    private func exceededRootLimit(byteCount: UInt64) -> String? {
        guard byteCount <= limits.maximumJSONEntryBytes else {
            return "maximumJSONEntryBytes"
        }
        guard byteCount <= limits.maximumCumulativeJSONBytes else {
            return "maximumCumulativeJSONBytes"
        }
        return nil
    }

    private func canvas(
        from root: [String: SceneJSONValue]
    ) -> SceneGraphCanvas? {
        guard case let .object(general)? = root["general"],
              case let .object(projection)? = general["orthogonalprojection"],
              let width = projection["width"]?.finiteNumber,
              let height = projection["height"]?.finiteNumber,
              width > 0,
              height > 0 else {
            return nil
        }
        return SceneGraphCanvas(width: width, height: height)
    }

    private func appendPackageDiagnostics(
        _ issues: [SceneAssetPackageIssue],
        to accumulator: inout SceneGraphStatusAccumulator
    ) {
        for issue in issues {
            switch issue {
            case let .unverifiedVersion(version):
                accumulator.append(
                    severity: .warning,
                    code: "package.unverified-version",
                    sourcePath: nil,
                    nodeID: nil,
                    jsonPath: nil,
                    arguments: [version],
                    evidence: .degraded
                )
            case let .overlappingEntryRange(first, second):
                accumulator.append(
                    severity: .warning,
                    code: "package.overlapping-entry-range",
                    sourcePath: second,
                    nodeID: nil,
                    jsonPath: nil,
                    arguments: [first.rawValue, second.rawValue],
                    evidence: .degraded
                )
            }
        }
    }
}

struct SceneGraphBuildPhaseState: Sendable {
    let rawObjects: [SceneJSONValue]
}

enum SceneGraphStatusEvidence: Sendable {
    case degraded
    case unsupported
    case invalid
}

struct SceneGraphStatusAccumulator: Sendable {
    private(set) var status: SceneGraphStatus = .exact
    private var diagnostics: [SceneGraphDiagnostic] = []
    private var reportedResourceLimits: Set<String> = []

    var sortedDiagnostics: [SceneGraphDiagnostic] {
        diagnostics.sorted(by: Self.precedes)
    }

    mutating func append(contentsOf parsed: [SceneGraphParserDiagnostic]) {
        for diagnostic in parsed {
            append(
                severity: diagnostic.severity,
                code: diagnostic.code,
                sourcePath: diagnostic.sourcePath,
                nodeID: diagnostic.nodeID,
                jsonPath: diagnostic.jsonPath,
                arguments: diagnostic.arguments,
                evidence: diagnostic.evidence
            )
        }
    }

    mutating func record(_ evidence: SceneGraphStatusEvidence) {
        status = Self.combined(status, evidence)
    }

    mutating func append(
        severity: SceneGraphDiagnosticSeverity,
        code: String,
        sourcePath: SceneVirtualPath?,
        nodeID: SceneNodeID?,
        jsonPath: String?,
        arguments: [String],
        evidence: SceneGraphStatusEvidence
    ) {
        if code == "graph.resource-limit",
           let limitName = arguments.first,
           !reportedResourceLimits.insert(limitName).inserted {
            record(evidence)
            return
        }
        diagnostics.append(
            SceneGraphDiagnostic(
                severity: severity,
                code: code,
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: jsonPath,
                dependencyPath: [],
                arguments: arguments
            )
        )
        record(evidence)
    }

    mutating func invalidResult(
        code: String,
        sourcePath: SceneVirtualPath?,
        arguments: [String] = []
    ) -> SceneGraphBuildResult {
        append(
            severity: .error,
            code: code,
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: nil,
            arguments: arguments,
            evidence: .invalid
        )
        return SceneGraphBuildResult(
            document: nil,
            status: status,
            diagnostics: sortedDiagnostics
        )
    }

    private static func combined(
        _ first: SceneGraphStatus,
        _ evidence: SceneGraphStatusEvidence
    ) -> SceneGraphStatus {
        let second: SceneGraphStatus
        switch evidence {
        case .degraded:
            second = .degraded
        case .unsupported:
            second = .unsupported
        case .invalid:
            second = .invalid
        }
        return rank(first) >= rank(second) ? first : second
    }

    private static func rank(_ status: SceneGraphStatus) -> Int {
        switch status {
        case .exact:
            0
        case .degraded:
            1
        case .unsupported:
            2
        case .invalid:
            3
        }
    }

    private static func precedes(
        _ first: SceneGraphDiagnostic,
        _ second: SceneGraphDiagnostic
    ) -> Bool {
        let firstSeverity = severityRank(first.severity)
        let secondSeverity = severityRank(second.severity)
        if firstSeverity != secondSeverity {
            return firstSeverity < secondSeverity
        }
        if let result = optionalPrecedes(
            first.sourcePath?.rawValue,
            second.sourcePath?.rawValue
        ) {
            return result
        }
        if let result = optionalPrecedes(
            first.nodeID?.objectIndex,
            second.nodeID?.objectIndex
        ) {
            return result
        }
        if let result = optionalPrecedes(first.jsonPath, second.jsonPath) {
            return result
        }
        if first.code != second.code {
            return first.code < second.code
        }
        return first.arguments.lexicographicallyPrecedes(second.arguments)
    }

    private static func optionalPrecedes<Value: Comparable>(
        _ first: Value?,
        _ second: Value?
    ) -> Bool? {
        switch (first, second) {
        case (nil, nil):
            nil
        case (nil, .some):
            true
        case (.some, nil):
            false
        case let (.some(first), .some(second)) where first != second:
            first < second
        default:
            nil
        }
    }

    private static func severityRank(
        _ severity: SceneGraphDiagnosticSeverity
    ) -> Int {
        switch severity {
        case .error:
            0
        case .warning:
            1
        case .info:
            2
        }
    }
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
