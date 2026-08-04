# Scene S2 Asset Resolver and Typed Graph Implementation Record

작성일: 2026-08-04

상태: implemented / completed

## 목적과 모듈 경계

S2는 S1의 bounded `scene.pkg` reader 위에 package 내부 reference를 안전하게
해석하고 Scene 의미를 renderer 독립 typed graph로 보존하는 계약을 추가했습니다.

```text
MacWallSceneFormats
        |
        v
MacWallSceneAssets
        |
        v
MacWallSceneGraph
```

- `MacWallSceneAssets`는 `SceneVirtualPath`, request/candidate/resolution,
  provenance, package entry identity, bounded entry access를 public
  `Sendable` value로 제공합니다.
- `MacWallSceneGraph`는 `SceneGraphDocument`, typed JSON, node/resource/
  dependency/hierarchy/instance/animation/script metadata, diagnostics,
  status, canonical summary를 public `Sendable` value로 제공합니다.
- `MacWallSceneAudit`는 같은 Assets resolver policy를 사용하도록 옮겼고,
  deterministic schema 2 report와 S1 aggregate catalog compatibility를
  유지했습니다.
- `MacWallCore`, `MacWallApp`, `MacWallNativeRuntimeSupport`, 기존
  `SceneRenderPlan`/CALayer prototype은 새 Graph target에 의존하지 않습니다.

## Resolver와 보존 정책

`SceneVirtualPath`는 package-relative path만 허용하고 exact case/Unicode를
보존합니다. Root/owner candidate, `.` normalization, root escape 거부,
texture shorthand, candidate dedupe와 ambiguity diagnostic을 resolver 한 곳에서
처리합니다. Resolution은 package entry identity를 가진 `package`, policy
evidence가 있는 `builtInCandidate` 또는 `externalCandidate`, `unresolved`,
`invalid`를 구분하며 모든 attempted candidate와 provenance를 남깁니다.
S2 production policy의 external prefix는 비어 있습니다.

Graph는 image, text, particle, sound, model, composition, fullscreen 및
unknown node를 삭제하지 않습니다. Model-material-pass-texture와
effect/shader dependency는 provenance와 함께 남고, parent/instance/override는
flatten하지 않는 reference edge입니다. Cycle은 deterministic diagnostic으로
처리합니다. Typed `SceneJSONValue`는 unknown JSON, effect, shader, script,
animation metadata를 보존하며 SceneScript, effect, custom shader, texture
payload는 실행, decode, upload하지 않습니다. Scene document 자체도 typed
dependency owner이며 root metadata의 effect, shader, texture, model, file
reference를 provenance와 함께 보존합니다.

상태 우선순위는 `invalid > unsupported > degraded > exact`입니다. 모든
raw 또는 degraded animation track은 최소 `degraded` status evidence를
기록합니다. 모든
configured limit은 injected boundary test로 검증하고, summary는 sorted key와
한 개 LF를 사용하는 deterministic, path-redacted schema 1 catalog result를
생성합니다.

## Local Fixture Catalog

Tracked `Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json`은 payload나
local path 없이 aggregate summary만 기록합니다. Local fixture gate는 각
fixture를 두 번 build하여 canonical summary bytes가 같은지 비교합니다. 세
fixed fixture가 모두 없을 때만 skip하고, 일부만 있으면 missing ID를 보고하며
실패하므로 zero skip은 세 ID가 모두 비교됐다는 뜻입니다.

| Workshop ID | Nodes | Resources | Dependencies | Status |
| --- | ---: | ---: | ---: | --- |
| `2174863503` | 28 | 74 | 183 (`136` package, `45` built-in candidate, `2` invalid) | `unsupported` |
| `2834933421` | 98 | 288 | 541 (`457` package, `77` built-in candidate, `2` unresolved, `5` invalid) | `unsupported` |
| `3516106265` | 69 | 58 | 245 (`218` package, `24` built-in candidate, `2` unresolved, `1` invalid) | `unsupported` |

The third fixture also records two animation tracks with eight keyframes.
All three statuses remain `unsupported`; this catalog is compatibility evidence,
not a claim of visual or renderer correctness.

## Verification

With the local-only `test` fixture symlink present:

- `swift test --filter SceneLocalFixtureGraphTests`: 5 tests, 0 failures,
  0 skips.
- `swift test`: 414 tests, 0 failures, 0 skips.
- `git diff --check`: no whitespace errors.
- Static searches found no prohibited framework imports, public `Any` or
  `[String: Any]` boundaries, or `Data(contentsOf:)`/preview/fallback references
  in the S2 targets. `MacWallSceneGraph` appears only in its target and test
  declarations in `Package.swift`, not in Core/App/Native sources.
- Fixture source repository status was clean. The untracked `test` symlink was
  not staged or modified; the three `scene.pkg` SHA-256 values matched the
  verified values recorded before final verification.

## Non-goals

This work does not implement S3 GPU Texture Pipeline or Metal rendering, a
Native Scene surface, Scene fallback, external asset integration, or execution
of SceneScript/effects/custom shaders. It does not integrate the graph into the
main app or replace the existing `SceneRenderPlan`/CALayer prototype. No visual
correctness or renderer completion is claimed.

## Related Documents

- [Scene Engine design](../superpowers/specs/2026-07-29-scene-engine-design.md)
- [Archived S2 design](../archive/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md)
- [Archived S2 plan](../archive/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md)
