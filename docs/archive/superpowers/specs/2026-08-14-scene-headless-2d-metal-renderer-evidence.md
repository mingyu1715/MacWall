# Scene S4 Headless 2D Metal Renderer Evidence

작성일: 2026-08-14

상태: implemented evidence gate / Gate 0 passed with restricted S4 semantics

## 1. 목적과 판정 기준

이 문서는 S4 renderer가 Wallpaper Engine Scene 의미를 추측 구현하지 않도록
좌표계, timeline, texture 계약을 구현 전에 고정한다. 판정은 다음 세 값만 사용한다.

- `confirmed`: 공식 문서, 현재 typed contract, local aggregate가 같은 의미를
  지지한다.
- `unsupported-for-S4`: 정확한 의미를 증명하지 못했으므로 S4가 적용하지 않는다.
- `requires-contract-change`: 의미는 확인했지만 현재 public contract만으로 정확히
  전달할 수 없어 선행 API 변경이 필요하다.

기존 `CALayer` prototype은 비교 자료일 뿐 정답으로 사용하지 않았다. local
Workshop package는 read-only로 열었고 이 문서에는 Workshop ID와 aggregate만
기록한다. host path, title, entry path, JSON payload, texture payload는 기록하지
않는다.

## 2. 확인한 공식 문서

확인일: 2026-08-14

- [ILayer](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/ILayer.html):
  `origin`은 layer position이고 `angles`는 degree, `scale`은 relative size다.
