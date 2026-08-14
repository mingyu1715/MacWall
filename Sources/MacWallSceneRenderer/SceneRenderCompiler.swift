import CryptoKit
import Foundation
import MacWallSceneGraph
import MacWallSceneTextures

public struct SceneRenderCompiler: Sendable {
    private let limits: SceneRenderLimits

    public init(limits: SceneRenderLimits = .init()) {
        self.limits = limits
    }

    public func compile(
        _ graphResult: SceneGraphBuildResult
    ) -> SceneRenderCompileResult {
        var diagnostics = graphResult.diagnostics.map(renderDiagnostic)
        guard let document = graphResult.document else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.missing-document"
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }
        guard graphResult.status != .invalid else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.invalid-graph"
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }
        guard let graphCanvas = document.canvas else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.invalid-canvas"
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }

        let canvas = SceneRenderCanvas(
            width: graphCanvas.width,
            height: graphCanvas.height
        )
        do {
            try limits.validate(canvas: canvas)
        } catch let error as SceneRenderError {
            diagnostics.append(limitDiagnostic(error))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        } catch {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.invalid-canvas"
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }

        guard let evaluationOrder = SceneRenderOrdering.evaluationOrder(
            nodes: document.nodes,
            hierarchyEdges: document.hierarchyEdges
        ), let evaluationParentIndices = SceneRenderOrdering.parentIndices(
            evaluationOrder: evaluationOrder,
            hierarchyEdges: document.hierarchyEdges
        ) else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.invalid-hierarchy"
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }

        let resources = ResourceIndex(document.resources)
        let dependencyIndex = DependencyIndex(document.dependencies)
        let animationIndex = AnimationIndex(document.animations)
        let nodeByID = Dictionary(uniqueKeysWithValues:
            document.nodes.map { ($0.id, $0) }
        )
        let unresolvedParentNodes = Set<SceneNodeID>(document.hierarchyEdges.compactMap { edge in
            if case .resolved = edge.resolution { return nil }
            return edge.childID
        })
        let instanceEdges = Dictionary(
            uniqueKeysWithValues: document.instanceEdges.map { ($0.instanceID, $0) }
        )
        var nodeTemplates: [SceneRenderNodeTemplate] = []
        nodeTemplates.reserveCapacity(evaluationOrder.count)
        var evaluationIndexByNodeID: [SceneNodeID: Int] = [:]
        evaluationIndexByNodeID.reserveCapacity(evaluationOrder.count)
        var wasDegraded = graphResult.status != .exact

        for (index, identity) in evaluationOrder.enumerated() {
            guard let node = nodeByID[identity.nodeID] else {
                diagnostics.append(.init(
                    severity: .error,
                    code: "renderer.invalid-hierarchy",
                    nodeID: identity.nodeID
                ))
                return result(nil, status: .invalid, diagnostics: diagnostics)
            }
            evaluationIndexByNodeID[node.id] = index
            var nodeDiagnostics: [SceneRenderDiagnostic] = []
            let exactBase = baseProperties(node, diagnostics: &nodeDiagnostics)
            let animationResult = supportedAnimations(
                animationIndex[node.id] ?? [],
                nodeID: node.id
            )
            nodeDiagnostics.append(contentsOf: animationResult.diagnostics)

            var isSupported = exactBase != nil
                && !unresolvedParentNodes.contains(node.id)
            if let instanceEdge = instanceEdges[node.id] {
                let code = instanceEdge.overrides.isEmpty
                    ? "renderer.unsupported-instance"
                    : "renderer.unsupported-instance-override"
                nodeDiagnostics.append(.init(
                    severity: .warning,
                    code: code,
                    nodeID: node.id
                ))
                isSupported = false
            }
            wasDegraded = wasDegraded
                || !isSupported
                || animationResult.wasDegraded
            diagnostics.append(contentsOf: nodeDiagnostics)
            nodeTemplates.append(.init(
                identity: identity,
                parentIndex: evaluationParentIndices[index],
                baseProperties: exactBase ?? .identity,
                animationBindings: isSupported ? animationResult.tracks : [],
                isSupported: isSupported
            ))
        }

        var unboundDraws: [SceneRenderUnboundDrawTemplate] = []

        for node in document.nodes.sorted(by: Self.nodePrecedes) {
            guard case .image = node.payload else {
                if node.payload.kind != .fullscreen {
                    diagnostics.append(.init(
                        severity: .information,
                        code: "renderer.unsupported-node-kind",
                        nodeID: node.id,
                        arguments: [String(describing: node.payload.kind)]
                    ))
                    wasDegraded = true
                }
                continue
            }

            guard let evaluationNodeIndex = evaluationIndexByNodeID[node.id],
                  nodeTemplates[evaluationNodeIndex].isSupported else {
                wasDegraded = true
                continue
            }

            let compiled = compileImageNode(
                node,
                evaluationNodeIndex: evaluationNodeIndex,
                resources: resources,
                dependencies: dependencyIndex
            )
            diagnostics.append(contentsOf: compiled.diagnostics)
            wasDegraded = wasDegraded || compiled.wasDegraded || compiled.template == nil
            if let template = compiled.template {
                unboundDraws.append(template)
            }
        }

        guard unboundDraws.count <= limits.maximumDrawItemCount else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.resource-limit",
                arguments: [SceneRenderLimit.drawItems.rawValue]
            ))
            return result(nil, status: .invalid, diagnostics: diagnostics)
        }
        guard !unboundDraws.isEmpty else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.no-renderable-images"
            ))
            return result(nil, status: .unsupported, diagnostics: diagnostics)
        }

        let orderedDraws = SceneRenderOrdering.ordered(unboundDraws)
        let bound = bindTextureManifest(orderedDraws)
        let fingerprint = SceneRenderFingerprint.make(
            canvas: canvas,
            draws: bound.drawTemplates,
            nodes: nodeTemplates,
            manifest: bound.textureManifest
        )
        let program = SceneRenderProgram(
            canvas: canvas,
            fingerprint: fingerprint,
            nodeTemplates: nodeTemplates,
            drawTemplates: bound.drawTemplates,
            textureManifest: bound.textureManifest
        )
        return result(
            program,
            status: wasDegraded ? .degraded : .exact,
            diagnostics: diagnostics
        )
    }

    private func compileImageNode(
        _ node: SceneGraphNode,
        evaluationNodeIndex: Int,
        resources: ResourceIndex,
        dependencies: DependencyIndex
    ) -> CompiledNode {
        var diagnostics: [SceneRenderDiagnostic] = []
        guard let modelPath = dependencies.modelPackagePath(
            owner: .node(node.id)
        ), let model = resources.models[modelPath] else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.missing-model",
                nodeID: node.id
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }
        guard modelFieldsAreRenderable(model) else {
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.unsupported-model",
                nodeID: node.id,
                resourceID: model.id
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }
        guard let materialPath = model.materialDependency.flatMap(packagePath),
              let material = resources.materials[materialPath] else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.missing-material",
                nodeID: node.id,
                resourceID: model.id
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }
        guard materialFieldsAreRenderable(material),
              material.passes.count == 1,
              let pass = material.passes.first,
              passFieldsAreRenderable(pass),
              pass.textureBindings.count == 1,
              let textureBinding = pass.textureBindings.first else {
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.unsupported-material",
                nodeID: node.id,
                resourceID: material.id
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }

        var wasDegraded = false
        if let shader = pass.shaderDependency {
            guard isSupportedBuiltInImageShader(shader) else {
                diagnostics.append(.init(
                    severity: .warning,
                    code: "renderer.custom-shader",
                    nodeID: node.id,
                    resourceID: material.id
                ))
                return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
            }
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.builtin-shader-emulated",
                nodeID: node.id,
                resourceID: material.id,
                arguments: [shader.request.requestedPath]
            ))
            wasDegraded = true
        }

        if !pass.effectDependencies.isEmpty {
            guard pass.effectDependencies.allSatisfy({ packagePath($0) != nil }) else {
                diagnostics.append(.init(
                    severity: .warning,
                    code: "renderer.unsupported-effect-chain",
                    nodeID: node.id,
                    resourceID: material.id
                ))
                return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
            }
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.base-effect-omitted",
                nodeID: node.id,
                resourceID: material.id
            ))
            wasDegraded = true
        }

        guard let texturePath = packagePath(textureBinding.dependency),
              let texture = resources.textures[texturePath] else {
            diagnostics.append(.init(
                severity: .error,
                code: "renderer.missing-texture",
                nodeID: node.id,
                resourceID: material.id
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }
        if let size = node.size,
           !size.isFiniteAndPositive {
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.invalid-node-property",
                nodeID: node.id,
                arguments: ["size"]
            ))
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }

        return .init(
            template: SceneRenderUnboundDrawTemplate(
                identity: .init(nodeID: node.id, instancePath: []),
                sourceOrder: node.sourceOrder,
                effectiveZ: 0,
                evaluationNodeIndex: evaluationNodeIndex,
                textureResource: texture,
                imageIndex: 0,
                colorIntent: .colorSRGB,
                localSize: node.size
            ),
            diagnostics: diagnostics,
            wasDegraded: wasDegraded
        )
    }

    private func baseProperties(
        _ node: SceneGraphNode,
        diagnostics: inout [SceneRenderDiagnostic]
    ) -> SceneRenderBaseProperties? {
        var unsupported: [String] = []
        if node.pivot != nil { unsupported.append("pivot") }
        if node.position != nil { unsupported.append("position") }
        if node.zOrder != nil { unsupported.append("zOrder") }
        if let angles = node.angles, angles.x != 0 || angles.y != 0 {
            unsupported.append("rotationXY")
        }
        if let color = node.color, !isIdentityWhite(color) {
            unsupported.append("color")
        }
        guard unsupported.isEmpty else {
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.unsupported-node-property",
                nodeID: node.id,
                arguments: unsupported.sorted()
            ))
            return nil
        }

        let origin = node.origin ?? .init(x: 0, y: 0, z: 0)
        let scale = node.scale ?? .init(x: 1, y: 1, z: 1)
        let rotationZ = node.angles?.z ?? 0
        let opacity = node.opacity ?? 1
        guard origin.isFinite,
              scale.isFinite,
              rotationZ.isFinite,
              opacity.isFinite,
              origin.z == 0 else {
            diagnostics.append(.init(
                severity: .warning,
                code: "renderer.invalid-node-property",
                nodeID: node.id
            ))
            return nil
        }

        return .init(
            origin: origin,
            pivot: .init(x: 0, y: 0, z: 0),
            position: .init(x: 0, y: 0, z: 0),
            scale: .init(x: scale.x, y: scale.y, z: 1),
            rotationZ: rotationZ,
            opacity: opacity,
            visible: node.visible ?? true,
            enabled: node.enabled ?? true,
            color: node.color ?? .init(red: 255, green: 255, blue: 255, alpha: 255),
            zOrder: 0
        )
    }

    private func supportedAnimations(
        _ animations: [SceneAnimationTrack],
        nodeID: SceneNodeID
    ) -> AnimationCompileResult {
        var tracks: [SceneTypedAnimationTrack] = []
        var diagnostics: [SceneRenderDiagnostic] = []
        for rawTrack in animations.sorted(by: { $0.propertyPath < $1.propertyPath }) {
            guard let track = rawTrack.typedTrack else {
                diagnostics.append(animationDiagnostic(
                    nodeID: nodeID,
                    property: rawTrack.propertyPath,
                    reason: "malformed"
                ))
                continue
            }
            let reason: String?
            if track.isRelative {
                reason = "relative"
            } else if track.startsPaused {
                reason = "startPaused"
            } else if !interpolationIsSupported(track) {
                reason = "interpolation"
            } else if !supportedAnimatedProperties.contains(track.property) {
                reason = "property"
            } else {
                reason = nil
            }
            if let reason {
                diagnostics.append(animationDiagnostic(
                    nodeID: nodeID,
                    property: track.property.rawValue,
                    reason: reason
                ))
            } else {
                tracks.append(track)
            }
        }
        tracks.sort { $0.property.rawValue < $1.property.rawValue }
        return .init(
            tracks: tracks,
            diagnostics: diagnostics,
            wasDegraded: !diagnostics.isEmpty
        )
    }

    private func interpolationIsSupported(
        _ track: SceneTypedAnimationTrack
    ) -> Bool {
        if track.property == .visibility {
            return track.keyframes.allSatisfy { $0.interpolation == .step }
        }
        return track.keyframes.allSatisfy { $0.interpolation == .linear }
    }

    private var supportedAnimatedProperties: Set<SceneRenderableProperty> {
        [.origin, .scale, .rotationZ, .opacity, .visibility]
    }

    private func animationDiagnostic(
        nodeID: SceneNodeID,
        property: String,
        reason: String
    ) -> SceneRenderDiagnostic {
        .init(
            severity: .warning,
            code: "renderer.unsupported-animation",
            nodeID: nodeID,
            arguments: [property, reason]
        )
    }

    private func bindTextureManifest(
        _ draws: [SceneRenderUnboundDrawTemplate]
    ) -> BoundRenderProgram {
        var manifest: [MutableManifestEntry] = []
        var manifestIndices: [TextureManifestKey: Int] = [:]
        var boundDraws: [SceneRenderDrawTemplate] = []
        boundDraws.reserveCapacity(draws.count)

        for (drawIndex, draw) in draws.enumerated() {
            let key = TextureManifestKey(
                resourceID: draw.textureResource.id,
                imageIndex: draw.imageIndex,
                colorIntent: draw.colorIntent
            )
            let manifestIndex: Int
            if let existing = manifestIndices[key] {
                manifestIndex = existing
                manifest[existing].dependentDrawIndices.append(drawIndex)
            } else {
                manifestIndex = manifest.count
                manifestIndices[key] = manifestIndex
                manifest.append(.init(
                    resource: draw.textureResource,
                    imageIndex: draw.imageIndex,
                    colorIntent: draw.colorIntent,
                    dependentDrawIndices: [drawIndex]
                ))
            }
            boundDraws.append(.init(
                identity: draw.identity,
                sourceOrder: draw.sourceOrder,
                effectiveZ: draw.effectiveZ,
                evaluationNodeIndex: draw.evaluationNodeIndex,
                textureManifestIndex: manifestIndex,
                localSize: draw.localSize
            ))
        }
        return .init(
            drawTemplates: boundDraws,
            textureManifest: manifest.map(\.immutable)
        )
    }

    private func result(
        _ program: SceneRenderProgram?,
        status: SceneRenderStatus,
        diagnostics: [SceneRenderDiagnostic]
    ) -> SceneRenderCompileResult {
        .init(
            program: program,
            status: status,
            diagnostics: diagnostics.sorted(by: diagnosticPrecedes)
        )
    }

    private func renderDiagnostic(
        _ diagnostic: SceneGraphDiagnostic
    ) -> SceneRenderDiagnostic {
        .init(
            severity: diagnostic.severity.renderSeverity,
            code: diagnostic.code,
            nodeID: diagnostic.nodeID,
            arguments: diagnostic.arguments
        )
    }

    private func limitDiagnostic(
        _ error: SceneRenderError
    ) -> SceneRenderDiagnostic {
        if case let .resourceLimit(limit) = error {
            return .init(
                severity: .error,
                code: "renderer.resource-limit",
                arguments: [limit.rawValue]
            )
        }
        return .init(severity: .error, code: "renderer.invalid-canvas")
    }

    private func diagnosticPrecedes(
        _ first: SceneRenderDiagnostic,
        _ second: SceneRenderDiagnostic
    ) -> Bool {
        let firstKey = DiagnosticSortKey(first)
        let secondKey = DiagnosticSortKey(second)
        return firstKey < secondKey
    }

    private func packagePath(
        _ dependency: SceneDependencyEdge
    ) -> String? {
        guard dependency.resolution.kind == .package else {
            return nil
        }
        return dependency.resolution.selected?.canonicalPath.rawValue
    }

    private func isSupportedBuiltInImageShader(
        _ dependency: SceneDependencyEdge
    ) -> Bool {
        guard dependency.resolution.kind == .builtInCandidate else {
            return false
        }
        let name = dependency.request.requestedPath.lowercased()
        return name == "genericimage"
            || name == "genericimage2"
            || name == "genericimage4"
    }

    private func modelFieldsAreRenderable(_ model: SceneModelResource) -> Bool {
        model.unknownFields.allSatisfy { key, value in
            switch key {
            case "mesh":
                value == .string("quad")
            case "autosize":
                value == .bool(true)
            default:
                false
            }
        }
    }

    private func materialFieldsAreRenderable(_ material: SceneMaterialResource) -> Bool {
        material.unknownFields.allSatisfy { key, value in
            key == "blend" && value == .string("normal")
        }
    }

    private func passFieldsAreRenderable(_ pass: SceneMaterialPass) -> Bool {
        pass.unknownFields.allSatisfy { key, value in
            switch key {
            case "blending":
                value == .string("translucent")
            case "combos":
                value == .object([:])
                    || value == .object(["version": .integer(2)])
                    || value == .object(["VERSION": .integer(2)])
            case "cullmode":
                value == .string("nocull")
            case "depth", "depthtest", "depthwrite":
                value == .bool(false) || value == .string("disabled")
            default:
                false
            }
        }
    }

    private func isIdentityWhite(_ color: SceneGraphColor) -> Bool {
        color.red == 255 && color.green == 255
            && color.blue == 255 && color.alpha == 255
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

struct SceneRenderUnboundDrawTemplate: Sendable {
    let identity: SceneRenderNodeIdentity
    let sourceOrder: Int
    let effectiveZ: Double
    let evaluationNodeIndex: Int
    let textureResource: SceneTextureResource
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
    let localSize: SceneGraphSize?
}

private struct CompiledNode {
    let template: SceneRenderUnboundDrawTemplate?
    let diagnostics: [SceneRenderDiagnostic]
    let wasDegraded: Bool
}

private struct AnimationCompileResult {
    let tracks: [SceneTypedAnimationTrack]
    let diagnostics: [SceneRenderDiagnostic]
    let wasDegraded: Bool
}

private struct BoundRenderProgram {
    let drawTemplates: [SceneRenderDrawTemplate]
    let textureManifest: [SceneRenderTextureManifestEntry]
}

private struct TextureManifestKey: Hashable {
    let resourceID: SceneResourceID
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
}

private struct MutableManifestEntry {
    let resource: SceneTextureResource
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
    var dependentDrawIndices: [Int]

    var immutable: SceneRenderTextureManifestEntry {
        .init(
            resource: resource,
            imageIndex: imageIndex,
            colorIntent: colorIntent,
            dependentDrawIndices: dependentDrawIndices
        )
    }
}

private struct ResourceIndex {
    var models: [String: SceneModelResource] = [:]
    var materials: [String: SceneMaterialResource] = [:]
    var textures: [String: SceneTextureResource] = [:]

    init(_ resources: [SceneGraphResource]) {
        for resource in resources {
            switch resource {
            case let .model(model): models[model.path.rawValue] = model
            case let .material(material): materials[material.path.rawValue] = material
            case let .texture(texture): textures[texture.path.rawValue] = texture
            case .effect, .shader: break
            }
        }
    }
}

private struct DependencyIndex {
    private var edgesByNode: [SceneNodeID: [SceneDependencyEdge]] = [:]

    init(_ dependencies: [SceneDependencyEdge]) {
        for dependency in dependencies {
            guard case let .node(nodeID) = dependency.owner else {
                continue
            }
            edgesByNode[nodeID, default: []].append(dependency)
        }
    }

    func modelPackagePath(owner: SceneDependencyOwner) -> String? {
        guard case let .node(nodeID) = owner,
              let matches = edgesByNode[nodeID]?.filter({ $0.request.role == .model }),
              matches.count == 1,
              let dependency = matches.first,
              dependency.resolution.kind == .package else {
            return nil
        }
        return dependency.resolution.selected?.canonicalPath.rawValue
    }
}

private struct AnimationIndex {
    private let tracksByNode: [SceneNodeID: [SceneAnimationTrack]]

    init(_ tracks: [SceneAnimationTrack]) {
        tracksByNode = Dictionary(grouping: tracks, by: \.nodeID)
    }

    subscript(nodeID: SceneNodeID) -> [SceneAnimationTrack]? {
        tracksByNode[nodeID]
    }
}

private struct DiagnosticSortKey: Comparable {
    let severity: Int
    let code: String
    let node: String
    let resource: String
    let arguments: String

    init(_ diagnostic: SceneRenderDiagnostic) {
        switch diagnostic.severity {
        case .error: severity = 0
        case .warning: severity = 1
        case .information: severity = 2
        }
        code = diagnostic.code
        node = diagnostic.nodeID?.rawValue ?? ""
        resource = diagnostic.resourceID?.rawValue ?? ""
        arguments = diagnostic.arguments.joined(separator: "\u{0}")
    }

    static func < (lhs: DiagnosticSortKey, rhs: DiagnosticSortKey) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        if lhs.node != rhs.node { return lhs.node < rhs.node }
        if lhs.resource != rhs.resource { return lhs.resource < rhs.resource }
        return lhs.arguments < rhs.arguments
    }
}

