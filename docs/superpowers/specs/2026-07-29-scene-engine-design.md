# MacWall Scene Engine Design

상태: Approved design / S0-S4 implemented / S5 next

작성일: 2026-07-29
대상: Wallpaper Engine Scene compatibility runtime

## 1. 목적

MacWall Scene Engine은 사용자가 직접 복사해 온 Wallpaper Engine
`scene.pkg`를 macOS에서 해석하고 Metal frame으로 렌더링합니다.

목표는 preview image를 움직이는 수준이 아니라 다음 파이프라인을
구현하는 것입니다.

```text
Workshop Scene project
-> versioned package and texture formats
-> resolved assets
-> typed scene graph
-> deterministic runtime evaluation
-> Metal render graph
-> native wallpaper frame
-> WallpaperAgent
```

첫 useful milestone은 일반적인 2D image Scene을 실제 asset과 animation으로
렌더링하는 것입니다. Text, particle, effect, SceneScript, 3D는 같은 구조 위에
순차적으로 추가합니다.

### S0 implementation evidence

S0는 [보관된 실행 계획](../../archive/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md)에
따라 구현했습니다. Schema version 1 audit contract, bounded TEX metadata
inspection, Scene JSON/dependency/script evidence, stable diagnostics를
처음 `MacWallCore`에 추가했고, 세 local fixture는 저작물 payload 없이
[aggregate catalog](../../../Tests/Fixtures/SceneAudit/local-scene-catalog.json)로
검증합니다. Focused Scene 25 tests와 전체 267 tests가 실패 없이 통과했으며,
이 결과는 S1에서 독립 모듈로 교체했습니다.

### S1 implementation evidence

S1은 [구현 기록](../../implemented/2026-07-29-scene-format-layer-hardening.md)에
따라 완료했습니다. `MacWallSceneFormats`와 `MacWallSceneAudit`을 분리하고,
bounded random-access PKG/TEX parsing, selected-mip software decode,
deterministic Audit schema 2를 구현했습니다. Core/App/CLI consumer를 새
모듈로 전환한 뒤 기존 Core format/audit 구현을 제거했습니다. 세 local
fixture와 S0 aggregate catalog가 일치했고, Formats 49 tests, Audit 17 tests,
RenderPlan 2 tests 및 전체 310 tests가 실패 없이 통과했습니다. S2, Metal,
Native Scene, Scene fallback, SceneScript/effect 실행은 시작하지 않았습니다.

### S2 implementation evidence

S2는 [구현 기록](../../implemented/2026-08-04-scene-asset-resolver-typed-graph.md)에
따라 완료했습니다. `MacWallSceneAssets`와 `MacWallSceneGraph`을
`MacWallSceneFormats` 위의 독립 target으로 추가하고, exact virtual path,
candidate/provenance policy, typed graph, deterministic status/summary를
구현했습니다. Audit는 같은 resolver policy를 사용하며 schema 2와 S1 aggregate
catalog compatibility를 유지합니다. Local fixture graph gate 4 tests와 전체
407 tests가 skip/failure 없이 통과했습니다. Metal, Native Scene, fallback,
external assets, execution, renderer/main-app integration은 시작하지 않았습니다.

## 2. 확정 정책

- 최종 renderer는 Metal 기반 headless renderer입니다.
- 현재 `CALayer` Scene renderer는 prototype이며 최종 engine으로 확장하지
  않습니다.
- Main App과 Native Wallpaper extension이 같은 format, graph, renderer
  module을 사용합니다.
- Native mode에서는 Scene renderer가 WallpaperAgent가 실행한 extension
  프로세스 안에서 동작합니다.
- Main App에서 생성한 `MTLTexture`를 extension으로 직접 전달하는 구조를
  사용하지 않습니다.
- Workshop folder만으로 동작할 수 있도록 필요한 built-in asset을
  clean-room으로 구현합니다.
- 사용자가 합법적으로 보유한 Wallpaper Engine `assets/` folder는 향후
  선택적인 compatibility source로만 지원할 수 있습니다.
- Wallpaper Engine built-in asset과 GPL implementation code를 repository나
  app bundle에 복사하지 않습니다.
- 실제 Workshop fixture는 `test/`에 local-only로 유지합니다.
- Git에는 synthetic fixture, aggregate audit metadata, test expectation만
  저장합니다.
