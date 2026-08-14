# Scene S4 Headless 2D Metal Renderer

작성일: 2026-08-14

상태: implemented / completed

## 완료 범위

S4는 S2 typed graph와 S3 GPU texture를 실제 offscreen 2D Metal frame으로
합성하는 독립 `MacWallSceneRenderer` target을 구현했다. AppKit, `MTKView`,
WallpaperAgent 또는 Main App 없이 fixed media time을 평가하고, renderer-owned
texture 또는 caller-provided texture에 결과를 출력한다.

```text
SceneGraphBuildResult
        |
SceneRenderCompiler
        |
immutable SceneRenderProgram
        |
SceneTextureStore + SceneRenderSession
        |
typed timeline + transform evaluation
        |
linear Metal composition
        |
BGRA8 sRGB frame / PNG snapshot
```

`MacWallSceneRenderer`는 `MacWallSceneGraph`와 `MacWallSceneTextures`만 Scene
module dependency로 사용한다. `MacWallCore`, `MacWallApp`, AppKit,
`MacWallNativeRuntimeSupport`, WallpaperExtensionKit, Desktop fallback과는
연결하지 않았다.

## Compile 및 frame 평가

- graph를 stable draw template와 texture manifest를 가진 immutable
  `SceneRenderProgram`으로 한 번 compile한다.
- source Z 방향, `sourceOrder`, stable node/instance identity 순서로 draw order를
  고정하고 texture 종류별 재정렬을 하지 않는다.
- typed origin, scale, Z rotation, opacity, visibility 및
  Loop/Mirror/Single timeline을 fixed media time에 평가한다.
- parent world transform과 child local transform을 합성하고, supported instance
  override만 typed contract로 반영한다.
- `Fit`, `Fill`, `Stretch` canvas scaling을 하나의 centered transform으로
  계산한다.
- image geometry는 node의 명시적 `size` 또는 S3 texture의 logical content
  extent에서 얻고 node origin을 중심으로 배치한다. Wallpaper Engine의 image
  `scale`은 pixel size가 아닌 상대 배율로 처리하며 2D output에서 Z scale은
  적용하지 않는다.
- 프로그램 fingerprint는 runtime identity와 JSON dictionary order에 의존하지
  않는다.

## Metal output

- source sRGB texture를 linear `RGBA16Float` target에서 premultiplied-alpha
  source-over로 합성한다.
- final pass는 `BGRA8Unorm_sRGB` output을 만들며 별도 alpha blending을 하지
  않는다.
- S3의 logical content rect, physical padding, top-left origin, mip chain을
  shader sampling 계약에 반영한다.
- renderer-owned target은 explicit completed-frame lease가 수명을 소유한다.
  caller-provided target은 same-device, pixel format, size, usage를 검증하고
  in-flight 동안 중복 제출을 거부한다.
- 최대 3 in-flight frame, target pool budget, snapshot readback budget을
  적용한다. invalidation 뒤 stale completion은 publish하지 않는다.
- command completion 뒤에만 frame을 완료하고 blocking
  `waitUntilCompleted()`를 사용하지 않는다.

기본 renderer limit:

| Limit | 기본값 |
| --- | ---: |
| Maximum output dimension | 16,384 |
| Maximum output pixels | 33,177,600 |
| Maximum draw items | 100,000 |
| Maximum in-flight frames | 3 |
| Render target budget | 512 MiB |
| Snapshot readback budget | 256 MiB |

## Snapshot

snapshot은 preview나 Workshop thumbnail이 아니라 같은 actual Metal output을
GPU completion 이후 readback해 ImageIO/CoreGraphics PNG로 encode한다. snapshot
encode가 실패해도 성공한 completed frame은 유지하고 typed diagnostic만
추가한다.

`preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`는 renderer 또는
snapshot source로 사용하지 않는다. S4 snapshot은 아직 P1/P2
`desktop-fallback.png` 정책에 연결하지 않았다.

## Degraded 및 unsupported 정책

