import Foundation

public struct SceneAuditor: Sendable {
    private let packageReader: ScenePackageReader
    private let textureReader: SceneTextureMetadataReader
    private let supportPolicy: SceneAuditSupportPolicy

    public init(
        packageReader: ScenePackageReader = ScenePackageReader(),
        textureReader: SceneTextureMetadataReader = SceneTextureMetadataReader(),
        supportPolicy: SceneAuditSupportPolicy = .s0
    ) {
        self.packageReader = packageReader
        self.textureReader = textureReader
        self.supportPolicy = supportPolicy
    }

    public func audit(url: URL) -> SceneAuditReport {
        do {
            return try audit(package: packageReader.read(url: url))
        } catch {
            return invalidReport(for: error)
        }
    }

    private func audit(package: ScenePackage) throws -> SceneAuditReport {
        guard package.entry(named: "scene.json") != nil else {
            throw ScenePackageError.missingSceneJSON
        }

        var documents: [String: Any] = [:]
        var scene: [String: Any]?
        var diagnostics: [SceneAuditDiagnostic] = []
        for entry in package.entries
            .filter({ Self.entryKind(for: $0.path) == "json" })
            .sorted(by: { $0.path < $1.path }) {
            do {
                let document = try JSONSerialization.jsonObject(
                    with: package.data(for: entry)
                )
                if entry.path == "scene.json" {
                    guard let dictionary = document as? [String: Any] else {
                        throw ScenePackageError.malformedSceneJSON
                    }
                    scene = dictionary
                }
                documents[entry.path] = document
            } catch {
                if entry.path == "scene.json" {
                    throw ScenePackageError.malformedSceneJSON
                }
                diagnostics.append(
                    SceneAuditDiagnostic(
                        severity: .warning,
                        code: "json.malformed",
                        path: entry.path,
                        message: "Packaged JSON could not be inspected."
                    )
                )
            }
        }
        guard let scene else {
            throw ScenePackageError.malformedSceneJSON
        }

        let evidence = SceneJSONInspector().inspect(
            scene: scene,
            documents: documents,
            package: package
        )
        diagnostics.append(contentsOf: evidence.diagnostics)

        var textures: [SceneAuditTextureSummary] = []
        var featureAccumulator = SceneAuditFeatureAccumulator()
        featureAccumulator.add(key: .packageIndex, count: 1, support: .exact)
        for (key, count) in evidence.featureCounts {
            featureAccumulator.add(
                key: key,
                count: count,
                support: Self.support(for: key)
            )
        }

        let textureEntries = package.entries
            .filter { Self.entryKind(for: $0.path) == "texture" }
            .sorted { $0.path < $1.path }
        for entry in textureEntries {
            do {
                let texture = try textureReader.read(
                    path: entry.path,
                    data: package.data(for: entry)
                )
                textures.append(texture)
                featureAccumulator.add(
                    key: .textureMetadata,
                    count: 1,
                    support: .exact
                )
                if texture.flagsRawValue & 4 != 0 {
                    featureAccumulator.add(
                        key: .animatedTexture,
                        count: 1,
                        support: .unsupported
                    )
                }
                if texture.flagsRawValue & 32 != 0 || texture.isVideoMP4 {
                    featureAccumulator.add(
                        key: .videoTexture,
                        count: 1,
                        support: .unsupported
                    )
                }
            } catch {
                featureAccumulator.add(
                    key: .textureMetadata,
                    count: 1,
                    support: .unknown
                )
                diagnostics.append(
                    SceneAuditDiagnostic(
                        severity: .warning,
                        code: "texture.metadata-invalid",
                        path: entry.path,
                        message: "Texture metadata could not be inspected."
                    )
                )
            }
        }

        let effectCount = package.entries.filter {
            let path = $0.path.lowercased()
            return path.hasPrefix("effects/")
                && path.hasSuffix(".json")
        }.count
        featureAccumulator.add(
            key: .effect,
            count: effectCount,
            support: .unsupported
        )

        let customShaderCount = package.entries.filter {
            let kind = Self.entryKind(for: $0.path)
            return kind == "vertexShader" || kind == "fragmentShader"
        }.count
        featureAccumulator.add(
            key: .customShader,
            count: customShaderCount,
            support: .unsupported
        )

        let features = featureAccumulator.observations
        let status = supportPolicy.evaluate(
            features: features,
            diagnostics: diagnostics
        )
        return SceneAuditReport(
            package: SceneAuditPackageSummary(
                version: package.magic,
                entryCount: package.entries.count
            ),
            canvas: evidence.canvas,
            entryKinds: Self.entryKindCounts(for: package.entries),
            objectKinds: evidence.objectKinds.map {
                SceneAuditCount(name: $0.key, count: $0.value)
            },
            textures: textures,
            dependencies: evidence.dependencies,
            scriptHandlers: evidence.scriptHandlers.map {
                SceneAuditCount(name: $0.key, count: $0.value)
            },
            features: features,
            diagnostics: diagnostics,
            status: status
        )
    }

