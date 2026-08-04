import Foundation
import XCTest
@testable import MacWallSceneAssets
import MacWallSceneFormats
import MacWallSceneTestSupport

final class ScenePackageAssetResolverTests: XCTestCase {
    func testTextureShorthandSelectsOwnerCandidateAndRecordsAmbiguity() throws {
        let resolver = try makeResolver()
        let request = SceneAssetRequest(
            requestedPath: "base",
            ownerPath: try SceneVirtualPath(
                canonicalPath: "models/sub/model.json"
            ),
            role: .texture,
            key: "textures"
        )

        let resolution = resolver.resolve(request)

        XCTAssertEqual(
            resolution.candidates.map(\.path.rawValue),
            [
                "models/sub/base.tex",
                "materials/base.tex",
                "base.tex"
            ]
        )
        XCTAssertEqual(resolution.kind, .package)
        XCTAssertEqual(
            resolution.selected?.canonicalPath.rawValue,
            "models/sub/base.tex"
        )
        XCTAssertEqual(
            resolution.issues,
            [
                .ambiguous(
                    selected: try SceneVirtualPath(
                        canonicalPath: "models/sub/base.tex"
                    ),
                    alternatives: [
                        try SceneVirtualPath(
                            canonicalPath: "materials/base.tex"
                        )
                    ]
                )
            ]
        )
    }

