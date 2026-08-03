import Foundation

public enum SceneAssetRole: String, Codable, CaseIterable, Hashable, Sendable {
    case scene
    case document
    case model
    case material
    case pass
    case effect
    case texture
    case shader
    case font
    case particle
    case sound
    case unknown
}

public struct SceneAssetRequest: Equatable, Sendable {
    public let requestedPath: String
    public let ownerPath: SceneVirtualPath?
    public let role: SceneAssetRole
    public let key: String?

    public init(
        requestedPath: String,
        ownerPath: SceneVirtualPath?,
        role: SceneAssetRole,
        key: String?
    ) {
        self.requestedPath = requestedPath
        self.ownerPath = ownerPath
        self.role = role
        self.key = key
    }
}

public enum SceneAssetCandidateOrigin: String, Codable, Equatable, Sendable {
    case rootExact
    case ownerRelative
    case ownerTextureExtension
    case materialsTextureExtension
    case rootTextureExtension
}

public struct SceneAssetCandidate: Equatable, Sendable {
    public let path: SceneVirtualPath
    public let origin: SceneAssetCandidateOrigin

    public init(path: SceneVirtualPath, origin: SceneAssetCandidateOrigin) {
        self.path = path
        self.origin = origin
    }
}

public struct SceneAssetEntryIdentity: Equatable, Sendable {
    public let relativeOffset: UInt64
    public let byteCount: UInt64

    public init(relativeOffset: UInt64, byteCount: UInt64) {
        self.relativeOffset = relativeOffset
        self.byteCount = byteCount
    }
}

public enum SceneAssetProvenance: Equatable, Sendable {
    case package(SceneAssetEntryIdentity)
    case builtInCandidate(policyVersion: Int)
    case externalCandidate(policyVersion: Int)
    case unresolved
}

public struct SceneResolvedAsset: Equatable, Sendable {
    public let request: SceneAssetRequest
    public let canonicalPath: SceneVirtualPath
    public let candidateOrigin: SceneAssetCandidateOrigin
    public let provenance: SceneAssetProvenance

    public init(
        request: SceneAssetRequest,
        canonicalPath: SceneVirtualPath,
        candidateOrigin: SceneAssetCandidateOrigin,
        provenance: SceneAssetProvenance
    ) {
        self.request = request
        self.canonicalPath = canonicalPath
        self.candidateOrigin = candidateOrigin
        self.provenance = provenance
    }
}

public enum SceneAssetResolutionKind: String, Codable, Equatable, Sendable {
    case package
    case builtInCandidate
    case externalCandidate
    case unresolved
    case invalid
}

public enum SceneAssetResolutionIssue: Equatable, Sendable {
    case invalidReference
    case pathEscape
    case candidateLimit(maximum: Int)
    case ambiguous(selected: SceneVirtualPath, alternatives: [SceneVirtualPath])
}

public struct SceneAssetResolution: Equatable, Sendable {
    public let request: SceneAssetRequest
    public let candidates: [SceneAssetCandidate]
    public let kind: SceneAssetResolutionKind
    public let selected: SceneResolvedAsset?
    public let issues: [SceneAssetResolutionIssue]

    public init(
        request: SceneAssetRequest,
        candidates: [SceneAssetCandidate],
        kind: SceneAssetResolutionKind,
        selected: SceneResolvedAsset?,
        issues: [SceneAssetResolutionIssue]
    ) {
        self.request = request
        self.candidates = candidates
        self.kind = kind
        self.selected = selected
        self.issues = issues
    }
}

public struct SceneAssetResolverLimits: Equatable, Sendable {
    public var maximumCandidatesPerRequest: Int

    public init(maximumCandidatesPerRequest: Int = 16) {
        self.maximumCandidatesPerRequest = maximumCandidatesPerRequest
    }
}

public struct SceneAssetSourcePolicy: Equatable, Sendable {
    public let version: Int
    public let builtInPrefixes: [String]
    public let externalPrefixes: [String]
    public let classifyBareShadersAsBuiltIn: Bool

    public init(
        version: Int,
        builtInPrefixes: [String],
        externalPrefixes: [String],
        classifyBareShadersAsBuiltIn: Bool
    ) {
        self.version = version
        self.builtInPrefixes = builtInPrefixes
        self.externalPrefixes = externalPrefixes
        self.classifyBareShadersAsBuiltIn = classifyBareShadersAsBuiltIn
    }

    public static let s2 = SceneAssetSourcePolicy(
        version: 1,
        builtInPrefixes: ["models/util/", "shaders/", "util/"],
        externalPrefixes: [],
        classifyBareShadersAsBuiltIn: true
    )
}

public struct SceneAssetPackageMetadata: Equatable, Sendable {
    public let version: String
    public let isVerifiedVersion: Bool
    public let entryCount: Int

    public init(
        version: String,
        isVerifiedVersion: Bool,
        entryCount: Int
    ) {
        self.version = version
        self.isVerifiedVersion = isVerifiedVersion
        self.entryCount = entryCount
    }
}

public enum SceneAssetPackageIssue: Equatable, Sendable {
    case unverifiedVersion(String)
    case overlappingEntryRange(first: SceneVirtualPath, second: SceneVirtualPath)
}

public enum SceneAssetAccessError: Error, Equatable, Sendable {
    case notPackageAsset
    case missingEntry
    case identityMismatch
}
