import Foundation

public enum SceneAuditStatus: String, Codable, Equatable, Sendable {
    case exact
    case degraded
    case unsupported
    case invalid
}

public enum SceneAuditFeatureSupport: String, Codable, Equatable, Sendable {
    case exact
    case degraded
    case unsupported
    case unknown
}

public enum SceneAuditFeatureKey: String, Codable, CaseIterable, Equatable, Sendable {
    case packageIndex
    case textureMetadata
    case imageLayer
    case textLayer
    case particleSystem
    case soundLayer
    case modelLayer
    case unknownObject
    case parentGraph
    case instance
    case animatedProperty
    case animatedTexture
    case videoTexture
    case effect
    case customShader
    case sceneScript
    case unresolvedAsset
}

public struct SceneAuditFeatureObservation: Codable, Equatable, Sendable {
    public let key: SceneAuditFeatureKey
    public let count: Int
    public let support: SceneAuditFeatureSupport

    public init(
        key: SceneAuditFeatureKey,
        count: Int,
        support: SceneAuditFeatureSupport
    ) {
        self.key = key
        self.count = count
        self.support = support
    }
}

public struct SceneAuditCount: Codable, Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct SceneAuditPackageSummary: Codable, Equatable, Sendable {
    public let version: String?
    public let entryCount: Int

    public init(version: String?, entryCount: Int) {
        self.version = version
        self.entryCount = entryCount
    }
}

public struct SceneAuditCanvas: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum SceneAuditDependencyResolution: String, Codable, Equatable, Sendable {
    case package
    case builtInCandidate
    case unresolved
}

public struct SceneAuditDependency: Codable, Equatable, Sendable {
    public let ownerPath: String
    public let key: String
    public let requestedPath: String
    public let resolvedPath: String?
    public let resolution: SceneAuditDependencyResolution

    public init(
        ownerPath: String,
        key: String,
        requestedPath: String,
        resolvedPath: String?,
        resolution: SceneAuditDependencyResolution
    ) {
        self.ownerPath = ownerPath
        self.key = key
        self.requestedPath = requestedPath
        self.resolvedPath = resolvedPath
        self.resolution = resolution
    }
}

public enum SceneAuditDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct SceneAuditDiagnostic: Codable, Equatable, Sendable {
    public let severity: SceneAuditDiagnosticSeverity
    public let code: String
    public let path: String?
    public let message: String

    public init(
        severity: SceneAuditDiagnosticSeverity,
        code: String,
        path: String?,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct SceneAuditTextureSummary: Codable, Equatable, Sendable {
    public let path: String
    public let version: String
    public let infoVersion: String
    public let formatRawValue: Int
    public let flagsRawValue: Int
    public let textureWidth: Int
    public let textureHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int
    public let declaredContainer: String
    public let effectiveContainer: String
    public let imageFormatRawValue: Int?
    public let isVideoMP4: Bool
    public let imageCount: Int
    public let mipmapCounts: [Int]
    public let animationVersion: String?
    public let animationFrameCount: Int

    public init(
        path: String,
        version: String,
        infoVersion: String,
        formatRawValue: Int,
        flagsRawValue: Int,
        textureWidth: Int,
        textureHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        declaredContainer: String,
        effectiveContainer: String,
        imageFormatRawValue: Int?,
        isVideoMP4: Bool,
        imageCount: Int,
        mipmapCounts: [Int],
        animationVersion: String?,
        animationFrameCount: Int
    ) {
        self.path = path
        self.version = version
        self.infoVersion = infoVersion
        self.formatRawValue = formatRawValue
        self.flagsRawValue = flagsRawValue
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.declaredContainer = declaredContainer
        self.effectiveContainer = effectiveContainer
        self.imageFormatRawValue = imageFormatRawValue
        self.isVideoMP4 = isVideoMP4
        self.imageCount = imageCount
        self.mipmapCounts = mipmapCounts
        self.animationVersion = animationVersion
        self.animationFrameCount = animationFrameCount
    }
}

public struct SceneAuditReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let package: SceneAuditPackageSummary
    public let canvas: SceneAuditCanvas?
    public let entryKinds: [SceneAuditCount]
    public let objectKinds: [SceneAuditCount]
    public let textures: [SceneAuditTextureSummary]
    public let dependencies: [SceneAuditDependency]
    public let scriptHandlers: [SceneAuditCount]
    public let features: [SceneAuditFeatureObservation]
    public let diagnostics: [SceneAuditDiagnostic]
    public let status: SceneAuditStatus

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        package: SceneAuditPackageSummary,
        canvas: SceneAuditCanvas?,
        entryKinds: [SceneAuditCount],
        objectKinds: [SceneAuditCount],
        textures: [SceneAuditTextureSummary],
        dependencies: [SceneAuditDependency],
        scriptHandlers: [SceneAuditCount],
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic],
        status: SceneAuditStatus
    ) {
        self.schemaVersion = schemaVersion
        self.package = package
        self.canvas = canvas
        self.entryKinds = entryKinds.sorted { $0.name < $1.name }
        self.objectKinds = objectKinds.sorted { $0.name < $1.name }
        self.textures = textures.sorted { $0.path < $1.path }
        self.dependencies = dependencies.sorted {
            if $0.ownerPath != $1.ownerPath {
                return $0.ownerPath < $1.ownerPath
            }
            if $0.key != $1.key {
                return $0.key < $1.key
            }
            return $0.requestedPath < $1.requestedPath
        }
        self.scriptHandlers = scriptHandlers.sorted { $0.name < $1.name }
        self.features = features.sorted { $0.key.rawValue < $1.key.rawValue }
        self.diagnostics = diagnostics.sorted {
            if $0.severity.rawValue != $1.severity.rawValue {
                return $0.severity.rawValue < $1.severity.rawValue
            }
            if $0.code != $1.code {
                return $0.code < $1.code
            }
            if $0.path != $1.path {
                return ($0.path ?? "") < ($1.path ?? "")
            }
            return $0.message < $1.message
        }
        self.status = status
    }
}

public struct SceneAuditSupportPolicy: Sendable {
    public static let s0 = Self()

    public func evaluate(
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic]
    ) -> SceneAuditStatus {
        if diagnostics.contains(where: { $0.severity == .error }) {
            return .invalid
        }
        if features.contains(where: {
            $0.support == .unsupported || $0.support == .unknown
        }) {
            return .unsupported
        }
        if diagnostics.contains(where: { $0.severity == .warning }) {
            return .degraded
        }
        if features.contains(where: { $0.support == .degraded }) {
            return .degraded
        }
        return .exact
    }
}

public enum SceneAuditReportEncoder {
    public static func encode(_ report: SceneAuditReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(report)
        data.append(0x0A)
        return data
    }
}
