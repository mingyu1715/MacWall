# MacWall Scene Asset Resolver and Typed Graph Design

상태: Design approved / written review pending / implementation plan not started

작성일: 2026-08-03
대상: Scene Engine S2 Asset Resolver and Typed Scene Graph

## 1. 목적

S2는 S1에서 안전하게 읽을 수 있게 된 Wallpaper Engine Scene package를
Metal renderer가 소비할 수 있는 typed scene graph로 변환합니다.

S2의 출력은 화면이 아니라 다음 두 계약입니다.

1. package 내부 reference를 canonical virtual path와 provenance로 해석하는
   `MacWallSceneAssets`
2. Scene의 object, resource, dependency, hierarchy, instance, animation을
   손실 없이 보존하는 `MacWallSceneGraph`

전체 흐름은 다음과 같습니다.

```text
scene.pkg
-> MacWallSceneFormats
-> MacWallSceneAssets
-> MacWallSceneGraph
-> S3 MacWallSceneMetal
```

현재 `MacWallCore/Scene/SceneRenderPlan.swift`와
`MacWallApp/Playback/SceneWallpaperView.swift`는 CALayer prototype입니다.
S2는 이 경로를 확장하거나 교체하지 않고 독립 모듈로 병행 구현합니다.
S3/S4 renderer가 준비되기 전까지 기존 prototype의 사용자 동작은 그대로
유지합니다.

## 2. 범위

### 2.1 포함

- package root-relative 및 owner-relative asset reference 해석
- exact case/Unicode를 보존하는 canonical virtual path
- model, material, pass, texture, shader, effect dependency 추적
- image, text, particle, sound, model, composition, fullscreen, unknown node 보존
- stable internal node ID와 원본 source ID 분리
- parent-child hierarchy, instance, override, animation metadata 표현
- raw unknown JSON을 `Sendable` typed value로 보존
- missing reference, duplicate ID, cycle, unsupported feature 진단
- deterministic graph summary와 local fixture aggregate catalog
- synthetic 및 local-only fixture 기반 정적 검증

### 2.2 제외

- Metal texture upload와 GPU renderer
- Scene frame 생성과 Native Wallpaper surface 연결
- Scene fallback PNG 생성
- SceneScript 또는 custom shader 실행
- effect, particle, text, sound, video texture의 runtime 실행
- Wallpaper Engine 설치의 global `assets/` folder 연결
- Wallpaper Engine built-in asset payload 복사 또는 bundle
- Main App/CLI의 Scene 사용자 기능 변경
- 기존 CALayer prototype 제거
- GUI/System Settings QA, package, DMG, notarization, `dist` 작업

## 3. 설계 결정

### 3.1 독립 모듈 병행 구현

새 모듈은 다음 dependency 방향을 사용합니다.

```text
MacWallSceneFormats
        |
        v
MacWallSceneAssets
        |
        v
MacWallSceneGraph
```

- `MacWallSceneAssets`는 package entry와 virtual path만 압니다.
- `MacWallSceneGraph`는 resolver를 사용하지만 PKG offset을 직접 해석하지
  않습니다.
- `MacWallSceneFormats`는 graph/node/material 의미를 알지 않습니다.
- `MacWallCore`와 `MacWallApp`은 S2에서 새 graph module에 의존하지 않습니다.
- S3 이후 renderer가 graph를 소비할 때 integration dependency를 추가합니다.

Format과 graph를 하나의 target으로 합치지 않습니다. Path/source ownership과
Scene semantic model은 변경 이유가 다르고, S3 renderer가 package format에
직접 결합되는 것을 막아야 하기 때문입니다.

### 3.2 기존 prototype을 즉시 교체하지 않음

기존 `SceneRenderPlan`은 최대 16개 image layer를 CALayer로 표시하는 제한된
경로입니다. 이 모델을 확장해 S2 graph로 만들면 임시 UI 제약이 최종 engine
계약에 섞입니다.

따라서 S2는 다음을 하지 않습니다.

