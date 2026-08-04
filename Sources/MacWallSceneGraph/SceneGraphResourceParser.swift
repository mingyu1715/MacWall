import Foundation
import MacWallSceneAssets

struct SceneGraphResourceParseResult: Sendable {
    let resources: [SceneGraphResource]
    let dependencies: [SceneDependencyEdge]
    let scripts: [SceneScriptMetadata]
    let diagnostics: [SceneGraphParserDiagnostic]
}

struct SceneGraphResourceParser: Sendable {
    private let resolver: ScenePackageAssetResolver
    private let limits: SceneGraphLimits
    private var cumulativeJSONBytes: UInt64
    private var resources: [SceneResourceID: SceneGraphResource] = [:]
    private var dependencies: [SceneDependencyEdge] = []
    private var dependencyKeys: Set<SceneGraphDependencyKey> = []
    private var dependencyEdges: [SceneGraphDependencyKey: SceneDependencyEdge] = [:]
    private var scripts: [SceneScriptMetadata] = []
    private var scriptKeys: Set<SceneGraphScriptKey> = []
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

    mutating func parse(
        root: [String: SceneJSONValue],
        sourcePath: SceneVirtualPath,
        nodes: [SceneGraphNode]
    ) -> SceneGraphResourceParseResult {
        inspectMetadata(
            in: .object(root),
            sourcePath: sourcePath,
            defaultOwner: nil,
            rootNodeIDs: nodes.map(\.id)
        )
        for node in nodes where !stopped {
            parse(node: node)
        }

        return SceneGraphResourceParseResult(
            resources: resources.values.sorted { $0.id < $1.id },
            dependencies: dependencies,
            scripts: scripts.sorted(by: Self.scriptPrecedes),
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

        inspectMetadata(
            in: .object(object),
            sourcePath: asset.canonicalPath,
            defaultOwner: .resource(SceneResourceID(kind: .model, path: asset.canonicalPath)),
            rootNodeIDs: []
        )

        let id = SceneResourceID(kind: .model, path: asset.canonicalPath)
        var fields = object
        let materialDependency: SceneDependencyEdge?
        if let material = fields["material"] {
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
            fields.removeValue(forKey: "material")
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

        inspectMetadata(
            in: .object(object),
            sourcePath: asset.canonicalPath,
            defaultOwner: .resource(SceneResourceID(kind: .material, path: asset.canonicalPath)),
            rootNodeIDs: []
        )

        let id = SceneResourceID(kind: .material, path: asset.canonicalPath)
        var fields = object
        let rawPasses = fields["passes"]
        var passes: [SceneMaterialPass] = []
        var nextSyntheticPassIndex = 0

        if let rawPasses {
            if case let .array(values) = rawPasses {
                fields.removeValue(forKey: "passes")
                nextSyntheticPassIndex = values.count
                for (index, value) in values.enumerated() where !stopped {
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
            } else {
                appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: "passes")
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
                index: nextSyntheticPassIndex,
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
        if documentDependency != nil {
            inspectMetadata(
                in: .object(object),
                sourcePath: sourcePath,
                defaultOwner: owner,
                rootNodeIDs: []
            )
        }
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
            followEffectIfPackageResolved(effect)
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
                    followEffectIfPackageResolved(edge)
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
            if let rawSlot = object["slot"] {
                if case let .string(value) = rawSlot {
                    slot = value
                } else {
                    slot = nil
                    appendInvalidProperty(
                        sourcePath: sourcePath,
                        jsonPath: "\(jsonPath).slot"
                    )
                }
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
        let dependencyKey = SceneGraphDependencyKey(
            owner: owner,
            jsonPath: jsonPath,
            role: request.role,
            requestedPath: request.requestedPath
        )
        guard dependencyKeys.insert(dependencyKey).inserted else {
            return dependencyEdges[dependencyKey]
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
        dependencyEdges[dependencyKey] = edge
        return edge
    }

    private mutating func followEffectIfPackageResolved(_ edge: SceneDependencyEdge) {
        guard edge.request.role == .effect,
              edge.resolution.kind == .package,
              let asset = edge.resolution.selected,
              !stopped else {
            return
        }
        followEffect(asset)
    }

    private mutating func followEffect(_ asset: SceneResolvedAsset) {
        let cacheKey = SceneGraphResourceCacheKey(role: .effect, path: asset.canonicalPath)
        guard parsedDocuments.insert(cacheKey).inserted, !stopped else {
            return
        }

        let id = SceneResourceID(kind: .effect, path: asset.canonicalPath)
        appendDiagnostic(
            severity: .warning,
            code: "graph.unsupported-effect",
            sourcePath: asset.canonicalPath,
            nodeID: nil,
            jsonPath: nil,
            arguments: [],
            status: .unsupported
        )
        guard let object = readJSONObject(asset) else {
            resources[id] = .effect(SceneEffectResource(
                id: id,
                path: asset.canonicalPath,
                dependencies: [],
                unknownFields: [:]
            ))
            return
        }

        let effectDependencies = inspectMetadata(
            in: .object(object),
            sourcePath: asset.canonicalPath,
            defaultOwner: .resource(id),
            rootNodeIDs: []
        )
        resources[id] = .effect(SceneEffectResource(
            id: id,
            path: asset.canonicalPath,
            dependencies: effectDependencies,
            unknownFields: object
        ))
    }

    @discardableResult
    private mutating func inspectMetadata(
        in root: SceneJSONValue,
        sourcePath: SceneVirtualPath,
        defaultOwner: SceneDependencyOwner?,
        rootNodeIDs: [SceneNodeID]
    ) -> [SceneDependencyEdge] {
        var discoveredDependencies: [SceneDependencyEdge] = []
        var stack = [SceneGraphMetadataStackEntry(
            value: root,
            jsonPath: "$",
            owner: defaultOwner,
            nodeID: nil,
            parentKey: nil
        )]

        while let entry = stack.popLast(), !stopped {
            switch entry.value {
            case let .object(object):
                for key in object.keys.sorted() {
                    guard let value = object[key] else { continue }
                    let jsonPath = Self.jsonPath(entry.jsonPath, appending: key)
                    if key == "script", case let .string(source) = value {
                        preserveScript(
                            source,
                            ownerPath: sourcePath,
                            nodeID: entry.nodeID,
                            jsonPath: jsonPath
                        )
                    }
                    if let owner = entry.owner,
                       let role = Self.assetRole(for: key, parentKey: entry.parentKey),
                       !Self.isTypedMaterialTopLevelBinding(
                           key: key,
                           owner: owner,
                           jsonPath: entry.jsonPath
                       ) {
                        discoveredDependencies.append(contentsOf: inspectAssetReference(
                            value,
                            key: key,
                            role: role,
                            owner: owner,
                            sourcePath: sourcePath,
                            nodeID: entry.nodeID,
                            jsonPath: jsonPath
                        ))
                    }
                    stack.append(SceneGraphMetadataStackEntry(
                        value: Self.metadataContinuation(
                            afterConsumingTextureReferencesIn: value,
                            key: key,
                            parentKey: entry.parentKey
                        ),
                        jsonPath: jsonPath,
                        owner: entry.owner,
                        nodeID: entry.nodeID,
                        parentKey: key
                    ))
                }
            case let .array(values):
                for index in values.indices.reversed() {
                    let isRootObject = entry.jsonPath == "$.objects"
                    let nodeID = isRootObject ? rootNodeIDs[safe: index] : entry.nodeID
                    let owner: SceneDependencyOwner?
                    if let materialID = Self.materialID(for: entry.owner),
                       entry.jsonPath == "$.passes" {
                        owner = .materialPass(material: materialID, index: index)
                    } else {
                        owner = nodeID.map(SceneDependencyOwner.node) ?? entry.owner
                    }
                    stack.append(SceneGraphMetadataStackEntry(
                        value: values[index],
                        jsonPath: "\(entry.jsonPath)[\(index)]",
                        owner: owner,
                        nodeID: nodeID,
                        parentKey: entry.parentKey
                    ))
                }
            default:
                break
            }
        }
        return discoveredDependencies
    }

    private mutating func inspectAssetReference(
        _ value: SceneJSONValue,
        key: String,
        role: SceneAssetRole,
        owner: SceneDependencyOwner,
        sourcePath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String
    ) -> [SceneDependencyEdge] {
        let references = Self.assetReferences(in: value, role: role, jsonPath: jsonPath)
        var edges: [SceneDependencyEdge] = []
        for (referencePath, reference) in references where !stopped {
            let request = SceneAssetRequest(
                requestedPath: reference,
                ownerPath: sourcePath,
                role: role,
                key: key
            )
            guard let edge = addDependency(
                owner: owner,
                key: key,
                request: request,
                sourcePath: sourcePath,
                nodeID: nodeID,
                jsonPath: referencePath
            ) else {
                continue
            }
            edges.append(edge)
            recordResolvedResource(edge, sourcePath: sourcePath, jsonPath: referencePath)
        }
        return edges
    }

    private mutating func recordResolvedResource(
        _ edge: SceneDependencyEdge,
        sourcePath: SceneVirtualPath,
        jsonPath: String
    ) {
        guard let asset = edge.resolution.selected else {
            return
        }
        switch edge.request.role {
        case .model where edge.resolution.kind == .package:
            followModel(asset)
        case .material where edge.resolution.kind == .package:
            followMaterial(asset)
        case .effect where edge.resolution.kind == .package:
            followEffect(asset)
        case .shader where edge.resolution.kind == .package || edge.resolution.kind == .builtInCandidate:
            let id = SceneResourceID(kind: .shader, path: asset.canonicalPath)
            if resources[id] == nil {
                resources[id] = .shader(SceneShaderResource(
                    id: id,
                    path: asset.canonicalPath,
                    resolution: edge.resolution
                ))
                if edge.resolution.kind == .package {
                    appendDiagnostic(
                        severity: .warning,
                        code: "graph.unsupported-shader",
                        sourcePath: sourcePath,
                        nodeID: nil,
                        jsonPath: jsonPath,
                        arguments: [edge.request.requestedPath],
                        status: .unsupported
                    )
                }
            }
        case .texture where edge.resolution.kind == .package:
            let id = SceneResourceID(kind: .texture, path: asset.canonicalPath)
            resources[id] = .texture(SceneTextureResource(
                id: id,
                path: asset.canonicalPath,
                resolution: edge.resolution
            ))
        default:
            break
        }
    }

    private static func assetRole(for key: String, parentKey: String?) -> SceneAssetRole? {
        switch key {
        case "image", "model":
            .model
        case "material":
            .material
        case "effect":
            .effect
        case "file":
            parentKey == "texture" || parentKey == "textures" ? .texture : .document
        case "font":
            .font
        case "particle":
            .particle
        case "shader":
            .shader
        case "sound":
            .sound
        case "texture", "textures":
            .texture
        default:
            nil
        }
    }

    private static func isTypedMaterialTopLevelBinding(
        key: String,
        owner: SceneDependencyOwner,
        jsonPath: String
    ) -> Bool {
        materialID(for: owner) != nil
            && jsonPath == "$"
            && (key == "texture" || key == "textures")
    }

    private static func materialID(for owner: SceneDependencyOwner?) -> SceneResourceID? {
        guard case let .resource(resourceID)? = owner,
              resourceID.kind == .material else {
            return nil
        }
        return resourceID
    }

    private static func metadataContinuation(
        afterConsumingTextureReferencesIn value: SceneJSONValue,
        key: String,
        parentKey: String?
    ) -> SceneJSONValue {
        guard let role = assetRole(for: key, parentKey: parentKey), role == .texture else {
            return value
        }
        switch value {
        case let .object(object):
            return .object(removingConsumedTextureReferenceFields(from: object))
        case let .array(values):
            return .array(values.map { element in
                guard case let .object(object) = element else {
                    return element
                }
                return .object(removingConsumedTextureReferenceFields(from: object))
            })
        default:
            return value
        }
    }

    private static func removingConsumedTextureReferenceFields(
        from object: [String: SceneJSONValue]
    ) -> [String: SceneJSONValue] {
        guard !assetReferences(in: .object(object), role: .texture).isEmpty else {
            return object
        }
        var continuation = object
        continuation.removeValue(forKey: "texture")
        continuation.removeValue(forKey: "file")
        return continuation
    }

    private static func assetReferences(
        in value: SceneJSONValue,
        role: SceneAssetRole,
        jsonPath: String = ""
    ) -> [(String, String)] {
        switch value {
        case let .string(reference):
            [(jsonPath, reference)]
        case let .array(values):
            values.enumerated().flatMap { index, element in
                assetReferences(
                    in: element,
                    role: role,
                    jsonPath: "\(jsonPath)[\(index)]"
                )
            }
        case let .object(object) where role == .texture:
            if case let .string(reference)? = object["texture"] {
                [(jsonPath, reference)]
            } else if case let .string(reference)? = object["file"] {
                [(jsonPath, reference)]
            } else {
                []
            }
        default:
            []
        }
    }

    private static func jsonPath(_ base: String, appending key: String) -> String {
        "\(base).\(key)"
    }

    private static func handlerNames(in source: String) -> [String] {
        let scalars = Array(source.unicodeScalars)
        var names: Set<String> = []
        var index = 0
        var isInString: Unicode.Scalar?
        var isLineComment = false
        var isBlockComment = false

        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if let quote = isInString {
                if scalar == "\\" {
                    index += 2
                    continue
                }
                if scalar == quote {
                    isInString = nil
                }
                index += 1
                continue
            }
            if isLineComment {
                if scalar == "\n" || scalar == "\r" {
                    isLineComment = false
                }
                index += 1
                continue
            }
            if isBlockComment {
                if scalar == "*", next == "/" {
                    isBlockComment = false
                    index += 2
                    continue
                }
                index += 1
                continue
            }
            if scalar == "/", next == "/" {
                isLineComment = true
                index += 2
                continue
            }
            if scalar == "/", next == "*" {
                isBlockComment = true
                index += 2
                continue
            }
            if scalar == "\"" || scalar == "'" || scalar == "`" {
                isInString = scalar
                index += 1
                continue
            }
            if Self.isIdentifierStart(scalar),
               Self.matches("function", in: scalars, at: index) {
                var cursor = index + "function".unicodeScalars.count
                while cursor < scalars.count, Self.isWhitespace(scalars[cursor]) {
                    cursor += 1
                }
                if cursor < scalars.count, scalars[cursor] == "*" {
                    cursor += 1
                    while cursor < scalars.count, Self.isWhitespace(scalars[cursor]) {
                        cursor += 1
                    }
                }
                guard cursor < scalars.count, Self.isIdentifierStart(scalars[cursor]) else {
                    index += 1
                    continue
                }
                let nameStart = cursor
                cursor += 1
                while cursor < scalars.count, Self.isIdentifierContinue(scalars[cursor]) {
                    cursor += 1
                }
                let name = String(String.UnicodeScalarView(scalars[nameStart..<cursor]))
                names.insert(name)
                index = cursor
                continue
            }
            index += 1
        }
        return names.sorted()
    }

    private static func matches(
        _ keyword: String,
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        let keywordScalars = Array(keyword.unicodeScalars)
        guard index + keywordScalars.count <= scalars.count,
              scalars[index..<(index + keywordScalars.count)].elementsEqual(keywordScalars) else {
            return false
        }
        let before = index > 0 ? scalars[index - 1] : nil
        let afterIndex = index + keywordScalars.count
        let after = afterIndex < scalars.count ? scalars[afterIndex] : nil
        return !(before.map(Self.isIdentifierContinue) ?? false)
            && !(after.map(Self.isIdentifierContinue) ?? false)
    }

    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "$" || scalar.properties.isAlphabetic
    }

    private static func isIdentifierContinue(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStart(scalar) || scalar.properties.numericType != nil
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    private static func scriptPrecedes(
        _ first: SceneScriptMetadata,
        _ second: SceneScriptMetadata
    ) -> Bool {
        if first.ownerPath != second.ownerPath {
            return first.ownerPath.rawValue < second.ownerPath.rawValue
        }
        if first.nodeID != second.nodeID {
            return (first.nodeID?.rawValue ?? "") < (second.nodeID?.rawValue ?? "")
        }
        return first.jsonPath < second.jsonPath
    }

    private mutating func preserveScript(
        _ source: String,
        ownerPath: SceneVirtualPath,
        nodeID: SceneNodeID?,
        jsonPath: String
    ) {
        let key = SceneGraphScriptKey(ownerPath: ownerPath, nodeID: nodeID, jsonPath: jsonPath)
        guard scriptKeys.insert(key).inserted else {
            return
        }
        scripts.append(SceneScriptMetadata(
            ownerPath: ownerPath,
            nodeID: nodeID,
            jsonPath: jsonPath,
            source: source,
            handlerNames: Self.handlerNames(in: source)
        ))
        appendDiagnostic(
            severity: .warning,
            code: "graph.scenescript-preserved-not-executed",
            sourcePath: ownerPath,
            nodeID: nodeID,
            jsonPath: jsonPath,
            arguments: [],
            status: .unsupported
        )
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
        cumulativeJSONBytes = next
        let data: Data
        do {
            data = try resolver.read(asset, maximumBytes: limits.maximumJSONEntryBytes)
        } catch {
            appendInvalidProperty(sourcePath: asset.canonicalPath, jsonPath: nil)
            return nil
        }
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

private struct SceneGraphDependencyKey: Hashable, Sendable {
    let owner: String
    let jsonPath: String
    let role: SceneAssetRole
    let requestedPath: String

    init(
        owner: SceneDependencyOwner,
        jsonPath: String,
        role: SceneAssetRole,
        requestedPath: String
    ) {
        switch owner {
        case let .node(nodeID):
            self.owner = "node:\(nodeID.rawValue)"
        case let .resource(resourceID):
            self.owner = "resource:\(resourceID.rawValue)"
        case let .materialPass(materialID, index):
            self.owner = "pass:\(materialID.rawValue):\(index)"
        }
        let normalizedPath = jsonPath.hasPrefix("$.")
            ? String(jsonPath.dropFirst(2))
            : jsonPath
        if case .materialPass = owner,
           normalizedPath.hasPrefix("passes["),
           let passPathEnd = normalizedPath.firstIndex(of: "]") {
            self.jsonPath = String(normalizedPath[normalizedPath.index(after: passPathEnd)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        } else {
            self.jsonPath = normalizedPath
        }
        self.role = role
        self.requestedPath = requestedPath
    }
}

private struct SceneGraphScriptKey: Hashable, Sendable {
    let ownerPath: SceneVirtualPath
    let nodeID: SceneNodeID?
    let jsonPath: String
}

private struct SceneGraphMetadataStackEntry: Sendable {
    let value: SceneJSONValue
    let jsonPath: String
    let owner: SceneDependencyOwner?
    let nodeID: SceneNodeID?
    let parentKey: String?
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct SceneGraphPassDocument: Sendable {
    let object: [String: SceneJSONValue]?
}
