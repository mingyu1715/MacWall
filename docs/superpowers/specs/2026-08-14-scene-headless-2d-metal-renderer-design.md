# Scene S4 Headless 2D Metal Renderer Design

작성일: 2026-08-14

상태: approved design / executable implementation plan pending / implementation not started

## 1. 결정 요약

S4는 S2 typed graph와 S3 GPU texture를 받아 실제 2D Scene frame을 만드는
독립 headless Metal renderer를 추가한다. `MTKView`, AppKit, WallpaperAgent,
Desktop window에 의존하지 않으며 같은 Scene, time, output configuration에서
재현 가능한 offscreen output을 생성한다.

핵심 구조는 compile과 frame evaluation을 분리하는 immutable render program이다.

```text
SceneGraphBuildResult
          |
          v
SceneRenderCompiler -> immutable SceneRenderProgram
                              |
SceneTextureStore + resolver -> SceneRenderSession
                              |
                              v
               SceneTimelineEvaluator(time)
                              |
                              v
                       SceneFramePlan
                              |
                              v
                    SceneMetalRenderer
                              |
                              v
                 offscreen MTLTexture / snapshot
```

매 frame마다 graph와 raw JSON을 다시 순회하지 않는다. compiler는 지원되는 image
layer, hierarchy, instance, animation, texture request를 stable draw template로
정규화한다. evaluator는 지정된 time의 값만 계산하고 renderer는 준비된 texture와
uniform을 사용해 Metal command를 encode한다.

S4 결과는 effect 없는 image composition까지 정확하게 그리는 첫 Scene output이다.
지원되지 않는 effect, shader, 3D 속성이 있어도 지원되는 base image layer를 정확히
그릴 수 있으면 `degraded`로 결과를 낸다. 효과를 흉내 내거나 thumbnail을 대신
그리지 않는다.

## 2. 배경과 현재 계약

현재 Scene pipeline은 다음 경계를 제공한다.

```text
MacWallSceneFormats
        |
        v
MacWallSceneAssets
        |
        v
MacWallSceneGraph
        |
        v
MacWallSceneTextures
```

- `MacWallSceneGraph`는 canvas, node, hierarchy, instance, resource, dependency,
  animation을 보존한다.
- node에는 stable `sourceOrder`, transform, opacity, color, Z와 typed payload가 있다.
- hierarchy와 instance reference는 resolved, missing, ambiguous 상태를 보존한다.
- animation의 value와 interpolation은 일부가 아직 `SceneJSONValue`에 머물러 있다.
- `MacWallSceneTextures`는 generation 단위 `SceneTextureLease`를 제공한다.
- lease에는 physical storage extent, logical content extent/rect, top-left origin,
  mip count와 resident byte가 있다.
- S3 color texture는 sRGB view를 제공하고 raw/decoded RGBA의 alpha는 straight로
  정규화한다.

S4는 이 계약을 소비하되 renderer 내부에서 raw Scene JSON을 해석하지 않는다.
필요한 animation과 override 의미는 `MacWallSceneGraph`에서 typed contract로
승격한 뒤 renderer로 전달한다.

기존 `MacWallCore/Scene/SceneRenderPlan.swift`와
`MacWallApp/Playback/SceneWallpaperView.swift`의 CALayer 경로는 prototype이다.
S4 구현 기반으로 확장하거나 최종 renderer와 공유하지 않는다.

## 3. 목표

- 독립 target `MacWallSceneRenderer`를 추가한다.
- image node를 stable Z/source order로 합성한다.
- parent-child transform과 supported instance override를 평가한다.
- origin/position, pivot, scale, Z rotation, opacity, visibility animation을 지정된
  time에서 평가한다.
- Loop, Mirror, Single playback mode와 relative/absolute track을 지원한다.
- cubic Bezier, linear, step interpolation을 typed contract로 평가한다.
- `Fit`, `Fill`, `Stretch` output scaling을 지원한다.
- S3 `contentRect`, top-left origin, mip chain을 정확히 사용한다.
- 선형 색 공간에서 premultiplied-alpha composition을 수행한다.
- caller-provided target 또는 renderer-owned offscreen target에 render한다.
- 실제 Metal output에서 CPU-readable PNG/pixel snapshot을 만든다.
- renderer status, diagnostics, limits, resource lifetime을 deterministic하게
  검증한다.
- 세 local Scene fixture를 fixed time/output size로 headless 검증한다.

## 4. 비목표

S4에서는 다음을 하지 않는다.