- Scene audit은 내부 API와 test support로 구현하며 새 CLI command를
  추가하지 않습니다.
- Scene snapshot은 실제 Metal output에서만 생성합니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`는 UI thumbnail일
  뿐 Scene output이나 fallback source가 아닙니다.

## 3. 조사 결과

### 3.1 Package 구조

현재 local fixture는 다음 package version을 포함합니다.

| Workshop ID | Package | Entries | Objects | 주요 기능 |
| --- | --- | ---: | ---: | --- |
| `2174863503` | `PKGV0008` | 107 | 28 | image, particle, sound, effect |
| `2834933421` | `PKGV0018` | 387 | 98 | image, text, particle, sound, effect, inline script |
| `3516106265` | `PKGV0023` | 125 | 69 | parent graph, instance, text, particle, effect, extensive SceneScript |

PKG는 length-prefixed `PKGVxxxx`, entry count, path/offset/length table,
data region으로 구성됩니다. Entry offset은 data region 시작을 기준으로
해석합니다.

Image asset의 일반적인 참조 chain은 다음과 같습니다.

```text
scene.json object.image
-> models/<name>.json
-> materials/<name>.json
-> passes[]
-> shader + textures[]
-> materials/<name>.tex
```

Package에는 custom effect, shader, texture가 들어갈 수 있지만
`genericimage4`, `genericparticle`, `util/white`, `common.h` 같은 Wallpaper
Engine built-in dependency는 포함되지 않을 수 있습니다.

### 3.2 Texture 구조

현재 fixture는 `TEXV0005`, `TEXI0001`, `TEXB0003`, `TEXB0004`를 사용합니다.

확인된 pixel format:

- RGBA8888
- DXT1 / BC1
- DXT3 / BC2
- DXT5 / BC3
- RG88
- R8

향후 format layer는 확인되지 않은 modern format도 raw value로 보존해야
합니다. 후보에는 half-float 계열, BC7, 10-bit, 16-bit float format이
포함됩니다.

`TEXB0003`은 여러 image와 각 image의 mip chain을 가질 수 있습니다.
`TEXB0004`는 일반 texture와 video texture 분기를 모두 고려해야 합니다.
GIF/sprite texture는 별도의 frame timing과 rectangle metadata를 가질 수
있습니다.

현재 decoder의 다음 동작은 최종 format layer에 적합하지 않습니다.

- 첫 image의 첫 mip만 읽음
- `flags & 0x24`를 일괄 거부
- `TEXB0004` 추가 header와 video payload를 구분하지 못함
- decode와 format parsing이 한 타입에 결합됨

### 3.3 Shader와 effect

Wallpaper Engine shader는 GLSL과 유사하지만 자체 preprocessor, combo,
annotation, built-in uniform, texture alias, render target 규칙을 사용합니다.
Custom shader source를 Metal에 직접 전달할 수 없습니다.

Effect는 image, text, fullscreen, composition layer에 적용되고 chain될 수
있습니다. 따라서 effect는 단일 layer property가 아니라 명시적인 render
pass graph로 표현해야 합니다.

## 4. 정확도 기준

완성도를 단순히 "화면이 나옴"으로 판단하지 않습니다.

각 Scene load 결과는 다음 중 하나입니다.

| 상태 | 의미 |
| --- | --- |
| `exact` | 필요한 asset과 기능이 모두 resolve되고 알려진 의미로 실행됨 |
| `degraded` | Scene은 출력되지만 일부 기능이 명시적으로 대체 또는 생략됨 |
| `unsupported` | 핵심 output을 신뢰할 수 없어 성공으로 표시하지 않음 |
| `invalid` | package 또는 data가 안전하게 해석될 수 없음 |

Unknown field, flag, object, shader feature를 조용히 버리지 않습니다. 원본
위치, raw value, dependency chain, 처리 결과를 diagnostic에 보존합니다.

Visual correctness는 다음 순서로 검증합니다.

1. synthetic fixture의 deterministic pixel test
2. 고정된 time/input/property로 생성한 local offscreen frame
3. 같은 resolution과 time의 Wallpaper Engine reference capture와 비교
4. 실제 Desktop에서 frame pacing과 lifecycle 확인

Reference capture는 local QA 자료이며 repository에 커밋하지 않습니다.

## 5. 프로세스 구조

Native Wallpaper는 Main App과 별도 extension 프로세스에서 실행됩니다.
Scene package와 renderer 실행 위치도 이 경계를 따라야 합니다.

```text
Main App
  scan/import
  audit/preflight
  stage immutable generation
  write play command
          |
          v
