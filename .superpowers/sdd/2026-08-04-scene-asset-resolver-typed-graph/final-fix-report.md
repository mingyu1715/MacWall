# MacWall Scene S2 Final Review Fix Report

Date: 2026-08-05

Branch: `feature/scene-s2-asset-graph`

Requirements source: `final-review.md`

## Status

All four Important findings and the Minor metadata-path collision finding were
addressed in the allowed final-review fix round. No S3 renderer, runtime,
fallback, execution, Core, App, or Native integration work was added.

## Findings, Fixes, and Tests

### Important 1: embedded dot-segment canonicalization

- Changed every root, materials-root, texture-root, and owner-relative
  candidate to use `SceneVirtualPath.resolving(reference:relativeTo:)`.
- Preserved candidate ordering, origin provenance, exact case/Unicode behavior,
  and fail-closed `pathEscape` classification when normalization escapes root.
- Added document-root, texture-owner, and embedded-root-escape regressions in
  `ScenePackageAssetResolverTests`.
- RED: `swift test --filter ScenePackageAssetResolverTests` executed 17 tests;
  the three new tests failed with 8 expected assertions because candidates were
  empty and root escape was reported as `invalidReference`.
- GREEN: the same 17 tests passed. Final affected Assets suite: 21 tests, 0
  failures. Shared-policy Audit verification: 18 tests, 0 failures.

### Important 2: scene/document dependency ownership

- Added the public typed and `Sendable`
  `SceneDependencyOwner.document(SceneVirtualPath)` case.
- Seeded recursive scene metadata discovery with `.document(sourcePath)` and
  added deterministic document-owner identity to dependency deduplication.
- Root-level `effect`, `file`, `model`, `shader`, and `texture` references now
  produce dependency edges with request owner path, resolution provenance,
  resources where applicable, and unsupported status evidence for retained
  effect/custom-shader semantics.
- Added `testPreservesSceneDocumentMetadataDependenciesWithProvenance`.
- RED: 1 test, 5 expected assertion failures for missing dependencies,
  resources, diagnostics, and status.
- GREEN: 1 test passed. Final Resource suite: 26 tests, 0 failures.

### Important 3: raw animation status evidence

- Raw value classification now marks its `SceneAnimationTrack` degraded even
  when options and keyframes are otherwise valid.
- `SceneGraphAnimationParseResult` now returns status evidence, and
  `SceneGraphBuilder` records it through the existing status accumulator.
- Added a known-property regression containing valid `origin` base data with
  noncanonical `x/y/z` channels and valid `color` base data with four
  `c0...c3` channels.
- RED: 1 test, 2 expected assertion failures because both tracks and the build
  remained exact.
- GREEN: 1 test passed. Final Animation suite: 9 tests, 0 failures.

### Important 4: all-three local fixture gate

- Extracted a deterministic fixture availability decision with three states:
  absent, partial with sorted missing IDs, and complete in fixed-ID order.
- Preserved absent-all `XCTSkip` behavior for environments without local
  fixtures.
- Partial availability now fails with the message
  `missing fixed fixture IDs: <sorted IDs>` and never processes a subset.
- Complete availability processes all three catalog fixtures, so zero skips
  proves all three were built twice and compared.
- Added `testPartialLocalFixtureAvailabilityReportsEveryMissingFixedID`.
- RED: 1 test, 1 expected assertion failure because a one-ID subset was
  classified as complete.
- GREEN: 1 test passed. Final local Graph fixture suite: 5 tests, 0 failures,
  0 skips.

### Minor 1: arbitrary metadata-key path collisions

- Object keys containing `.`, `[`, `]`, quote, backslash, control characters,
  or the empty string now use deterministic bracket-quoted JSON-path
  components. Quotes, backslashes, and control characters are escaped.
- Ordinary display paths remain unchanged, for example
  `$.objects[0].script`; unsafe keys render readably, for example
  `$["a.b"].texture`.
- The escaped display path remains the dependency/script deduplication key, so
  literal delimiter keys cannot collide with nested object/array paths.
