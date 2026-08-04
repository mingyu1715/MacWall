import Foundation

struct SceneAssetCandidateBuildResult: Sendable {
    let candidates: [SceneAssetCandidate]
    let invalidIssue: SceneAssetResolutionIssue?
}

struct SceneAssetCandidatePolicy: Sendable {
    let limits: SceneAssetResolverLimits

    func candidates(
        for request: SceneAssetRequest
    ) -> SceneAssetCandidateBuildResult {
        let reference = request.requestedPath
        let isExplicitOwnerRelative = reference.hasPrefix("./")
            || reference.hasPrefix("../")

        do {
            let candidates: [SceneAssetCandidate]
            if isExplicitOwnerRelative {
                candidates = [
                    try candidate(
                        reference: reference,
                        owner: request.ownerPath,
                        origin: .ownerRelative
                    )
                ]
            } else if request.role == .texture && !hasPathExtension(reference) {
                candidates = try textureShorthandCandidates(
                    reference: reference,
                    owner: request.ownerPath
                )
            } else {
                candidates = [
                    try candidate(
                        reference: reference,
                        owner: nil,
                        origin: .rootExact
                    ),
                    try candidate(
                        reference: reference,
                        owner: request.ownerPath,
                        origin: .ownerRelative
                    )
                ]
            }

            let uniqueCandidates = deduplicated(candidates)
            guard uniqueCandidates.count <= limits.maximumCandidatesPerRequest else {
                return SceneAssetCandidateBuildResult(
                    candidates: uniqueCandidates,
                    invalidIssue: .candidateLimit(
                        maximum: limits.maximumCandidatesPerRequest
                    )
                )
            }
            return SceneAssetCandidateBuildResult(
                candidates: uniqueCandidates,
                invalidIssue: nil
            )
        } catch SceneVirtualPathError.escapesRoot {
            return SceneAssetCandidateBuildResult(
                candidates: [],
                invalidIssue: .pathEscape
            )
        } catch {
            return SceneAssetCandidateBuildResult(
                candidates: [],
                invalidIssue: .invalidReference
            )
        }
    }

    private func textureShorthandCandidates(
        reference: String,
        owner: SceneVirtualPath?
    ) throws -> [SceneAssetCandidate] {
        let textureReference = reference + ".tex"
        return [
            try candidate(
                reference: textureReference,
                owner: owner,
                origin: .ownerTextureExtension
            ),
            try candidate(
                reference: "materials/" + textureReference,
                owner: nil,
                origin: .materialsTextureExtension
            ),
            try candidate(
                reference: textureReference,
                owner: nil,
                origin: .rootTextureExtension
            )
        ]
    }

    private func candidate(
        reference: String,
        owner: SceneVirtualPath?,
        origin: SceneAssetCandidateOrigin
    ) throws -> SceneAssetCandidate {
        SceneAssetCandidate(
            path: try SceneVirtualPath.resolving(
                reference: reference,
                relativeTo: owner
            ),
            origin: origin
        )
    }

    private func deduplicated(
        _ candidates: [SceneAssetCandidate]
    ) -> [SceneAssetCandidate] {
        var seenPaths = Set<SceneVirtualPath>()
        return candidates.filter { seenPaths.insert($0.path).inserted }
    }

    private func hasPathExtension(_ path: String) -> Bool {
        guard let filenameStart = path.lastIndex(of: "/") else {
            return hasFilenameExtension(path)
        }
        return hasFilenameExtension(String(path[path.index(after: filenameStart)...]))
    }

    private func hasFilenameExtension(_ filename: String) -> Bool {
        guard let dot = filename.lastIndex(of: ".") else {
            return false
        }
        return dot != filename.startIndex
            && filename.index(after: dot) != filename.endIndex
    }
}
