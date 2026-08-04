# Scene Asset Resolver and Typed Graph Implementation Plan

상태: implemented / completed / archived

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scene.pkg` 내부 reference를 안전하게 해석하는 `MacWallSceneAssets`와 모든 Scene object, dependency, hierarchy, instance, animation, unknown metadata를 deterministic하게 보존하는 `MacWallSceneGraph`를 구현한다.

**Architecture:** `MacWallSceneAssets`는 `MacWallSceneFormats`의 immutable archive 위에서 canonical virtual path, candidate policy, provenance, bounded content access를 소유합니다. `MacWallSceneGraph`는 Assets만 소비해 typed JSON, node/resource graph, validation, status, canonical summary를 만들며 기존 `SceneRenderPlan`/CALayer prototype과 병행 유지합니다. 기존 `MacWallSceneAudit`의 중복 reference 해석은 Assets로 위임해 Graph와 Audit가 같은 정책을 사용하게 합니다.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation/CoreFoundation, XCTest, existing `MacWallSceneFormats` random-access archive, JSONSerialization with an internal typed conversion boundary.

## Global Constraints

- 설계 기준은 `docs/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md`입니다.
- 지원 플랫폼은 기존 package 기준인 macOS 14+입니다.
- dependency 방향은 `MacWallSceneFormats -> MacWallSceneAssets -> MacWallSceneGraph`입니다.
- `MacWallSceneAssets`는 `MacWallSceneFormats`와 Foundation 외에 Audit/Core/AppKit/Metal에 의존하지 않습니다.
- `MacWallSceneGraph`는 `MacWallSceneAssets`와 Foundation/CoreFoundation 외에 Audit/Core/AppKit/Metal/AVFoundation에 의존하지 않습니다.
- `MacWallSceneAudit`는 reference 해석을 `MacWallSceneAssets`에 위임하되 schema version 2와 기존 aggregate catalog를 유지합니다.
- `MacWallCore`, `MacWallApp`, `SceneRenderPlan`, `SceneWallpaperView`, Native Wallpaper backend는 S2에서 새 Graph target에 의존하지 않습니다.
- public graph boundary에 `Any`, `[String: Any]`, `NSNumber`를 노출하지 않습니다.
- package path는 exact case/Unicode를 유지하고 URL decoding, percent decoding, case folding, Unicode normalization을 하지 않습니다.
- package 전체 `Data(contentsOf:)`, unbounded entry read, host path 문자열 결합을 추가하지 않습니다.
- package size 512 MiB, package entry 100,000개, path 4,096 bytes, index 64 MiB의 S1 limit을 유지합니다.
- JSON entry는 16 MiB, graph build 누적 JSON은 64 MiB, request candidate는 16개로 제한합니다.
- graph node는 100,000개, dependency edge는 500,000개, animation keyframe은 1,000,000개, JSON depth는 256, hierarchy traversal depth는 4,096으로 제한합니다.
- built-in production policy version 1은 bare shader와 `util/`, `models/util/`, `shaders/` prefix만 evidence로 분류합니다.
- production external asset prefix는 S2에서 빈 목록입니다. Test에서 주입한 명시적 prefix만 `externalCandidate`를 검증합니다.
- missing package entry를 근거 없이 built-in/external로 추측하지 않습니다.
- instance는 reference로 유지하고 subtree를 복제/flatten하지 않습니다.
- SceneScript, effect, custom shader는 metadata만 보존하고 실행하지 않습니다.
- texture payload를 inspect/decode/upload하지 않습니다.
- actual Wallpaper Engine `assets/` folder, bookmark, user selection UI를 구현하지 않습니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`를 Scene output이나 fallback source로 사용하지 않습니다.
- 실제 Workshop payload는 `test/` local-only read-only fixture로만 사용하고 Git에 추가하지 않습니다.
- GPL implementation과 Wallpaper Engine built-in asset/shader/texture를 복사하지 않습니다.
- 새 `macwallctl` command를 추가하지 않습니다.
- 자동 검증은 focused `swift test`, 전체 `swift test`, `rg`, `git diff --check`, local fixture read-only inspection만 사용합니다.
- `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행, package, DMG, notarization, `dist` 작업을 하지 않습니다.

---

## File Structure

새 Assets production 파일:

- `Sources/MacWallSceneAssets/SceneVirtualPath.swift`
  - canonical package path와 owner-relative normalization
- `Sources/MacWallSceneAssets/SceneAssetModels.swift`
  - request, role, candidate, resolution, provenance, package metadata
- `Sources/MacWallSceneAssets/SceneAssetCandidatePolicy.swift`
  - document/texture candidate order와 built-in/external classification
- `Sources/MacWallSceneAssets/ScenePackageAssetResolver.swift`
  - exact archive lookup, ambiguity, bounded read/source access

새 Graph production 파일:

- `Sources/MacWallSceneGraph/SceneJSONValue.swift`
  - `Sendable` JSON value와 bounded internal decoder
- `Sources/MacWallSceneGraph/SceneGraphPrimitives.swift`
  - limits, status, diagnostics, canvas/vector/color, node/source ID
- `Sources/MacWallSceneGraph/SceneGraphNode.swift`
  - typed node payload와 common properties
- `Sources/MacWallSceneGraph/SceneGraphHierarchy.swift`
  - parent/instance/override edge와 reference resolution
- `Sources/MacWallSceneGraph/SceneGraphResource.swift`
  - model/material/pass/texture/shader/effect resource와 dependency edge
- `Sources/MacWallSceneGraph/SceneGraphAnimation.swift`
  - source-preserving track/channel/keyframe model
- `Sources/MacWallSceneGraph/SceneGraphDocument.swift`
  - immutable document, script metadata, build result
- `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`
  - archive open, root parse, phase orchestration, status accumulation
- `Sources/MacWallSceneGraph/SceneGraphNodeParser.swift`
  - source-order node classification/common property parsing
- `Sources/MacWallSceneGraph/SceneGraphHierarchyResolver.swift`
  - multimap reference linking과 iterative cycle validation
- `Sources/MacWallSceneGraph/SceneGraphResourceParser.swift`
  - on-demand model/material/pass/effect traversal과 memoization
- `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`
  - animation wrapper discovery와 typed/raw channel parsing
- `Sources/MacWallSceneGraph/SceneGraphSummary.swift`
  - aggregate summary와 canonical JSON encoder

새 test 파일:

- `Tests/MacWallSceneAssetsTests/SceneVirtualPathTests.swift`
- `Tests/MacWallSceneAssetsTests/ScenePackageAssetResolverTests.swift`
- `Tests/MacWallSceneGraphTests/SceneJSONValueTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphModelsTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphBuilderTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphHierarchyTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphLimitsAndSummaryTests.swift`
- `Tests/MacWallSceneGraphTests/SceneLocalFixtureGraphTests.swift`
- `Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json`

수정 파일:

- `Package.swift`
  - Assets/Graph production target, tests, Audit dependency 추가
- `Sources/MacWallSceneAudit/SceneAuditModels.swift`
  - `externalCandidate` resolution case 추가
- `Sources/MacWallSceneAudit/SceneJSONInspector.swift`
  - 자체 candidate 규칙 제거, Assets resolver 사용
- `Sources/MacWallSceneAudit/SceneAuditor.swift`
  - archive당 resolver 생성 및 inspector 전달
- `Tests/MacWallSceneAuditTests/SceneAuditorTests.swift`
  - owner-relative/정책 공유/schema 2 회귀 검증
- `docs/README.md`
- `docs/development-log.md`
- `docs/development-roadmap.md`
- `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- `docs/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md`

완료 단계에서 이동할 문서:

- `docs/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md`
  -> `docs/archive/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md`
- `docs/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md`
  -> `docs/archive/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md`

완료 기록:

- `docs/implemented/2026-08-04-scene-asset-resolver-typed-graph.md`

`README.md`, `README.ko.md`, `Sources/MacWallCore/Scene/SceneRenderPlan.swift`,
`Sources/MacWallApp/Playback/SceneWallpaperView.swift`는 사용자 동작이 바뀌지
않으므로 수정하지 않습니다.

---

## Preflight

- [ ] **Step 1: Confirm branch and clean baseline**

Run:

```bash
git status --short --branch
swift test --filter MacWallSceneFormatsTests
swift test --filter MacWallSceneAuditTests
swift test --filter SceneRenderPlanTests
```

Expected:

- intended branch is active
- no unrelated dirty files are included in this plan
- Formats 49 tests, Audit 17 tests, RenderPlan 2 tests pass at the recorded S1 baseline

