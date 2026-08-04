import Foundation
import MacWallSceneAssets

struct SceneGraphResourceParseResult: Sendable {
    let resources: [SceneGraphResource]
    let dependencies: [SceneDependencyEdge]
    let diagnostics: [SceneGraphParserDiagnostic]
}

struct SceneGraphResourceParser: Sendable {
    private let resolver: ScenePackageAssetResolver
    private let limits: SceneGraphLimits
    private var cumulativeJSONBytes: UInt64
    private var resources: [SceneResourceID: SceneGraphResource] = [:]
    private var dependencies: [SceneDependencyEdge] = []
    private var diagnostics: [SceneGraphParserDiagnostic] = []
    private var parsedDocuments: Set<SceneGraphResourceCacheKey> = []
    private var parsedPassDocuments: [SceneGraphResourceCacheKey: SceneGraphPassDocument] = [:]
    private var stopped = false

    init(
        resolver: ScenePackageAssetResolver,
        limits: SceneGraphLimits,
        initialCumulativeJSONBytes: UInt64
    ) {
        self.resolver = resolver
        self.limits = limits
        cumulativeJSONBytes = initialCumulativeJSONBytes
    }

    mutating func parse(nodes: [SceneGraphNode]) -> SceneGraphResourceParseResult {
        for node in nodes where !stopped {
            parse(node: node)
        }

        return SceneGraphResourceParseResult(
            resources: resources.values.sorted { $0.id < $1.id },
            dependencies: dependencies,
            diagnostics: diagnostics
        )
    }

    private mutating func parse(node: SceneGraphNode) {
        let reference: (String, SceneAssetRole, String)?
        switch node.payload {
        case let .image(value):
            reference = (value, .model, "image")
        case let .model(value):
            reference = (value, .model, "model")
        case let .particle(value):
            reference = (value, .particle, "particle")
        case let .sound(value):
            reference = (value, .sound, "sound")
        case let .composition(value?):
            reference = (value, .document, "composition")
        default:
            reference = nil
        }

        guard let reference else {
            return
        }
        let request = SceneAssetRequest(
            requestedPath: reference.0,
            ownerPath: node.id.documentPath,
            role: reference.1,
            key: reference.2
        )
        guard let edge = addDependency(
            owner: .node(node.id),
            key: reference.2,
            request: request,
            sourcePath: node.id.documentPath,
            nodeID: node.id,
            jsonPath: "objects[\(node.id.objectIndex)].\(reference.2)"
        ) else {
            return
        }
        if reference.1 == .model,
           edge.resolution.kind == .package,
           let asset = edge.resolution.selected {
            followModel(asset)
        }
    }

    private mutating func followModel(_ asset: SceneResolvedAsset) {
        let cacheKey = SceneGraphResourceCacheKey(role: .model, path: asset.canonicalPath)
        guard parsedDocuments.insert(cacheKey).inserted, !stopped else {
            return
        }
        guard let object = readJSONObject(asset) else {
            return
        }

        let id = SceneResourceID(kind: .model, path: asset.canonicalPath)
        var fields = object
        let materialDependency: SceneDependencyEdge?
        if let material = fields.removeValue(forKey: "material") {
            guard case let .string(reference) = material else {
                appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: "material")
                resources[id] = .model(
                    SceneModelResource(
                        id: id,
                        path: asset.canonicalPath,
                        materialDependency: nil,
                        unknownFields: fields
                    )
                )
                return
            }
            materialDependency = addDependency(
                owner: .resource(id),
                key: "material",
                request: SceneAssetRequest(
                    requestedPath: reference,
                    ownerPath: asset.canonicalPath,
                    role: .material,
                    key: "material"
                ),
                sourcePath: asset.canonicalPath,
                nodeID: nil,
                jsonPath: "material"
            )
        } else {
            materialDependency = nil
        }

