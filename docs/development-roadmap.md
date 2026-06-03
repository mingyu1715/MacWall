# MacWall 개발 로드맵

수정일: 2026-06-04

이 문서는 현재 활성 제품 개발 방향과 Scene 개발 방향을 정리합니다. 완료된 세부 구현 계획은 `docs/implemented/`에 기록하고, 과거 계획은 `docs/archive/`에 보관합니다.

## 1. 제품 정체성

MacWall은 사용자가 Windows에서 직접 복사해 온 Wallpaper Engine project를 macOS에서 로컬로 실행하는 runtime입니다.

```text
사용자가 복사한 Workshop folder
-> local scan
-> import할 project 선택
-> app-managed Mac library로 복사
-> macOS desktop layer에서 Video, Web, Scene content 실행
```

대상 format:

| Format | 목표 동작 |
| --- | --- |
| Video | `AVPlayer` 기반 native playback |
| Web | restricted `WKWebView` 기반 local playback |
| Scene | `scene.pkg`를 위한 별도 Metal compatibility runtime |

## 2. 현재 상태

### 구현 완료

- 복사된 Workshop folder를 scan해서 Video, Web, Image, Scene project를 분류합니다.
- 선택한 project를 app-managed Mac library로 import합니다.
- local video file을 별도 import할 수 있습니다.
- MP4, MOV, M4V를 `AVPlayer`로 재생합니다.
- WebM, MKV, AVI를 local `ffmpeg`로 H.264 MP4로 변환합니다.
- local Web wallpaper를 restricted `WKWebView` 안에서 재생합니다.
- Web wallpaper mouse interaction을 선택적으로 켤 수 있습니다.
- 다른 app이 desktop을 덮어도 wallpaper window를 유지합니다.
- desktop이 가려졌을 때 standalone Video는 현재 frame에서 pause합니다.
- desktop이 가려졌을 때 Web은 CSS animation을 pause하되 embedded Web video는 계속 보이게 유지합니다.
- Scene은 Metal runtime 전까지 Workshop thumbnail을 임시 desktop layer fallback으로 보여줄 수 있습니다.
- `scene.pkg` parsing, 일부 `.tex` decode, 일부 2D layer `CALayer` prototype rendering이 experimental toggle 뒤에 있습니다.
- bundled macOS screen saver path로 animated Lock Screen playback을 실행합니다.
- Video, Image, Web wallpaper에 대해 asset별 `Derived/desktop-fallback.png` cache를 유지합니다.
- Space 변경 후 active Video/Web fallback cache를 live output에서 refresh합니다.
- live playback 전환은 hidden/staged replacement window set을 먼저 만든 뒤 성공 시에만 old windows를 닫습니다.
- screen-change, wake, visibility update는 deterministic scheduler boundary를 통해 debounce합니다.
- item 전환 실패 시 이전 live playback, fallback active asset, space-refresh active asset, `lastPlayedAssetId`를 유지합니다.

### 임시 동작

- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png` 같은 Workshop preview file은 UI thumbnail입니다.
- Metal Scene runtime이 완성되기 전까지 Scene thumbnail은 desktop layer의 임시 placeholder로만 사용할 수 있습니다.
- Workshop preview는 Spaces 전환용 macOS system-wallpaper fallback이 되면 안 됩니다.
- 현재 `CALayer` Scene renderer는 prototype입니다. 최종 Scene engine으로 확장하지 않습니다.

### 성능 정책

- 일반 Web wallpaper에 대해 조기 최적화를 하지 않습니다.
- 평상시 active playback에서 CPU 사용량이 대략 `10%` 이상으로 유지될 때 조사합니다.
- desktop이 가려졌을 때 runtime을 tear down / rebuild하기보다 reduced activity를 우선합니다.
- Scene texture memory는 process RSS와 별도로 추적합니다.
- Scene texture는 Wallpaper Engine documentation의 권장 기준인 약 `300 MB` VRAM 이하를 우선 목표로 합니다. `500 MB` 미만은 허용 가능할 수 있지만 기본 목표가 되어서는 안 됩니다.

## 3. 근시일 Product Phase

### Phase P1: Desktop Fallback Cache

목표: Spaces 전환과 full-screen 전환 중 기존 macOS system wallpaper가 잠깐 보이는 현상을 줄입니다.

상태: 구현 완료. Video, Image, Web wallpaper의 `desktop-fallback.png` cache가 구현되었습니다. active Video/Web wallpaper의 Space-change refresh도 구현되었습니다. Scene snapshot generation은 실제 Scene frame을 render할 수 있는 Metal Scene runtime 이후로 보류합니다.

```text
선택한 wallpaper Play
├─ live desktop runtime 시작
├─ fallback coordination용 active asset 표시
├─ Derived/desktop-fallback.png 있음
│  └─ generator 없이 macOS system wallpaper에 적용
└─ cache 없음
   └─ 비동기 fallback generation 예약
      ├─ 지원되는 경우 대표 frame 캡처
      ├─ Derived/desktop-fallback.png 저장
      └─ asset이 아직 active일 때만 macOS system wallpaper 적용