If unrelated user changes exist, preserve them and stage only S2 files in every commit.

---

### Task 1: Canonical Scene Virtual Path

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallSceneAssets/SceneVirtualPath.swift`
- Create: `Tests/MacWallSceneAssetsTests/SceneVirtualPathTests.swift`

**Interfaces:**

- Consumes: S1 `MacWallSceneFormats`
- Produces: `SceneVirtualPath.init(canonicalPath:)`
- Produces: `SceneVirtualPath.resolving(reference:relativeTo:)`
- Produces: `SceneVirtualPathError`
- Consumed by: Tasks 2-13

- [ ] **Step 1: Add the Assets target and failing path tests**

Add these target declarations to `Package.swift`:

```swift
.target(
    name: "MacWallSceneAssets",
    dependencies: ["MacWallSceneFormats"]
),
.testTarget(
    name: "MacWallSceneAssetsTests",
    dependencies: [
        "MacWallSceneAssets",
        "MacWallSceneFormats",
        "MacWallSceneTestSupport"
    ]
),
```

Create `SceneVirtualPathTests.swift` with the exact behavior:

```swift
import XCTest
@testable import MacWallSceneAssets

final class SceneVirtualPathTests: XCTestCase {
    func testPreservesExactCaseAndUnicode() throws {
        let path = try SceneVirtualPath(
            canonicalPath: "재료/Texture.TEX"
        )
        XCTAssertEqual(path.rawValue, "재료/Texture.TEX")
    }

    func testResolvesOwnerRelativeDotSegments() throws {
        let owner = try SceneVirtualPath(
            canonicalPath: "models/sub/model.json"
        )
        XCTAssertEqual(
            try SceneVirtualPath.resolving(
                reference: "../materials/./base.json",
                relativeTo: owner
            ).rawValue,
            "models/materials/base.json"
        )
    }

