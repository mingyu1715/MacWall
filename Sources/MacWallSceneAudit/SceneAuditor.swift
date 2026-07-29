import Foundation
import MacWallSceneFormats

public struct SceneAuditLimits: Equatable, Sendable {
    public var maximumJSONEntryBytes: UInt64
    public var maximumCumulativeJSONBytes: UInt64

    public init(
        maximumJSONEntryBytes: UInt64 = 16 * 1_024 * 1_024,
        maximumCumulativeJSONBytes: UInt64 =
            64 * 1_024 * 1_024
    ) {
        self.maximumJSONEntryBytes = maximumJSONEntryBytes
        self.maximumCumulativeJSONBytes =
            maximumCumulativeJSONBytes
    }
}

public struct SceneAuditor: Sendable {
    private let packageReader: ScenePackageArchiveReader
    private let textureReader: SceneTextureFormatReader
    private let supportPolicy: SceneAuditSupportPolicy
    private let limits: SceneAuditLimits

    public init(
        packageReader: ScenePackageArchiveReader = .init(),
        textureReader: SceneTextureFormatReader = .init(),
        supportPolicy: SceneAuditSupportPolicy = .s1,
        limits: SceneAuditLimits = .init()
    ) {
        self.packageReader = packageReader
        self.textureReader = textureReader
        self.supportPolicy = supportPolicy
        self.limits = limits
    }

    public func audit(url: URL) -> SceneAuditReport {
        do {
            return audit(
                archive: try packageReader.read(url: url)
            )
        } catch {
            return invalidPackageReport(for: error)
        }
    }

    public func audit(
        source: any SceneByteSource
    ) -> SceneAuditReport {
        do {
            return audit(
                archive: try packageReader.read(source: source)
            )
        } catch {
            return invalidPackageReport(for: error)
        }
    }