private extension SceneGraphDiagnosticSeverity {
    var renderSeverity: SceneRenderDiagnosticSeverity {
        switch self {
        case .info: .information
        case .warning: .warning
        case .error: .error
        }
    }
}

private extension SceneGraphVector3 {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

private extension SceneGraphSize {
    var isFiniteAndPositive: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

private enum SceneRenderFingerprint {
    static func make(
        canvas: SceneRenderCanvas,
        draws: [SceneRenderDrawTemplate],
        nodes: [SceneRenderNodeTemplate],
        manifest: [SceneRenderTextureManifestEntry]
    ) -> String {
        var encoder = CanonicalEncoder()
        encoder.append("MacWall.SceneRenderProgram")
        encoder.append(3)
        encoder.append(canvas.width)
        encoder.append(canvas.height)
        encoder.append(nodes.count)
        nodes.forEach { encoder.append($0) }
        encoder.append(draws.count)
        draws.forEach { encoder.append($0) }
        encoder.append(manifest.count)
        manifest.forEach { encoder.append($0) }
        return SHA256.hash(data: encoder.data).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private struct CanonicalEncoder {
    var data = Data()

    mutating func append(_ value: Int) {
        append(UInt64(bitPattern: Int64(truncatingIfNeeded: value)))
    }

    mutating func append(_ value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: Double) {
        append(value.bitPattern)
    }

    mutating func append(_ value: Bool) {
        data.append(value ? 1 : 0)
    }

    mutating func append(_ value: String) {
        let bytes = Data(value.utf8)
        append(bytes.count)
        data.append(bytes)
    }

    mutating func append(_ identity: SceneRenderNodeIdentity) {
        append(identity.nodeID.rawValue)
        append(identity.instancePath.count)
        identity.instancePath.forEach { append($0.rawValue) }
    }

    mutating func append(_ draw: SceneRenderDrawTemplate) {
        append(draw.identity)
        append(draw.sourceOrder)
        append(draw.effectiveZ)
        append(draw.evaluationNodeIndex)
        append(draw.textureManifestIndex)
        append(draw.localSize != nil)
        if let localSize = draw.localSize {
            append(localSize.width)
            append(localSize.height)
        }
    }

    mutating func append(_ node: SceneRenderNodeTemplate) {
        append(node.identity)
        append(node.parentIndex != nil)
        if let parentIndex = node.parentIndex { append(parentIndex) }
        append(node.baseProperties)
        append(node.animationBindings.count)
        node.animationBindings.forEach { append($0) }
        append(node.isSupported)
    }

    mutating func append(_ properties: SceneRenderBaseProperties) {
        append(properties.origin)
        append(properties.pivot)
        append(properties.position)
        append(properties.scale)
        append(properties.rotationZ)
        append(properties.opacity)
        append(properties.visible)
        append(properties.enabled)
        append(properties.color.red)
        append(properties.color.green)
        append(properties.color.blue)
        append(properties.color.alpha)
        append(properties.zOrder)
    }

    mutating func append(_ vector: SceneGraphVector3) {
        append(vector.x)
        append(vector.y)
        append(vector.z)
    }

    mutating func append(_ track: SceneTypedAnimationTrack) {
        append(track.property.rawValue)
        append(track.playbackMode.rawValue)
        append(track.durationSeconds)
        append(track.isRelative)
        append(track.startsPaused)
        append(track.keyframes.count)
        track.keyframes.forEach { append($0) }
    }

    mutating func append(_ keyframe: SceneTypedAnimationKeyframe) {
        append(keyframe.timeSeconds)
        switch keyframe.value {
        case let .scalar(value):
            append("scalar")
            append(value)
        case let .vector3(value):
            append("vector3")
            append(value)
        case let .boolean(value):
            append("boolean")
            append(value)
        }
        switch keyframe.interpolation {
        case .linear:
            append("linear")
        case .step:
            append("step")
        case let .cubicBezier(points):
            append("cubicBezier")
            append(points.x1)
            append(points.y1)
            append(points.x2)
            append(points.y2)
        }
    }

    mutating func append(_ entry: SceneRenderTextureManifestEntry) {
        append(entry.resource.id.rawValue)
        append(entry.resource.path.rawValue)
        append(entry.imageIndex)
        append(entry.colorIntent.rawValue)
        append(entry.dependentDrawIndices.count)
        entry.dependentDrawIndices.forEach { append($0) }
    }
}