Native runtime store
  Generations/<generation>/
    manifest.json
    scene.pkg
    project.json
          |
          v
Wallpaper extension process
  read generation
  parse/resolve/build graph
  create renderer session
  create one render instance per Desktop context
  render first frame for every target context
  commit candidate generation
          |
          v
CAContext -> AVSampleBufferDisplayLayer -> WallpaperAgent
```

Main App에서 미리 만든 graph나 GPU resource를 extension으로 직렬화하지
않습니다. Format과 graph code는 공유하되 각 프로세스가 자기 소유의 runtime
object를 만듭니다.

### 5.1 Generation staging

Scene staging은 기존 video `source.mp4` 단일 파일 규칙과 분리합니다.

- `NativeRuntimeAssetKind.scene`을 추가합니다.
- generation directory는 immutable manifest와 allowlisted Scene source를
  포함합니다.
- symbolic link, path escape, file replacement를 거부합니다.
- manifest에는 schema, asset ID, entrypoint, file size/hash, display mode,
  user property snapshot을 기록합니다.
- candidate 실패 시 staging generation만 제거하고 active generation은
  유지합니다.
- optional external asset은 audit로 확인된 dependency만 별도 subtree에
  stage하는 방식을 우선하며 전체 proprietary assets folder를 app bundle에
  복사하지 않습니다.

### 5.2 Multi-display

하나의 active generation은 immutable parsed document와 GPU resource cache를
공유할 수 있습니다. Display별로 size, scale, display ID, output buffer pool을
가진 render instance를 생성합니다.

- 모든 Desktop context는 같은 monotonic Scene clock을 사용합니다.
- first frame은 모든 target context에서 준비되어야 합니다.
- 하나라도 실패하면 candidate context 전체를 정리합니다.
- 기존 active context는 candidate commit 전까지 유지합니다.
- partial or half-swapped state를 허용하지 않습니다.

## 6. Module 경계

실제 Swift target 이름은 `MacWallScene*` prefix를 사용합니다. 아래 이름은
책임을 나타냅니다.

| Module | 의존성 | 책임 |
| --- | --- | --- |
| `MacWallSceneFormats` | Foundation | PKG/TEX/versioned binary/JSON document |
| `MacWallSceneAudit` | Formats | deterministic report, support matrix, fixture test support |
| `MacWallSceneAssets` | Formats | canonical path, layered resolver, dependency provenance |
| `MacWallSceneGraph` | Formats, Assets | typed node/material/pass/effect/animation graph |
| `MacWallSceneRuntime` | Graph | clock, property, input, lifecycle, later SceneScript |
| `MacWallSceneTextures` | Graph, Assets, Formats, Metal | GPU texture 준비, generation ownership, memory budget |
| `MacWallSceneRenderer` | Graph, Textures, Metal | immutable render program, graph evaluation, render pass, actual-output snapshot |
| `MacWallSceneNativeAdapter` | Renderer, NativeRuntimeSupport | CVPixelBuffer/sample buffer output |

`MacWallCore`는 최종 Metal renderer를 소유하지 않습니다. S1에서 기존 Scene
format/audit 구현을 제거했으며 compatibility facade, typealias, re-export를
두지 않습니다.

## 7. Format layer

### 7.1 Random-access package

`ScenePackageArchiveReader`는 package 전체 `Data(contentsOf:)` 대신 bounded
random-access reader를 사용합니다.

- file size, entry count, path length, entry size limit
- signed/unsigned overflow 검사
- duplicate canonical path 검사
- overlapping range를 report하고 정책에 따라 거부
- truncated table/data 검사
- absolute path, `..`, empty component, backslash, NUL 거부
- 필요한 entry만 read

Package index는 Sendable immutable value이고 file handle lifetime은 별도
reader가 관리합니다.

### 7.2 Texture descriptor와 decode 분리

Format parser는 GPU upload 여부와 관계없이 다음 metadata를 보존합니다.

- header version
- format raw value
- flags raw value와 알려진 bit
- logical image size와 padded texture size
- image count
- image별 mip chain
- compression metadata
- animated frame metadata
- video payload metadata

CPU decoder와 Metal uploader는 이 descriptor를 입력으로 받습니다.

Direct compressed upload는 `MTLDevice` capability를 runtime에 확인한 경우에만
사용합니다. 지원되지 않는 format은 bounded CPU decode 또는 compatible
transcode를 사용합니다.

## 8. Asset resolver

Resolver 우선순위:

```text
1. generation의 package-local entry
2. MacWall clean-room built-in semantic asset
3. 명시적으로 staged된 optional compatibility asset
4. unresolved result
```

Resolver는 filename guess를 여러 곳에 복제하지 않습니다. 모든 참조는
canonical virtual path로 변환하고 다음 provenance를 반환합니다.

```text
requested path
canonical path
resolved source
content identity/hash
dependency parent
fallback/substitution 여부
```

Built-in은 원본 file을 복제하지 않고 의미 단위로 구현합니다.

- generic image/material pipeline
- standard sampler와 blend mode
- white, black, neutral normal, no-flow 등 생성 texture
- fullscreen/solid layer model
- 지원 effect의 Metal shader와 uniform mapping

Optional Wallpaper Engine assets path는 필수 설치 조건이 아니며 자동 탐색하지
않습니다.

## 9. Typed Scene Graph

Scene graph는 렌더링 가능한 layer만 추리는 plan이 아닙니다. 원본 Scene의
의미와 미지원 data를 보존하는 중간 표현입니다.

주요 node:

- image
- text
- particle
- sound
- model
- composition
- fullscreen
- unknown

공통 data:

- stable object ID와 source location
- parent/child와 instance/override
- visibility와 Z order
- origin, anchor, size, scale, rotation, opacity
- material/pass/texture binding
- effect chain
- animation track과 interpolation
- script source/event binding
- feature support status

Parent graph는 cycle을 검증합니다. Instance는 원본 graph를 무제한 복제하지
않고 prototype reference와 override로 표현합니다.

좌표계, anchor, rotation 방향, texture UV, alpha convention은 parser마다
변환하지 않고 graph normalization 한 지점에서 MacWall canonical convention으로
변환합니다.

## 10. Runtime evaluation

Runtime은 renderer와 시간을 분리합니다.

```text
SceneClock + InputSnapshot + PropertySnapshot
-> SceneGraphEvaluator
-> immutable EvaluatedSceneFrame
-> SceneMetalRenderer
```

- renderer가 `sleep`하거나 wall clock을 직접 읽지 않습니다.
- 같은 graph, time, input, property는 같은 evaluated frame을 만듭니다.
- pause는 clock advancement를 멈추고 마지막 frame을 유지합니다.
- resume은 time jump 없이 이어집니다.
- display context들은 한 generation clock을 공유합니다.
- dynamic user property update는 generation-scoped command로 적용합니다.
- unsupported script/effect가 graph 전체 mutation을 깨뜨리지 않도록
  transaction 단위로 평가합니다.

## 11. Metal renderer

Renderer는 `MTKView`에 종속되지 않는 headless API입니다. Legacy window나
개발 preview가 필요하면 별도 view adapter가 renderer output을 표시합니다.

첫 2D frame:

```text
evaluate graph
-> prepare visible resources
-> calculate parent/world transforms
-> encode image passes in stable order
-> composite into output texture
-> submit command buffer
-> publish completed SceneFrame
```

핵심 component:

- resource registry and cache
- texture uploader
- pipeline/sampler cache
- transform evaluator
- render graph compiler
- transient render target pool
- output frame pool
- frame diagnostics

프레임마다 pipeline, sampler, static geometry, texture를 다시 만들지 않습니다.
Transient target은 lifetime analysis 결과에 따라 pool에서 재사용합니다.

### 11.1 Color와 alpha

- color texture와 data texture를 구분합니다.
- color texture는 확인된 color space에 따라 sRGB decode를 적용합니다.
- mask, flow, normal, R/RG texture는 linear data로 취급합니다.
- 내부 합성은 premultiplied alpha convention 하나로 정규화합니다.
- 최종 output color attachment와 sample buffer color metadata를 일치시킵니다.
- color interpretation이 불명확한 format은 audit에 기록하고 reference frame으로
  검증합니다.

### 11.2 Native frame

Scene renderer는 extension 안에서 IOSurface-backed `CVPixelBufferPool`의
buffer를 얻고 `CVMetalTextureCache`로 Metal render target을 만듭니다.

```text
CVPixelBuffer
<-> CVMetalTexture
<- Metal rendering
-> command buffer completion
-> CMSampleBuffer
-> AVSampleBufferVideoRenderer
```

`CVMetalTexture`는 GPU command 완료까지 강하게 유지합니다. 완료되지 않은
buffer를 sample renderer에 enqueue하지 않습니다. Output pool은 bounded
triple buffering을 기본으로 하며 실제 frame pacing 결과로 조정합니다.

기존 Native Video에서 검증된 `AVSampleBufferDisplayLayer`,
`sampleBufferRenderer`, generation lifecycle을 재사용합니다. Scene 전용
`CAMetalLayer`를 remote `CAContext`에 직접 연결하는 방식은 별도 probe에서
검증되기 전 기본 경로로 사용하지 않습니다.

## 12. Effect와 shader

두 단계 전략을 사용합니다.

### 12.1 Clean-room semantic effects

사용 빈도가 높은 built-in 의미를 Metal로 직접 구현합니다.

- color adjustment
- opacity/mask
- blur
- bloom
- blend
- shake/distortion
- fullscreen/composition pass

Effect 하나가 실패하면 해당 effect를 명시적으로 degraded 처리할 수 있지만,
입력 layer 자체를 잃으면 안 됩니다.

### 12.2 Custom shader compatibility

후속 단계에서 제한적인 translation pipeline을 검토합니다.

```text
Wallpaper Engine shader source
-> include resolver
-> annotation/combo preprocessor
-> normalized GLSL-like IR
-> validated translation
-> MSL
-> cached Metal library
```

임의 source를 신뢰하지 않습니다. Include depth, source size, variant count,
compile time, texture binding, render target size에 제한을 둡니다. Translation
실패는 original diagnostic과 함께 effect 단위로 격리합니다.

GPL renderer code는 복사하지 않습니다. 호환 가능한 third-party compiler를
도입한다면 해당 license와 notice를 별도로 보존합니다.

## 13. Text, particle, media, script

### Text

- packaged font를 process-private registration으로 관리
- shaping/layout은 Core Text 기반
- alignment, line spacing, transform, material/effect 연결
- missing font는 명시적 fallback과 diagnostic

### Particle

- emitter/operator/render data를 typed graph로 유지
- GPU-instanced update/render
- fixed-step simulation과 bounded particle count
- random seed를 고정할 수 있어야 golden test가 가능

### Animated/video texture와 sound

- multi-image/GIF timing은 Scene clock에 연결
- video texture는 AVFoundation decode를 별도 producer로 사용
- audio layer와 media integration은 Scene lifecycle에 종속
- hidden/suspended 상태의 decode와 simulation 정책을 분리

### SceneScript

SceneScript는 별도 execution boundary입니다.

- ECMAScript runtime은 명시적으로 노출한 API만 접근
- filesystem, process, network API를 제공하지 않음
- JS context는 전용 serial executor에서 사용
- init/update/event별 execution budget
- heap, recursion, dynamic asset count 제한
- runtime violation 시 해당 script를 중지하고 Scene은 degraded 상태로 유지
- time, input, media, property는 snapshot으로 전달

## 14. Lifecycle과 오류 처리

Lifecycle:

```text
idle
-> loading
-> graphReady
-> resourcesPreparing
-> firstFrameReady
-> active
-> suspended
-> stopping
-> stopped
```

모든 async 작업은 generation token을 검증합니다.

- 새 Play, Remove, reimport는 이전 generation을 invalidate
- candidate resource가 늦게 완료되어 active generation을 덮지 못함
- stop은 decoder, script, command buffer completion, frame pool을 정리
- sleep/covered 상태는 마지막 frame을 유지하고 clock/decode/simulation을
  정책에 따라 suspend
- device loss 또는 renderer failure는 active frame을 유지한 transactional
  replacement를 한 번 시도

오류 분류:

- `invalidInput`
- `unsafeInput`
- `unsupportedFormat`
- `missingAsset`
- `unsupportedFeature`
- `resourceLimit`
- `shaderCompile`
- `rendererFailure`
- `cancelled`

User-facing error와 developer diagnostic을 분리합니다.

## 15. Resource와 성능 정책

Parser limit과 runtime budget을 설정값으로 관리하고 audit에 기록합니다.

- package와 entry byte limit
- texture dimension와 decoded byte limit
- active GPU texture budget
- transient render target budget
- shader variant count
- script heap/time budget
- particle count
- video decoder count

초기 performance 원칙:

- 4K output에서 frame당 heap allocation 최소화
- texture/pipeline dedupe
- asynchronous resource preparation
- visible first frame에 필요한 resource 우선
- background loading은 bounded concurrency
- covered/battery/thermal 상태는 quality profile로 제어
- 해상도 저하는 output size보다 effect/particle scale을 먼저 조정

정확한 숫자는 대표 fixture 측정 후 정하며 근거 없이 조기 고정하지 않습니다.

## 16. 테스트 전략

### 16.1 Git tracked synthetic fixtures

- valid minimal PKG
- truncated header/table/data
- unsafe path와 duplicate canonical path
- invalid/overlapping range
- TEXB0003 single/multi-image/mipmap
- TEXB0004 regular/video branch
- known texture format과 unknown raw value
- parent cycle와 instance override
- material/pass/effect dependency chain
- unknown object/effect/script event

### 16.2 Local real fixtures

- 세 fixture의 deterministic audit JSON
- parse/resource peak 측정
- unresolved built-in dependency catalog
- fixed time offscreen render
- Wallpaper Engine local reference frame 비교

원본 package, texture, shader, reference screenshot은 Git에 커밋하지 않습니다.

### 16.3 Renderer test

- GUI 없이 offscreen Metal texture render
- pixel tolerance와 alpha/color test
- transform/timeline deterministic test
- multiple display size/scale test
- first-frame all-or-nothing commit simulation
- cancellation, stale generation, partial failure
- pause/resume clock continuity
- resource cache dedupe와 eviction

GPU/OS 차이로 bit-exact 결과가 안정적이지 않은 경우 명시적인 channel tolerance와
perceptual metric을 사용합니다.

### 16.4 Human QA gate

실제 WallpaperAgent 선택, System Settings 조작, Desktop 출력, fullscreen
transition은 사용자가 직접 확인합니다. 자동화가 대신 조작하지 않습니다.

## 17. 구현 단계

### S0: Format Research and Audit Contract

- fixture catalog와 aggregate report 확정
- internal `SceneAudit` API
- synthetic malformed corpus
- unknown/unresolved reporting

### S1: Format Layer

상태: implemented / completed

- random-access PKG
- versioned TEX descriptor
- all image/mip metadata
- strict limits and errors
- [구현 기록](../../implemented/2026-07-29-scene-format-layer-hardening.md)

### S2: Asset Resolver and Typed Graph

상태: implemented / completed

- canonical virtual paths
- clean-room built-in contract
- model/material/pass dependency graph
- typed nodes, parent, instance, animation
- [구현 기록](../../implemented/2026-08-04-scene-asset-resolver-typed-graph.md)

### S3: GPU Texture Pipeline

상태: implemented / completed

S3는 `MacWallSceneTextures` 독립 target에 capability mapping, direct raw/BC
upload, ImageIO/software fallback, full-mip metadata, memory reservation,
generation cache/store를 구현했다. 결과는
[S3 구현 기록](../../implemented/2026-08-06-scene-gpu-texture-pipeline.md)에,
설계와 실행 계획은 각각
[archive design](../../archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md) 및
[archive plan](../../archive/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md)에
보관한다.

최종 S3 코드 commit `9677d1d` 검증은 focused S3
`164 tests, 0 failures, 0 skips`, full `swift test`
`583 tests, 0 failures, 0 skips`다. Compact mip-chain classification과 제출된
Metal resource의 completion lifetime까지 회귀 검증했다. Renderer, Desktop output,
Scene fallback, animation/video, heap/streaming은 S3에 포함하지 않는다.

### S4: Headless 2D Metal Renderer

상태: implemented / completed. 결과는
[S4 구현 기록](../../implemented/2026-08-14-scene-headless-2d-metal-renderer.md)을
기준으로 한다. 완료된
[설계](../../archive/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-design.md),
[Gate 0 evidence](../../archive/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md),
[실행 계획](../../archive/superpowers/plans/2026-08-14-scene-headless-2d-metal-renderer.md)은
archive에 보관한다.

- immutable compiled render program
- image layer와 stable transform/opacity/Z order
- typed parent/instance/Loop-Mirror-Single timeline
- linear RGBA16Float composition과 BGRA8 sRGB output
- deterministic offscreen frame과 actual Metal snapshot
- effect/text/particle/media/3D는 후속 phase로 유지

세 fixed local fixture는 `320x180 @ 0.5s`에서 actual Metal output을 만들고,
path/payload-free semantic pixel catalog와 두 번의 deterministic render로
검증했다. focused S4 `67 tests`, renderer target `77 tests`, full
`swift test` `668 tests`가 실패 없이 통과했고 single-GPU 환경의 cross-device
validation 1건만 skip했다. Desktop output, Native adapter와 Scene fallback은
S4에 연결하지 않았다.

### S5: Native Scene Frame Adapter

- scene generation staging
- extension-side renderer
- IOSurface-backed output pool
- first-frame transactional commit
- Native Wallpaper Desktop QA

### S6-S12

- S6 Effects render graph
- S7 Text
- S8 Particles
- S9 Animated/video texture, sound, media
- S10 Puppet warp
- S11 User properties and sandboxed SceneScript
- S12 3D, advanced shader compatibility, regression hardening

## 18. 첫 milestone 완료 조건

S0-S5 완료 시:

- 세 local fixture가 crash 없이 audit됨
- unknown/unsupported/unresolved 결과가 deterministic하게 기록됨
- `2174863503`이 preview 없이 Metal image composition으로 출력됨
- `2834933421`, `3516106265`가 fixed layer cap 없이 graph로 load됨
- 같은 time/input/property가 같은 offscreen frame을 생성함
- Scene renderer가 Native Wallpaper extension 프로세스에서 실행됨
- 모든 target Desktop context의 first frame이 준비된 뒤 generation이 commit됨
- Scene snapshot이 실제 Metal render target에서 생성됨
- Video/Web/Legacy backend 동작은 변경되지 않음

Effect, particle, text, script가 남아 있는 Scene은 이 시점에 `exact`로 표시하지
않습니다.

## 19. 대안 판단

### 기존 CALayer prototype 확장

부모/instance, render target, effect chain, particle, custom shader, deterministic
frame output에 맞지 않아 채택하지 않습니다.

### OpenGL/GPL renderer port

초기 coverage는 높을 수 있지만 macOS native pipeline, Metal 목표, MIT repository
정책과 맞지 않아 채택하지 않습니다.

### Main App renderer와 cross-process texture 전달

프로세스 lifecycle, extension sandbox, multi-display candidate transaction을
복잡하게 만들고 현재 검증된 native frame path를 우회하므로 채택하지 않습니다.

### Clean-room Metal + 후속 제한적 shader translation

라이선스, 안정성, 디버깅 가능성, 단계적 compatibility를 가장 잘 만족하므로
채택합니다.

## 20. 라이선스와 출처

MacWall repository의 project-authored code는 전체 MIT license를 적용합니다.
Native Wallpaper Backend와 Scene Engine을 별도 제한 license로 분리하지
않습니다.

MIT는 사용, 수정, 배포, sublicense, 판매를 허용합니다. 단순 복사 후 판매를
별도로 금지하는 조건은 MIT와 함께 둘 수 없으며 이번 결정에서는 추가하지
않습니다.

원작 Workshop Wallpaper Bridge notice와 현재 작업자 notice는 repository
root `LICENSE`에 유지합니다. 호환 가능한 third-party dependency를 사용하면
각 dependency의 license와 notice도 보존합니다.

## 21. 참고 자료

- [Wallpaper Engine SceneScript Reference](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html)
- [Wallpaper Engine IEngine asset registration](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html)
- [Wallpaper Engine Effects Introduction](https://docs.wallpaperengine.io/en/scene/effects/introduction.html)
- [Wallpaper Engine Shader Syntax](https://docs.wallpaperengine.io/en/scene/shader/syntax.html)
- [Wallpaper Engine Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)
- [Wallpaper Engine Asset Sharing](https://docs.wallpaperengine.io/en/scene/assets/sharing.html)
- [Apple CVMetalTextureCacheCreateTextureFromImage](https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage(_:_:_:_:_:_:_:_:_:))
- [Apple AVSampleBufferDisplayLayer](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer)
- [Apple MTLTexture](https://developer.apple.com/documentation/metal/mtltexture)
- [RePKG](https://github.com/notscuffed/repkg), MIT format research reference
- [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine), GPL behavior comparison only