    private func audit(
        archive: ScenePackageArchive
    ) -> SceneAuditReport {
        var diagnostics = packageDiagnostics(for: archive)
        guard let sceneEntry = archive.entry(
            named: "scene.json"
        ) else {
            diagnostics.append(
                invalidIndexDiagnostic(severity: .error)
            )
            return invalidArchiveReport(
                archive: archive,
                diagnostics: diagnostics
            )
        }

        guard sceneEntry.byteCount
                <= limits.maximumJSONEntryBytes,
              sceneEntry.byteCount
                <= limits.maximumCumulativeJSONBytes else {
            diagnostics.append(
                resourceDiagnostic(
                    severity: .error,
                    path: "scene.json"
                )
            )
            return invalidArchiveReport(
                archive: archive,
                diagnostics: diagnostics
            )
        }

        let sceneValue: Any
        do {
            let data = try archive.read(
                entry: sceneEntry,
                maximumBytes: limits.maximumJSONEntryBytes
            )
            sceneValue = try JSONSerialization.jsonObject(
                with: data
            )
        } catch {
            diagnostics.append(
                diagnosticForSceneRead(error)
            )
            return invalidArchiveReport(
                archive: archive,
                diagnostics: diagnostics
            )
        }
        guard let scene = sceneValue as? [String: Any] else {
            diagnostics.append(
                invalidIndexDiagnostic(severity: .error)
            )
            return invalidArchiveReport(
                archive: archive,
                diagnostics: diagnostics
            )
        }

        var cumulativeJSONBytes = sceneEntry.byteCount
        var documents: [String: Any] = [
            "scene.json": sceneValue
        ]
        let auxiliaryEntries = archive.entries
            .filter {
                $0.path != "scene.json"
                    && Self.entryKind(for: $0.path) == "json"
            }
            .sorted { $0.path < $1.path }

        for entry in auxiliaryEntries {
            guard entry.byteCount
                    <= limits.maximumJSONEntryBytes else {
                diagnostics.append(
                    resourceDiagnostic(
                        severity: .warning,
                        path: entry.path
                    )
                )
                continue
            }
            let (nextCumulative, overflow) =
                cumulativeJSONBytes.addingReportingOverflow(
                    entry.byteCount
                )
            guard !overflow,
                  nextCumulative
                    <= limits.maximumCumulativeJSONBytes else {
                diagnostics.append(
                    resourceDiagnostic(
                        severity: .warning,
                        path: entry.path
                    )
                )
                continue
            }

            do {
                let data = try archive.read(
                    entry: entry,
                    maximumBytes: limits.maximumJSONEntryBytes
                )
                documents[entry.path] =
                    try JSONSerialization.jsonObject(with: data)
                cumulativeJSONBytes = nextCumulative
            } catch {
                diagnostics.append(
                    invalidIndexDiagnostic(
                        severity: .warning,
                        path: entry.path
                    )
                )
            }
        }

        let packagePaths = Set(archive.entries.map(\.path))
        let evidence = SceneJSONInspector().inspect(
            scene: scene,
            documents: documents,
            packagePaths: packagePaths
        )
        diagnostics.append(contentsOf: evidence.diagnostics)

        var featureAccumulator = SceneAuditFeatureAccumulator()
        featureAccumulator.add(
            key: .packageIndex,
            count: 1,
            support: .exact
        )
        for (key, count) in evidence.featureCounts {
            featureAccumulator.add(
                key: key,
                count: count,
                support: Self.support(for: key)
            )
        }

        var textures: [SceneAuditTextureSummary] = []
        let textureEntries = archive.entries
            .filter {
                Self.entryKind(for: $0.path) == "texture"
            }
            .sorted { $0.path < $1.path }
        for entry in textureEntries {
            do {
                let inspection = try textureReader.inspect(
                    source: archive.source(for: entry),
                    path: entry.path
                )
                switch inspection {
                case .parsed(let descriptor):
                    textures.append(
                        Self.summary(from: descriptor)
                    )
                    featureAccumulator.add(
                        key: .textureMetadata,
                        count: 1,
                        support: .exact
                    )
                    if descriptor.flagsRawValue & 4 != 0
                        || descriptor.animation != nil {
                        featureAccumulator.add(
                            key: .animatedTexture,
                            count: 1,
                            support: .unsupported
                        )
                    }
                    if descriptor.flagsRawValue & 32 != 0
                        || descriptor.isVideoMP4 {
                        featureAccumulator.add(
                            key: .videoTexture,
                            count: 1,
                            support: .unsupported
                        )
                    }
                    if descriptor.trailingByteRange != nil {
                        diagnostics.append(
                            SceneAuditDiagnostic(
                                severity: .warning,
                                code: "texture.trailing-bytes",
                                path: entry.path,
                                message:
                                    "Texture metadata has trailing bytes."
                            )
                        )
                    }
                case .unsupported(let metadata):
                    textures.append(
                        Self.summary(from: metadata)
                    )
                    featureAccumulator.add(
                        key: .textureMetadata,
                        count: 1,
                        support: .unknown
                    )
                    diagnostics.append(
                        Self.diagnostic(for: metadata)
                    )
                }
            } catch {
                textures.append(
                    Self.invalidTextureSummary(path: entry.path)
                )
                featureAccumulator.add(
                    key: .textureMetadata,
                    count: 1,
                    support: .unknown
                )
                diagnostics.append(
                    SceneAuditDiagnostic(
                        severity: .warning,
                        code: "texture.invalid-metadata",
                        path: entry.path,
                        message:
                            "Texture metadata could not be inspected."
                    )
                )
            }
        }

        let effectCount = archive.entries.filter {
            let path = $0.path.lowercased()
            return path.hasPrefix("effects/")
                && path.hasSuffix(".json")
        }.count
        featureAccumulator.add(
            key: .effect,
            count: effectCount,
            support: .unsupported
        )

        let customShaderCount = archive.entries.filter {
            let kind = Self.entryKind(for: $0.path)
            return kind == "vertexShader"
                || kind == "fragmentShader"
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
                version: archive.version.rawValue,
                entryCount: archive.entries.count
            ),
            canvas: evidence.canvas,
            entryKinds: Self.entryKindCounts(
                for: archive.entries
            ),
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

    private func invalidPackageReport(
        for error: Error
    ) -> SceneAuditReport {
        let diagnostic: SceneAuditDiagnostic
        if let formatError = error as? SceneFormatError {
            diagnostic = Self.packageDiagnostic(
                for: formatError
            )
        } else {
            diagnostic = invalidIndexDiagnostic(
                severity: .error
            )
        }
        return SceneAuditReport(
            package: SceneAuditPackageSummary(
                version: nil,
                entryCount: 0
            ),
            canvas: nil,
            entryKinds: [],
            objectKinds: [],
            textures: [],
            dependencies: [],
            scriptHandlers: [],
            features: [],
            diagnostics: [diagnostic],
            status: .invalid
        )
    }

    private func invalidArchiveReport(
        archive: ScenePackageArchive,
        diagnostics: [SceneAuditDiagnostic]
    ) -> SceneAuditReport {
        SceneAuditReport(
            package: SceneAuditPackageSummary(
                version: archive.version.rawValue,
                entryCount: archive.entries.count
            ),
            canvas: nil,
            entryKinds: Self.entryKindCounts(
                for: archive.entries
            ),
            objectKinds: [],
            textures: [],
            dependencies: [],
            scriptHandlers: [],
            features: [],
            diagnostics: diagnostics,
            status: .invalid
        )
    }

    private func packageDiagnostics(
        for archive: ScenePackageArchive
    ) -> [SceneAuditDiagnostic] {
        archive.issues.map { issue in
            switch issue {
            case .unverifiedVersion:
                return SceneAuditDiagnostic(
                    severity: .warning,
                    code: "package.unverified-version",
                    path: nil,
                    message:
                        "Package version has not been verified."
                )
            case .overlappingEntryRange(
                _,
                let secondPath
            ):
                return SceneAuditDiagnostic(
                    severity: .warning,
                    code: "package.overlapping-entry-range",
                    path: secondPath,
                    message:
                        "Package entry ranges overlap."
                )
            }
        }
    }

    private func diagnosticForSceneRead(
        _ error: Error
    ) -> SceneAuditDiagnostic {
        if case SceneFormatError.resourceLimit = error {
            return resourceDiagnostic(
                severity: .error,
                path: "scene.json"
            )
        }
        return invalidIndexDiagnostic(severity: .error)
    }

    private func invalidIndexDiagnostic(
        severity: SceneAuditDiagnosticSeverity,
        path: String? = nil
    ) -> SceneAuditDiagnostic {
        SceneAuditDiagnostic(
            severity: severity,
            code: "package.invalid-index",
            path: path,
            message: "Scene package content could not be inspected."
        )
    }

    private func resourceDiagnostic(
        severity: SceneAuditDiagnosticSeverity,
        path: String?
    ) -> SceneAuditDiagnostic {
        SceneAuditDiagnostic(
            severity: severity,
            code: "resource.limit-exceeded",
            path: path,
            message:
                "Scene resource exceeds a configured safety limit."
        )
    }

    private static func packageDiagnostic(
        for error: SceneFormatError
    ) -> SceneAuditDiagnostic {
        let code: String
        switch error {
        case .duplicatePath:
            code = "package.duplicate-entry-path"
        case .resourceLimit:
            code = "resource.limit-exceeded"
        default:
            code = "package.invalid-index"
        }
        return SceneAuditDiagnostic(
            severity: .error,
            code: code,
            path: nil,
            message: "Scene package audit failed."
        )
    }

    private static func summary(
        from descriptor: SceneTextureDescriptor
    ) -> SceneAuditTextureSummary {
        let trailingByteCount =
            descriptor.trailingByteRange.map {
                $0.upperBound - $0.lowerBound
            } ?? 0
        return SceneAuditTextureSummary(
            path: descriptor.path,
            status: .parsed,
            version: descriptor.version,
            infoVersion: descriptor.infoVersion,
            formatRawValue: descriptor.formatRawValue,
            flagsRawValue: descriptor.flagsRawValue,
            textureWidth: descriptor.textureWidth,
            textureHeight: descriptor.textureHeight,
            imageWidth: descriptor.imageWidth,
            imageHeight: descriptor.imageHeight,
            declaredContainer: descriptor.declaredContainer,
            mipmapLayout: descriptor.mipmapLayout.rawValue,
            imageFormatRawValue:
                descriptor.imageFormatRawValue,
            isVideoMP4: descriptor.isVideoMP4,
            imageCount: descriptor.images.count,
            mipmapCounts: descriptor.images.map {
                $0.mipmaps.count
            },
            animationVersion: descriptor.animation?.version,
            animationFrameCount:
                descriptor.animation?.frameCount,
            trailingByteCount: trailingByteCount
        )
    }

    private static func summary(
        from metadata: SceneTextureUnsupportedMetadata
    ) -> SceneAuditTextureSummary {
        let status: SceneAuditTextureStatus
        switch metadata.kind {
        case .outerVersion:
            status = .unsupportedVersion
        case .infoVersion:
            status = .unsupportedInfoVersion
        case .container:
            status = .unsupportedContainer
        case .animationVersion:
            status = .invalid
        }
        return SceneAuditTextureSummary(
            path: metadata.path,
            status: status,
            version: metadata.version,
            infoVersion: metadata.infoVersion,
            formatRawValue: nil,
            flagsRawValue: nil,
            textureWidth: nil,
            textureHeight: nil,
            imageWidth: nil,
            imageHeight: nil,
            declaredContainer: metadata.declaredContainer,
            mipmapLayout: nil,
            imageFormatRawValue: nil,
            isVideoMP4: nil,
            imageCount: nil,
            mipmapCounts: nil,
            animationVersion: metadata.animationVersion,
            animationFrameCount: nil,
            trailingByteCount: nil
        )
    }

    private static func invalidTextureSummary(
        path: String
    ) -> SceneAuditTextureSummary {
        SceneAuditTextureSummary(
            path: path,
            status: .invalid,
            version: nil,
            infoVersion: nil,
            formatRawValue: nil,
            flagsRawValue: nil,
            textureWidth: nil,
            textureHeight: nil,
            imageWidth: nil,
            imageHeight: nil,
            declaredContainer: nil,
            mipmapLayout: nil,
            imageFormatRawValue: nil,
            isVideoMP4: nil,
            imageCount: nil,
            mipmapCounts: nil,
            animationVersion: nil,
            animationFrameCount: nil,
            trailingByteCount: nil
        )
    }

    private static func diagnostic(
        for metadata: SceneTextureUnsupportedMetadata
    ) -> SceneAuditDiagnostic {
        let code: String
        switch metadata.kind {
        case .outerVersion:
            code = "texture.unsupported-version"
        case .infoVersion:
            code = "texture.unsupported-info-version"
        case .container:
            code = "texture.unsupported-container"
        case .animationVersion:
            code = "texture.invalid-metadata"
        }
        return SceneAuditDiagnostic(
            severity: .warning,
            code: code,
            path: metadata.path,
            message: "Texture metadata layout is not supported."
        )
    }

    private static func entryKindCounts(
        for entries: [ScenePackageEntry]
    ) -> [SceneAuditCount] {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entryKind(for: entry.path), default: 0] += 1
        }
        return counts.map {
            SceneAuditCount(name: $0.key, count: $0.value)
        }
    }

    private static func entryKind(for path: String) -> String {
        switch URL(
            filePath: path
        ).pathExtension.lowercased() {
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
        var value = values[key]
            ?? Value(count: 0, support: support)
        value.count += count
        if Self.rank(support) > Self.rank(value.support) {
            value.support = support
        }
        values[key] = value
    }

    private static func rank(
        _ support: SceneAuditFeatureSupport
    ) -> Int {
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
