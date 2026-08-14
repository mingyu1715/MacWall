import CryptoKit
import Foundation
import MacWallSceneAssets
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
        var unboundDraws: [SceneRenderUnboundDrawTemplate] = []
        var wasDegraded = graphResult.status != .exact

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

            let compiled = compileImageNode(
                node,
                resources: resources,
                dependencies: dependencyIndex,
                animations: animationIndex[node.id] ?? []
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
            evaluationOrder: evaluationOrder,
            evaluationParentIndices: evaluationParentIndices,
            manifest: bound.textureManifest
        )
        let program = SceneRenderProgram(
            canvas: canvas,
            fingerprint: fingerprint,
            drawTemplates: bound.drawTemplates,
            evaluationOrder: evaluationOrder,
            evaluationParentIndices: evaluationParentIndices,
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
        resources: ResourceIndex,
        dependencies: DependencyIndex,
        animations: [SceneAnimationTrack]
    ) -> CompiledNode {
        var diagnostics: [SceneRenderDiagnostic] = []
        guard let baseProperties = baseProperties(node, diagnostics: &diagnostics) else {
            return .init(template: nil, diagnostics: diagnostics, wasDegraded: true)
        }
        guard let modelPath = dependencies.packagePath(
            owner: .node(node.id),
            role: .model
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

        let animationResult = supportedAnimations(animations, nodeID: node.id)
        diagnostics.append(contentsOf: animationResult.diagnostics)
        wasDegraded = wasDegraded || animationResult.wasDegraded
        return .init(
            template: SceneRenderUnboundDrawTemplate(
                identity: .init(nodeID: node.id, instancePath: []),
                sourceOrder: node.sourceOrder,
                effectiveZ: 0,
                textureResource: texture,
                imageIndex: 0,
                colorIntent: .colorSRGB,
                baseProperties: baseProperties,
                animationBindings: animationResult.tracks
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
              origin.z == 0,
              scale.z == 1 else {
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
            scale: scale,
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
                textureManifestIndex: manifestIndex,
                baseProperties: draw.baseProperties,
                animationBindings: draw.animationBindings
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
    ) -> SceneVirtualPath? {
        guard dependency.resolution.kind == .package else {
            return nil
        }
        return dependency.resolution.selected?.canonicalPath
    }

    private func isSupportedBuiltInImageShader(
        _ dependency: SceneDependencyEdge
    ) -> Bool {
        guard dependency.resolution.kind == .builtInCandidate else {
            return false
        }
        let name = dependency.request.requestedPath.lowercased()
        return name == "genericimage" || name == "genericimage4"
    }

    private func modelFieldsAreRenderable(_ model: SceneModelResource) -> Bool {
        model.unknownFields.allSatisfy { key, value in
            key == "mesh" && value == .string("quad")
        }
    }

    private func materialFieldsAreRenderable(_ material: SceneMaterialResource) -> Bool {
        material.unknownFields.allSatisfy { key, value in
            key == "blend" && value == .string("normal")
        }
    }

    private func passFieldsAreRenderable(_ pass: SceneMaterialPass) -> Bool {
        pass.unknownFields.allSatisfy { key, value in
            key == "depth" && value == .bool(false)
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
    let textureResource: SceneTextureResource
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
    let baseProperties: SceneRenderBaseProperties
    let animationBindings: [SceneTypedAnimationTrack]
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
    var models: [SceneVirtualPath: SceneModelResource] = [:]
    var materials: [SceneVirtualPath: SceneMaterialResource] = [:]
    var textures: [SceneVirtualPath: SceneTextureResource] = [:]

    init(_ resources: [SceneGraphResource]) {
        for resource in resources {
            switch resource {
            case let .model(model): models[model.path] = model
            case let .material(material): materials[material.path] = material
            case let .texture(texture): textures[texture.path] = texture
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

    func packagePath(
        owner: SceneDependencyOwner,
        role: SceneAssetRole
    ) -> SceneVirtualPath? {
        guard case let .node(nodeID) = owner,
              let matches = edgesByNode[nodeID]?.filter({ $0.request.role == role }),
              matches.count == 1,
              let dependency = matches.first,
              dependency.resolution.kind == .package else {
            return nil
        }
        return dependency.resolution.selected?.canonicalPath
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

private enum SceneRenderFingerprint {
    static func make(
        canvas: SceneRenderCanvas,
        draws: [SceneRenderDrawTemplate],
        evaluationOrder: [SceneRenderNodeIdentity],
        evaluationParentIndices: [Int?],
        manifest: [SceneRenderTextureManifestEntry]
    ) -> String {
        var encoder = CanonicalEncoder()
        encoder.append("MacWall.SceneRenderProgram")
        encoder.append(1)
        encoder.append(canvas.width)
        encoder.append(canvas.height)
        encoder.append(evaluationOrder.count)
        for (identity, parentIndex) in zip(evaluationOrder, evaluationParentIndices) {
            encoder.append(identity)
            encoder.append(parentIndex != nil)
            if let parentIndex { encoder.append(parentIndex) }
        }
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
        append(draw.textureManifestIndex)
        append(draw.baseProperties)
        append(draw.animationBindings.count)
        draw.animationBindings.forEach { append($0) }
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