- `SceneRenderPlan` public API 확장
- `SceneWallpaperView`에 S2 graph 연결
- compatibility facade 또는 typealias로 두 모델을 위장해 통합
- S2 성공을 기존 CALayer 출력으로 판정

기존 경로의 제거 시점은 S4 headless Metal renderer와 App consumer가 새
graph를 실제로 소비한 뒤 별도 계획에서 결정합니다.

## 4. MacWallSceneAssets

### 4.1 책임

`MacWallSceneAssets`는 package 내부 reference를 안전하고 결정적으로
해석하고, resource content를 S1의 bounded source API로 제공합니다.

핵심 모델은 다음 책임을 갖습니다.

| Type | 책임 |
| --- | --- |
| `SceneVirtualPath` | 검증된 package-relative canonical path |
| `SceneAssetRequest` | 요청 문자열, owner path, asset role |
| `SceneAssetCandidate` | 순서가 보존된 해석 후보와 생성 근거 |
| `SceneResolvedAsset` | canonical path, package entry identity, provenance |
| `SceneAssetResolution` | resolved/candidate/unresolved 결과와 시도 목록 |
| `ScenePackageAssetResolver` | candidate 생성, exact lookup, bounded read/source 제공 |

구체적인 initializer와 method signature는 구현 계획에서 현재 S1 public API와
대조해 고정합니다. 다만 위 책임과 dependency 방향은 S2 public contract입니다.

### 4.2 Virtual path 규칙

`SceneVirtualPath`는 host filesystem path가 아닙니다.

- `/`로 구분되는 package 내부 상대 경로만 허용합니다.
- absolute path, backslash, NUL, 빈 component를 거부합니다.
- `.`은 제거하고 `..`은 owner 기준으로 정규화하되 package root 밖으로
  나가면 거부합니다.
- case와 Unicode scalar를 변경하거나 normalization하지 않습니다.
- package lookup은 S1 archive의 exact entry name을 사용합니다.
- URL decoding, percent decoding, case-folding, filesystem existence check를
  하지 않습니다.
- canonical path를 host path와 문자열 결합해 열지 않습니다.

Reference가 owner-relative인지 root-relative인지 문서마다 일관되지 않을 수
있으므로 resolver는 role별 candidate policy를 사용합니다. 모든 candidate는
생성 순서와 이유를 결과에 기록합니다.

### 4.3 Candidate 정책

일반 document/model/material/pass/effect reference는 다음 순서입니다.

1. 입력을 package root-relative path로 해석한 exact candidate
2. owner document directory 기준 relative candidate

Texture reference는 extension 생략 관행을 처리합니다.

1. extension이 있으면 exact root candidate
2. extension이 있으면 owner-relative candidate
3. shorthand이면 owner directory 아래 `<reference>.tex`
4. shorthand이면 `materials/<reference>.tex`
5. shorthand이면 package root의 `<reference>.tex`

같은 canonical path가 여러 규칙에서 만들어지면 첫 candidate 하나로
dedupe합니다. 여러 서로 다른 candidate가 실제 entry로 존재하면 정책상
앞선 candidate를 선택하되 `asset.ambiguous-resolution` diagnostic에 선택된
path와 나머지 path를 기록합니다. Candidate 수는 resource limit으로
제한합니다.

Role별 예외를 parser 곳곳에 복사하지 않습니다. 새 관행을 발견하면
`SceneAssetCandidatePolicy` 한 곳과 fixture evidence를 함께 갱신합니다.

### 4.4 Provenance와 identity

Resolved asset은 최소한 다음 evidence를 보존합니다.

- 원본 requested reference
- owner virtual path
- asset role
- 선택된 canonical virtual path
- candidate 생성 규칙
- package entry offset/length identity
- 모든 attempted candidate

S2 package 내부 identity는 canonical path와 S1 entry metadata로 충분합니다.
Content hash 계산은 전체 payload를 불필요하게 읽을 수 있으므로 S2 graph
build의 필수 조건으로 두지 않습니다. Native generation staging의 immutable
manifest/hash는 S5 경계에서 별도로 처리합니다.