        resources[id] = .model(
            SceneModelResource(
                id: id,
                path: asset.canonicalPath,
                materialDependency: materialDependency,
                unknownFields: fields
            )
        )
        if let materialDependency,
           materialDependency.resolution.kind == .unresolved
                || materialDependency.resolution.kind == .invalid {
            appendDiagnostic(
                severity: .warning,
                code: "graph.unresolved-material",
                sourcePath: asset.canonicalPath,
                nodeID: nil,
                jsonPath: "material",
                arguments: [materialDependency.request.requestedPath],
                status: .unsupported
            )
        }
        guard let materialDependency,
              case .package = materialDependency.resolution.kind,
              let material = materialDependency.resolution.selected,
              !stopped else {
            return
        }
        followMaterial(material)
    }

    private mutating func followMaterial(_ asset: SceneResolvedAsset) {
        let cacheKey = SceneGraphResourceCacheKey(role: .material, path: asset.canonicalPath)
        guard parsedDocuments.insert(cacheKey).inserted, !stopped else {
            return
        }
        guard let object = readJSONObject(asset) else {
            return
        }

        let id = SceneResourceID(kind: .material, path: asset.canonicalPath)
        var fields = object
        let rawPasses = fields.removeValue(forKey: "passes")
        var passes: [SceneMaterialPass] = []

        if let rawPasses {
            guard case let .array(values) = rawPasses else {
                appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: "passes")
                resources[id] = .material(
                    SceneMaterialResource(
                        id: id,
                        path: asset.canonicalPath,
                        passes: passes,
                        unknownFields: fields
                    )
                )
                return
            }
            for value in values where !stopped {
                let index = passes.count
                switch value {
                case let .object(pass):
                    passes.append(parsePass(
                        pass,
                        index: index,
                        materialID: id,
                        sourcePath: asset.canonicalPath,
                        documentDependency: nil
                    ))
                case let .string(reference):
                    passes.append(parseReferencedPass(
                        reference,
                        index: index,
                        materialID: id,
                        ownerPath: asset.canonicalPath
                    ))
                default:
                    appendInvalidProperty(
                        sourcePath: asset.canonicalPath,
                        jsonPath: "passes[\(index)]"
                    )
                }
            }
        }

        var topLevelBindings: [String: SceneJSONValue] = [:]
        if let texture = fields.removeValue(forKey: "texture") {
            topLevelBindings["texture"] = texture
        }
        if let textures = fields.removeValue(forKey: "textures") {
            topLevelBindings["textures"] = textures
        }
        if !topLevelBindings.isEmpty, !stopped {
            passes.append(parsePass(
                topLevelBindings,
                index: passes.count,
                materialID: id,
                sourcePath: asset.canonicalPath,
                documentDependency: nil
            ))
        }

        resources[id] = .material(
            SceneMaterialResource(
                id: id,
                path: asset.canonicalPath,
                passes: passes,
                unknownFields: fields
            )
        )
    }

    private mutating func parseReferencedPass(
        _ reference: String,
        index: Int,
        materialID: SceneResourceID,
        ownerPath: SceneVirtualPath
    ) -> SceneMaterialPass {
        let request = SceneAssetRequest(
            requestedPath: reference,
            ownerPath: ownerPath,
            role: .pass,
            key: "passes"
        )
        let edge = addDependency(
            owner: .materialPass(material: materialID, index: index),
            key: "passes",
            request: request,
            sourcePath: ownerPath,
            nodeID: nil,
            jsonPath: "passes[\(index)]"
        )
        guard let edge,
              case .package = edge.resolution.kind,
              let asset = edge.resolution.selected,
              let object = readPassDocument(asset) else {
            return SceneMaterialPass(
                index: index,
                sourcePath: edge?.resolution.selected?.canonicalPath,
                documentDependency: edge,
                shaderDependency: nil,
                textureBindings: [],
                effectDependencies: [],
                rawValue: .string(reference),
                unknownFields: [:]
            )
        }
        return parsePass(
            object,
            index: index,
            materialID: materialID,
            sourcePath: asset.canonicalPath,
            documentDependency: edge
        )
    }

    private mutating func parsePass(
        _ object: [String: SceneJSONValue],
        index: Int,
        materialID: SceneResourceID,
        sourcePath: SceneVirtualPath,
        documentDependency: SceneDependencyEdge?
    ) -> SceneMaterialPass {
        var fields = object
        let owner = SceneDependencyOwner.materialPass(material: materialID, index: index)
        let shaderDependency = parseSingleReference(
            key: "shader",
            role: .shader,
            from: &fields,
            owner: owner,
            sourcePath: sourcePath,
            jsonPath: "shader"
        )
        if let shaderDependency,
           let asset = shaderDependency.resolution.selected,
           shaderDependency.resolution.kind == .package
                || shaderDependency.resolution.kind == .builtInCandidate {
            let id = SceneResourceID(kind: .shader, path: asset.canonicalPath)
            resources[id] = .shader(SceneShaderResource(id: id, path: asset.canonicalPath, resolution: shaderDependency.resolution))
        }

        var textureBindings: [SceneTextureBinding] = []
        if let texture = fields.removeValue(forKey: "texture") {
            textureBindings.append(contentsOf: parseTextureBindings(
                texture,
                owner: owner,
                sourcePath: sourcePath,
                jsonPath: "texture"
            ))
        }
        if let textures = fields.removeValue(forKey: "textures") {
            let values: [SceneJSONValue]
            if case let .array(array) = textures {
                values = array
            } else {
                values = [textures]
            }
            for (bindingIndex, value) in values.enumerated() where !stopped {
                textureBindings.append(contentsOf: parseTextureBindings(
                    value,
                    owner: owner,
                    sourcePath: sourcePath,
                    jsonPath: "textures[\(bindingIndex)]"
                ))
            }
        }

        var effectDependencies: [SceneDependencyEdge] = []
        if let effect = parseSingleReference(
            key: "effect",
            role: .effect,
            from: &fields,
            owner: owner,
            sourcePath: sourcePath,
            jsonPath: "effect"
        ) {
            effectDependencies.append(effect)
        }
        if let effects = fields.removeValue(forKey: "effects") {
            let values: [SceneJSONValue]
            if case let .array(array) = effects {
                values = array
            } else {
                values = [effects]
            }
            for (effectIndex, value) in values.enumerated() where !stopped {
                guard case let .string(reference) = value else {
                    appendInvalidProperty(
                        sourcePath: sourcePath,
                        jsonPath: "effects[\(effectIndex)]"
                    )
                    continue
                }
                if let edge = addDependency(
                    owner: owner,
                    key: "effects",
                    request: SceneAssetRequest(
                        requestedPath: reference,
                        ownerPath: sourcePath,
                        role: .effect,
                        key: "effects"
                    ),
                    sourcePath: sourcePath,
                    nodeID: nil,
                    jsonPath: "effects[\(effectIndex)]"
                ) {
                    effectDependencies.append(edge)
                }
            }
        }

        return SceneMaterialPass(
            index: index,
            sourcePath: sourcePath,
            documentDependency: documentDependency,
            shaderDependency: shaderDependency,
            textureBindings: textureBindings,
            effectDependencies: effectDependencies,
            rawValue: .object(object),
            unknownFields: fields
        )
    }

    private mutating func parseTextureBindings(
        _ value: SceneJSONValue,
        owner: SceneDependencyOwner,
        sourcePath: SceneVirtualPath,
        jsonPath: String
    ) -> [SceneTextureBinding] {
        let binding: (reference: String, slot: String?)
        switch value {
        case let .string(reference):
            binding = (reference, nil)
        case let .object(object):
            let reference: String?
            if case let .string(value)? = object["texture"] {
                reference = value
            } else if case let .string(value)? = object["file"] {
                reference = value
            } else {
                reference = nil
            }
            guard let reference else {
                appendInvalidProperty(sourcePath: sourcePath, jsonPath: jsonPath)
                return []
            }
            let slot: String?
            if case let .string(value)? = object["slot"] {
                slot = value
            } else {
                slot = nil
            }
            binding = (reference, slot)
        default:
            appendInvalidProperty(sourcePath: sourcePath, jsonPath: jsonPath)
            return []
        }

        let request = SceneAssetRequest(
            requestedPath: binding.reference,
            ownerPath: sourcePath,
            role: .texture,
            key: "texture"
        )
        guard let edge = addDependency(
            owner: owner,
            key: "texture",
            request: request,
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: jsonPath
        ) else {
            return []
        }
        if edge.resolution.kind == .package,
           let asset = edge.resolution.selected {
            let id = SceneResourceID(kind: .texture, path: asset.canonicalPath)
            resources[id] = .texture(
                SceneTextureResource(id: id, path: asset.canonicalPath, resolution: edge.resolution)
            )
        } else if edge.resolution.kind == .unresolved || edge.resolution.kind == .invalid {
            appendDiagnostic(
                severity: .warning,
                code: "graph.unresolved-texture",
                sourcePath: sourcePath,
                nodeID: nil,
                jsonPath: jsonPath,
                arguments: [binding.reference],
                status: .unsupported
            )
        }
        return [SceneTextureBinding(slot: binding.slot, rawValue: value, dependency: edge)]
    }

    private mutating func parseSingleReference(
        key: String,
        role: SceneAssetRole,
        from fields: inout [String: SceneJSONValue],
        owner: SceneDependencyOwner,
        sourcePath: SceneVirtualPath,
        jsonPath: String
    ) -> SceneDependencyEdge? {
        guard let value = fields.removeValue(forKey: key) else {
            return nil
        }
        guard case let .string(reference) = value else {
            appendInvalidProperty(sourcePath: sourcePath, jsonPath: jsonPath)
            return nil
        }
        return addDependency(
            owner: owner,
            key: key,
            request: SceneAssetRequest(
                requestedPath: reference,
                ownerPath: sourcePath,
                role: role,
                key: key
            ),
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: jsonPath
        )
    }

    private mutating func addDependency(
        owner: SceneDependencyOwner,
        key: String,
        request: SceneAssetRequest,
        sourcePath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String
    ) -> SceneDependencyEdge? {
        guard !stopped else {
            return nil
        }
        let resolution = resolver.resolve(request)
        appendResolutionDiagnostics(
            resolution,
            sourcePath: sourcePath,
            nodeID: nodeID,
            jsonPath: jsonPath
        )
        guard dependencies.count < limits.maximumDependencyEdgeCount else {
            appendResourceLimit(sourcePath: sourcePath)
            return nil
        }
        let edge = SceneDependencyEdge(
            owner: owner,
            key: key,
            request: request,
            resolution: resolution
        )
        dependencies.append(edge)
        return edge
    }

    private mutating func readJSONObject(
        _ asset: SceneResolvedAsset
    ) -> [String: SceneJSONValue]? {
        guard case let .package(identity) = asset.provenance else {
            return nil
        }
        guard identity.byteCount <= limits.maximumJSONEntryBytes else {
            appendResourceLimit(sourcePath: asset.canonicalPath)
            return nil
        }
        let (next, overflow) = cumulativeJSONBytes.addingReportingOverflow(identity.byteCount)
        guard !overflow, next <= limits.maximumCumulativeJSONBytes else {
            appendResourceLimit(sourcePath: asset.canonicalPath)
            return nil
        }
        let data: Data
        do {
            data = try resolver.read(asset, maximumBytes: limits.maximumJSONEntryBytes)
        } catch {
            appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: nil)
            return nil
        }
        cumulativeJSONBytes = next
        do {
            guard case let .object(object) = try SceneJSONDocumentDecoder(
                maximumDepth: limits.maximumJSONDepth
            ).decode(data) else {
                appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: nil)
                return nil
            }
            return object
        } catch {
            appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: nil)
            return nil
        }
    }

    private mutating func readPassDocument(
        _ asset: SceneResolvedAsset
    ) -> [String: SceneJSONValue]? {
        let key = SceneGraphResourceCacheKey(role: .pass, path: asset.canonicalPath)
        if let cached = parsedPassDocuments[key] {
            return cached.object
        }
        let document = SceneGraphPassDocument(object: readJSONObject(asset))
        parsedPassDocuments[key] = document
        return document.object
    }

    private mutating func appendResolutionDiagnostics(
        _ resolution: SceneAssetResolution,
        sourcePath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String
    ) {
        for issue in resolution.issues {
            switch issue {
            case .invalidReference, .candidateLimit:
                appendDiagnostic(
                    severity: .warning,
                    code: "asset.invalid-reference",
                    sourcePath: sourcePath,
                    nodeID: nodeID,
                    jsonPath: jsonPath,
                    arguments: [resolution.request.requestedPath],
                    status: .unsupported
                )
            case .pathEscape:
                appendDiagnostic(
                    severity: .warning,
                    code: "asset.path-escape",
                    sourcePath: sourcePath,
                    nodeID: nodeID,
                    jsonPath: jsonPath,
                    arguments: [resolution.request.requestedPath],
                    status: .unsupported
                )
            case let .ambiguous(selected, alternatives):
                appendDiagnostic(
                    severity: .warning,
                    code: "asset.ambiguous-resolution",
                    sourcePath: sourcePath,
                    nodeID: nodeID,
                    jsonPath: jsonPath,
                    arguments: [selected.rawValue] + alternatives.map(\.rawValue),
                    status: .unsupported
                )
            }
        }
        switch resolution.kind {
        case .builtInCandidate:
            appendDiagnostic(
                severity: .warning,
                code: "asset.builtin-candidate",
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: jsonPath,
                arguments: [resolution.request.requestedPath],
                status: .unsupported
            )
        case .externalCandidate:
            appendDiagnostic(
                severity: .warning,
                code: "asset.external-candidate",
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: jsonPath,
                arguments: [resolution.request.requestedPath],
                status: .unsupported
            )
        case .unresolved:
            appendDiagnostic(
                severity: .warning,
                code: "asset.unresolved",
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: jsonPath,
                arguments: [resolution.request.requestedPath],
                status: .unsupported
            )
        default:
            break
        }
    }

    private mutating func appendInvalidProperty(
        sourcePath: SceneVirtualPath,
        jsonPath: String?
    ) {
        appendDiagnostic(
            severity: .warning,
            code: "graph.invalid-property",
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: jsonPath,
            arguments: [],
            status: .unsupported
        )
    }

    private mutating func appendResourceLimit(sourcePath: SceneVirtualPath) {
        guard !stopped else {
            return
        }
        stopped = true
        appendDiagnostic(
            severity: .error,
            code: "graph.resource-limit",
            sourcePath: sourcePath,
            nodeID: nil,
            jsonPath: nil,
            arguments: [],
            status: .invalid
        )
    }

    private mutating func appendDiagnostic(
        severity: SceneGraphDiagnosticSeverity,
        code: String,
        sourcePath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String?,
        arguments: [String],
        status: SceneGraphStatus
    ) {
        diagnostics.append(
            SceneGraphParserDiagnostic(
                severity: severity,
                code: code,
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: jsonPath,
                arguments: arguments,
                status: status
            )
        )
    }
}

private struct SceneGraphResourceCacheKey: Hashable, Sendable {
    let role: SceneAssetRole
    let path: SceneVirtualPath
}

private struct SceneGraphPassDocument: Sendable {
    let object: [String: SceneJSONValue]?
}