지원되는 base image draw가 남아 있으면 알려진 범위만 실제로 그린 뒤
`degraded`와 deterministic diagnostic을 반환한다. 다음 기능을 흉내 내거나
조용히 성공 처리하지 않는다.

- custom effect와 shader semantics
- text, particle, sound
- animated texture와 video texture
- SceneScript와 user property
- puppet warp, 3D model, light, camera
- 증명되지 않은 material/pass state와 animation semantics

핵심 draw를 신뢰할 수 없으면 `unsupported`, 입력이나 graph가 유효하지 않으면
`invalid`로 분류한다. 일부 texture 준비 실패는 해당 draw만 제외하고 surviving
draw set과 diagnostic을 고정한다.

## Local Fixture Gate

tracked catalog
`Tests/Fixtures/SceneRenderer/local-scene-renderer-catalog.json`은 세 fixed local
fixture를 Graph builder, compiler, texture session, renderer 전체 경로로
`320x180`, media time `0.5s`, `fit`에서 두 번 렌더링한 aggregate다.

| Workshop ID | Compiled draws | Rendered | Skipped | Status |
| --- | ---: | ---: | ---: | --- |
| `2174863503` | 7 | 7 | 0 | degraded |
| `2834933421` | 7 | 6 | 1 | degraded |
| `3516106265` | 11 | 1 | 10 | degraded |

세 결과 모두 actual Metal output의 17x9 semantic pixel sample이 비어 있지 않고,
두 번의 render에서 status, draw count, diagnostic count와 sample hash가
일치한다. fixed layer cap은 사용하지 않는다.

catalog에는 ID, configuration, status, draw/skipped/diagnostic count와 semantic
sample hash만 기록한다. host path, package path, JSON/texture payload와 screenshot은
포함하지 않는다. PNG 증거는 test writer가 명시적으로 실행될 때
`/tmp/macwall-scene-renderer-local-fixtures/`에만 생성한다. 루트 `test/` fixture는
읽기 전용이며 package hash가 실행 전후 같은지 검증한다.

## 검증

2026-08-14 Asia/Seoul 기준:

- focused Graph/compiler/evaluator/Metal/snapshot/local fixture:
  `67 tests, 0 failures, 1 skip`
- `MacWallSceneRendererTests`: `77 tests, 0 failures, 1 skip`
- 전체 `swift test`: `668 tests, 0 failures, 1 skip`
- skip 1건은 single-GPU 머신에서 실행할 수 없는 cross-device target validation이다.
- local fixture catalog writer와 일반 comparison gate 모두 통과했다.
- renderer source의 AppKit/Core/App/Native Runtime/WallpaperExtensionKit/fallback
  참조와 raw JSON/preview/blocking completion 참조가 없음을 정적 검사했다.
- `git diff --check`와 local `test/` 무변경 검사를 통과했다.

앱 또는 GUI, System Settings, package/DMG/notarization/dist 작업은 실행하지 않았다.
사용자에게 보이는 동작은 변경하지 않아 root `README.ko.md`와 `README.md`는
수정하지 않았다.

## 설계 근거와 보관 문서

- [S4 설계](../archive/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-design.md)
- [S4 Gate 0 evidence](../archive/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md)
- [S4 실행 계획](../archive/superpowers/plans/2026-08-14-scene-headless-2d-metal-renderer.md)

Gate 0은 Wallpaper Engine 공식 SceneScript/timeline 문서와 Apple Metal 문서,
read-only local aggregate를 대조해 S4가 구현할 의미를 제한했다. 증명되지 않은
동작은 구현 편의를 위해 추정하지 않았다.

## 다음 단계

다음 Scene phase는 **S5 Native Scene Frame Adapter**다. S5는 extension process
안에서 renderer session을 만들고 IOSurface-backed target에 frame을 출력해 native
wallpaper pipeline으로 전달한다.

S5 전에는 S4 output을 Desktop surface, `desktop-fallback.png`, 기존 CALayer
prototype 또는 Main App playback에 연결하지 않는다. Effect render graph, text,
particle, animated/video texture와 SceneScript도 각각 후속 phase로 유지한다.