### 4.5 Built-in 및 external asset 경계

Package에 없는 알려진 Wallpaper Engine built-in reference와 향후 global
`assets/` reference는 S2에서 실제로 resolve하지 않습니다.

Resolution은 다음 source 상태를 구분합니다.

| 상태 | 의미 |
| --- | --- |
| `package` | 현재 package entry로 exact resolve됨 |
| `builtInCandidate` | clean-room replacement가 향후 필요함 |
| `externalCandidate` | 사용자가 선택한 external assets source가 향후 필요함 |
| `unresolved` | 알려진 source classification 없이 찾지 못함 |

Built-in/external candidate의 이름과 dependency edge는 graph에 남깁니다.
실제 source provider, 사용자 선택 UI, bookmark, file access, payload 변환은
후속 compatibility 작업입니다. 외부 source가 없다는 이유로 package graph
전체를 폐기하지 않습니다.

Candidate classification은 단순히 package lookup이 실패했다는 이유로
추측하지 않습니다. Fixture에서 확인한 namespace/name과 versioned policy에
일치할 때만 `builtInCandidate` 또는 `externalCandidate`로 분류하고, 근거가
없으면 `unresolved`로 남깁니다.

## 5. MacWallSceneGraph

### 5.1 Graph document

`SceneGraphDocument`는 renderer와 audit/test consumer가 공유하는 immutable
value model입니다.

최소 구성은 다음과 같습니다.

- Scene metadata와 canvas/viewport 정보
- source document provenance
- 순서가 보존된 node collection
- parent/child 및 instance edge
- material, pass, texture, shader, effect resource record
- animation track과 keyframe metadata
- dependency edge와 resolution 결과
- typed property와 unknown raw field

Graph의 collection iteration과 summary output은 source order 또는 명시된
stable order를 사용합니다. Dictionary iteration order에 의존하지 않습니다.

### 5.2 Node identity

Wallpaper Engine source ID는 누락되거나 중복될 수 있으므로 graph 내부 ID와
분리합니다.

- `SceneNodeID`: source document canonical path와 object index를 결합한
  deterministic unique internal ID
- `SceneSourceIdentifier`: 원본 integer/string ID를 손실 없이 보존
- source ID lookup: 하나의 ID가 여러 node를 가리킬 수 있는 multimap

Missing source ID는 object index 기반 internal ID로 정상 보존합니다. Duplicate
source ID는 node를 덮어쓰지 않고 모두 보존하며
`graph.duplicate-source-id`를 기록합니다. Duplicate ID를 사용하는 parent,
instance, override reference는 임의의 첫 node로 연결하지 않고 ambiguous
edge로 남깁니다.

### 5.3 Node 종류

공통 속성과 종류별 payload를 분리합니다.

공통 속성:

- name/source identifier/internal ID
- source order와 z-order
- visible/enabled
- position, rotation, scale, size, origin/pivot
- opacity/color
- parent reference
- instance source와 override metadata
- animation binding
- raw unknown fields

보존할 node kind:

- image
- text
- particle
- sound
- model
- composition
- fullscreen
- unknown(type name과 raw payload)

S2는 지원하지 않는 종류를 image로 위장하거나 삭제하지 않습니다. Unknown
node도 순서, transform, hierarchy, dependency evidence를 유지합니다.

### 5.4 Typed JSON value

Public graph boundary 밖으로 `[String: Any]`, `Any`, `NSNumber`를 노출하지
않습니다. Unknown field와 아직 해석하지 않은 payload는 재귀적인
`SceneJSONValue`로 보존합니다.

```text
SceneJSONValue
  null
  bool(Bool)
  integer(Int64)
  number(Double)
  string(String)
  array([SceneJSONValue])
  object([String: SceneJSONValue])
```

`SceneJSONValue`는 `Sendable`, `Equatable`, `Codable`을 만족하고 bool과 number를
구분합니다. Object의 deterministic encoding/summary는 key를 정렬합니다.
Source JSON의 whitespace와 key lexical order까지 보존하는 것이 목표는
아니지만 값의 종류와 의미를 잃어서는 안 됩니다.

