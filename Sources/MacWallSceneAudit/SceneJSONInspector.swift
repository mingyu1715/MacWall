import Foundation
import MacWallSceneAssets

struct SceneJSONAuditEvidence: Sendable {
    var canvas: SceneAuditCanvas?
    var objectKinds: [String: Int] = [:]
    var featureCounts: [SceneAuditFeatureKey: Int] = [:]
    var dependencies: [SceneAuditDependency] = []
    var scriptHandlers: [String: Int] = [:]
    var diagnostics: [SceneAuditDiagnostic] = []
}

struct SceneJSONInspector: Sendable {
    private static let assetReferenceRoles: [String: SceneAssetRole] = [
        "effect": .effect,
        "file": .document,
        "font": .font,
        "image": .model,
        "material": .material,
        "model": .model,
        "particle": .particle,
        "shader": .shader,
        "sound": .sound,
        "texture": .texture,
        "textures": .texture
    ]

    func inspect(
        scene: [String: Any],
        documents: [String: Any],
        resolver: ScenePackageAssetResolver
    ) -> SceneJSONAuditEvidence {
        var evidence = SceneJSONAuditEvidence()
        evidence.canvas = canvas(from: scene)
        inspectObjects(in: scene, evidence: &evidence)

        for ownerPath in documents.keys.sorted() {
            guard let document = documents[ownerPath] else {
                continue
            }
            inspectDocument(
                document,
                ownerPath: ownerPath,
                resolver: resolver,
                evidence: &evidence
            )
        }
        evidence.featureCounts[.unresolvedAsset] =
            evidence.dependencies.filter {
                $0.resolution == .unresolved
            }.count
        return evidence
    }

    private func canvas(
        from scene: [String: Any]
    ) -> SceneAuditCanvas? {
        guard let general = scene["general"] as? [String: Any],
              let projection =
                general["orthogonalprojection"] as? [String: Any],
              let width = projection["width"] as? Int,
              let height = projection["height"] as? Int else {
            return nil
        }
        return SceneAuditCanvas(width: width, height: height)
    }

    private func inspectObjects(
        in scene: [String: Any],
        evidence: inout SceneJSONAuditEvidence
    ) {
        guard let objects = scene["objects"] as? [Any] else {
            return
        }
        for value in objects {
            guard let object = value as? [String: Any] else {
                continue
            }
            let classification = classify(object)
            evidence.objectKinds[
                classification.name,
                default: 0
            ] += 1
            evidence.featureCounts[
                classification.feature,
                default: 0
            ] += 1

            if object["parent"] != nil {
                evidence.featureCounts[
                    .parentGraph,
                    default: 0
                ] += 1
            }
            if object["instance"] != nil
                || object["instanceoverride"] != nil {
                evidence.featureCounts[
                    .instance,
                    default: 0
                ] += 1
            }
            if containsAnimation(object) {
                evidence.featureCounts[
                    .animatedProperty,
                    default: 0
                ] += 1
            }
        }
    }

    private func classify(
        _ object: [String: Any]
    ) -> (name: String, feature: SceneAuditFeatureKey) {
        if object["image"] != nil {
            return ("image", .imageLayer)
        }
        if object["text"] != nil {
            return ("text", .textLayer)
        }
        if object["particle"] != nil {
            return ("particle", .particleSystem)
        }
        if object["sound"] != nil {
            return ("sound", .soundLayer)
        }
        if object["model"] != nil {
            return ("model", .modelLayer)
        }
        return ("unknown", .unknownObject)
    }

    private func containsAnimation(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if dictionary["animation"] != nil {
                return true
            }
            return dictionary.values.contains(
                where: containsAnimation
            )
        }
        if let array = value as? [Any] {
            return array.contains(where: containsAnimation)
        }
        return false
    }

    private func inspectDocument(
        _ value: Any,
        ownerPath: String,
        resolver: ScenePackageAssetResolver,
        evidence: inout SceneJSONAuditEvidence
    ) {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                guard let child = dictionary[key] else {
                    continue
                }
                if key == "script", let script = child as? String {
                    evidence.featureCounts[
                        .sceneScript,
                        default: 0
                    ] += 1
                    addScriptHandlers(
                        from: script,
                        to: &evidence.scriptHandlers
                    )
                }
                if let role = Self.assetReferenceRoles[key] {
                    let references = assetReferences(
                        for: key,
                        value: child
                    )
                    evidence.dependencies.append(
                        contentsOf: references.map {
                            resolve(
                                requestedPath: $0,
                                ownerPath: ownerPath,
                                key: key,
                                role: role,
                                resolver: resolver
                            )
                        }
                    )
                }
                inspectDocument(
                    child,
                    ownerPath: ownerPath,
                    resolver: resolver,
                    evidence: &evidence
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                inspectDocument(
                    child,
                    ownerPath: ownerPath,
                    resolver: resolver,
                    evidence: &evidence
                )
            }
        }
    }

    private func assetReferences(
        for key: String,
        value: Any
    ) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if key == "textures", let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return []
    }

    private func resolve(
        requestedPath: String,
        ownerPath: String,
        key: String,
        role: SceneAssetRole,
        resolver: ScenePackageAssetResolver
    ) -> SceneAuditDependency {
        let request = SceneAssetRequest(
            requestedPath: requestedPath,
            ownerPath: try? SceneVirtualPath(
                canonicalPath: ownerPath
            ),
            role: role,
            key: key
        )
        let resolution = resolver.resolve(request)
        switch resolution.kind {
        case .package:
            return SceneAuditDependency(
                ownerPath: ownerPath,
                key: key,
                requestedPath: requestedPath,
                resolvedPath: resolution.selected?.canonicalPath.rawValue,
                resolution: .package
            )
        case .builtInCandidate:
            return SceneAuditDependency(
                ownerPath: ownerPath,
                key: key,
                requestedPath: requestedPath,
                resolvedPath: nil,
                resolution: .builtInCandidate
            )
        case .externalCandidate:
            return SceneAuditDependency(
                ownerPath: ownerPath,
                key: key,
                requestedPath: requestedPath,
                resolvedPath: nil,
                resolution: .externalCandidate
            )
        case .unresolved, .invalid:
            return SceneAuditDependency(
                ownerPath: ownerPath,
                key: key,
                requestedPath: requestedPath,
                resolvedPath: nil,
                resolution: .unresolved
            )
        }
    }

    private func addScriptHandlers(
        from script: String,
        to counts: inout [String: Int]
    ) {
        let pattern =
            #"(?:export\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return
        }
        let range = NSRange(
            script.startIndex..<script.endIndex,
            in: script
        )
        for match in expression.matches(
            in: script,
            range: range
        ) {
            guard match.numberOfRanges > 1,
                  let handlerRange = Range(
                      match.range(at: 1),
                      in: script
                  ) else {
                continue
            }
            counts[
                String(script[handlerRange]),
                default: 0
            ] += 1
        }
    }
}