    func testDocumentRootExactPrecedesOwnerRelativeLookup() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "scene.json",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .document,
                key: nil
            )
        )

        XCTAssertEqual(
            resolution.candidates.map(\.path.rawValue),
            ["scene.json", "models/sub/scene.json"]
        )
        XCTAssertEqual(resolution.selected?.canonicalPath.rawValue, "scene.json")
    }

    func testDocumentRootReferenceCanonicalizesEmbeddedDotSegments() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "models/../scene.json",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .document,
                key: nil
            )
        )

        XCTAssertEqual(
            resolution.candidates.map(\.path.rawValue),
            ["scene.json", "models/sub/scene.json"]
        )
        XCTAssertEqual(resolution.kind, .package)
        XCTAssertEqual(resolution.selected?.canonicalPath.rawValue, "scene.json")
    }

    func testTextureOwnerReferenceCanonicalizesEmbeddedDotSegments() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "nested/../base.tex",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .texture,
                key: "textures"
            )
        )

        XCTAssertEqual(
            resolution.candidates.map(\.path.rawValue),
            ["base.tex", "models/sub/base.tex"]
        )
        XCTAssertEqual(resolution.kind, .package)
        XCTAssertEqual(
            resolution.selected?.canonicalPath.rawValue,
            "models/sub/base.tex"
        )
        XCTAssertEqual(resolution.selected?.candidateOrigin, .ownerRelative)
    }

    func testExplicitDotReferencesAreOwnerRelativeOnly() throws {
        let resolver = try makeResolver()
        let owner = try SceneVirtualPath(
            canonicalPath: "models/sub/model.json"
        )

        let current = resolver.resolve(
            SceneAssetRequest(
                requestedPath: "./base.tex",
                ownerPath: owner,
                role: .texture,
                key: nil
            )
        )
        let parent = resolver.resolve(
            SceneAssetRequest(
                requestedPath: "../materials/owner.json",
                ownerPath: owner,
                role: .material,
                key: nil
            )
        )

        XCTAssertEqual(current.candidates.map(\.path.rawValue), ["models/sub/base.tex"])
        XCTAssertEqual(current.selected?.canonicalPath.rawValue, "models/sub/base.tex")
        XCTAssertEqual(parent.candidates.map(\.path.rawValue), ["models/materials/owner.json"])
        XCTAssertEqual(parent.selected?.canonicalPath.rawValue, "models/materials/owner.json")
    }

    func testExtensionBearingTextureUsesRootExactBeforeOwnerRelative() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "materials/root.json",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .texture,
                key: "textures"
            )
        )

        XCTAssertEqual(
            resolution.candidates.map(\.path.rawValue),
            ["materials/root.json", "models/sub/materials/root.json"]
        )
        XCTAssertEqual(
            resolution.selected?.canonicalPath.rawValue,
            "materials/root.json"
        )
    }

    func testDuplicateCandidatePathKeepsFirstOrigin() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "model.json",
                ownerPath: try SceneVirtualPath(canonicalPath: "model.json"),
                role: .model,
                key: nil
            )
        )

        XCTAssertEqual(
            resolution.candidates,
            [
                .init(
                    path: try SceneVirtualPath(canonicalPath: "model.json"),
                    origin: .rootExact
                )
            ]
        )
    }

    func testLookupPreservesExactCaseAndUnicode() throws {
        let resolver = try makeResolver()
        let matching = resolver.resolve(
            SceneAssetRequest(
                requestedPath: "재료/Texture.TEX",
                ownerPath: nil,
                role: .texture,
                key: nil
            )
        )
        let mismatched = resolver.resolve(
            SceneAssetRequest(
                requestedPath: "재료/texture.tex",
                ownerPath: nil,
                role: .texture,
                key: nil
            )
        )

        XCTAssertEqual(matching.kind, .package)
        XCTAssertEqual(matching.selected?.canonicalPath.rawValue, "재료/Texture.TEX")
        XCTAssertEqual(mismatched.kind, .unresolved)
    }

    func testBuiltInPolicyClassifiesOnlyExactBareAndPrefixShaderEvidence() throws {
        let resolver = try makeResolver()
        let references = ["blur", "util/common.glsl", "models/util/common.glsl", "shaders/common.glsl"]

        for reference in references {
            let resolution = resolver.resolve(
                SceneAssetRequest(
                    requestedPath: reference,
                    ownerPath: nil,
                    role: .shader,
                    key: "shader"
                )
            )

            XCTAssertEqual(resolution.kind, .builtInCandidate, reference)
            XCTAssertEqual(resolution.selected?.canonicalPath.rawValue, reference)
            XCTAssertEqual(
                resolution.selected?.provenance,
                .builtInCandidate(policyVersion: 1),
                reference
            )
        }

        XCTAssertEqual(
            resolver.resolve(
                SceneAssetRequest(
                    requestedPath: "blur.glsl",
                    ownerPath: nil,
                    role: .shader,
                    key: "shader"
                )
            ).kind,
            .unresolved
        )
        XCTAssertEqual(
            resolver.resolve(
                SceneAssetRequest(
                    requestedPath: "Util/common.glsl",
                    ownerPath: nil,
                    role: .shader,
                    key: "shader"
                )
            ).kind,
            .unresolved
        )
    }

    func testMissingReferenceIsUnresolvedByDefault() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "missing/file.bin",
                ownerPath: nil,
                role: .unknown,
                key: nil
            )
        )

        XCTAssertEqual(resolution.kind, .unresolved)
        XCTAssertEqual(resolution.selected, nil)
        XCTAssertEqual(resolution.issues, [])
    }

    func testInjectedExternalPrefixClassifiesMissingReference() throws {
        let resolver = try makeResolver(
            sourcePolicy: SceneAssetSourcePolicy(
                version: 9,
                builtInPrefixes: [],
                externalPrefixes: ["shared/"],
                classifyBareShadersAsBuiltIn: false
            )
        )

        let resolution = resolver.resolve(
            SceneAssetRequest(
                requestedPath: "shared/texture.tex",
                ownerPath: nil,
                role: .texture,
                key: nil
            )
        )

        XCTAssertEqual(resolution.kind, .externalCandidate)
        XCTAssertEqual(
            resolution.selected?.provenance,
            .externalCandidate(policyVersion: 9)
        )
    }

    func testDefaultProductionExternalPrefixListIsEmpty() throws {
        XCTAssertEqual(SceneAssetSourcePolicy.s2.externalPrefixes, [])
        XCTAssertEqual(
            try makeResolver().resolve(
                SceneAssetRequest(
                    requestedPath: "shared/texture.tex",
                    ownerPath: nil,
                    role: .texture,
                    key: nil
                )
            ).kind,
            .unresolved
        )
    }

    func testCandidateLimitReturnsInvalidEvidenceBeforeLookup() throws {
        let resolution = try makeResolver(
            limits: .init(maximumCandidatesPerRequest: 1)
        ).resolve(
            SceneAssetRequest(
                requestedPath: "base",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .texture,
                key: nil
            )
        )

        XCTAssertEqual(resolution.kind, .invalid)
        XCTAssertEqual(resolution.selected, nil)
        XCTAssertEqual(resolution.issues, [.candidateLimit(maximum: 1)])
    }

    func testPathEscapeReturnsInvalidPathEscapeIssue() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "../outside.tex",
                ownerPath: try SceneVirtualPath(canonicalPath: "model.json"),
                role: .texture,
                key: nil
            )
        )

        XCTAssertEqual(resolution.kind, .invalid)
        XCTAssertEqual(resolution.selected, nil)
        XCTAssertEqual(resolution.issues, [.pathEscape])
    }

    func testEmbeddedRootEscapeReturnsInvalidPathEscapeIssue() throws {
        let resolution = try makeResolver().resolve(
            SceneAssetRequest(
                requestedPath: "models/../../outside.json",
                ownerPath: try SceneVirtualPath(
                    canonicalPath: "models/sub/model.json"
                ),
                role: .document,
                key: nil
            )
        )

        XCTAssertEqual(resolution.kind, .invalid)
        XCTAssertEqual(resolution.selected, nil)
        XCTAssertEqual(resolution.issues, [.pathEscape])
    }

    func testReadOverMaximumRejectsBeforePayloadRead() throws {
        let bytes = ScenePackageFixtureBuilder.make(entries: Self.syntheticEntries)
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(data: bytes)
        )
        let resolver = try ScenePackageAssetResolver.open(source: recording)
        let asset = try XCTUnwrap(
            resolver.resolve(
                SceneAssetRequest(
                    requestedPath: "scene.json",
                    ownerPath: nil,
                    role: .scene,
                    key: nil
                )
            ).selected
        )
        recording.resetReadRanges()

        XCTAssertThrowsError(try resolver.read(asset, maximumBytes: 1)) { error in
            XCTAssertEqual(
                error as? SceneFormatError,
                .resourceLimit(.entryBytes)
            )
        }
        XCTAssertEqual(recording.readRanges, [])
    }

    func testSourceRejectsAssetWhoseIdentityDiffersFromEntry() throws {
        let first = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: [
                    .init(path: "scene.json", data: Data("{}".utf8))
                ])
            )
        )
        let second = try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: [
                    .init(path: "scene.json", data: Data("{ }".utf8))
                ])
            )
        )
        let asset = try XCTUnwrap(
            first.resolve(
                SceneAssetRequest(
                    requestedPath: "scene.json",
                    ownerPath: nil,
                    role: .scene,
                    key: nil
                )
            ).selected
        )

        XCTAssertThrowsError(try second.source(for: asset)) { error in
            XCTAssertEqual(error as? SceneAssetAccessError, .identityMismatch)
        }
    }

    private static let syntheticEntries: [ScenePackageFixtureEntry] = [
        .init(path: "scene.json", data: Data("{}".utf8)),
        .init(path: "models/sub/model.json", data: Data("{}".utf8)),
        .init(path: "models/materials/owner.json", data: Data("{}".utf8)),
        .init(path: "materials/root.json", data: Data("{}".utf8)),
        .init(path: "materials/base.tex", data: Data([1])),
        .init(path: "models/sub/base.tex", data: Data([2])),
        .init(path: "재료/Texture.TEX", data: Data([3]))
    ]

    private func makeResolver(
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> ScenePackageAssetResolver {
        try ScenePackageAssetResolver.open(
            source: SceneDataByteSource(
                data: ScenePackageFixtureBuilder.make(entries: Self.syntheticEntries)
            ),
            limits: limits,
            sourcePolicy: sourcePolicy
        )
    }
}