### 5.5 Resource graph

Image node reference는 다음 dependency를 명시적으로 모델링합니다.

```text
node
-> model document
-> material document
-> material pass
-> shader/effect metadata
-> texture binding
-> resolved asset or unresolved source candidate
```

- 같은 canonical document/resource는 한 번 parse하고 memoize합니다.
- 여러 node가 같은 material/texture를 reference하면 resource record를
  공유하고 edge만 추가합니다.
- S2는 texture payload를 decode하지 않습니다.
- Material/pass에서 해석한 공통 field와 raw unknown field를 함께 보존합니다.
- Shader source, combo, effect parameter는 실행하지 않고 metadata와
  dependency로만 보존합니다.
- Inline SceneScript는 source metadata와 binding location만 보존하고 절대
  실행하지 않습니다.

### 5.6 Parent, instance, override

Parent-child 관계는 별도 edge로 표현하고 node collection의 소유권과
혼합하지 않습니다.

- missing parent는 node를 삭제하지 않고 unresolved edge로 유지합니다.
- parent cycle은 deterministic cycle path와 함께 진단합니다.
- instance는 원본 graph/subtree를 복제하지 않고 source reference로
  표현합니다.
- override는 target property path와 raw/typed value의 sparse map으로
  보존합니다.
- instance cycle은 graph explosion 없이 reference cycle로 진단합니다.
- S2에서 instance를 flatten하지 않습니다. Runtime evaluation/flattening은
  S4 계약입니다.

### 5.7 Animation

S2 animation은 실행기가 아니라 데이터 계약입니다.

- target node/resource
- property path
- interpolation/easing raw value
- ordered keyframe time/value
- loop/duration metadata
- 해석한 typed value와 원본 raw value

Position, rotation, scale, opacity처럼 확인된 property는 typed channel로
표현합니다. 아직 지원하지 않는 property나 keyframe shape도 raw channel로
남깁니다. 일부 keyframe이 malformed이면 전체 object를 삭제하지 않고 해당
channel의 status와 diagnostic을 기록합니다.

## 6. Build pipeline

Graph build 순서는 다음과 같습니다.

1. `ScenePackageArchive`를 열고 `ScenePackageAssetResolver`를 생성합니다.
2. entrypoint `scene.json`을 bounded read합니다.
3. JSON을 `SceneJSONValue`로 decode하고 root schema를 검사합니다.
4. source order대로 object를 typed node로 변환합니다.
5. node의 model/material/pass/effect document를 resolver로 해석합니다.
6. canonical path별 parse cache를 사용해 resource record와 dependency edge를
   생성합니다.
7. source ID lookup, parent/instance/override edge를 연결합니다.
8. duplicate, missing reference, parent/instance cycle, resource limit을
   검증합니다.
9. stable diagnostic와 deterministic summary를 생성합니다.

Input 오류가 있어도 안전하게 생성할 수 있는 node/resource는 유지합니다.
Package/archive 자체를 신뢰할 수 없거나 root Scene JSON을 읽을 수 없는
경우에만 document가 없는 `invalid` result를 반환합니다.

## 7. 결과 상태와 진단

S2는 상위 Scene Engine과 같은 상태 체계를 사용합니다.

| 상태 | S2 의미 |
| --- | --- |
| `exact` | 모든 graph reference와 확인된 의미를 보존함 |
| `degraded` | graph는 유효하지만 일부 property/channel을 raw로만 보존함 |
| `unsupported` | 핵심 asset/node 의미가 unresolved 또는 미지원이라 정확한 render를 보장할 수 없음 |
| `invalid` | package, root JSON, identity, cycle 또는 limit 위반으로 graph를 신뢰할 수 없음 |

상태 우선순위는 `invalid > unsupported > degraded > exact`입니다. Graph가
유지되더라도 renderer가 성공으로 표시해도 된다는 뜻은 아닙니다.

초기 상태 판정 규칙은 다음과 같습니다.