    private func invalidReport(for error: Error) -> SceneAuditReport {
        SceneAuditReport(
            package: SceneAuditPackageSummary(version: nil, entryCount: 0),
            canvas: nil,
            entryKinds: [],
            objectKinds: [],
            textures: [],
            dependencies: [],
            scriptHandlers: [],
            features: [],
            diagnostics: [
                SceneAuditDiagnostic(
                    severity: .error,
                    code: Self.stableCode(for: error),
                    path: nil,
                    message: "Scene package audit failed."
                )
            ],
            status: .invalid
        )
    }

    private static func entryKindCounts(
        for entries: [ScenePackageEntry]
    ) -> [SceneAuditCount] {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entryKind(for: entry.path), default: 0] += 1
        }
        return counts.map { SceneAuditCount(name: $0.key, count: $0.value) }
    }

    private static func entryKind(for path: String) -> String {
        switch URL(filePath: path).pathExtension.lowercased() {
        case "json":
            return "json"
        case "tex":
            return "texture"
        case "vert":
            return "vertexShader"
        case "frag":
            return "fragmentShader"
        case "ttf", "otf":
            return "font"
        case "mp3", "wav", "ogg", "m4a", "aac", "flac":
            return "audio"
        case "mp4", "mov", "webm", "m4v":
            return "video"
        default:
            return "other"
        }
    }

    private static func support(
        for key: SceneAuditFeatureKey
    ) -> SceneAuditFeatureSupport {
        switch key {
        case .packageIndex, .textureMetadata:
            return .exact
        case .imageLayer, .animatedProperty:
            return .degraded
        case .textLayer,
             .particleSystem,
             .soundLayer,
             .modelLayer,
             .unknownObject,
             .parentGraph,
             .instance,
             .animatedTexture,
             .videoTexture,
             .effect,
             .customShader,
             .sceneScript,
             .unresolvedAsset:
            return .unsupported
        }
    }

    private static func stableCode(for error: Error) -> String {
        guard let error = error as? ScenePackageError else {
            return "package.io"
        }
        switch error {
        case .unsupportedMagic:
            return "package.unsupported-magic"
        case .packageTooLarge:
            return "package.too-large"
        case .invalidEntryCount:
            return "package.invalid-entry-count"
        case .invalidStringLength:
            return "package.invalid-string-length"
        case .truncatedPackage:
            return "package.truncated"
        case .unsafeEntryPath:
            return "package.unsafe-entry-path"
        case .invalidEntryRange:
            return "package.invalid-entry-range"
        case .missingSceneJSON:
            return "scene.missing-json"
        case .malformedSceneJSON:
            return "scene.malformed-json"
        }
    }
}

private struct SceneAuditFeatureAccumulator {
    private struct Value {
        var count: Int
        var support: SceneAuditFeatureSupport
    }

    private var values: [SceneAuditFeatureKey: Value] = [:]

    var observations: [SceneAuditFeatureObservation] {
        values.map {
            SceneAuditFeatureObservation(
                key: $0.key,
                count: $0.value.count,
                support: $0.value.support
            )
        }
    }

    mutating func add(
        key: SceneAuditFeatureKey,
        count: Int,
        support: SceneAuditFeatureSupport
    ) {
        guard count > 0 else {
            return
        }
        var value = values[key] ?? Value(count: 0, support: support)
        value.count += count
        if Self.rank(support) > Self.rank(value.support) {
            value.support = support
        }
        values[key] = value
    }

    private static func rank(_ support: SceneAuditFeatureSupport) -> Int {
        switch support {
        case .exact:
            return 0
        case .degraded:
            return 1
        case .unsupported:
            return 2
        case .unknown:
            return 3
        }
    }
}