```

규칙:

- cached fallback이 있으면 즉시 사용합니다. 자동으로 regenerate하거나 비교하지 않습니다.
- fallback 작업은 Play/Apply의 side effect입니다. live playback을 block하면 안 됩니다.
- automatic generation은 cache가 없고 runtime이 대표 frame을 만들 수 있을 때만 실행합니다.
- manual generation/regeneration은 library item menu에서 제공합니다.
- Stop Playback은 `Derived/desktop-fallback.png`를 보존합니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`, Workshop thumbnail은 system-wallpaper fallback source가 아닙니다.
- 원래 macOS wallpaper로 돌아가고 싶으면 macOS System Settings에서 직접 변경합니다.

Space refresh:

- live playback이 active인 상태에서 `NSWorkspace.activeSpaceDidChangeNotification`을 감지합니다.
- 짧은 stabilization delay 후 refresh하고, throttle을 둡니다.
- active Video/Web wallpaper만 live output에서 refresh합니다.
- refresh path는 `Derived/desktop-fallback.png`를 atomic replace합니다.
- 같은 asset이 아직 active일 때만 macOS system wallpaper를 다시 적용합니다.
- Image와 Scene wallpaper는 반복 Space refresh 대상에서 제외합니다.

Format behavior:

| Format | Cache source |
| --- | --- |
| Video | 실제 source video의 `0.5s` 근처 frame, Space 변경 후 live current frame |
| Image | 실제 source image를 PNG로 normalize |
| Web | restricted `WKWebView` output, Space 변경 후 live WebView output |
| Scene | P1/P2에서 `desktop-fallback.png` 미지원 |
| Unsupported Scene | 기존 macOS system wallpaper 유지 |

Scene fallback 정책:

- Scene wallpaper는 P1/P2에서 `desktop-fallback.png`를 생성하지 않습니다.
- Scene fallback은 Metal Scene runtime이 실제 Scene frame을 render할 수 있을 때까지 보류합니다.
- 미래 Scene fallback은 Scene renderer output 또는 render target에서 나와야 합니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`는 UI thumbnail일 뿐 fallback source가 아닙니다.
- 현재 `CALayer` Scene renderer는 prototype이며 최종 engine으로 확장하지 않습니다.

Library item `...` menu:

```text
Show in Finder
Generate Desktop Fallback
Regenerate Desktop Fallback
Remove
```

Storage 예시:

```text
Assets/
└── <encoded-library-directory>/
    └── Derived/
        ├── playback.mp4
        └── desktop-fallback.png