- [Adding your first assets](https://docs.wallpaperengine.io/en/scene/first/assets.html):
  parent가 이동, 회전, scale되면 child도 함께 변환된다.
- [Assets overview](https://docs.wallpaperengine.io/en/scene/assets/overview.html):
  2D asset의 앞뒤는 layer list 순서로 정의한다.
- [CursorEvent](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/CursorEvent.html):
  2D wallpaper에서 Z position은 사용되지 않으며 image local coordinate는 image
  size 범위다.
- [Timeline introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html):
  timeline은 정해진 duration을 가지며 기본 easing은 Bezier이고 handle을 끄면
  linear가 된다.
- [Single and mirrored timeline animations](https://docs.wallpaperengine.io/en/scene/timeline/modes.html):
  Single은 끝값에서 정지하고 Mirror는 forward 뒤 같은 속도로 reverse한다.
- [Modifying colors with SceneScript](https://docs.wallpaperengine.io/en/scene/scenescript/tutorial/colors.html):
  color 값은 RGB `0...255`임을 설명하지만 transfer function은 명시하지 않는다.

공식 editor 문서의 duration 단위는 seconds다. 그러나 package의 serialized
`options.length` 자체가 seconds라는 뜻은 아니며, 아래 local evidence는 이 필드가
frame 길이임을 보여 준다.

## 3. Local Aggregate

### 3.1 Graph

| Workshop ID | Nodes | Image nodes | Parent edges | Instance edges | Animation tracks/keyframes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `2174863503` | 28 | 23 | 0 | 0 | 0 / 0 |
| `2834933421` | 98 | 88 | 0 | 0 | 0 / 0 |
| `3516106265` | 69 | 49 | 53 | 0 | 2 / 8 |

- 195개 node 중 `origin`은 186개에서 typed parse되었다.
- `pivot`, node-level `position`, `zorder`/`zindex`, node tint `color`는 세 fixture
  모두 0건이었다.
- instance edge와 instance override도 모두 0건이었다.
- 53개 parent edge의 child origin은 nonzero parent 아래 local offset 형태였고,
  공식 hierarchy 동작과 `parentWorld * local` 순서가 일치한다.
- 두 animation은 모두 `fps = 30`, `length = 18`, `mode = single`이고 마지막
  keyframe `frame = 18`은 `0.6s`다. 따라서 serialized duration은
  `length / fps = 0.6s`다. 한 track은 `startpaused = true`다.
- 두 animation의 interpolation은 별도 문자열이 아니라 keyframe의 `front`/`back`
  handle metadata로 저장되어 있었다. 이 handle의 정확한 normalized basis는 공식
  문서에서 확인되지 않았다.

### 3.2 Texture

| Workshop ID | Planned static textures | Multi-mip | Padded | Padded multi-mip | Per-mip rect 필요 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `2174863503` | 33 | 14 | 32 | 14 | 14 |
| `2834933421` | 134 | 73 | 73 | 72 | 70 |
| `3516106265` | 21 | 5 | 4 | 2 | 1 |
| **Total** | **188** | **92** | **109** | **88** | **85** |

85개 texture는 mip level이 내려갈 때 정수 반올림 때문에
`logicalExtent / storageExtent`가 mip 0과 달라졌다. mip-0의 단일
`SceneTextureLease.contentRect`를 모든 level에 적용하면 linear/trilinear sample이
padding을 읽을 수 있다.

## 4. Gate Decision

| 질문 | 판정 | S4 고정 정책 |
| --- | --- | --- |
| pivot anchor | `unsupported-for-S4` | explicit `pivot` node는 `render.unsupported-explicit-pivot`로 skip한다. pivot이 없으면 image local quad의 중심을 origin에 둔다. |
| Z direction | `unsupported-for-S4` | 2D explicit Z/`zorder`/`zindex`는 `render.unsupported-explicit-z`로 skip한다. 기본 합성은 ascending `sourceOrder`이며 뒤에 encode된 layer가 앞에 합성된다. |
| origin/position | `confirmed` for origin, `unsupported-for-S4` for position | `origin`은 2D pixel position이다. 별도 `position` 또는 둘의 결합은 `render.unsupported-position`으로 skip한다. |
| parent matrix order | `confirmed` | column-vector 기준 `world = parentWorld * local`, local은 `T(origin) * Rz * S`다. parent opacity/visibility/enabled도 descendant에 전파한다. |
| instance override priority | `unsupported-for-S4` | fixture와 공식 precedence 근거가 없으므로 override가 있는 instance는 `render.unsupported-instance-override`로 skip한다. raw override는 보존한다. |
| texture orientation | `confirmed` | S3 `topLeft` row와 Scene top-left UV를 유지한다. Y 반전은 canvas-to-Metal clip 변환에서 한 번만 수행한다. |
| padded mip sampling | `requires-contract-change` | lease에 level별 logical extent/content rect를 추가한다. 이 계약 전에는 padded multi-mip trilinear rendering을 exact로 publish하지 않는다. |
| straight alpha | `confirmed` | S3 lease는 straight alpha다. fragment에서 linear tint/opacity 뒤 explicit premultiply하고 `one / oneMinusSourceAlpha` blend를 사용한다. |
| tint color space | `unsupported-for-S4` | transfer function 근거가 없다. absent/identity white만 exact이며 non-white tint는 `render.unsupported-tint-color-space`로 skip한다. |
| `length/fps/time/frame` | `requires-contract-change` | serialized `length`와 `frame`은 frame 단위다. exact duration/keyframe time은 `length / fps`, `frame / fps`다. explicit `time` only 또는 fps 없는 length는 `render.invalid-timeline-timebase`다. |
| Loop/Mirror/Single endpoint | `confirmed` | Loop은 `[0,duration)`, Mirror는 period `2 * duration`, Single은 duration 이후 마지막 keyframe을 유지한다. |
| start-paused | `unsupported-for-S4` | flag는 typed/raw evidence로 보존한다. SceneScript가 없는 S4는 해당 track을 자동 시작하지 않고 base value를 유지하며 `render.unsupported-start-paused`를 낸다. |

## 5. Timeline 세부 제한

- explicit `loop`, `mirror`, `single`만 typed mode로 인정한다. mode가 없는 editor
  기본 track은 Loop로 정규화할 수 있다.
- `relative = true`는 fixture precedence 근거가 없어
  `render.unsupported-relative-track`으로 base value를 유지한다.
- handle이 비활성화되어 linear임을 증명할 수 있는 segment만 S4 exact 대상이다.
  `front`/`back` enabled handle의 cubic mapping과 step serialization은
  `render.unsupported-timeline-interpolation`으로 남긴다.
- duplicate keyframe time은 source order의 마지막 값을 택하지 않는다. typed track을
  만들지 않고 invalid/degraded diagnostic으로 남긴다.
- 부분 vector channel 실패는 유효 channel만 적용하지 않는다. property 전체의 base
  value를 유지한다.

## 6. 선행 Contract 변경

Task 1은 Graph의 `duration` 명칭을 serialized frame length와 분리한다.
renderer에 전달하는 `SceneTypedAnimationTrack.durationSeconds`는 유효한
`length / fps`로만 생성한다. raw `length`, `fps`, keyframe `frame`, `time`은 기존
audit contract에 계속 보존한다.

Texture target은 각 mip의 logical sampling 영역을 public lease metadata로 전달한다.
최소 계약은 다음 의미를 제공해야 한다.

```text
mipContentExtents[level]
mipContentRects[level] = logical extent / storage extent at that level
```

배열 count는 `mipmapLevelCount`와 같아야 하며 level 0은 기존 `contentExtent`와
`contentRect`와 동일해야 한다. S4 sampler/shader는 이 metadata를 실제 LOD와 함께
사용할 수 있어야 한다. exact lod-aware clamp가 불가능하면 mipmapped padded
texture는 mip 0 고정 또는 layer skip으로 명시적으로 degrade한다.

## 7. Gate 결론

Gate 0은 **통과**다. Task 1 이후 구현을 진행할 수 있다. 단, 다음 조건은 S4 exact
범위 밖이다.

- explicit pivot, explicit 2D Z, node `position`
- instance override precedence
- non-white tint transfer
- relative/start-paused track
- 증명되지 않은 cubic/step serialization

per-mip content region과 frame-based timeline duration은 구현 전에 계약을 변경한다.
지원되지 않는 의미는 base image로 조용히 대체하지 않고 위 diagnostic code로
결정론적으로 기록한다.