    func testRejectsUnsafeOrEscapingReferences() throws {
        let owner = try SceneVirtualPath(
            canonicalPath: "models/model.json"
        )
        let cases: [(String, SceneVirtualPathError)] = [
            ("", .empty),
            ("/absolute.json", .absolute),
            (#"folder\file.json"#, .backslash),
            ("folder/\0file.json", .nul),
            ("folder//file.json", .emptyComponent),
            ("../../outside.json", .escapesRoot)
        ]

        for (reference, expected) in cases {
            XCTAssertThrowsError(
                try SceneVirtualPath.resolving(
                    reference: reference,
                    relativeTo: owner
                )
            ) { error in
                XCTAssertEqual(error as? SceneVirtualPathError, expected)
            }
        }
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneVirtualPathTests
```

Expected: compile failure because `SceneVirtualPath` and
`SceneVirtualPathError` do not exist.

- [ ] **Step 3: Implement canonical normalization**

Define these exact public declarations:

```swift
public enum SceneVirtualPathError: Error, Equatable, Sendable {
    case empty
    case absolute
    case backslash
    case nul
    case emptyComponent
    case escapesRoot
}

public struct SceneVirtualPath:
    Codable,
    Comparable,
    Hashable,
    Sendable
{
    public let rawValue: String

    public init(canonicalPath: String) throws

    public static func resolving(
        reference: String,
        relativeTo owner: SceneVirtualPath?
    ) throws -> SceneVirtualPath

    public static func < (
        lhs: SceneVirtualPath,
        rhs: SceneVirtualPath
    ) -> Bool
}
```

Implementation rules:

1. `init(canonicalPath:)` accepts only nonempty package paths with no absolute prefix, backslash, NUL, empty, `.` or `..` component.
2. `resolving` validates the raw reference before normalization.
3. When `owner` exists, start from `owner.rawValue` with its final filename component removed.
4. When `owner` is nil, start from package root.
5. Remove `.` and pop one component for `..`; reject a pop from the empty root.
6. Preserve every remaining component byte-for-byte as Swift `String`; do not lowercase, precompose, decompose, decode, trim, or standardize.
7. `Comparable` compares `rawValue` with Swift lexical ordering only for deterministic output.
8. Implement Codable manually; decoding must call `init(canonicalPath:)` so serialized input cannot bypass validation.

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneVirtualPathTests
```

Expected: all path tests pass.

Commit:

```bash
git add Package.swift Sources/MacWallSceneAssets/SceneVirtualPath.swift Tests/MacWallSceneAssetsTests/SceneVirtualPathTests.swift
git commit -m "feat(scene): add canonical virtual paths"
```

---

### Task 2: Package Asset Resolver and Provenance

**Files:**

- Create: `Sources/MacWallSceneAssets/SceneAssetModels.swift`
- Create: `Sources/MacWallSceneAssets/SceneAssetCandidatePolicy.swift`
- Create: `Sources/MacWallSceneAssets/ScenePackageAssetResolver.swift`
- Create: `Tests/MacWallSceneAssetsTests/ScenePackageAssetResolverTests.swift`

**Interfaces:**

- Consumes: Task 1 `SceneVirtualPath`, S1 `ScenePackageArchive`
- Produces: `SceneAssetRequest`, `SceneAssetResolution`, `SceneResolvedAsset`
- Produces: `SceneAssetSourcePolicy.s2`
- Produces: `ScenePackageAssetResolver.open(url:)`, `open(source:)`, `resolve`, `read`, `source`
- Consumed by: Tasks 3 and 6-13

- [ ] **Step 1: Write failing candidate, resolution, ambiguity, and bounded-read tests**

Build a synthetic package containing:

```text
scene.json
models/sub/model.json
models/materials/owner.json
materials/root.json
materials/base.tex
models/sub/base.tex
재료/Texture.TEX
```

The tests must assert:

```swift
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
```

Add separate tests for:

- document root exact before owner-relative
- explicit `./` and `../` owner-relative only
- extension-bearing texture root exact then owner-relative
- duplicate candidate path removed while preserving first origin
- exact case/Unicode lookup
- bare shader and `util/`, `models/util/`, `shaders/` as built-in candidates
- unknown missing reference as unresolved
- injected `externalPrefixes: ["shared/"]` as external candidate
- default production external prefix list empty
- `maximumCandidatesPerRequest: 1` returns invalid candidate-limit evidence
- path escape returns `.invalid` with `.pathEscape`
- read above maximum returns `.resourceLimit(.entryBytes)` before payload read
- resolved asset with a different resolver entry offset/length is rejected as `.identityMismatch`

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ScenePackageAssetResolverTests
```

Expected: compile failure because asset models and resolver do not exist.

- [ ] **Step 3: Add immutable asset models and policies**

Define these exact model shapes:

```swift
public enum SceneAssetRole:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
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
}

public enum SceneAssetCandidateOrigin:
    String,
    Codable,
    Equatable,
    Sendable
{
    case rootExact
    case ownerRelative
    case ownerTextureExtension
    case materialsTextureExtension
    case rootTextureExtension
}

public struct SceneAssetCandidate: Equatable, Sendable {
    public let path: SceneVirtualPath
    public let origin: SceneAssetCandidateOrigin
}

public struct SceneAssetEntryIdentity: Equatable, Sendable {
    public let relativeOffset: UInt64
    public let byteCount: UInt64
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
}

public enum SceneAssetResolutionKind:
    String,
    Codable,
    Equatable,
    Sendable
{
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
    case ambiguous(
        selected: SceneVirtualPath,
        alternatives: [SceneVirtualPath]
    )
}

public struct SceneAssetResolution: Equatable, Sendable {
    public let request: SceneAssetRequest
    public let candidates: [SceneAssetCandidate]
    public let kind: SceneAssetResolutionKind
    public let selected: SceneResolvedAsset?
    public let issues: [SceneAssetResolutionIssue]
}

public struct SceneAssetResolverLimits: Equatable, Sendable {
    public var maximumCandidatesPerRequest: Int

    public init(maximumCandidatesPerRequest: Int = 16)
}

public struct SceneAssetSourcePolicy: Equatable, Sendable {
    public let version: Int
    public let builtInPrefixes: [String]
    public let externalPrefixes: [String]
    public let classifyBareShadersAsBuiltIn: Bool

    public static let s2: SceneAssetSourcePolicy
}

public struct SceneAssetPackageMetadata: Equatable, Sendable {
    public let version: String
    public let isVerifiedVersion: Bool
    public let entryCount: Int
}

public enum SceneAssetPackageIssue: Equatable, Sendable {
    case unverifiedVersion(String)
    case overlappingEntryRange(
        first: SceneVirtualPath,
        second: SceneVirtualPath
    )
}

public enum SceneAssetAccessError: Error, Equatable, Sendable {
    case notPackageAsset
    case missingEntry
    case identityMismatch
}
```

All stored properties receive explicit public initializers in their declaring
files. `SceneAssetSourcePolicy.s2` is exactly:

```swift
SceneAssetSourcePolicy(
    version: 1,
    builtInPrefixes: ["models/util/", "shaders/", "util/"],
    externalPrefixes: [],
    classifyBareShadersAsBuiltIn: true
)
```

Keep candidate construction in the dedicated file with these internal types:

```swift
struct SceneAssetCandidateBuildResult: Sendable {
    let candidates: [SceneAssetCandidate]
    let invalidIssue: SceneAssetResolutionIssue?
}

struct SceneAssetCandidatePolicy: Sendable {
    let limits: SceneAssetResolverLimits

    func candidates(
        for request: SceneAssetRequest
    ) -> SceneAssetCandidateBuildResult
}
```

`SceneAssetSourcePolicy` classifies only after candidate lookup fails. Prefix
matching is exact case-sensitive matching against the validated requested path;
bare-shader matching requires role `.shader`, no `/`, and no path extension.

- [ ] **Step 4: Implement candidate order and resolver access**

Define the resolver API:

```swift
public struct ScenePackageAssetResolver: Sendable {
    public let package: SceneAssetPackageMetadata
    public let packageIssues: [SceneAssetPackageIssue]

    public init(
        archive: ScenePackageArchive,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    )

    public static func open(
        url: URL,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> ScenePackageAssetResolver

    public static func open(
        source: any SceneByteSource,
        limits: SceneAssetResolverLimits = .init(),
        sourcePolicy: SceneAssetSourcePolicy = .s2
    ) throws -> ScenePackageAssetResolver

    public func resolve(
        _ request: SceneAssetRequest
    ) -> SceneAssetResolution

    public func source(
        for asset: SceneResolvedAsset
    ) throws -> SceneBoundedByteSource

    public func read(
        _ asset: SceneResolvedAsset,
        maximumBytes: UInt64
    ) throws -> Data
}
```

Candidate algorithm:

1. Reject empty/backslash/NUL/absolute references before producing candidates.
2. If reference begins `./` or `../`, produce owner-relative candidates only.
3. For non-texture roles, produce root exact then owner-relative.
4. For extension-bearing texture references, produce root exact then owner-relative.
5. For texture shorthand, produce owner directory plus `.tex`, `materials/` plus `.tex`, then root plus `.tex`.
6. Dedupe by exact `SceneVirtualPath` while preserving first candidate and origin.
7. Check limit before archive lookup; excess returns `.invalid` and `.candidateLimit`.
8. Select the first existing candidate. Record later existing candidates in one sorted `.ambiguous` issue.
9. If none exist, classify only through `SceneAssetSourcePolicy`; otherwise return unresolved.
10. Map virtual-path root escape to `.pathEscape`; map all other path failures to `.invalidReference`.

`source(for:)` re-looks up the canonical path and compares relative offset and
byte count to the asset identity before returning `archive.source(for:)`.
`read` delegates to `archive.read(entry:maximumBytes:)`; it must not expose an
unbounded overload.

- [ ] **Step 5: Run GREEN and commit**

Run:

```bash
swift test --filter MacWallSceneAssetsTests
```

Expected: all Assets tests pass with no whole-package payload read.

Commit:

```bash
git add Sources/MacWallSceneAssets Tests/MacWallSceneAssetsTests
git commit -m "feat(scene): resolve package asset references"
```

---

### Task 3: Share Resolver Policy with Scene Audit

**Files:**

- Modify: `Package.swift`
- Modify: `Sources/MacWallSceneAudit/SceneAuditModels.swift`
- Modify: `Sources/MacWallSceneAudit/SceneJSONInspector.swift`
- Modify: `Sources/MacWallSceneAudit/SceneAuditor.swift`
- Modify: `Tests/MacWallSceneAuditTests/SceneAuditorTests.swift`

**Interfaces:**

- Consumes: Task 2 `ScenePackageAssetResolver`
- Preserves: `SceneAuditReport.schemaVersion == 2`
- Produces: `SceneAuditDependencyResolution.externalCandidate`
- Removes: Audit-local texture and built-in candidate construction

- [ ] **Step 1: Write resolver-sharing regression tests**

Add tests proving:

```swift
XCTAssertEqual(report.schemaVersion, 2)
XCTAssertTrue(report.dependencies.contains {
    $0.ownerPath == "models/sub/model.json"
        && $0.requestedPath == "../materials/base.json"
        && $0.resolvedPath == "models/materials/base.json"
        && $0.resolution == .package
})
```

Also preserve existing expectations for `genericimage4` as built-in,
`effects/missing/effect.json` as unresolved, deterministic encoding, and the
tracked S1 aggregate catalog.

- [ ] **Step 2: Run the focused test before migration**

Run:

```bash
swift test --filter SceneAuditorTests
```

Expected: the new owner-relative assertion fails under the Audit-local exact/
texture-only resolver.

- [ ] **Step 3: Route Audit dependency inspection through Assets**

Change `Package.swift`:

```swift
.target(
    name: "MacWallSceneAudit",
    dependencies: [
        "MacWallSceneFormats",
        "MacWallSceneAssets"
    ]
),
```

Add `.externalCandidate` to `SceneAuditDependencyResolution` without changing
schema version 2.

Change the inspector signature to:

```swift
func inspect(
    scene: [String: Any],
    documents: [String: Any],
    resolver: ScenePackageAssetResolver
) -> SceneJSONAuditEvidence
```

Map JSON keys to roles as follows:

```text
image -> model
model -> model
material -> material
effect -> effect
file -> document
font -> font
particle -> particle
shader -> shader
sound -> sound
texture/textures -> texture
```

For every reference, construct `SceneAssetRequest` with the exact owner entry
path, call `resolver.resolve`, and map the result kind to Audit resolution.
Remove `packagePaths`, the local texture candidate array, and local built-in
prefix checks from `SceneJSONInspector`.

In `SceneAuditor`, construct one resolver from the already-open archive and
pass it to the inspector. Do not reopen the package.

- [ ] **Step 4: Run Audit and Assets regression suites**

Run:

```bash
swift test --filter MacWallSceneAssetsTests
swift test --filter MacWallSceneAuditTests
```

Expected: Assets tests pass; Audit schema 2 tests and local aggregate catalog
pass with no error diagnostic or whole-package read.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MacWallSceneAudit Tests/MacWallSceneAuditTests/SceneAuditorTests.swift
git commit -m "refactor(scene): share asset resolution with audit"
```

---

### Task 4: Typed JSON Boundary and Graph Limits

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallSceneGraph/SceneJSONValue.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphPrimitives.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneJSONValueTests.swift`

**Interfaces:**

- Consumes: Task 2 Assets target
- Produces: `SceneJSONValue`
- Produces: internal `SceneJSONDocumentDecoder.decode(_:)`
- Produces: `SceneGraphLimits`
- Consumed by: Tasks 5-13

- [ ] **Step 1: Add the Graph target and failing JSON tests**

Add:

```swift
.target(
    name: "MacWallSceneGraph",
    dependencies: ["MacWallSceneAssets"]
),
.testTarget(
    name: "MacWallSceneGraphTests",
    dependencies: [
        "MacWallSceneGraph",
        "MacWallSceneAssets",
        "MacWallSceneFormats",
        "MacWallSceneTestSupport"
    ]
),
```

Tests must distinguish all JSON cases:

```swift
let value = try SceneJSONDocumentDecoder(
    maximumDepth: 8
).decode(Data(#"{"bool":true,"int":7,"double":7.5,"null":null}"#.utf8))

XCTAssertEqual(
    value,
    .object([
        "bool": .bool(true),
        "int": .integer(7),
        "double": .number(7.5),
        "null": .null
    ])
)
```

Add Codable round-trip, sorted-key JSON encoding, malformed JSON, root fragment,
and injected depth 2 rejection tests.

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneJSONValueTests
```

Expected: compile failure because Graph JSON types do not exist.

- [ ] **Step 3: Implement the typed value and bounded conversion**

Define:

```swift
public enum SceneJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([SceneJSONValue])
    case object([String: SceneJSONValue])
}

extension SceneJSONValue: Codable {}

enum SceneJSONDocumentError: Error, Equatable {
    case malformed
    case depthLimit(maximum: Int)
}

struct SceneJSONDocumentDecoder {
    let maximumDepth: Int
    func decode(_ data: Data) throws -> SceneJSONValue
}
```

Implementation rules:

1. Parse with `JSONSerialization.jsonObject(options: [.fragmentsAllowed])` internally.
2. Walk `[String: Any]`/`[Any]` with an explicit `(value, depth)` stack before conversion and reject depth above the configured maximum.
3. Convert only after validation; recursion is then bounded to at most 256 in production.
4. Use CoreFoundation type IDs to distinguish `CFBoolean` from `CFNumber`.
5. Use `CFNumberIsFloatType`; store exactly representable signed integers as `.integer`, all floating JSON numbers as `.number`.
6. Reject non-finite numeric values.
7. Implement Codable manually so object keys encode through keyed containers; canonical byte ordering is Task 11's encoder responsibility.

Add production limits:

```swift
public struct SceneGraphLimits: Equatable, Sendable {
    public var maximumJSONEntryBytes: UInt64
    public var maximumCumulativeJSONBytes: UInt64
    public var maximumNodeCount: Int
    public var maximumDependencyEdgeCount: Int
    public var maximumAnimationKeyframeCount: Int
    public var maximumJSONDepth: Int
    public var maximumHierarchyDepth: Int

    public init(
        maximumJSONEntryBytes: UInt64 = 16 * 1_024 * 1_024,
        maximumCumulativeJSONBytes: UInt64 = 64 * 1_024 * 1_024,
        maximumNodeCount: Int = 100_000,
        maximumDependencyEdgeCount: Int = 500_000,
        maximumAnimationKeyframeCount: Int = 1_000_000,
        maximumJSONDepth: Int = 256,
        maximumHierarchyDepth: Int = 4_096
    )
}
```

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneJSONValueTests
git add Package.swift Sources/MacWallSceneGraph/SceneJSONValue.swift Sources/MacWallSceneGraph/SceneGraphPrimitives.swift Tests/MacWallSceneGraphTests/SceneJSONValueTests.swift
git commit -m "feat(scene): add typed graph JSON boundary"
```

Expected: all typed JSON and default-limit tests pass.

---

### Task 5: Immutable Typed Graph Model

**Files:**

- Modify: `Sources/MacWallSceneGraph/SceneGraphPrimitives.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphNode.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphHierarchy.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphResource.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphAnimation.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphDocument.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphModelsTests.swift`

**Interfaces:**

- Consumes: Task 4 `SceneJSONValue`, `SceneGraphLimits`
- Produces: immutable graph public contract used by all later tasks and S3

- [ ] **Step 1: Write model construction and Sendable compile tests**

Construct a document with one image node, one hierarchy edge, one material,
one texture dependency, one animation, one script metadata record and assert
exact equality. Add:

```swift
private func requireSendable<T: Sendable>(_: T.Type) {}

func testPublicGraphValuesAreSendable() {
    requireSendable(SceneGraphDocument.self)
    requireSendable(SceneGraphBuildResult.self)
    requireSendable(SceneGraphNode.self)
    requireSendable(SceneGraphResource.self)
    requireSendable(SceneAnimationTrack.self)
}
```

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphModelsTests
```

Expected: compile failure because graph model types do not exist.

- [ ] **Step 3: Add exact primitive, node, and hierarchy types**

Define status and diagnostics:

```swift
public enum SceneGraphStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case exact
    case degraded
    case unsupported
    case invalid
}

public enum SceneGraphDiagnosticSeverity:
    String,
    Codable,
    Equatable,
    Sendable
{
    case info
    case warning
    case error
}

public struct SceneGraphDiagnostic: Equatable, Sendable {
    public let severity: SceneGraphDiagnosticSeverity
    public let code: String
    public let sourcePath: SceneVirtualPath?
    public let nodeID: SceneNodeID?
    public let jsonPath: String?
    public let dependencyPath: [SceneVirtualPath]
    public let arguments: [String]
}
```

Define the numeric primitives exactly:

```swift
public struct SceneGraphCanvas: Equatable, Sendable {
    public let width: Double
    public let height: Double
}

public struct SceneGraphVector3: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
}

public struct SceneGraphSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
}

public struct SceneGraphColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
}
```

Define IDs and node payload:

```swift
public struct SceneNodeID:
    Codable,
    Comparable,
    Hashable,
    Sendable
{
    public let documentPath: SceneVirtualPath
    public let objectIndex: Int
    public var rawValue: String { get }

    public init(
        documentPath: SceneVirtualPath,
        objectIndex: Int
    )
}

public enum SceneSourceIdentifier:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case integer(Int64)
    case string(String)
}

public enum SceneNodePayload: Equatable, Sendable {
    case image(reference: String)
    case text(SceneJSONValue)
    case particle(reference: String)
    case sound(reference: String)
    case model(reference: String)
    case composition(reference: String?)
    case fullscreen
    case unknown(typeName: String?, rawValue: SceneJSONValue)
}

public enum SceneNodeKind: Equatable, Sendable {
    case image
    case text
    case particle
    case sound
    case model
    case composition
    case fullscreen
    case unknown(String?)
}

extension SceneNodePayload {
    public var kind: SceneNodeKind { get }
}

public struct SceneGraphNode: Equatable, Sendable {
    public let id: SceneNodeID
    public let sourceIdentifier: SceneSourceIdentifier?
    public let sourceOrder: Int
    public let name: String?
    public let payload: SceneNodePayload
    public let visible: Bool?
    public let enabled: Bool?
    public let zOrder: Double?
    public let origin: SceneGraphVector3?
    public let pivot: SceneGraphVector3?
    public let position: SceneGraphVector3?
    public let scale: SceneGraphVector3?
    public let angles: SceneGraphVector3?
    public let size: SceneGraphSize?
    public let opacity: Double?
    public let color: SceneGraphColor?
    public let unknownFields: [String: SceneJSONValue]
}
```

`SceneNodeID.rawValue` is exactly
`<documentPath>#objects[<zero-based-index>]`.

Define hierarchy/reference types:

```swift
public enum SceneNodeReferenceResolution: Equatable, Sendable {
    case resolved(SceneNodeID)
    case missing
    case ambiguous([SceneNodeID])
}

public struct SceneHierarchyEdge: Equatable, Sendable {
    public let childID: SceneNodeID
    public let requestedParent: SceneSourceIdentifier
    public let resolution: SceneNodeReferenceResolution
}

public struct ScenePropertyOverride: Equatable, Sendable {
    public let propertyPath: String
    public let value: SceneJSONValue
}

public struct SceneInstanceEdge: Equatable, Sendable {
    public let instanceID: SceneNodeID
    public let requestedSource: SceneSourceIdentifier
    public let resolution: SceneNodeReferenceResolution
    public let overrides: [ScenePropertyOverride]
}
```

- [ ] **Step 4: Add resource, animation, script, document, and result types**

Define stable resource identity and dependency owner:

```swift
public enum SceneResourceKind:
    String,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case model
    case material
    case effect
    case shader
    case texture
}

public struct SceneResourceID:
    Codable,
    Comparable,
    Hashable,
    Sendable
{
    public let kind: SceneResourceKind
    public let path: SceneVirtualPath
    public var rawValue: String { get }

    public init(kind: SceneResourceKind, path: SceneVirtualPath)
}

public enum SceneDependencyOwner: Equatable, Sendable {
    case node(SceneNodeID)
    case resource(SceneResourceID)
    case materialPass(material: SceneResourceID, index: Int)
}

public struct SceneDependencyEdge: Equatable, Sendable {
    public let owner: SceneDependencyOwner
    public let key: String
    public let request: SceneAssetRequest
    public let resolution: SceneAssetResolution
}
```

Add these exact resource records with public initializers:

```swift
public struct SceneModelResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let materialDependency: SceneDependencyEdge?
    public let unknownFields: [String: SceneJSONValue]
}

public struct SceneMaterialResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let passes: [SceneMaterialPass]
    public let unknownFields: [String: SceneJSONValue]
}

public struct SceneMaterialPass: Equatable, Sendable {
    public let index: Int
    public let sourcePath: SceneVirtualPath?
    public let documentDependency: SceneDependencyEdge?
    public let shaderDependency: SceneDependencyEdge?
    public let textureBindings: [SceneTextureBinding]
    public let effectDependencies: [SceneDependencyEdge]
    public let rawValue: SceneJSONValue
    public let unknownFields: [String: SceneJSONValue]
}

public struct SceneTextureBinding: Equatable, Sendable {
    public let slot: String?
    public let rawValue: SceneJSONValue
    public let dependency: SceneDependencyEdge
}

public struct SceneEffectResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let dependencies: [SceneDependencyEdge]
    public let unknownFields: [String: SceneJSONValue]
}

public struct SceneShaderResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let resolution: SceneAssetResolution
}

public struct SceneTextureResource: Equatable, Sendable {
    public let id: SceneResourceID
    public let path: SceneVirtualPath
    public let resolution: SceneAssetResolution
}

public enum SceneGraphResource: Equatable, Sendable {
    case model(SceneModelResource)
    case material(SceneMaterialResource)
    case effect(SceneEffectResource)
    case shader(SceneShaderResource)
    case texture(SceneTextureResource)

    public var id: SceneResourceID { get }
}
```

`SceneResourceID.rawValue` is exactly `<kind.rawValue>:<path.rawValue>` and
`Comparable` compares that value lexically. For built-in/external candidates,
`path` is the first validated candidate path; no host path or payload is stored.
Every public struct in this task receives an explicit memberwise public
initializer so S3 can consume the model without `@testable` imports.

Define animation source-preserving types:

```swift
public enum SceneAnimationValueKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case scalar
    case vector2
    case vector3
    case raw
}

public enum SceneAnimationTrackStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case exact
    case degraded
}

public struct SceneAnimationKeyframe: Equatable, Sendable {
    public let frame: Double?
    public let time: Double?
    public let value: SceneJSONValue?
    public let interpolation: SceneJSONValue?
    public let unknownFields: [String: SceneJSONValue]
}

public struct SceneAnimationChannel: Equatable, Sendable {
    public let name: String
    public let keyframes: [SceneAnimationKeyframe]
    public let rawValue: SceneJSONValue
}

public struct SceneAnimationTrack: Equatable, Sendable {
    public let nodeID: SceneNodeID
    public let propertyPath: String
    public let valueKind: SceneAnimationValueKind
    public let fps: Double?
    public let duration: Double?
    public let isRelative: Bool?
    public let channels: [SceneAnimationChannel]
    public let status: SceneAnimationTrackStatus
    public let rawValue: SceneJSONValue
}
```

Define document/result:

```swift
public struct SceneScriptMetadata: Equatable, Sendable {
    public let ownerPath: SceneVirtualPath
    public let nodeID: SceneNodeID?
    public let jsonPath: String
    public let source: String
    public let handlerNames: [String]
}

public struct SceneGraphDocument: Equatable, Sendable {
    public let package: SceneAssetPackageMetadata
    public let sourcePath: SceneVirtualPath
    public let canvas: SceneGraphCanvas?
    public let sceneMetadata: [String: SceneJSONValue]
    public let nodes: [SceneGraphNode]
    public let hierarchyEdges: [SceneHierarchyEdge]
    public let instanceEdges: [SceneInstanceEdge]
    public let resources: [SceneGraphResource]
    public let dependencies: [SceneDependencyEdge]
    public let animations: [SceneAnimationTrack]
    public let scripts: [SceneScriptMetadata]
}

public struct SceneGraphBuildResult: Equatable, Sendable {
    public let document: SceneGraphDocument?
    public let status: SceneGraphStatus
    public let diagnostics: [SceneGraphDiagnostic]
}
```

- [ ] **Step 5: Run GREEN and commit**

```bash
swift test --filter SceneGraphModelsTests
git add Sources/MacWallSceneGraph Tests/MacWallSceneGraphTests/SceneGraphModelsTests.swift
git commit -m "feat(scene): define typed scene graph model"
```

Expected: model equality and Sendable compile tests pass.

---

### Task 6: Root Document and Typed Node Build

**Files:**

- Create: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`
- Create: `Sources/MacWallSceneGraph/SceneGraphNodeParser.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphBuilderTests.swift`

**Interfaces:**

- Consumes: Tasks 2, 4, 5
- Produces: `SceneGraphBuilder.build(url:)`
- Produces: `SceneGraphBuilder.build(resolver:)`
- Initially produces: nodes with empty hierarchy/resource/animation/script arrays
- Extended by: Tasks 7-10

- [ ] **Step 1: Write failing root/node tests**

Use one synthetic package with image, text, particle, sound, model,
composition, fullscreen, and unknown objects. Assert:

```swift
XCTAssertEqual(
    result.document?.nodes.map(\.id.rawValue),
    (0..<8).map { "scene.json#objects[\($0)]" }
)
XCTAssertEqual(
    result.document?.nodes.map(\.payload.kind),
    [
        .image, .text, .particle, .sound,
        .model, .composition, .fullscreen, .unknown(nil)
    ]
)
XCTAssertEqual(result.status, .unsupported)
XCTAssertTrue(result.diagnostics.contains {
    $0.code == "graph.unknown-node"
})
```

Also test:

- integer/string/missing source IDs preserved
- source order above 16 with no layer cap
- `general.orthogonalprojection` canvas parsing
- typed common `origin`, `position`, `scale`, `angles`, `size`, `alpha`, `color`, visibility, enabled, z order
- wrapped `{ "value": value }` base properties
- unknown node retains full raw value
- unknown noncritical field retained and degrades status
- missing `objects` treated as empty exact graph
- non-array `objects`, non-object entry, malformed JSON, missing `scene.json`, oversized root JSON, and invalid package return stable diagnostics

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphBuilderTests
```

Expected: compile failure because `SceneGraphBuilder` does not exist.

- [ ] **Step 3: Implement phase orchestration and node parsing**

Define:

```swift
public struct SceneGraphBuilder: Sendable {
    public init(limits: SceneGraphLimits = .init())

    public func build(url: URL) -> SceneGraphBuildResult

    public func build(
        resolver: ScenePackageAssetResolver
    ) -> SceneGraphBuildResult
}
```

Build rules:

1. `build(url:)` opens one resolver and maps open failures to `graph.invalid-package`, error severity, invalid status, nil document.
2. Resolve `scene.json` with role `.scene`; missing/invalid root returns `graph.malformed-scene-json`, invalid, nil document.
3. Check 16 MiB entry and cumulative limits before bounded read.
4. Decode through `SceneJSONDocumentDecoder(maximumDepth:)`; require object root.
5. Parse canvas from `general.orthogonalprojection.width/height` as finite positive numbers.
6. Preserve all root keys except `objects` in `sceneMetadata`.
7. Check `objects.count` against `maximumNodeCount` before reserving or converting node storage.
8. Require each `objects` element to be an object; malformed elements produce `graph.invalid-property` and remain as unknown nodes rather than changing indices.
9. Build `SceneNodeID` from source path and original zero-based index.
10. Parse source ID only from integer/string; retain malformed raw ID in unknown fields and add `graph.invalid-property`.
11. Classify payload by keys in exact order: image, text, particle, sound, model, composition, fullscreen, then exact lowercase `type` values for those same kinds; otherwise preserve the original type string as unknown.
12. Extract known common fields and retain every unconsumed key in `unknownFields`.
13. Parse wrapped `value` without evaluating `animation`.
14. Never decode textures or stop at 16 nodes.
15. Retain the typed raw object array in the builder's internal phase state for hierarchy, dependency, script, and animation parsers; do not expose it publicly.
16. Convert resolver package issues to deterministic diagnostics: unverified version and overlapping entry range are warning/degraded evidence.

Common field mapping is exact: `visible`, `enabled`, `origin`, `pivot`,
`position`, `scale`, `angles`, `size`, `alpha`, `color`, and first present of
`zorder`/`zindex`. String vectors accept comma or ASCII whitespace separators;
arrays require finite numeric values. Unrecognized aliases remain raw rather
than being guessed.

Add internal status accumulation with precedence
`invalid > unsupported > degraded > exact`, then sort diagnostics by severity,
source path, object index, JSON path, code, arguments. Severity rank is
`error`, `warning`, `info`; nil path/ID/JSON path sorts before a present value.

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneGraphBuilderTests
git add Sources/MacWallSceneGraph/SceneGraphBuilder.swift Sources/MacWallSceneGraph/SceneGraphNodeParser.swift Tests/MacWallSceneGraphTests/SceneGraphBuilderTests.swift
git commit -m "feat(scene): build typed nodes from scene JSON"
```

Expected: all node/root tests pass; existing Core prototype tests remain unchanged.

---

### Task 7: Parent, Instance, Override, and Cycle Validation

**Files:**

- Create: `Sources/MacWallSceneGraph/SceneGraphHierarchyResolver.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphHierarchyTests.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`

**Interfaces:**

- Consumes: Task 5 hierarchy models, Task 6 nodes
- Produces: deterministic hierarchy/instance edges and diagnostics

- [ ] **Step 1: Write failing hierarchy tests**

Cover:

```swift
XCTAssertEqual(
    document.hierarchyEdges,
    [
        SceneHierarchyEdge(
            childID: nodes[1].id,
            requestedParent: .integer(1),
            resolution: .resolved(nodes[0].id)
        )
    ]
)
```

Add cases for:

- integer and string source ID references
- missing parent/source retained as `.missing`
- duplicate source ID preserves both nodes and emits `graph.duplicate-source-id`
- duplicate unreferenced ID degrades status
- referenced duplicate resolves as `.ambiguous` and makes status unsupported
- sparse `instanceoverride` object sorted into property-path/value pairs
- override array records with explicit `property` and `value`
- parent self-cycle, multi-node parent cycle, instance cycle
- cycle path order starts at lexically smallest `SceneNodeID`
- injected hierarchy depth 2 rejects a chain of length 3
- 10,000-node chain uses an explicit work stack without recursive overflow

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphHierarchyTests
```

Expected: edges are empty or hierarchy resolver symbols are missing.

- [ ] **Step 3: Implement multimap linking and iterative validation**

Implementation rules:

1. Build `[SceneSourceIdentifier: [SceneNodeID]]` in source order.
2. Emit one duplicate diagnostic per duplicate identifier with sorted internal IDs.
3. Parse `parent` and `instance` through the same scalar identifier helper used for node IDs.
4. Resolve to `.resolved`, `.missing`, or `.ambiguous`; never select the first ambiguous target.
5. Convert override object keys to `ScenePropertyOverride` sorted by property path.
6. Convert override arrays in source order, rejecting malformed entries with `graph.invalid-property` while retaining valid entries.
7. Build adjacency only from resolved edges.
8. Detect parent and instance cycles with iterative color-state DFS and an explicit stack.
9. Canonicalize cycle paths by rotating to the lexically smallest node ID and choose the lexically smaller direction when both describe the same cycle.
10. Record parent cycles as `graph.parent-cycle`, instance cycles as `graph.instance-cycle`, error severity and invalid status.
11. Record missing parent as `graph.missing-parent` and missing instance source as `graph.missing-instance`; ambiguous edges include sorted candidate node IDs in diagnostic arguments.
12. Enforce `maximumHierarchyDepth` during traversal and map overflow to `graph.resource-limit`, invalid.
13. Missing/ambiguous edges are unsupported but do not delete nodes.

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneGraphHierarchyTests
swift test --filter SceneGraphBuilderTests
git add Sources/MacWallSceneGraph/SceneGraphHierarchyResolver.swift Sources/MacWallSceneGraph/SceneGraphBuilder.swift Tests/MacWallSceneGraphTests/SceneGraphHierarchyTests.swift
git commit -m "feat(scene): resolve graph hierarchy and instances"
```

Expected: hierarchy and node build suites pass.

---

### Task 8: Model, Material, Pass, and Texture Dependency Graph

**Files:**

- Create: `Sources/MacWallSceneGraph/SceneGraphResourceParser.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`

**Interfaces:**

- Consumes: Task 2 resolver, Task 5 resource models, Task 6 nodes
- Produces: memoized model/material/pass/texture resources and dependencies
- Extended by: Task 9 effect/shader/script metadata

- [ ] **Step 1: Write failing resource-chain tests**

Use this synthetic chain:

```text
scene.json object.image -> models/background.json
models/background.json material -> materials/background.json
materials/background.json passes[0].shader -> genericimage4
materials/background.json passes[0].textures[0] -> background
background -> materials/background.tex
```

Assert:

```swift
XCTAssertEqual(
    document.resources.map(\.id.rawValue),
    [
        "material:materials/background.json",
        "model:models/background.json",
        "shader:genericimage4",
        "texture:materials/background.tex"
    ]
)
XCTAssertEqual(
    document.dependencies.map(\.resolution.kind),
    [.package, .package, .builtInCandidate, .package]
)
```

Add cases for:

- two nodes sharing the same model/material/texture produce one resource record and separate node edges
- owner-relative model/material document reference
- root versus owner ambiguity diagnostic carried into graph diagnostics
- material top-level `texture`/`textures`
- inline dictionary pass and string pass-document reference
- texture binding string and object `{ "slot": "albedo", "texture": "base" }`
- missing model/material/texture maps to stable unresolved diagnostics and unsupported
- invalid auxiliary JSON retains the owner node and returns unsupported rather than nil document
- auxiliary JSON entry and cumulative byte limits
- no texture payload source/read call

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphResourceTests
```

Expected: resources and dependency edges are empty.

- [ ] **Step 3: Implement on-demand memoized resource traversal**

Resource traversal rules:

1. Start only from asset-bearing node payloads; do not scan every package JSON file.
2. Map image references to `.model`, model node references to `.model`, particle to `.particle`, sound to `.sound`, and composition reference to `.document`.
3. Add one node dependency edge before following a resolved package asset.
4. Parse each canonical model/material/pass path once using a cache keyed by `(role, path)`.
5. Count every bounded JSON read against `maximumCumulativeJSONBytes` with checked addition.
6. Model documents consume `material`; preserve all other fields.
7. Material documents parse ordered `passes`; a dictionary is inline, while a string creates a `.pass` dependency and records its resolved source path on the nested pass.
8. Each pass parses `shader`, `texture`, `textures`, `effect`, and `effects`; preserve all other fields.
9. Texture binding objects retain raw value and optional `slot`; resolve their `texture`, `file`, or string value.
10. Add one `SceneTextureResource` only for package-resolved textures. Add shader candidate resource records for package or built-in resolutions without reading shader payload.
11. Convert resolver issues to exact asset diagnostics: `asset.invalid-reference`, `asset.path-escape`, `asset.ambiguous-resolution`, `asset.builtin-candidate`, `asset.external-candidate`, and `asset.unresolved`.
12. Add `graph.unresolved-material` when a model's material is unavailable and `graph.unresolved-texture` when a pass texture is unavailable.
13. Sort resources by `SceneResourceID`; preserve pass/texture binding source order.
14. Stop before adding an edge beyond `maximumDependencyEdgeCount`; emit `graph.resource-limit` and invalid status.

Do not call `resolver.source(for:)` or texture format readers in this task.

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneGraphResourceTests
swift test --filter SceneGraphBuilderTests
git add Sources/MacWallSceneGraph/SceneGraphResourceParser.swift Sources/MacWallSceneGraph/SceneGraphBuilder.swift Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift
git commit -m "feat(scene): build material dependency graph"
```

Expected: resource graph and node suites pass.

---

### Task 9: Effect, Shader, and SceneScript Metadata

**Files:**

- Modify: `Sources/MacWallSceneGraph/SceneGraphResourceParser.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`
- Modify: `Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift`

**Interfaces:**

- Consumes: Task 8 resource traversal
- Produces: effect resource records, custom shader dependencies, script metadata
- Does not produce: executable script/shader/effect objects

- [ ] **Step 1: Add failing metadata-only tests**

Add a material pass with a package effect document, a custom package shader,
a bare built-in shader, nested effect texture reference, and inline scripts at
scene, node, material, and effect locations.

Assert all four owner/path pairs are present:

```swift
XCTAssertEqual(document.scripts.count, 4)
XCTAssertTrue(document.scripts.contains {
    $0.ownerPath.rawValue == "scene.json"
        && $0.jsonPath == "$.script"
})
XCTAssertTrue(document.scripts.contains {
    $0.ownerPath.rawValue == "scene.json"
        && $0.jsonPath == "$.objects[0].script"
})
XCTAssertTrue(document.scripts.contains {
    $0.ownerPath.rawValue == "materials/background.json"
        && $0.jsonPath == "$.script"
})
XCTAssertTrue(document.scripts.contains {
    $0.ownerPath.rawValue == "effects/glow/effect.json"
        && $0.jsonPath == "$.script"
})
XCTAssertTrue(result.diagnostics.contains {
    $0.code == "graph.scenescript-preserved-not-executed"
})
XCTAssertTrue(result.diagnostics.contains {
    $0.code == "graph.unsupported-effect"
})
XCTAssertEqual(result.status, .unsupported)
```

Verify handler extraction returns sorted unique names for
`init`, `update`, `applyUserProperties`, and arbitrary valid function names.
Verify strings inside comments are not claimed as executable handlers; the
source is still retained verbatim.

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphResourceTests
```

Expected: scripts/effect metadata are absent.

- [ ] **Step 3: Preserve metadata without execution**

Implementation rules:

1. Resolve effect document references with role `.effect`; parse each package effect once.
2. Recursively inspect scene, node, model, material, pass, and effect JSON for the known asset keys from Task 3 using an explicit stack and deterministic key ordering.
3. Create dependency edges for texture, shader, model, material, sound, font, particle, effect, and file references with their mapped role; dedupe by owner, JSON path, role, and requested string so Task 8 edges are not duplicated.
4. Record custom package shader and built-in shader as `SceneShaderResource`; never compile or translate source.
5. Discover any string value whose exact key is `script` in scene/node/resource JSON.
6. Store source verbatim with owner path, optional node ID, and JSON path.
7. Extract handler names with a small lexical scanner that skips string literals, line comments, and block comments before matching function declarations; sort and dedupe names.
8. Emit one `graph.scenescript-preserved-not-executed` diagnostic per script and one `graph.unsupported-effect` per effect resource.
9. Effect, custom shader, and script evidence makes status unsupported.
10. Sort scripts by owner path, optional node ID, then JSON path.
11. Do not import JavaScriptCore, Metal, AppKit, WebKit, or execute content.

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneGraphResourceTests
git add Sources/MacWallSceneGraph/SceneGraphResourceParser.swift Sources/MacWallSceneGraph/SceneGraphBuilder.swift Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift
git commit -m "feat(scene): preserve effect and script metadata"
```

Expected: metadata tests pass with no execution dependency.

---

### Task 10: Source-Preserving Animation Tracks

**Files:**

- Create: `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`

**Interfaces:**

- Consumes: Task 5 animation model, Task 6 node raw properties
- Produces: ordered typed/raw animation tracks

- [ ] **Step 1: Write failing scalar/vector/raw animation tests**

Use source wrappers matching observed Scene data:

```json
{
  "origin": {
    "value": "10 20 0",
    "animation": {
      "options": {"fps": 30, "length": 60, "relative": false},
      "c0": [{"frame": 0, "value": 10}, {"frame": 30, "value": 20}],
      "c1": [{"frame": 0, "value": 20}, {"frame": 30, "value": 40}],
      "c2": [{"frame": 0, "value": 0}, {"frame": 30, "value": 0}]
    }
  }
}
```

Assert `valueKind == .vector3`, channel order `c0,c1,c2`, frame 30 maps to
time 1.0, options are preserved, and raw animation remains available.

Add cases for:

- scalar alpha
- vector2 size
- unknown property raw track
- fractional frame/time and explicit time values
- interpolation/easing field preservation
- malformed channel/keyframe retained as degraded raw track with `graph.invalid-property`
- nonpositive/malformed fps leaves time nil rather than dividing
- source key order does not affect deterministic channel order
- injected keyframe limit stops at the boundary and invalidates the graph

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphAnimationTests
```

Expected: animation array is empty.

- [ ] **Step 3: Implement iterative animation discovery and parsing**

Implementation rules:

1. Inspect every node object's property dictionary before dropping known fields.
2. A track exists only when a property object contains an `animation` object.
3. Preserve the full animation object as `rawValue`.
4. Parse options `fps`, `length`, `relative` without inventing defaults.
5. Sort channel keys by numeric suffix when both are `c<number>`; place all other names lexically after numbered channels.
6. Preserve keyframe source order within each channel.
7. Parse `frame`, explicit `time`, `value`, and `interpolation`/`easing`; keep remaining fields in `unknownFields`.
8. Compute `time = frame / fps` only when explicit time is absent and fps is finite and positive.
9. Infer scalar/vector2/vector3 only from confirmed numeric channel count/value shape; otherwise use raw.
10. Keep malformed channels as degraded tracks and add stable diagnostics rather than deleting the node.
11. Count keyframes with checked addition and stop before exceeding `maximumAnimationKeyframeCount`.
12. Sort final tracks by node ID then property path.

- [ ] **Step 4: Run GREEN and commit**

```bash
swift test --filter SceneGraphAnimationTests
swift test --filter SceneGraphBuilderTests
git add Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift Sources/MacWallSceneGraph/SceneGraphBuilder.swift Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift
git commit -m "feat(scene): preserve animation tracks"
```

Expected: animation and root/node suites pass.

---

### Task 11: Resource Limits, Status Policy, and Canonical Summary

**Files:**

- Create: `Sources/MacWallSceneGraph/SceneGraphSummary.swift`
- Create: `Tests/MacWallSceneGraphTests/SceneGraphLimitsAndSummaryTests.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphResourceParser.swift`
- Modify: `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`

**Interfaces:**

- Consumes: complete Tasks 6-10 graph result
- Produces: `SceneGraphSummary`, `SceneGraphSummarizer`, `SceneGraphSummaryEncoder`
- Produces: final deterministic status and diagnostic ordering
- Consumed by: Task 12 local fixture gate

- [ ] **Step 1: Write failing limit/status/determinism tests**

Inject small limits to prove every production default without large allocation:

- node count 1 with 2 objects
- dependency edge count 1 with 2 references
- JSON entry 32 bytes with a larger root
- cumulative JSON equal-to-limit success and one-byte-over failure
- JSON depth 2 with depth 3
- animation keyframe count 1 with 2 frames
- hierarchy depth 2 with chain depth 3

Assert status precedence with separate synthetic cases:

```text
unknown noncritical property -> degraded
duplicate unreferenced ID -> degraded
asset ambiguity with deterministic selected candidate -> degraded
unknown node -> unsupported
missing/ambiguous edge -> unsupported
built-in/external/unresolved asset -> unsupported
effect/custom shader/script -> unsupported
malformed root/path escape/limit/cycle -> invalid
```

The external case uses a resolver built with
`SceneAssetSourcePolicy(version: 99, builtInPrefixes: [], externalPrefixes: ["shared/"], classifyBareShadersAsBuiltIn: false)`;
do not change the production `.s2` policy's empty external prefix list.

Build the same package twice and require byte-identical summary encoding.

- [ ] **Step 2: Run RED**

```bash
swift test --filter SceneGraphLimitsAndSummaryTests
```

Expected: summary symbols are missing and at least one final limit/status case fails.

- [ ] **Step 3: Implement aggregate summary and canonical encoding**

Define:

```swift
public struct SceneGraphCount:
    Codable,
    Equatable,
    Sendable
{
    public let name: String
    public let count: Int
}

public struct SceneGraphSummary:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: Int
    public let packageVersion: String?
    public let nodeKinds: [SceneGraphCount]
    public let hierarchyEdgeCount: Int
    public let instanceEdgeCount: Int
    public let overrideCount: Int
    public let resourceKinds: [SceneGraphCount]
    public let dependencyResolutions: [SceneGraphCount]
    public let animationTrackCount: Int
    public let animationKeyframeCount: Int
    public let scriptCount: Int
    public let diagnosticCodes: [SceneGraphCount]
    public let status: SceneGraphStatus
}

public enum SceneGraphSummarizer {
    public static func summarize(
        _ result: SceneGraphBuildResult
    ) -> SceneGraphSummary
}

public enum SceneGraphSummaryEncoder {
    public static func encode(
        _ summary: SceneGraphSummary
    ) throws -> Data
}
```

Rules:

1. Schema version is 1.
2. Count names are raw enum names, sorted lexically.
3. No node names, source paths, owner paths, Workshop paths, host paths, timestamps, PID, UUID, addresses, raw scripts, or payload bytes appear.
4. Encode with `JSONEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` and append exactly one newline.
5. Diagnostic ordering follows Task 6; summary diagnostic codes are counted and sorted.
6. Apply status precedence in one internal `SceneGraphStatusAccumulator`; parser components report evidence rather than assigning final status independently.
7. Checked count overflow and every configured limit map to one stable `graph.resource-limit` diagnostic with limit name in arguments.
8. Path escape is error/invalid; invalid reference is warning/unsupported unless it prevents root loading.

- [ ] **Step 4: Run all Graph suites and commit**

```bash
swift test --filter MacWallSceneGraphTests
git add Sources/MacWallSceneGraph Tests/MacWallSceneGraphTests/SceneGraphLimitsAndSummaryTests.swift
git commit -m "feat(scene): add graph limits and canonical summary"
```

Expected: all Graph synthetic tests pass and repeated summary bytes match.

---

### Task 12: Local Scene Graph Fixture Catalog Gate

**Files:**

- Create: `Tests/MacWallSceneGraphTests/SceneLocalFixtureGraphTests.swift`
- Create: `Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json`

**Interfaces:**

- Consumes: Task 11 summary and local `test/<workshop-id>/scene.pkg`
- Produces: schema 1 aggregate graph compatibility evidence
- Does not store: Workshop payload, source path, node name, script source, raw JSON

- [ ] **Step 1: Add the local fixture test and explicit catalog writer**

Define local catalog types inside the test file:

```swift
private struct LocalSceneGraphCatalog: Codable {
    let schemaVersion: Int
    let fixtures: [LocalSceneGraphFixture]
}

private struct LocalSceneGraphFixture: Codable {
    let workshopID: String
    let summary: SceneGraphSummary
}
```

Test behavior:

1. Read tracked catalog schema 1.
2. Resolve only `test/<workshopID>/scene.pkg` from repository root.
3. If no tracked fixture exists locally, throw one `XCTSkip`.
4. Wrap each package in `RecordingSceneByteSource` and build through `ScenePackageAssetResolver.open(source:)`.
5. Compare actual summary with tracked summary.
6. Build each fixture twice and compare canonical summary bytes.
7. Assert graph node count equals the S1 aggregate object count: 28, 98, 69.
8. Assert no full-package read and maximum single read at most 16 MiB.
9. Assert every diagnostic argument excludes repository root and `/Users/`.
10. Assert `SceneRenderPlan`, preview image names, and texture payload bytes are not inputs.

When `MACWALL_UPDATE_LOCAL_SCENE_GRAPH_CATALOG=1`, generate the catalog from
exactly IDs `2174863503`, `2834933421`, `3516106265`, sort by ID, and write
only `SceneGraphSummary` aggregate fields with sorted-key formatting and one
newline. If any of the three fixture packages is missing, fail without writing.

- [ ] **Step 2: Verify RED before catalog generation**

```bash
swift test --filter SceneLocalFixtureGraphTests
```

Expected: failure because the tracked catalog file does not exist.

- [ ] **Step 3: Generate and inspect aggregate catalog**

Run once:

```bash
MACWALL_UPDATE_LOCAL_SCENE_GRAPH_CATALOG=1 swift test --filter SceneLocalFixtureGraphTests
```

Then inspect:

```bash
rg -n '/Users/|scene\.pkg|preview\.gif|preview\.jpg|thumbnail\.jpg|cover\.png|"source"[[:space:]]*:|sourcePath|ownerPath|nodeName' Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json
```

Expected: generation test passes; the `rg` command prints no matches. Review
the diff and confirm it contains only schema, IDs, aggregate counts, diagnostics,
and status.

- [ ] **Step 4: Run the normal local gate and focused Scene suites**

```bash
swift test --filter SceneLocalFixtureGraphTests
swift test --filter MacWallSceneAssetsTests
swift test --filter MacWallSceneGraphTests
swift test --filter MacWallSceneAuditTests
swift test --filter SceneRenderPlanTests
```

Expected:

- all three local graph summaries match
- Assets, Graph, Audit, and prototype RenderPlan tests pass
- no whole-package read occurs

- [ ] **Step 5: Commit**

```bash
git add Tests/MacWallSceneGraphTests/SceneLocalFixtureGraphTests.swift Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json
git commit -m "test(scene): gate typed graph with local fixtures"
```

---

### Task 13: Completion Documentation and Full Verification

**Files:**

- Create: `docs/implemented/2026-08-04-scene-asset-resolver-typed-graph.md`
- Modify: `docs/README.md`
- Modify: `docs/development-log.md`
- Modify: `docs/development-roadmap.md`
- Modify: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- Move: S2 design and this plan to `docs/archive/superpowers/`

**Interfaces:**

- Consumes: actual commits and verification output from Tasks 1-12
- Produces: implemented record and roadmap transition to S3 planning

- [ ] **Step 1: Run full non-GUI verification**

Run:

```bash
swift test
git diff --check
rg -n 'import (AppKit|SwiftUI|Metal|MetalKit|AVFoundation|WebKit|JavaScriptCore)' Sources/MacWallSceneAssets Sources/MacWallSceneGraph
rg -n '^public .*Any|^public .*\[String: Any\]' Sources/MacWallSceneAssets Sources/MacWallSceneGraph
rg -n 'MacWallSceneGraph' Sources/MacWallCore Sources/MacWallApp Sources/MacWallNativeRuntimeSupport Package.swift
rg -n 'Data\(contentsOf:|preview\.gif|preview\.jpg|thumbnail\.jpg|cover\.png|desktop-fallback\.png' Sources/MacWallSceneAssets Sources/MacWallSceneGraph
git status --short
```

Expected:

- full Swift test suite passes with zero failures
- no diff whitespace errors
- forbidden framework import search prints no matches
- public `Any` boundary search prints no matches
- Graph dependency search prints only its target/test declarations in `Package.swift`, not Core/App/Native sources
- unbounded read/thumbnail/fallback search prints no matches
- only intended S2 files are dirty before documentation commit

- [ ] **Step 2: Create the implemented record with measured evidence**

The implemented record must contain:

- module dependency and public contract summary
- resolver candidate/provenance policy
- Audit policy migration and schema 2 compatibility
- node/resource/hierarchy/instance/animation preservation behavior
- actual local fixture node/resource/dependency/status counts from the catalog
- exact focused/full test counts copied from command output
- deterministic/path-redacted catalog result
- explicit non-goals: S3 Metal, Native Scene, fallback, external assets, execution
- no claim of visual correctness or renderer completion

Do not write predicted test counts or performance numbers.

- [ ] **Step 3: Update active documentation and archive completed plan**

Update:

- `docs/README.md`: add S2 implemented record, remove active S2 spec/plan links, state S3 planning next
- `docs/development-roadmap.md`: mark S2 implemented with measured verification, set next Scene work to S3 GPU Texture Pipeline design
- `docs/development-log.md`: add KST timestamp, commits, tests, local fixture result, non-goals
- overarching Scene design: status `S0-S2 implemented / S3 planning next` and S2 evidence link
- S2 design status: implemented before moving to archive

Move:

```bash
git mv docs/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md docs/archive/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md
git mv docs/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md docs/archive/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md
```

Confirm README user behavior did not change, so `README.md` and `README.ko.md`
remain unchanged.

- [ ] **Step 4: Validate document state**

```bash
rg --files docs | sort
rg -n 'S2 planning next|S2 .*다음 planning|written review pending|implementation plan not started' docs --glob '!docs/archive/**'
rg -n 'S3 GPU Texture Pipeline' docs/README.md docs/development-roadmap.md docs/superpowers/specs/2026-07-29-scene-engine-design.md
git diff --check
```

Expected:

- completed S2 spec/plan exist only under archive
- stale active S2 state search prints no matches
- active docs name S3 as next Scene planning phase
- no Markdown whitespace errors

- [ ] **Step 5: Commit documentation**

```bash
git add docs
git commit -m "docs(scene): record S2 graph implementation"
```

- [ ] **Step 6: Final evidence check**

```bash
git status --short --branch
git log --oneline --decorate -14
swift test
```

Expected: clean worktree, one focused local commit per implementation gate,
and full Swift suite passes with zero failures. Do not run GUI, build,
package, DMG, notarization, or `dist` commands.

---

## Final Acceptance Checklist

- [ ] `MacWallSceneAssets` and `MacWallSceneGraph` are independent targets.
- [ ] Root/owner references, exact case/Unicode, dot normalization, path escape, texture shorthand, ambiguity, and bounded reads are tested.
- [ ] Audit and Graph share one asset candidate/source classification policy.
- [ ] Audit schema 2 and S1 aggregate catalog remain compatible.
- [ ] All 28, 98, and 69 local fixture objects become graph nodes without a fixed cap.
- [ ] Image, text, particle, sound, model, composition, fullscreen, and unknown nodes are preserved.
- [ ] Model-material-pass-texture and effect/shader dependencies retain provenance.
- [ ] Parent/instance/override references are not flattened and cycles are deterministic.
- [ ] Unknown JSON, effect, shader, script, and animation metadata remain typed/Sendable and are never executed.
- [ ] Every configured limit has an injected boundary test.
- [ ] Status precedence and diagnostic ordering are deterministic.
- [ ] Local catalog contains aggregate metadata only and repeated summaries are byte-identical.
- [ ] Existing `SceneRenderPlan`/CALayer prototype, Native Wallpaper, fallback, Core/App user flows are unchanged.
- [ ] Focused and full `swift test` pass with zero failures.
- [ ] No GUI/build/package/DMG/notarization/`dist` command was run.
