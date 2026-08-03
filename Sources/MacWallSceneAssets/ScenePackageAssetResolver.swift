import Foundation
import MacWallSceneFormats

public struct ScenePackageAssetResolver: Sendable {
    public let package: SceneAssetPackageMetadata
    public let packageIssues: [SceneAssetPackageIssue]

    private let archive: ScenePackageArchive
    private let candidatePolicy: SceneAssetCandidatePolicy
    private let sourcePolicy: SceneAssetSourcePolicy

    public init(
        archive: ScenePackageArchive,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) {
        self.archive = archive
        candidatePolicy = SceneAssetCandidatePolicy(limits: limits)
        self.sourcePolicy = sourcePolicy
        package = SceneAssetPackageMetadata(
            version: archive.version.rawValue,
            isVerifiedVersion: archive.version.isVerified,
            entryCount: archive.entries.count
        )
        packageIssues = archive.issues.compactMap(Self.packageIssue)
    }

    public static func open(
        url: URL,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> ScenePackageAssetResolver {
        try open(
            source: SceneFileByteSource(url: url),
            limits: limits,
            sourcePolicy: sourcePolicy
        )
    }

    public static func open(
        source: any SceneByteSource,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> ScenePackageAssetResolver {
        ScenePackageAssetResolver(
            archive: try ScenePackageArchiveReader().read(source: source),
            limits: limits,
            sourcePolicy: sourcePolicy
        )
    }

    public func resolve(
        _ request: SceneAssetRequest
    ) -> SceneAssetResolution {
        let buildResult = candidatePolicy.candidates(for: request)
        if let invalidIssue = buildResult.invalidIssue {
            return SceneAssetResolution(
                request: request,
                candidates: buildResult.candidates,
                kind: .invalid,
                selected: nil,
                issues: [invalidIssue]
            )
        }

        let matchingCandidates = buildResult.candidates.compactMap { candidate in
            archive.entry(named: candidate.path.rawValue).map {
                (candidate, $0)
            }
        }
        if let (candidate, entry) = matchingCandidates.first {
            let selected = packageAsset(
                request: request,
                candidate: candidate,
                entry: entry
            )
            let alternatives = matchingCandidates.dropFirst()
                .map(\.0.path)
                .sorted()
            let issues: [SceneAssetResolutionIssue] = alternatives.isEmpty
                ? []
                : [.ambiguous(
                    selected: candidate.path,
                    alternatives: alternatives
                )]
            return SceneAssetResolution(
                request: request,
                candidates: buildResult.candidates,
                kind: .package,
                selected: selected,
                issues: issues
            )
        }

        return classifiedResolution(
            request: request,
            candidates: buildResult.candidates
        )
    }

    public func source(
        for asset: SceneResolvedAsset
    ) throws -> SceneBoundedByteSource {
        let entry = try packageEntry(for: asset)
        return archive.source(for: entry)
    }

    public func read(
        _ asset: SceneResolvedAsset,
        maximumBytes: UInt64
    ) throws -> Data {
        try archive.read(
            entry: packageEntry(for: asset),
            maximumBytes: maximumBytes
        )
    }

    private func packageAsset(
        request: SceneAssetRequest,
        candidate: SceneAssetCandidate,
        entry: ScenePackageEntry
    ) -> SceneResolvedAsset {
        SceneResolvedAsset(
            request: request,
            canonicalPath: candidate.path,
            candidateOrigin: candidate.origin,
            provenance: .package(
                SceneAssetEntryIdentity(
                    relativeOffset: entry.relativeOffset,
                    byteCount: entry.byteCount
                )
            )
        )
    }

    private func classifiedResolution(
        request: SceneAssetRequest,
        candidates: [SceneAssetCandidate]
    ) -> SceneAssetResolution {
        guard let candidate = candidates.first else {
            return SceneAssetResolution(
                request: request,
                candidates: candidates,
                kind: .unresolved,
                selected: nil,
                issues: []
            )
        }

        let requestedPath = request.requestedPath
        if isBuiltInCandidate(requestedPath, role: request.role) {
            return candidateResolution(
                request: request,
                candidates: candidates,
                candidate: candidate,
                kind: .builtInCandidate,
                provenance: .builtInCandidate(policyVersion: sourcePolicy.version)
            )
        }
        if sourcePolicy.externalPrefixes.contains(where: {
            requestedPath.hasPrefix($0)
        }) {
            return candidateResolution(
                request: request,
                candidates: candidates,
                candidate: candidate,
                kind: .externalCandidate,
                provenance: .externalCandidate(policyVersion: sourcePolicy.version)
            )
        }
        return SceneAssetResolution(
            request: request,
            candidates: candidates,
            kind: .unresolved,
            selected: nil,
            issues: []
        )
    }

    private func candidateResolution(
        request: SceneAssetRequest,
        candidates: [SceneAssetCandidate],
        candidate: SceneAssetCandidate,
        kind: SceneAssetResolutionKind,
        provenance: SceneAssetProvenance
    ) -> SceneAssetResolution {
        SceneAssetResolution(
            request: request,
            candidates: candidates,
            kind: kind,
            selected: SceneResolvedAsset(
                request: request,
                canonicalPath: candidate.path,
                candidateOrigin: candidate.origin,
                provenance: provenance
            ),
            issues: []
        )
    }

    private func isBuiltInCandidate(
        _ requestedPath: String,
        role: SceneAssetRole
    ) -> Bool {
        if sourcePolicy.builtInPrefixes.contains(where: {
            requestedPath.hasPrefix($0)
        }) {
            return true
        }
        return sourcePolicy.classifyBareShadersAsBuiltIn
            && role == .shader
            && !requestedPath.contains("/")
            && !hasPathExtension(requestedPath)
    }

    private func hasPathExtension(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: ".") else {
            return false
        }
        return dot != path.startIndex
            && path.index(after: dot) != path.endIndex
    }

    private func packageEntry(
        for asset: SceneResolvedAsset
    ) throws -> ScenePackageEntry {
        guard case let .package(identity) = asset.provenance else {
            throw SceneAssetAccessError.notPackageAsset
        }
        guard let entry = archive.entry(named: asset.canonicalPath.rawValue) else {
            throw SceneAssetAccessError.missingEntry
        }
        guard entry.relativeOffset == identity.relativeOffset,
              entry.byteCount == identity.byteCount else {
            throw SceneAssetAccessError.identityMismatch
        }
        return entry
    }

    private static func packageIssue(
        _ issue: ScenePackageIndexIssue
    ) -> SceneAssetPackageIssue? {
        switch issue {
        case let .unverifiedVersion(version):
            return .unverifiedVersion(version)
        case let .overlappingEntryRange(firstPath, secondPath):
            guard let first = try? SceneVirtualPath(canonicalPath: firstPath),
                  let second = try? SceneVirtualPath(canonicalPath: secondPath) else {
                return nil
            }
            return .overlappingEntryRange(first: first, second: second)
        }
    }
}