- effect와 custom shader 실행
- text, particle, sound, animated texture, video texture
- SceneScript, user property, input binding
- puppet warp, 3D model, X/Y rotation, light, camera
- WallpaperAgent/Native Wallpaper adapter와 Desktop Scene 출력
- Scene fallback cache 생성 또는 macOS wallpaper 변경
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png` 사용
- `MTKView`, AppKit window, GUI/System Settings 검증
- `MTLHeap`, sparse texture, projected-size mip streaming
- HDR, wide-color display, tone mapping

S4 snapshot은 테스트와 후속 S5/S12 경계를 위한 actual render output이다. P1/P2
`desktop-fallback.png` 정책에 Scene을 추가하는 작업이 아니다.

## 5. 검토한 대안

### 5.1 선택: immutable compiled render program

graph를 한 번 compile하고 frame마다 timeline과 matrix만 평가한다.

장점:

- raw graph 해석과 GPU encoding을 분리할 수 있다.
- unsupported feature를 compile 시점에 한 번 분류할 수 있다.
- stable ordering과 resource request가 frame 사이에서 흔들리지 않는다.
- CPU-only compiler/evaluator test와 실제 Metal test를 분리할 수 있다.
- S5에서 candidate session을 준비한 뒤 first-frame commit하는 구조로 확장된다.

비용:

- compile-time model과 frame-time model이 별도로 필요하다.
- graph 변경 시 새 program/session generation을 만들어야 한다.

S4의 correctness와 후속 transactional runtime에 가장 적합하므로 이 방식을
채택한다.

### 5.2 기각: graph direct traversal per frame

구현 시작은 빠르지만 raw JSON, hierarchy traversal, resource lookup과 draw encoding이
한 경로에 섞인다. 4K/60fps에서 불필요한 CPU work와 allocation이 반복되고,
unsupported 의미가 frame마다 달라질 수 있어 기각한다.

### 5.3 보류: ECS 또는 범용 render graph 선행

장기적으로 particle, effect, 3D에는 유용하지만 S4의 image composition만 위해
ECS와 범용 pass scheduler를 먼저 도입하면 계약이 실제 사용보다 앞선다. S6 effect
render graph에서 측정된 요구에 맞춰 추가한다.

## 6. Target과 의존성

새 target:

```text
MacWallSceneRenderer
|- MacWallSceneGraph
|- MacWallSceneTextures
|- Foundation
|- Metal
|- CoreGraphics
|- ImageIO
|- CryptoKit
`- simd
```

의존성 규칙:

- `MacWallSceneRenderer`는 `MacWallCore`, `MacWallApp`, AppKit,
  `MacWallNativeRuntimeSupport`, WallpaperExtensionKit에 의존하지 않는다.
- `MacWallSceneGraph`는 Metal을 import하지 않는다.
- renderer는 S3 `SceneTextureStore` public API와 lease metadata만 사용한다.
- renderer는 package file을 직접 열거나 texture를 decode하지 않는다.
- snapshot encoder만 CoreGraphics/ImageIO를 사용하며 renderer command path와
  분리한다.

예상 파일 책임:

```text
Sources/MacWallSceneRenderer/
|- SceneRenderModels.swift
|- SceneRenderLimits.swift
|- SceneRenderCompiler.swift
|- SceneRenderOrdering.swift
|- SceneTimelineEvaluator.swift
|- SceneTransformEvaluator.swift
|- SceneRenderSession.swift
|- SceneMetalPipelines.swift
|- SceneMetalRenderer.swift
|- SceneSnapshotReader.swift
`- Shaders/SceneImage.metal
```

파일명은 구현 중 지역 패턴에 맞춰 조정할 수 있지만 compiler, evaluator, GPU
session, snapshot 책임을 한 타입에 합치지 않는다.

## 7. Public Contract 방향

아래 이름은 구현 계획에서 확정할 conceptual contract다. 필드 하나하나보다 책임과
소유권이 설계 기준이다.

### 7.1 Compile result

```swift
public struct SceneRenderCompileResult: Sendable {
    public let program: SceneRenderProgram?
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]
}
```

`SceneRenderProgram`은 immutable, `Sendable`, CPU-only 값이다. Metal object,
resolver, file URL을 저장하지 않는다.

program은 다음을 보존한다.

- validated canvas
- stable draw templates
- parent/instance evaluation order
- typed animation bindings
- texture acquisition manifest와 graph resource identity
- compile diagnostics와 exact/degraded 상태
- deterministic program fingerprint

texture acquisition manifest entry는 validated `SceneTextureResource`, image index,
color intent를 보존한다. 이는 S3 `acquire`가 요구하는 exact resource resolution을
잃지 않기 위한 CPU-only graph value다. S3의 runtime-random
`SceneTexturePackageID`는 program이나 fingerprint에 넣지 않는다. S3 Textures target은
package ID와 resolver를 감싼 additive `SceneTexturePackageContext`와 context 기반
`acquire` overload를 제공한다. session 준비 시 caller가 이 context를 제공하고
manifest entry와 함께 `SceneTextureRequest`를 만든다. 따라서 Renderer target은
`MacWallSceneAssets`를 직접 import하거나 의존하지 않는다.

fingerprint는 canonical graph identity/value, compiler policy version, output에
영향을 주는 typed option만 포함한다. UUID, absolute path, object address,
`MTLDevice` identity는 제외한다.

### 7.2 Session

```swift
public actor SceneRenderSession {
    // Device-bound state, texture generation, in-flight frame ownership.
}
```

session은 하나의 `MTLDevice`, command queue, pipeline/sampler state,
`SceneTextureGenerationID`, texture lease set, render target pool을 소유한다.
Main actor 격리를 사용하지 않는다. 다른 device의 texture/target을 받으면 명시적으로
거부한다.

### 7.3 Frame request/result

frame request는 최소 다음 값으로 구성한다.

- monotonic media time (`Double`, seconds)
- output width/height
- `Fit`, `Fill`, `Stretch`
- transparent clear color
- caller target lease 또는 owned offscreen target 선택
- snapshot 요청 여부

frame result는 제출 성공만 의미하지 않는다. command buffer completion이 성공한
뒤에만 publish 가능한 completed frame을 반환한다.

- output texture 또는 caller target identity
- evaluated time
- status와 diagnostics
- draw/skipped count
- GPU completion result
- optional snapshot artifact

renderer-owned output은 단순 `MTLTexture`가 아니라 frame lease로 반환한다. lease가
살아있는 동안 해당 target slot을 재사용하지 않는다. caller-provided target은
exclusive target lease/token으로 전달한다. caller는 submission 시작부터 completion
handoff까지 다른 command가 target을 읽거나 쓰지 않도록 보장하고, S4는 target을
강하게 retain하며 자기 submission 사이의 중복만 추적한다.

## 8. Compile Pipeline

compiler는 `SceneGraphDocument`만 따로 받지 않고 `SceneGraphBuildResult`를 입력으로
받아 upstream status와 diagnostics를 잃지 않는다. compiler는 다음 순서로 동작한다.

1. canvas와 renderer limits를 검증한다.
2. graph status와 cycle/reference diagnostics를 확인한다.
3. renderable image node를 선택한다.
4. model/material/pass/texture dependency에서 image texture request를 결정한다.
5. hierarchy와 instance graph를 stable topological order로 정규화한다.
6. `MacWallSceneGraph`가 검증한 typed instance override를 소비한다.
7. animation track을 typed binding으로 연결한다.
8. Z, source order, node ID의 deterministic tie-break order를 계산한다.
9. unsupported feature와 skipped layer diagnostic을 기록한다.
10. immutable program과 texture acquisition manifest를 만든다.

compiler는 texture를 load하거나 Metal pipeline을 생성하지 않는다. texture store,
package resolver, package/generation identity는 device-bound session 준비 단계에
전달한다.

upstream graph diagnostics는 전부 보존하되 graph status를 기계적으로 복사하지
않는다. S2의 `unsupported`는 effect/shader 보존만으로도 발생하므로 S4가 exact base
image subset을 render할 수 있으면 renderer 결과는 `degraded`가 맞다.

- `invalid` graph 또는 document 부재는 `invalid`다.
- S4 image output에 필수인 chain의 unsupported/missing은 `unsupported`다.
- S4 비범위 effect/shader/text/particle/media가 함께 있으나 image subset을 그릴 수
  있으면 `degraded`다.
- S4 지원 의미와 diagnostics가 모두 exact일 때만 `exact`다.

동일 단계의 status 결합 우선순위는 `invalid > unsupported > degraded > exact`다.

### 8.1 Stable draw order

draw order는 투명 합성 결과이므로 단순 최적화 대상이 아니다. 기본 key는 다음과
같다.

```text
effective Z -> sourceOrder -> stable node/instance identity
```

Z 방향과 instance가 source order를 상속/대체하는 정확한 의미는 구현 gate 0의
fixture evidence로 확정한다. evidence가 현재 가정과 다르면 key 자체를 수정하고
테스트로 고정한다. 같은 key의 draw를 texture별로 재정렬하지 않는다.

### 8.2 Resource mapping

지원되는 image node가 하나의 exact color texture로 resolve될 때만 draw template를
만든다. 다음은 layer 단위 diagnostic과 skip 대상이다.

- missing/ambiguous texture dependency
- unsupported animated/video/multi-image texture
- color texture로 사용할 수 없는 data-linear resource
- S3 acquisition failure

unsupported effect/custom shader가 있어도 plain image texture, UV, geometry,
transform이 그 기능과 독립적이라는 graph evidence가 있을 때만 base image를
degraded render한다. custom shader가 texture selection, UV deformation, color,
alpha, geometry에 필수면 이를 no-op으로 취급하지 않고 해당 layer를 skip한다.

일부 layer만 실패하면 남은 exact layer를 그리고 scene은 `degraded`다. renderable
layer가 하나도 없으면 `unsupported`다.

## 9. Graph Contract 보강

현재 animation keyframe interpolation과 instance override는 raw value를 포함한다.
S4 구현 전에 `MacWallSceneGraph`에 다음 typed 의미를 additive하게 추가한다.

### 9.1 Typed timeline

- playback mode: `loop`, `mirror`, `single`
- value mode: `absolute`, `relative`
- interpolation: `cubicBezier`, `linear`, `step`
- validated keyframe time/value
- Bezier control metadata
- start-paused evidence는 보존하되 SceneScript 없는 S4 자동 재생 여부를 gate 0에서
  확정

unknown mode/interpolation은 linear로 추측하지 않는다. 해당 property는 node의 base
value를 유지하고 track에 degraded diagnostic을 남긴다.

### 9.2 Typed instance override

S4 지원 override:

- origin/position
- scale
- `angles.z`
- opacity
- visible/enabled
- Z

unknown path, type mismatch, X/Y rotation은 적용하지 않고 degraded diagnostic으로
보존한다. `SceneInstanceEdge`가 typed override collection을 공개하고 기존 raw
override는 audit/compatibility evidence로만 보존한다. renderer compiler는
`ScenePropertyOverride.propertyPath/value`를 직접 해석하지 않는다.

## 10. Transform와 좌표계

모든 graph 계산은 CPU에서 `Double`로 수행하고, 검증된 최종 matrix/uniform만
GPU `Float`로 변환한다.

기본 evaluation 순서:

```text
base property
-> instance override
-> timeline value at time
-> local transform
-> parent world * local
-> canvas-to-output transform
```

- `origin`은 Wallpaper Engine 공식 API상 layer position이다.
- `pivot`은 회전/scale 기준점으로 사용한다.
- `angles.z`만 2D 회전으로 지원한다.
- parent transform과 opacity/visibility는 child에 전파한다.
- opacity는 각 단계에서 임의 clamp하지 않고 final fragment 입력 전 유효 범위로
  정규화한다.
- NaN, infinity, singular/overflowing matrix는 해당 frame/layer diagnostic과 skip
  또는 invalid로 분류한다.

다음은 아직 근거 검증이 필요한 항목이다.

- pivot 단위와 texture/canvas 상대 기준
- origin과 별도 position이 동시에 있을 때 결합 순서
- Z의 앞/뒤 방향
- instance override와 source animation의 우선순위
- top-left Scene 좌표에서 Metal clip space로 가는 Y 변환 위치

이 항목은 gate 0에서 fixture 값을 수작업으로 추측하지 않고 parser evidence,
Wallpaper Engine 공식 동작, 기존 prototype output을 교차 대조한 뒤 synthetic test로
고정한다.

## 11. Timeline Evaluation

evaluator는 wall clock을 직접 읽지 않는다. caller가 전달한 media time만 사용한다.
따라서 unit test와 snapshot은 real sleep 없이 fixed time으로 재현된다.

mode 의미:

- Loop: duration 뒤 처음으로 돌아간다.
- Mirror: forward duration과 reverse duration을 반복한다.
- Single: duration 이후 마지막 값을 유지한다.

Wallpaper Engine 공식 문서는 기본 timeline easing이 Bezier이며 linear는 Bezier를
끄는 방식이라고 설명한다. S4는 keyframe metadata가 이를 증명할 때만 해당
interpolation을 적용한다.

정책:

- invalid/zero duration은 typed diagnostic으로 분류한다.
- keyframe time은 stable sort하며 동일 time 처리 규칙을 parser contract로 고정한다.
- relative track은 base/override property에 evaluated delta를 적용한다.
- supported property의 channel 일부만 invalid면 전체 vector를 임의 보간하지 않고
  base channel을 유지한다.
- frame rate는 keyframe frame 값을 seconds로 변환하는 metadata이며 render tick을
  강제하지 않는다.
- fixed input/time 평가에는 allocation과 I/O가 없어야 한다.

## 12. Output Scaling

Scene canvas와 output surface 비율은 하나의 canvas-to-output matrix로 처리한다.

- Fit: 전체 canvas가 보이도록 uniform scale하고 남는 영역은 transparent다.
- Fill: output을 채우도록 uniform scale하고 넘치는 canvas를 crop한다.
- Stretch: X/Y를 독립 scale한다.

crop은 texture UV를 임의 변경하지 않고 output transform/scissor에서 처리한다.
같은 mode와 dimensions는 같은 matrix를 생성해야 한다. invalid canvas, zero/negative
output, integer overflow는 frame 제출 전에 거부한다.

## 13. Texture Sampling

S4 image color request는 S3 `.colorSRGB` lease를 사용한다.

- `contentRect`만 sample하며 texel-center mapping과 logical-edge clamp로 physical
  padding이 linear filter footprint에 섞이지 않게 한다.
- top-left origin 변환은 shader boundary에서 정확히 한 번 수행한다.
- minification/magnification은 linear다.
- mip filter는 linear로 두어 trilinear sampling을 사용한다.
- anisotropy 기본값은 8이며 device limit에 맞춰 낮춘다.
- address mode는 clamp-to-edge다.
- sampler와 pipeline state는 frame마다 생성하지 않는다.

현재 `SceneTextureLease`는 mip-0 `contentRect`만 공개한다. gate 0에서 모든 supported
padded mip의 logical/storage 비율이 이 단일 rect로 안전하게 표현되는지 검증한다.
비율이 level마다 달라지면 S4 구현 전에 S3 lease를 per-mip content extent/rect로
확장한다. metadata가 부족한 padded texture에 trilinear filtering을 추측 적용하지
않으며, 정확한 lod-aware clamp가 준비될 때까지 해당 mip path를 degraded로
제한한다.

Apple 문서상 mip filtering은 sampler의 별도 설정이며 sRGB pixel format은 texture
read/write에서 색 channel 감마 변환을 수행한다. 따라서 S4는 source sRGB texture
view와 linear composition target의 역할을 분리한다.

## 14. Color와 Alpha Pipeline

S4 기준 pipeline:

```text
sRGB color texture
-> hardware sRGB decode
-> linear fragment color
-> node tint and opacity
-> explicit premultiplication
-> linear RGBA16Float composition
-> final BGRA8 sRGB conversion
```

- source alpha는 S3 계약에 따라 straight alpha다.
- node tint가 sRGB numeric value라는 evidence를 gate 0에서 확인하고 linear로
  변환한 뒤 곱한다. 의미가 불명확한 non-white tint를 linear 값으로 추측하지 않는다.
- final fragment output은 premultiplied alpha다.
- blend factor는 source `one`, destination `oneMinusSourceAlpha`다.
- alpha channel에는 sRGB transfer function을 적용하지 않는다.
- clear color 기본은 transparent black이다.
- internal composition format은 `.rgba16Float`다.
- standard final output은 `.bgra8Unorm_srgb`다.

S4는 HDR metadata, EDR headroom, display profile conversion을 추측하지 않는다.
wide-color/HDR은 별도 design gate에서 다룬다.

## 15. Render Pass와 Target

S4는 두 종류의 target을 지원한다.

1. renderer-owned offscreen target
2. caller-provided compatible target lease

표준 frame은 linear composition pass와 final output conversion pass로 구성한다.
이는 effect render graph가 아니라 color/format 경계를 명확히 하기 위한 고정
pipeline이다. S6는 이 사이에 effect pass를 추가할 수 있다.

caller target 검증:

- 같은 `MTLDevice`
- expected width/height
- render-target usage
- S4 standard final format인 `.bgra8Unorm_srgb`
- private/shared storage가 사용 목적에 부합
- caller가 completion까지 exclusive GPU access를 보장하는 target lease/token

Metal은 다른 owner가 제출한 command의 전역 in-flight 상태를 조회하는 API를
제공하지 않는다. 따라서 S4는 외부 submission 부재를 검증한다고 주장하지 않는다.
session은 자신이 받은 token과 target을 completion까지 강하게 보존하고, 같은 token이
자기 in-flight set에 중복 제출되는 것만 거부한다.

S4에서 `.bgra8Unorm`을 sRGB bytes처럼 취급하거나 암묵적으로 manual gamma encode하지
않는다. IOSurface/CVPixelBuffer target format 확장은 S5 adapter 설계에서 명시한다.

renderer-owned intermediate는 GPU-only private storage를 사용한다. snapshot
readback은 별도 shared staging buffer/texture로 복사한다. Apple의 storage-mode와
CPU/GPU synchronization 지침에 따라 private render resource에 CPU가 직접
접근하지 않는다.

## 16. Session Lifecycle

준비와 publication 순서:

```text
compile program
-> create texture generation
-> attempt every supported texture acquisition
-> finalize surviving draw set and status
-> create pipeline/sampler/target pool
-> session ready
-> evaluate frame
-> encode and commit
-> command completion success
-> publish completed frame
```

- session preparation result는 acquisition 성공 binding, 실패 binding diagnostic,
  surviving draw/skipped count, recomputed status를 immutable하게 보존한다.
- 하나의 texture acquisition이 실패하면 그 binding을 사용하는 draw template를
  stable하게 제거하고 결과를 `degraded`로 낮춘다. 이는 resource-local
  unsupported/decode/allocation 실패에만 적용한다.
- task cancellation, invalid generation, device loss처럼 session 전체 의미가 깨지는
  실패는 partial ready session으로 낮추지 않고 preparation 자체를 취소/실패한다.
- 모든 acquisition attempt와 pipeline 준비가 끝나기 전에는 session을 ready로
  공개하지 않는다.
- surviving renderable draw가 하나 이상일 때만 ready session을 만든다. 하나도
  남지 않으면 partial/black session 대신 `unsupported` preparation failure를
  반환하고 generation/resource를 정리한다.
- 첫 frame이 실패하면 partial/black candidate frame을 공개하지 않는다.
- renderer-owned mode에서 새 frame이 실패하면 session이 보유한 마지막 successful
  completed frame lease를 유지한다. caller-provided target mode에서는 실패 frame을
  publish하지 않는 책임이 caller에게 있다.
- graph/configuration 변경은 existing session을 mutate하지 않고 새 candidate
  program/session generation을 만든다.
- S4 자체는 Desktop active session 교체를 수행하지 않는다. S5가 transactional
  replacement를 소유한다.
- cancellation/invalid session은 새 command 제출을 막고 이미 제출된 resource는
  completion까지 유지한다.
- texture generation은 마지막 in-flight completion 뒤 정확히 한 번 release한다.

## 17. Concurrency와 Resource Lifetime

- compiler/evaluator는 pure value operation으로 Main actor 밖에서 실행한다.
- `SceneRenderSession` actor가 mutable GPU submission state를 직렬화한다.
- Metal command completion은 actor state를 직접 무단 변경하지 않고 명시적
  completion handoff를 사용한다.
- max in-flight frame 기본값은 3이다.
- uniform/staging resource는 in-flight ring으로 미리 할당한다.
- submitted texture lease, target, buffer는 command completion까지 보존한다.
- completed owned-frame target은 frame lease와 session의 last-success ownership이
  모두 끝날 때까지 pool로 반환하지 않는다.
- completion, cancellation, error 경로는 reservation과 ownership을 정확히 한 번
  반환한다.
- command completion 전 동일 offscreen target을 재사용하지 않는다.
- steady-state frame path에서 heap allocation, file I/O, texture decode를 하지 않는다.

투명 layer는 order-dependent이므로 opaque sorting이나 texture batching을 위해 draw
order를 바꾸지 않는다. 연속 draw의 state reuse는 순서를 보존하는 범위에서만 한다.

## 18. Limits와 Budget

S4 기본 limit:

| 항목 | 기본값 | 정책 |
| --- | ---: | --- |
| 최대 output dimension | 16,384 | Metal/device limit 중 작은 값 사용 |
| 최대 output pixels | 33,177,600 | 8K UHD 상한 |
| 최대 draw items | 100,000 | S2 node limit과 동일 |
| configured max in-flight | 3 | budget에 따라 effective count 감소 가능 |
| aggregate render-target budget | 512 MiB | intermediate/final/in-flight 전체 preflight |
| snapshot readback budget | 256 MiB | 요청별 bounded staging |

render-target byte 계산은 checked arithmetic을 사용한다. 4K는 일반적으로 3개
in-flight slot을 유지할 수 있지만 8K에서는 aggregate budget에 맞춰 effective
in-flight count를 1까지 낮출 수 있다. 한 frame의 mandatory target조차 budget에
맞지 않으면 allocation을 시도하지 않고 resource-limit error를 반환한다.

S2 graph limit과 S3 resident/staging/decoded budget은 그대로 적용한다. S4가 이를
우회하거나 별도 unbounded cache를 만들지 않는다.

## 19. Status, Diagnostics, Error Handling

renderer status:

- `exact`: 모든 S4 지원 의미를 정확히 compile/evaluate/render
- `degraded`: 지원되지 않는 부분을 명시적으로 제외하고 exact base image를 render
- `unsupported`: renderable image가 없거나 essential supported chain이 unresolved
- `invalid`: graph cycle, invalid canvas/limit, device/pipeline/target invariant 실패

원칙:

- effect/shader 미지원은 base image를 정확히 그릴 수 있을 때만 degraded다.
- missing texture layer 하나는 skip하고 diagnostic을 남긴다.
- 모든 layer가 skip되면 unsupported이며 투명/검정 화면을 성공으로 반환하지 않는다.
- unknown interpolation을 linear로, unknown effect를 no-op effect로 위장하지 않는다.
- thumbnail/preview는 어떤 오류 경로에서도 render source가 아니다.
- diagnostic은 stable code, node/resource identity, severity, deterministic arguments를
  가지며 absolute local path와 private payload를 포함하지 않는다.
- GPU command failure는 frame failure이며 마지막 successful frame을 유지한다.

## 20. Snapshot

`SceneSnapshotReader`는 동일 frame의 실제 final Metal output을 읽는다.

```text
completed final target
-> bounded GPU blit/readback staging
-> command completion
-> CGImage/PNG encode
```

- snapshot은 frame rendering과 별도 opt-in 작업이다.
- render command path에서 동기 `waitUntilCompleted`를 호출하지 않는다.
- row-byte alignment와 BGRA/RGBA conversion을 명시적으로 처리한다.
- color profile은 standard sRGB로 기록한다.
- PNG encode는 GPU completion 뒤 background executor에서 수행한다.
- snapshot 실패는 completed render frame을 무효화하지 않는다.
- S4 test/QA output은 `/tmp` 또는 untracked local directory에만 쓴다.

## 21. Implementation Gate 0: 가정 검증

코드 구현 전에 다음 증거 표를 작성하고 test expectation을 확정한다.

| 질문 | 확인 방법 | gate 결과 |
| --- | --- | --- |
| pivot의 단위와 기준 | local fixture raw graph + 공식 동작 + prototype 비교 | 식과 fixture expectation 고정 |
| Z 앞/뒤 방향 및 tie-break | 서로 겹치는 fixture node/order 분석 | stable order test 고정 |
| origin/position 결합 | graph raw value와 실제 composition 비교 | local matrix 순서 고정 |
| instance override 우선순위 | source/instance/animation 조합 fixture 분석 | typed override contract 고정 |
| texture orientation | S3 top-left/contentRect synthetic texture | shader flip 위치 고정 |
| padded mip sampling | mip별 logical/storage extent와 edge pixel probe | per-mip rect 필요 여부 고정 |
| alpha convention | S3 decoder/fixture edge pixel 확인 | premultiplication test 고정 |
| node tint color space | raw color와 controlled fixture pixel 비교 | sRGB-to-linear 규칙 고정 |
| timeline mode/interpolation | Wallpaper Engine 공식 문서 + raw keyframe evidence | typed parser/evaluator test 고정 |

기존 CALayer prototype은 참고 출력일 뿐 정답 source가 아니다. 공식 문서에 없는
세부 동작은 fixture evidence와 controlled synthetic probe가 일치할 때만 exact로
채택한다. 불명확하면 기능을 degraded로 남기고 추측 구현하지 않는다.

## 22. 테스트 전략

### 22.1 CPU-only unit test

- compile status와 stable diagnostics
- resource mapping과 layer skip
- hierarchy topological order와 cycle rejection
- instance expansion/override precedence
- stable Z/source/identity order
- Loop/Mirror/Single time mapping
- absolute/relative and Bezier/linear/step interpolation
- parent/local/world/canvas matrix
- Fit/Fill/Stretch matrix
- checked limit and byte-budget calculation
- deterministic program fingerprint

CPU test는 fake/fixed time을 사용하고 real sleep에 의존하지 않는다.

### 22.2 Headless Metal test

실제 `MTLDevice`가 있는 환경에서 작은 synthetic texture와 output을 pixel readback해
검증한다.

- orientation과 `contentRect` padding exclusion
- sRGB decode/linear tint/final encode
- straight source to premultiplied output
- alpha blend order
- nearest-edge/clamp behavior와 mip selection sanity
- parent transform and Z overlap
- Fit/Fill/Stretch crop/letterbox
- snapshot row layout와 PNG decode round trip
- command failure/cancellation/target reuse lifetime

동일 device/OS/configuration에서는 exact expected pixel을 사용한다. GPU/OS가 다른
환경은 명시적 channel tolerance와 structural invariant를 사용하며 exact file hash를
요구하지 않는다.

### 22.3 Synthetic golden

작고 license-safe한 synthetic Scene과 expected PNG만 Git에 추적한다. golden은
지원 기능별 최소 사례이며 대형 통합 screenshot을 정답으로 쓰지 않는다.

### 22.4 Local fixture gate

사용자가 보유한 세 local fixture를 fixed time과 output size로 검증한다.

- `2174863503`: static image composition baseline
- `2834933421`: fixed layer cap 없이 전체 graph compile/render
- `3516106265`: BC3/RG/R8 resource와 newer package graph 경로

추적 가능한 결과는 path-redacted aggregate뿐이다. fixture asset이나 copyrighted
output screenshot은 Git에 추가하지 않는다. QA PNG는 `/tmp` 또는 ignored local
directory에만 둔다.

### 22.5 Review loop

- design 작성 후 self-review와 독립 review
- executable plan 작성 후 다시 contract/official-doc review
- 각 implementation task는 RED -> GREEN -> focused test -> commit
- graph/texture/renderer 경계 변경 시 upstream focused test 포함
- branch 완료 전 전체 `swift test`, static privacy/path scan, independent final review

GUI, 앱 실행, System Settings, package/DMG/notarization/dist 작업은 S4 검증에
포함하지 않는다.

## 23. Acceptance Criteria

S4 완료 조건:

1. `MacWallSceneRenderer`가 Core/App/WallpaperAgent 없이 build/test된다.
2. renderer가 raw JSON을 해석하지 않는다.
3. supported image node, hierarchy, instance, transform, opacity, visibility, Z,
   fixed-time timeline을 offscreen Metal frame으로 만든다.
4. Fit/Fill/Stretch가 pixel test로 검증된다.
5. orientation, content rect, sRGB/linear conversion, premultiplied alpha가 actual
   Metal readback test로 검증된다.
6. same device/configuration/time/input에서 deterministic frame plan과 output을
   생성한다.
7. 세 local fixture가 fixed layer cap 없이 compile되고 renderable image set을
   실제 Metal output으로 만든다.
8. unsupported effect/shader/text/particle/media는 fake output 없이 stable degraded
   diagnostics를 만든다.
9. no-renderable-layer, invalid canvas, limits, GPU failure가 black frame success로
   발표되지 않는다.
10. snapshot이 actual final Metal output에서 생성되고 thumbnail을 사용하지 않는다.
11. in-flight resource가 completion까지 유지되고 cancellation/error에서 정확히 한
    번 정리된다.
12. Desktop Scene, Scene fallback, Native adapter, GUI를 시작하지 않는다.

`2174863503`은 합리적인 static composition baseline이어야 한다.
`2834933421`과 `3516106265`는 기존 prototype layer cap 없이 graph 전체를
compile해야 한다. Effect/Text/Particle 미지원으로 전체 visual parity를 S4 완료
조건으로 오해하지 않는다.

## 24. 구현 순서 방향

상세 task는 별도 executable implementation plan에서 작성한다. 순서만 고정한다.

1. gate 0 evidence와 typed graph animation/override contract
2. pure render models, limits, compiler, ordering
3. timeline/transform/scaling evaluator
4. Metal pipeline, sampler, target pool
5. texture acquisition과 immutable session staging
6. image composition/final conversion
7. snapshot readback
8. synthetic Metal integration/golden
9. 세 local fixture gate와 full regression
10. documentation, independent review, completion record

S4를 완료하고 별도 승인된 뒤에만 S5 Native Scene Frame Adapter 계획으로 넘어간다.

## 25. 위험과 완화

### Format 의미를 잘못 추정할 위험

가장 큰 위험이다. gate 0에서 pivot, Z, instance, timeline 의미를 먼저 증명하고
불명확한 의미는 degraded로 남긴다.

### 색/alpha가 대체로 맞지만 edge에서 틀릴 위험

sRGB source view, linear float composition, explicit premultiplication, final sRGB
conversion을 pixel test로 분리한다. 육안 fixture 비교만으로 통과시키지 않는다.

### GPU lifetime race

actor session, fixed in-flight ring, completion-owned resource set, exactly-once cleanup
test로 제한한다.

### 대형 Scene의 CPU/GPU memory 폭증

compile/draw/output/in-flight/readback limit을 submission 전에 계산하고 S2/S3 budget을
우회하지 않는다.

### S4가 범용 engine으로 비대해질 위험

image 2D composition과 fixed-time timeline만 구현한다. effect render graph, text,
particle, media, SceneScript, 3D는 각각 후속 phase로 남긴다.

## 26. 근거 문서

### Apple 공식 문서

- [MTLPixelFormat](https://developer.apple.com/documentation/metal/mtlpixelformat)
- [MTLTextureUsage](https://developer.apple.com/documentation/metal/mtltextureusage)
- [Render target texture usage](https://developer.apple.com/documentation/metal/mtltextureusage/rendertarget)
- [Adding mipmap filtering to samplers](https://developer.apple.com/documentation/metal/adding-mipmap-filtering-to-samplers)
- [MTLSamplerState](https://developer.apple.com/documentation/metal/mtlsamplerstate)
- [Customizing render pass setup](https://developer.apple.com/documentation/metal/customizing-render-pass-setup)
- [Choosing a resource storage mode for Apple GPUs](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus)
- [Setting resource storage modes](https://developer.apple.com/documentation/metal/setting-resource-storage-modes)
- [Synchronizing CPU and GPU work](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work)
- [Resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization)
- [Reading pixel data from a drawable texture](https://developer.apple.com/documentation/metal/reading-pixel-data-from-a-drawable-texture)
- [Metal Best Practices: Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)
- [Metal feature set tables](https://developer.apple.com/metal/capabilities/)

Apple 문서는 pixel format, sampler, render-target usage, private/shared storage,
in-flight resource synchronization 설계의 근거다. 구체적인 budget과 module 경계는
이 문서들을 바탕으로 한 MacWall 설계 판단이다.

### Wallpaper Engine 공식 문서

- [Timeline Animation Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)
- [Single & Mirrored Timeline Animations](https://docs.wallpaperengine.io/en/scene/timeline/modes.html)
- [Combined Timeline Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)
- [SceneScript ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html)
- [Resize Screen Event](https://docs.wallpaperengine.io/en/scene/scenescript/reference/event/resizeScreen.html)

이 문서는 origin이 layer position이라는 점, Loop/Mirror/Single 동작, 기본 Bezier와
linear 전환 개념을 확인하는 근거다. package 내부 field mapping과 세부 transform
순서는 공개 문서만으로 확정할 수 없으므로 gate 0 evidence가 추가로 필요하다.

### 내부 기준

- [Scene Engine Design](2026-07-29-scene-engine-design.md)
- [S2 implementation record](../../implemented/2026-08-04-scene-asset-resolver-typed-graph.md)
- [S3 implementation record](../../implemented/2026-08-06-scene-gpu-texture-pipeline.md)
- [S3 archived design](../../archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md)