```

### Phase P2: Playback Stability

상태: 구현 완료. 세부 기록은 `docs/implemented/2026-06-04-p2-playback-stability.md`에 있습니다.

- replacement windows는 hidden/staged 상태로 먼저 생성합니다.
- 모든 target screen에 대한 replacement 생성이 성공해야 replacement set을 show하고 old windows를 close합니다.
- replacement 생성 실패 또는 multi-monitor partial failure는 staged windows만 cleanup하고 기존 live playback을 유지합니다.
- screen-change restore는 300ms debounce 후 실행합니다.
- wake restore는 500ms debounce 후 실행합니다.
- visibility update는 200ms debounce 후 실행합니다.
- debounce 검증은 fake scheduler 기반 unit test로 처리하며 real sleep timing에 의존하지 않습니다.
- A -> failing B 전환은 B fallback을 적용하지 않고 A live playback/fallback/space-refresh/`lastPlayedAssetId`를 유지합니다.
- monitor attach/detach, resolution change, sleep/wake 검증은 GUI 실행 없는 simulated unit/integration test 범위로 처리했습니다.
- 실제 macOS GUI QA는 별도 승인 후 후속 검증으로 남겨둡니다.

### Phase P3: Web Runtime Completion

- `wallpaperPropertyListener`를 통한 Wallpaper Engine Web property default를 지원합니다.
- local-file access policy와 optional remote-network policy를 분리합니다.
- loading error와 JavaScript error reporting을 추가합니다.
- `Web Mouse Interaction`을 global development toggle에서 per-item option 방향으로 옮깁니다.
- 기본값은 secure local-only입니다. remote network는 사용자가 명시적으로 허용할 때만 다룹니다.

### Phase P4: Per-item Options

초기 구현은 P1의 item menu까지만 제공합니다. 더 큰 options window는 나중에 추가합니다.

후보 option:

```text
Wallpaper Options
├─ Display: Fit / Fill / Stretch
├─ Color: brightness / contrast / saturation / temperature
├─ Playback: speed / volume / covered-screen behavior
└─ Desktop Fallback: generate / regenerate / show in Finder
```

설정은 Mac library manifest에 저장합니다. 원본 Workshop file은 수정하지 않습니다.

### Phase P5: Release Hardening

- development-only toggle을 숨기거나 명확히 표시합니다.
- library migration과 deletion behavior를 검증합니다.
- first-run guidance를 추가합니다.
- CPU, RSS, texture memory, loading time을 측정합니다.
- Video, Web, Scene regression suite를 확장합니다.
- 공개 macOS build의 signing / notarization 흐름은 release 단계에서 별도 계획으로 다룹니다.

## 4. Scene Runtime 전략

Scene support는 Video/Web playback의 작은 확장이 아니라 별도 engineering track입니다.

### 별도 runtime이 필요한 이유

Wallpaper Engine Scene은 단순 flat image layer보다 넓은 기능을 갖습니다.

- Effect는 image, text, fullscreen, composition layer에 적용될 수 있고 여러 effect가 chain될 수 있습니다.
- Particle system은 renderer, emitter, initializer, operator, child system, cursor control point를 포함합니다.
- Puppet Warp는 geometry, bone, weight, timeline animation을 포함합니다.
- SceneScript는 ECMAScript 2018을 따르며 매 frame `update` handler를 실행할 수 있습니다.
- Wallpaper Engine shader는 GLSL에 가까운 형태이며 target graphics API에 맞춘 translation 전략이 필요할 수 있습니다.

최종 Scene engine에는 typed scene graph, timeline runtime, asset resolver, render graph, Metal renderer가 필요합니다.

### 목표 architecture

```text
scene.pkg
   |
   v
PKG / TEX decoding layer
   |
   +------ optional user-copied Wallpaper Engine assets folder
   |
   v
Asset resolver
   |
   v
Typed scene graph
   |
   +------ timeline / properties / script runtime
   |
   v
Metal render graph
   |
   +------ MTKView desktop output
   |
   +------ desktop-fallback.png snapshot