| Evidence | 상태 영향 |
| --- | --- |
| 알 수 없는 비핵심 property/raw animation 보존 | `degraded` |
| duplicate source ID만 있고 reference ambiguity 없음 | `degraded` |
| unknown node, missing/ambiguous edge, unresolved/built-in/external asset | `unsupported` |
| 실행하지 않는 effect/custom shader/SceneScript가 output에 연결됨 | `unsupported` |
| malformed root, path escape, resource limit, parent/instance cycle | `invalid` |

하나의 evidence가 여러 상태에 해당하면 더 높은 우선순위를 사용합니다.
Duplicate source ID를 실제 edge가 참조해 target이 ambiguous해지면
`unsupported`로 승격합니다.

Diagnostic은 stable code, severity, source virtual path, source node ID/object
index, JSON property path, dependency path를 가질 수 있습니다.

초기 stable code 집합:

- `asset.invalid-reference`
- `asset.path-escape`
- `asset.ambiguous-resolution`
- `asset.builtin-candidate`
- `asset.external-candidate`
- `asset.unresolved`
- `graph.malformed-scene-json`
- `graph.resource-limit`
- `graph.duplicate-source-id`
- `graph.missing-parent`
- `graph.parent-cycle`
- `graph.missing-instance`
- `graph.instance-cycle`
- `graph.unknown-node`
- `graph.invalid-property`
- `graph.unresolved-material`
- `graph.unresolved-texture`
- `graph.unsupported-effect`
- `graph.scenescript-preserved-not-executed`

같은 input에서 diagnostic ordering과 message arguments는 동일해야 합니다.
절대 local path, PID, object address, timestamp를 summary/catalog에 넣지
않습니다.

## 8. Resource limits

S1의 package/entry limit을 그대로 적용하고 S2 semantic limit을 추가합니다.

| Limit | 초기값 |
| --- | ---: |
| 한 JSON entry | 16 MiB |
| graph build 중 누적 JSON read | 64 MiB |
| resolution candidate/request | 16 |
| node count | 100,000 |
| dependency edge count | 500,000 |
| animation keyframe count | 1,000,000 |
| JSON nesting depth | 256 |
| hierarchy/cycle traversal depth | 4,096 |

Limit은 `SceneGraphLimits`로 주입 가능하게 해 작은 synthetic fixture에서
경계 테스트를 수행합니다. Limit 초과는 allocation이나 recursion을 계속하지
않고 `graph.resource-limit`과 `invalid`를 반환합니다. Thread stack에 의존한
재귀 traversal 대신 explicit work stack을 사용합니다.

## 9. Determinism과 concurrency

- Resolver, graph document, node/resource value는 `Sendable`을 목표로 합니다.
- Archive read와 JSON/graph build는 MainActor 밖에서 실행할 수 있어야 합니다.
- S2 public type은 AppKit, SwiftUI, Metal, AVFoundation에 의존하지 않습니다.
- Graph build 결과는 같은 package bytes와 limits에서 byte-stable canonical
  summary를 생성해야 합니다.
- Parallel parse를 도입하더라도 최종 node/resource/diagnostic order는 source
  order와 canonical path order로 다시 정렬합니다.
- S2 초기 구현은 correctness 우선으로 serial build를 허용합니다. 병렬화는
  profile evidence가 있을 때 별도 최적화로 진행합니다.

## 10. 검증 전략

### 10.1 Synthetic tests

`MacWallSceneAssetsTests`:

- root-relative/owner-relative resolve
- `.`/`..` normalization과 root escape 거부
- case/Unicode exact lookup
- texture shorthand candidate order와 dedupe
- ambiguous resolution diagnostic
- built-in/external/unresolved classification
- bounded content read와 request candidate limit

`MacWallSceneGraphTests`:

- 모든 node kind와 unknown node 보존
- integer/string/missing/duplicate source ID
- stable internal ID와 source order
- parent tree, missing parent, parent cycle
- instance/override와 instance cycle
- model-material-pass-texture dependency dedupe
- unknown material/effect/script metadata 보존
- typed/raw animation channel과 malformed keyframe
- status precedence, limits, deterministic diagnostics/summary