- Added `testMetadataKeysWithPathDelimitersDoNotCollide`, covering a nested
  `a.b` path versus literal `"a.b"` and array `items[0]` versus literal
  `"items[0]"`.
- RED: 1 test, 2 expected assertion failures because only 2 of 4 occurrences
  survived and only 2 display paths were reported.
- GREEN: 1 test passed. Included in the 26-test Resource suite.

## Commits

- `1cab12e0a485a0026580b77177498e013032855c` -
  `fix(scene): address S2 final review`
- This report is committed separately after generation; its SHA is returned in
  the final task response because a commit cannot contain its own stable SHA.

## Verification

### Focused tests

| Command | Result |
| --- | --- |
| `swift test --filter MacWallSceneAssetsTests` | 21 tests, 0 failures |
| `swift test --filter SceneGraphResourceTests` | 26 tests, 0 failures |
| `swift test --filter SceneGraphAnimationTests` | 9 tests, 0 failures |
| `swift test --filter SceneLocalFixtureGraphTests` | 5 tests, 0 failures, 0 skips |
| `swift test --filter MacWallSceneAuditTests` | 18 tests, 0 failures |

### Full tests

- Final `swift test`: 414 tests, 0 failures, 0 skips.
- The full suite was run after production, test, and public-contract
  documentation changes.

### Local fixture evidence

The active fixture gate actually processed these fixed IDs in sorted order,
building and comparing each twice:

| Workshop ID | Expected graph nodes | Final SHA-256 |
| --- | ---: | --- |
| `2174863503` | 28 | `dc6789343f590606895807f95d488f156f364ba6f81e4cf45c19f77c4ec38e4a` |
| `2834933421` | 98 | `5421937cb7d7d351ae729b1089ae6d95af37e49dee4733783818c07ee8fe6ae5` |
| `3516106265` | 69 | `e8afe45b021de9be2169c2b694c057db3dacbf6f3467bc8c33b07b1bd2286bbe` |

The final hashes exactly match the pre-edit baselines. `git -C test status
--short --branch` reported only the clean fixture-source branch header before
and after verification. The tracked aggregate Graph catalog did not change.

### Static and diff checks

| Check | Result |
| --- | --- |
| `git diff --check` and `git diff --cached --check` | no whitespace errors |
| Prohibited framework import search in SceneAssets/SceneGraph | no matches |
| Public `Any` / `[String: Any]` boundary search | no matches |
| Core/App/Native `MacWallSceneGraph` dependency search | no source matches; only expected `Package.swift` target/test declarations at lines 32, 99, and 101 |
| Unbounded read / preview / fallback reference search in S2 targets | no matches |
| Fixture source git status | clean |
| Worktree staging audit | only the 10 intended implementation/test/doc files were staged; `test` was not staged |

No GUI, `swift build`, `xcodebuild`, package, DMG, notarization, `dist`, crawl,
download, auth, or DRM command was run.

## Changed Files

- `Sources/MacWallSceneAssets/SceneAssetCandidatePolicy.swift`
- `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`
- `Sources/MacWallSceneGraph/SceneGraphBuilder.swift`
- `Sources/MacWallSceneGraph/SceneGraphResource.swift`
- `Sources/MacWallSceneGraph/SceneGraphResourceParser.swift`
- `Tests/MacWallSceneAssetsTests/ScenePackageAssetResolverTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift`
- `Tests/MacWallSceneGraphTests/SceneGraphResourceTests.swift`
- `Tests/MacWallSceneGraphTests/SceneLocalFixtureGraphTests.swift`
- `docs/implemented/2026-08-04-scene-asset-resolver-typed-graph.md`
- `.superpowers/sdd/2026-08-04-scene-asset-resolver-typed-graph/final-fix-report.md`

## Concerns

- The local `test` symlink remains intentionally untracked and was used only as
  read-only verification input. It was never staged.
- The fixture source files were unchanged and their repository was clean, but
  filesystem permissions do not provide an OS-level immutability guarantee.
- S2 still preserves unsupported effect, shader, script, and raw animation
  semantics as typed metadata only. It does not execute or render them.
- S3 GPU texture upload/rendering, Native integration, fallback changes, and
  execution remain explicitly out of scope and were not started.