```

### Module boundary

| Module | Responsibility |
| --- | --- |
| `SceneFormats` | PKG entry, TEX metadata, compressed payload, versioned format detail 읽기 |
| `SceneAudit` | sample과 unsupported feature에 대한 deterministic JSON report 생성 |
| `SceneAssets` | package-local asset과 optional user-copied shared asset resolve |
| `SceneGraph` | JSON을 typed layer, composition, material, effect, animation track으로 변환 |
| `SceneMetal` | GPU resource upload 및 Metal frame render |
| `SceneRuntime` | time, pause state, user property, input, 이후 SceneScript 구동 |
| `SceneSnapshot` | desktop fallback cache용 대표 Scene frame 캡처 |

최종 Metal runtime logic은 `MacWallCore`에 넣지 않습니다. core package는 desktop rendering 없이 CLI에서도 사용할 수 있어야 합니다.

## 5. Scene 개발 단계

### S0: Format Research and Fixture Catalog

목표: 최종 renderer를 만들기 전에 input surface를 이해합니다.

- `macwallctl scene-audit <scene.pkg>`의 stable JSON output을 설계합니다.
- PKG version, TEX container, TEX pixel format, flag, object type, material, effect, shader, font, audio, video texture, script, unresolved path를 기록합니다.
- Scene이 `scene.pkg` 외부 shared Wallpaper Engine asset에 의존하는지 기록합니다.
- local test fixture별 audit snapshot을 저장합니다.
- `supported`, `partially-supported`, `unsupported`, `unknown` 상태를 가진 support matrix를 만듭니다.

완료 기준:

- 기존 Scene fixture가 deterministic audit JSON을 생성합니다.
- unknown format을 crash 없이 report합니다.
- texture decoding 전에 audit report를 사용할 수 있습니다.

### S1: Format Layer Hardening

- package, texture, compression, pixel-format parsing을 focused file로 분리합니다.
- path traversal protection을 유지합니다.
- 필요하면 eager whole-package loading을 bounded random-access read로 바꿉니다.
- `PKGV0008`, `PKGV0018`, `PKGV0023` sample을 parse/report합니다.
- TEX container와 format metadata를 보존합니다.
- software decode는 test와 screenshot fallback으로 유지합니다.

### S2: Minimal Metal Renderer

- `MTKView` 기반 Scene view를 추가합니다.
- Metal device, command queue, render pipeline, quad geometry, orthographic camera, alpha blending을 추가합니다.
- image layer를 stable Z order로 render합니다.
- `Fit`, `Fill`, `Stretch`를 구현합니다.
- covered 상태에서는 draw loop를 pause하고 마지막 rendered frame을 유지합니다.
- 같은 rendered output에서 snapshot을 캡처합니다.

### S3: GPU Texture Pipeline

- mipmap과 texture padding metadata를 지원합니다.
- Metal pixel format이 허용하는 경우 compressed texture를 직접 upload합니다.
- software decompression은 fallback으로만 둡니다.
- repeated texture reference를 dedupe합니다.
- async loading과 bounded cache를 추가합니다.
- active texture memory를 diagnostics에 표시합니다.

### S4: 2D Scene Graph and Timeline

- layer transform, anchor, origin, size, scale, angle, alpha, visibility, Z ordering을 구현합니다.
- parent-child transform, composition layer, fullscreen layer, clipping mask를 추가합니다.
- loop, mirror, easing, start delay, relative timeline behavior를 구현합니다.
- static composition이 맞은 뒤 basic mouse parallax를 추가합니다.

완료 기준:

- `2174863503`이 합리적인 static composition으로 보입니다.
- `2834933421`이 prototype의 fixed 16-layer cap 때문에 대부분의 layer를 잃지 않습니다.
- Scene fallback snapshot은 실제 Metal output에서 생성할 수 있습니다.

### S5: Effects Render Graph

- offscreen render target과 chained render pass를 추가합니다.
- color adjustment, blur, bloom, blend, shake 계열 effect부터 시작합니다.
- unsupported effect를 layer별로 report합니다.
- effect 하나가 실패해도 전체 Scene을 깨지 않게 skip합니다.
- compatible custom shader에 대한 안전한 translation 전략을 조사합니다.

### S6: Text Layers

- packaged font를 안전하게 load합니다.
- alignment, color, alpha, scale, basic timeline을 가진 text layer를 render합니다.
- missing font fallback behavior를 추가합니다.

### S7: GPU Particle Systems

- GPU-instanced particle을 추가합니다.
- rain, snow, dust, leaf 계열 common system부터 시작합니다.
- renderer, emitter, initializer, operator subset을 점진적으로 구현합니다.
- child system과 cursor control point는 이후 추가합니다.

### S8: Animated Textures, Video, Audio

- GIF 또는 sprite-sheet texture animation을 추가합니다.
- compatible한 경우 AVFoundation 기반 video texture를 추가합니다.
- sound layer와 mute control을 추가합니다.
- audio spectrum input은 ordinary audio playback이 안정화된 뒤 추가합니다.

### S9: Puppet Warp

- mesh geometry, skeleton, weight, animation track을 parse합니다.
- Metal에서 vertex skinning을 구현합니다.
- advanced physics와 inverse kinematics는 basic weighted animation 이후에 다룹니다.

### S10: User Properties and Sandboxed SceneScript

- `project.json`의 item property를 parse합니다.
- 지원 가능한 property type으로 per-item control을 구성합니다.
- explicit API binding을 가진 sandboxed ECMAScript 2018 runtime을 설계합니다.
- `init`, `update`, `applyUserProperties`, resize event부터 시작합니다.
- cursor와 media integration event는 이후 추가합니다.

SceneScript는 execution boundary입니다. 임의 filesystem, process, network access를 얻으면 안 됩니다.

### S11: 3D Models, Lighting, Advanced Shaders

- 3D는 별도 renderer capability로 취급합니다.
- model, camera, light, reflection을 점진적으로 추가합니다.
- 흔치 않은 custom shader variant는 unsupported로 둘지 결정합니다.

### S12: Integration and Regression Hardening

- 실제 Scene output에서 desktop fallback cache를 생성합니다.
- Spaces swipe transition과 full-screen transition을 검증합니다.
- multi-monitor behavior를 검증합니다.
- sleep / wake를 검증합니다.
- CPU, RSS, active texture memory, frame time을 측정합니다.
- 대표 fixture용 golden screenshot을 추가합니다.

## 6. 현재 Scene Fixture Matrix

local fixture는 `test/` 아래에 있습니다. 사용자가 직접 복사한 local compatibility test용 sample입니다.

| Workshop ID | PKG version | Package entries | Objects | 주요 feature | 현재 결과 |
| --- | --- | ---: | ---: | --- | --- |
| `2174863503` | `PKGV0008` | 107 | 28 | 23 image layers, 3 particle systems, 7 effects, 14 shaders, 2 sound layers | prototype이 14 image texture decode, advanced feature 미지원 |
| `2834933421` | `PKGV0018` | 387 | 98 | 88 image layers, 3 particle systems, 16 effects, 44 shaders, 2 text layers, 5 sound layers | prototype fixed layer cap에 걸려 composition detail 손실 |
| `3516106265` | `PKGV0023` | 125 | 69 | 49 image layers, 7 particle systems, 12 effects, 24 shaders, 11 text layers, 1 sound layer | renderable image-layer path resolve 실패 |

추가 fixture:

| Workshop ID | Type | Purpose |
| --- | --- | --- |
| `3589742531` | Video | direct Video playback regression |
| `1828698678` | Web | interactive Web wallpaper 및 heavy DOM regression |

## 7. 기존 코드 지도

현재 prototype file:

| Path | 현재 책임 |
| --- | --- |
| `Sources/MacWallCore/Scene/ScenePackage.swift` | PKG reader와 lightweight analysis |
| `Sources/MacWallCore/Scene/SceneTexture.swift` | TEX reader와 software decode path |
| `Sources/MacWallCore/Scene/SceneLZ4BlockDecoder.swift` | LZ4 block decode |
| `Sources/MacWallCore/Scene/SceneDXTDecoder.swift` | DXT1, DXT3, DXT5 software decode |
| `Sources/MacWallCore/Scene/SceneRenderPlan.swift` | prototype image-layer extraction과 basic animation parsing |
| `Sources/MacWallApp/Playback/SceneWallpaperView.swift` | prototype `CALayer` rendering |

향후 규칙:

- module을 나누는 동안 기존 parser test를 보존합니다.
- audit output 없이 unknown feature를 조용히 skip하지 않습니다.
- `preview.gif`를 Scene rendering 성공 증거로 사용하지 않습니다.
- S4가 검증될 때까지 experimental Scene rendering은 development toggle 뒤에 둡니다.

## 8. 참고 자료

### Wallpaper Engine 공식 문서

| Topic | Reference | 이유 |
| --- | --- | --- |
| Effects | [Introduction to Effects](https://docs.wallpaperengine.io/en/scene/effects/introduction.html) | effect 적용 범위와 chain 구조 확인 |
| Particles | [Particle Systems Overview](https://docs.wallpaperengine.io/en/scene/particles/introduction.html) | renderer, emitter, initializer, operator, child-system, control-point 개념 확인 |
| Texture memory | [Texture Optimization](https://docs.wallpaperengine.io/en/scene/performance/texture.html) | VRAM guideline, DXT compression, padding 이해 |
| Puppet Warp | [Puppet Warp Introduction](https://docs.wallpaperengine.io/en/scene/puppet-warp/introduction.html) | geometry, bone, weight, timeline deformation 이해 |
| SceneScript | [SceneScript Reference](https://docs.wallpaperengine.io/en/scene/scenescript/reference.html) | ECMAScript 2018 behavior, per-frame update, user-property event 확인 |
| Shader programming | [Shader Programming Overview](https://docs.wallpaperengine.io/en/scene/shader/overview.html) | GLSL-like shader surface와 compatibility caveat 확인 |

### Apple 문서

| Topic | Reference | 이유 |
| --- | --- | --- |
| Metal-backed view | [MTKView](https://developer.apple.com/documentation/metalkit/mtkview) | desktop Scene output과 frame-loop control |
| Texture loading | [MTKTextureLoader](https://developer.apple.com/documentation/metalkit/mtktextureloader) | native Metal texture loading path |
| Metal textures | [MTLTexture](https://developer.apple.com/documentation/metal/mtltexture) | GPU texture representation |
| Command buffers | [MTLCommandBuffer](https://developer.apple.com/documentation/metal/mtlcommandbuffer) | frame submission과 synchronization |

### 외부 구현 참고

| Project | License | 이 project에서 허용되는 사용 |
| --- | --- | --- |
| [RePKG](https://github.com/notscuffed/repkg) | MIT | PKG/TEX format research reference |
| [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) | GPL-3.0 | behavior와 feature scope 비교 전용, MIT project에 code copy 금지 |
| [open-wallpaper-engine](https://github.com/waywallen/open-wallpaper-engine) | GPL-2.0 | architecture와 runtime scope 비교 전용, MIT project에 code copy 금지 |

## 9. License 및 Asset Guardrail

- project는 MIT-compatible하게 유지합니다.
- GPL implementation code를 project에 복사하지 않습니다.
- GPL project는 behavior reference와 comparison target으로만 사용합니다.
- MIT-licensed implementation detail을 참고해 적용한 경우 origin을 기록합니다.
- Wallpaper Engine shared asset을 bundle하지 않습니다.
- shared asset이 필요하면 사용자가 합법적으로 보유한 local `assets` folder를 직접 복사하고 명시적으로 선택하게 합니다.

## 10. 권장 실행 순서

Product work:

```text
P1 Desktop Fallback Cache (완료)
-> P2 Playback Stability (완료)
-> P3 Web Runtime Completion
```

Scene runtime work:

```text
S0 Format Research and Fixture Catalog
-> S1 Format Layer Hardening
-> S2 Minimal Metal Renderer
-> S3 GPU Texture Pipeline
-> S4 2D Scene Graph and Timeline
-> S5 Effects
-> S6 Text
-> S7 Particles
-> S8 Animated Textures, Video, Audio
-> S9 Puppet Warp
-> S10 Properties and SceneScript
-> S11 3D and Advanced Shaders
-> S12 Integration Hardening
```

첫 useful Scene milestone은 S4입니다. 그 시점에 common 2D Scene은 실제 asset에서 render되고, desktop fallback snapshot도 실제 renderer output에서 생성되어야 하며, normal playback이 Workshop thumbnail에 기대면 안 됩니다.

## 11. 다음 Planning Session

다음 product work를 시작하기 전에:

1. P3 Web Runtime Completion 설계/spec 문서를 작성합니다.
2. P3 실행 가능한 구현 계획을 작성합니다.
3. Web property API, local-only policy, optional remote-network policy, Web error reporting acceptance criteria를 확정합니다.
4. P3 방향과 Scene runtime 우선순위가 확정되기 전에는 Scene S0를 시작하지 않습니다.