### 10.2 Local fixture gate

사용자가 제공한 local-only Scene fixture 3개를 read-only로 build합니다.

- `2174863503`
- `2834933421`
- `3516106265`

Repository에는 payload나 source path를 커밋하지 않습니다. 대신
`Tests/Fixtures/SceneGraph/local-scene-graph-catalog.json`에 다음 aggregate
evidence만 기록합니다.

- schema version과 package version
- node kind count
- parent/instance/override count
- material/pass/texture/shader/effect dependency count
- animation track/keyframe count
- package/built-in/external/unresolved resolution count
- diagnostic code count와 final status

Catalog 생성은 explicit opt-in helper로만 수행하고 일반 test는 catalog와
현재 local result를 비교합니다. Fixture가 없으면 local gate만 skip하고
synthetic/full package tests는 계속 실행합니다.

같은 fixture를 반복 build해 canonical summary가 동일한지 검증합니다.

### 10.3 허용 검증

- focused `swift test`
- 전체 `swift test`
- `git diff --check`
- `rg` 기반 target/dependency/forbidden-scope 정적 검사

S2 완료 판정에 GUI 출력이나 Metal frame을 사용하지 않습니다.

## 11. Acceptance criteria

S2는 다음 조건을 모두 만족할 때 완료입니다.

1. `MacWallSceneAssets`와 `MacWallSceneGraph` target이 독립적으로 존재합니다.
2. package path escape 없이 root/owner reference를 deterministic하게
   resolve합니다.
3. 세 local fixture의 모든 Scene object를 fixed layer cap 없이 graph node로
   보존합니다.
4. image/text/particle/sound/model/composition/fullscreen/unknown node가 조용히
   사라지지 않습니다.
5. model-material-pass-texture dependency와 provenance를 추적합니다.
6. parent/instance/override를 reference graph로 표현하고 cycle을 안전하게
   진단합니다.
7. unknown JSON/effect/script/animation metadata를 `Sendable` value로
   보존합니다.
8. exact/degraded/unsupported/invalid 상태와 stable diagnostic이
   deterministic합니다.
9. local fixture aggregate catalog와 반복 summary가 일치합니다.
10. focused 및 전체 `swift test`가 통과합니다.
11. 기존 CALayer prototype, Native Wallpaper, fallback, Main App 사용자 흐름에
    동작 변경이 없습니다.

## 12. 대안 검토

### 대안 A: Assets와 Graph를 한 target으로 구현

파일 수는 줄지만 format/source ownership과 semantic graph가 결합됩니다.
향후 external source, staged generation, S3 renderer가 package 구현 세부에
의존하게 되므로 선택하지 않습니다.

### 대안 B: 기존 SceneRenderPlan을 확장

현재 image/CALayer 중심 제약과 fixed layer cap을 그대로 물려받고 unknown,
instance, effect, resource graph를 표현하기 어렵습니다. 최종 Metal engine을
다시 설계해야 하므로 선택하지 않습니다.

### 대안 C: external assets integration을 S2에 포함

Wallpaper Engine 설치 위치, user bookmark, 권한, shared asset provenance,
clean-room policy가 graph correctness와 독립적인 문제입니다. 현재 package
graph의 정확한 경계를 먼저 고정하기 위해 actual integration은 미룹니다.

## 13. 후속 단계

문서 검토 승인 후 S2 executable implementation plan을 작성합니다. 계획은
target/API 추가, resolver, typed JSON, node/resource graph, validation,
synthetic/local fixture gate, aggregate catalog, 전체 검증을 작은 TDD task와
독립 review checkpoint로 나눕니다.

S2 구현이 완료되기 전에는 다음을 시작하지 않습니다.

- S3 GPU Texture Pipeline
- S4 Headless 2D Metal Renderer
- S5 Native Scene Frame Adapter
- Scene fallback
- external Wallpaper Engine `assets/` integration
- SceneScript/effect execution
