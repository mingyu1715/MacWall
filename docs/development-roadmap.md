# MacWall 개발 로드맵

수정일: 2026-08-13

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
- Scene은 Metal runtime 전까지 experimental `CALayer` prototype 뒤에서만 제한적으로 다루며, system-wallpaper fallback을 만들지 않습니다.
- `scene.pkg` parsing, 일부 `.tex` decode, 일부 2D layer `CALayer` prototype rendering이 experimental toggle 뒤에 있습니다.
- Scene S1 Format Layer Hardening으로 bounded random-access PKG/TEX parsing,
  selected-mip decode, deterministic Audit schema 2를 독립 모듈로
  분리했습니다.
- bundled macOS screen saver path로 animated Lock Screen playback을 실행합니다.
- Video, Image, Web wallpaper에 대해 asset별 `Derived/desktop-fallback.png` cache를 유지합니다.
- Space 변경 후 active Video/Web fallback cache를 live output에서 refresh합니다.
- `Restore on Stop` 옵션이 켜진 경우 정적 이미지 original wallpaper를 앱 지원 폴더에 복사하고, Stop Playback 시 app-applied fallback과 현재 wallpaper가 일치할 때만 복원합니다.
- live playback 전환은 hidden/staged replacement window set을 먼저 만든 뒤 성공 시에만 old windows를 닫습니다.
- screen-change, wake, visibility update는 deterministic scheduler boundary를 통해 debounce합니다.
- item 전환 실패 시 이전 live playback, fallback active asset, space-refresh active asset, `lastPlayedAssetId`를 유지합니다.
- Fullscreen -> Desktop 복귀 빨간약은 custom desktop-level `NSWindow`가 살아있어도 macOS native Desktop Picture layer가 먼저 합성되는 문제로 보고, macOS 26 native wallpaper pipeline spike를 준비합니다.

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
│  └─ 필요 시 original wallpaper를 capture한 뒤 macOS system wallpaper에 적용
└─ cache 없음
   └─ 비동기 fallback generation 예약
      ├─ 지원되는 경우 대표 frame 캡처
      ├─ Derived/desktop-fallback.png 저장
      └─ asset이 아직 active일 때만 필요 시 original wallpaper를 capture한 뒤 적용
```

규칙:

- cached fallback이 있으면 즉시 사용합니다. 자동으로 regenerate하거나 비교하지 않습니다.
- fallback 작업은 Play/Apply의 side effect입니다. live playback을 block하면 안 됩니다.
- automatic generation은 cache가 없고 runtime이 대표 frame을 만들 수 있을 때만 실행합니다.
- manual generation/regeneration은 library item menu에서 제공합니다.
- original macOS wallpaper capture는 `Restore on Stop` 옵션이 켜져 있고 앱이 `desktop-fallback.png`를 system wallpaper로 실제 적용하기 직전에만 실행합니다.
- original capture는 active Space + display 기준으로 읽은 `com.apple.wallpaper.choice.image` 정적 이미지 URL만 저장합니다.
- original 정적 이미지 파일은 `Application Support/MacWall/DesktopWallpaperRestore/Originals`에 복사하고, Stop Playback은 복사본을 우선 사용합니다.
- MacWall `Derived/desktop-fallback.png`는 original wallpaper로 capture하지 않습니다.
- `Macintosh` 같은 macOS 기본/동적 wallpaper provider는 stale `NSWorkspace.desktopImageURL` 값을 original로 저장하지 않고, 옵션 활성화 또는 Play 시점에 경고합니다.
- restore state는 `Application Support/MacWall/DesktopWallpaperRestore/restore-state-v2.json`에 저장합니다.
- Stop Playback은 current wallpaper가 앱이 적용한 fallback과 일치할 때만 저장된 정적 original wallpaper로 복원합니다.
- Stop Playback은 `Derived/desktop-fallback.png` cache 파일을 삭제하지 않습니다.
- 다른 item fallback 적용이 성공하면 이전 item의 `Derived/desktop-fallback.png`는 삭제합니다.
- 사용자가 앱 재생 중 macOS 설정에서 wallpaper를 직접 바꿨다면 Stop Playback은 그 변경을 덮어쓰지 않습니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`, Workshop thumbnail은 system-wallpaper fallback source가 아닙니다.

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

### Phase P2.5: macOS 26 Native Wallpaper Mode Spike

상태: spike 구현 및 수동 검증 완료. 세부 기록은 `docs/implemented/2026-06-15-macos-26-native-wallpaper-spike.md`에 있습니다.

확인된 결과:

- macOS 26에서 third-party `com.apple.wallpaper` extension discovery/load가 가능합니다.
- `WallpaperAgent`가 `MacWallNativeWallpaperExtension` process를 실행합니다.
- `connect`, `provideSettingsViewModels`, `acquire` handshake가 통과했습니다.
- `CAContext.remoteContext`와 `WallpaperRemoteContextXPC`를 통해 native wallpaper surface를 확보했습니다.
- `AVSampleBufferDisplayLayer` 기반 generated frame과 실제 mp4 playback이 Desktop wallpaper surface에 출력되었습니다.
- Fullscreen -> Desktop 복귀 시 기존 desktop-level `NSWindow` backend의 red-pill 문제가 native path에서 해결됨을 사용자 관측으로 확인했습니다.

Spike 자체는 production 기능이 아닙니다.

- 검증된 runtime은 P2.6에서 production target으로 승격됐으며, spike는 production runtime QA가 끝날 때까지 비교 기준으로 유지합니다.
- 기존 `NSWindow` backend는 유지합니다.
- snapshot/export gate는 별도 활성 작업으로 남아 있습니다.
- asset mp4 playback timing은 bounded PTS pump, continuous loop PTS, `CMSampleBufferRenderSynchronizer` normal profile까지 구현하고 검증했습니다.
- 4K60 H.264 sample에서 재생 품질과 timing은 안정적이었지만 BGRA decode path의 높은 IOSurface memory는 후속 최적화 대상으로 남아 있습니다.
- Web, Scene, fallback PNG 정책 변경은 제외합니다.
- SIP 비활성화, Dock/Finder injection, 시스템 wallpaper DB 직접 수정은 금지합니다.

활성 후속 문서:

- `docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md`
- `docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md`
- `docs/superpowers/specs/2026-06-19-native-wallpaper-playback-timing.md`
- `docs/superpowers/plans/2026-07-20-native-wallpaper-playback-timing.md`

### Phase P2.6: Native Wallpaper Backend Promotion

상태: 구현 완료 / AdHocQA runtime 사용자 검증 대기 / production signing gate 유지

목표:

- 검증된 `MacWallNativeWallpaperSpike` runtime을 MacWall Main App의 production playback backend로 승격합니다.
- 하나의 앱 안에서 Native와 Legacy backend를 분리합니다.
- macOS 26+ Apple Silicon Video는 Native backend 대상으로 삼습니다.
- macOS 25 이하, Intel, Native 미지원 format은 기존 Legacy backend를 유지합니다.

핵심 결정:

- Xcode app container가 containing app과 embedded wallpaper extension을 소유합니다.
- 기존 Core/App/CLI와 테스트는 Swift Package로 유지합니다.
- Main App과 extension은 App Group generation manifest와 ACK로 통신합니다.
- Native wallpaper가 활성화되지 않은 Play 요청에는 `취소`, `기존 방식으로 재생`, `배경화면 설정 열기`를 제공합니다.
- Native playback에서는 Desktop fallback과 original wallpaper restore state를 변경하지 않습니다.
- 새 generation은 모든 active Desktop context에서 준비된 뒤에만 이전 generation을 교체합니다.
- 구현 검증은 명령어, 정적 검사, 자동 테스트, 제공된 로그 분석 범위로 제한합니다.

구현 결과:

- `MacWallNativeRuntimeSupport`에 versioned command/status, atomic App Group store, immutable Video staging, generation state machine을 분리했습니다.
- `MacWallHostApp`이 sandboxed `MacWallNativeWallpaperExtension`을 `Contents/Extensions`에 embed하며 Lock Screen saver target도 함께 소유합니다.
- production extension에 검증된 `connect`, `provideSettingsViewModels`, `acquire`, remote `CAContext`, Video frame bridge를 승격했습니다.
- extension은 heartbeat와 generation-aware ACK를 기록하고, 모든 Desktop context의 첫 frame이 준비된 경우에만 replacement를 commit합니다.
- Main App은 Native/Legacy backend를 eligibility로 routing하며, 실패한 Native 전환은 기존 성공 playback을 유지합니다.
- Native 미활성 Play에는 `취소`, `기존 방식으로 재생`, `배경화면 설정 열기` 3버튼 흐름을 연결했습니다.
- Native Stop은 마지막 frame을 유지하며, Native 경로는 fallback PNG와 original wallpaper restore state를 변경하지 않습니다.
- development-only `AdHocQA` configuration과 scheme은 Host/Extension이 POSIX account home 아래 `~/Library/Application Support/MacWall/NativeRuntimeAdHocQA`를 공유하도록 분리했습니다.
- `AdHocQA` extension에만 위 디렉터리로 제한한 Sandbox temporary exception을 적용하며, Debug/Release는 기존 App Group transport를 유지합니다.
- App Group 접근 실패 시 `development-home`으로 자동 fallback하지 않습니다.
- `Scripts/native-wallpaper-adhoc-qa.sh`에 QA 전용 `reset`, `install`, `status`, `logs` 흐름을 추가했습니다.

검증 결과:

- 전체 `swift test`: 208 tests, 0 failures
- AdHocQA transport/store/backend focused test: 22 tests, 0 failures
- project structure guard 및 Bash syntax 검사 통과
- Xcode target/scheme 목록 검사 통과
- Host + `Contents/Extensions` embedded appex unsigned compile 통과
- `AdHocQA` Host/Extension ad-hoc signed build와 `codesign --verify --deep --strict` 통과
- 빌드 산출물의 Host/Extension transport 값이 모두 `development-home`임을 확인
- Host에는 App Group entitlement가 없고, Extension에는 sandbox와 정확한 QA home-relative read/write 예외만 적용됨을 확인
- production WallpaperAgent discovery/handshake는 통과했지만, ad-hoc App Group write는 `NSCocoaErrorDomain 513`으로 실패했습니다.
- 이번 AdHocQA 구현 후 System Settings 선택, 실제 Desktop 출력, Host/Extension command round trip, Fullscreen/Space 전환은 실행하지 않았습니다.
- proper Apple signing/provisioning 기반 App Group runtime QA가 통과하기 전에는 P2.6 완료 기록을 만들거나 승격 계획을 archive하지 않습니다.

설계:

- `docs/superpowers/specs/2026-07-27-native-wallpaper-backend-promotion-design.md`

실행 계획:

- `docs/superpowers/plans/2026-07-28-native-wallpaper-backend-promotion.md`

이번 phase 제외:

- snapshot/export 해결
- Native Web/Scene
- pixel format 및 IOSurface memory 최적화
- GUI/System Settings 자동 검증
- package, DMG, notarization, `dist` 작업

### Phase P2.7: Native Auto-pause 및 Runtime Stability

상태: 구현 및 정적 검증 완료 / 사용자 runtime QA 대기

구현 결과:

- Main App이 Desktop visibility를 감지해 active Native generation에 `playback-control.json`을 발행합니다.
- Desktop covered/visible 상태는 각각 200ms debounce를 사용하고, sleep은 즉시 suspend, wake는 500ms 후 visibility를 재평가합니다.
- Extension은 마지막 frame과 reader 상태를 유지한 채 playback clock과 decode/read/enqueue pump만 가역적으로 중단합니다.
- 전환 중 candidate는 모든 Desktop context에서 first frame을 만든 뒤 최신 suspension 상태를 적용합니다.
- active renderer 첫 실패는 기존 surface를 유지한 채 같은 generation의 replacement를 한 번만 준비합니다.
- 같은 generation의 복구가 다시 실패하면 무한 재시작하지 않고 active bridge를 마지막 frame으로 freeze하며 failed status를 기록합니다.
- Native Stop ACK 이후 generation staging과 transient display/playback control만 정리하고 runtime root와 QA transport는 보존합니다.
- Legacy fallback, original wallpaper restore, snapshot/export, Web, Scene 동작은 변경하지 않았습니다.

검증 결과:

- 전체 `swift test`: 254 tests, 0 failures
- Native focused test와 project structure guard 통과
- Host + embedded Native extension unsigned AdHocQA compile 통과
- 앱 실행, System Settings 조작, 실제 Desktop runtime QA는 수행하지 않았습니다.

완료 기록:

- `docs/implemented/2026-07-29-native-auto-pause-runtime-stability.md`

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
versioned PKG / TEX format layer
   |
   v
layered asset resolver
   |
   +------ MacWall clean-room built-ins
   |
   +------ optional explicitly staged compatibility assets
   |
   v
typed scene graph
   |
   +------ deterministic clock / properties / input / script runtime
   |
   v
headless Metal render graph
   |
   +------ offscreen test / snapshot adapter
   |
   +------ legacy view adapter
   |
   +------ extension-side IOSurface/CVPixelBuffer adapter
   |
   v
AVSampleBufferDisplayLayer -> WallpaperAgent
```

Native Wallpaper extension은 Main App과 다른 프로세스입니다. Native Scene
mode에서는 extension이 generation에 stage된 Scene source를 직접
parse/render합니다. Main App이 만든 `MTLTexture`를 extension으로 전달하지
않습니다.

### Module boundary

| Module | Responsibility |
| --- | --- |
| `SceneFormats` | PKG entry, TEX metadata, compressed payload, versioned format detail 읽기 |
| `SceneAudit` | sample과 unsupported feature에 대한 deterministic JSON report 생성 |
| `SceneAssets` | package-local asset과 optional user-copied shared asset resolve |
| `SceneGraph` | JSON을 typed layer, composition, material, effect, animation track으로 변환 |
| `SceneMetal` | GPU resource upload 및 Metal frame render |
| `SceneRuntime` | time, pause state, user property, input, 이후 SceneScript 구동 |
| `SceneNativeAdapter` | extension 내부 Metal output을 IOSurface-backed sample buffer로 변환 |
| `SceneSnapshot` | desktop fallback cache용 대표 Scene frame 캡처 |

최종 Metal runtime logic은 `MacWallCore`에 넣지 않습니다. Format과 audit
module은 AppKit/Metal desktop rendering 없이 test와 non-GUI code에서 사용할
수 있어야 합니다.

## 5. Scene 개발 단계

### S0: Format Research and Fixture Catalog

상태: 구현 완료

목표: 최종 renderer를 만들기 전에 input surface를 이해합니다.

- 새 CLI command 없이 internal `SceneAudit` API와 test support의 stable
  report contract를 설계합니다.
- PKG version, TEX container, TEX pixel format, flag, object type, material, effect, shader, font, audio, video texture, script, unresolved path를 기록합니다.
- Scene이 `scene.pkg` 외부 shared Wallpaper Engine asset에 의존하는지 기록합니다.
- local test fixture별 audit snapshot을 저장합니다.
- `supported`, `partially-supported`, `unsupported`, `unknown` 상태를 가진 support matrix를 만듭니다.

완료 기준:

- 기존 Scene fixture가 deterministic audit JSON을 생성합니다.
- unknown format을 crash 없이 report합니다.
- texture decoding 전에 audit report를 사용할 수 있습니다.

구현 결과:

- schema version 1의 internal `SceneAuditReport`와 canonical JSON encoder를
  `MacWallCore`에 추가했습니다.
- TEX payload를 decode/copy하지 않고 `TEXB0003`, `TEXB0004`, image/mipmap,
  animation metadata를 bounded parse합니다.
- Scene JSON의 object, parent/instance, animation, dependency, effect, shader,
  inline SceneScript evidence를 deterministic report로 만듭니다.
- 세 local fixture의 aggregate count만
  `Tests/Fixtures/SceneAudit/local-scene-catalog.json`에 추적합니다.
- S0 구현은 S1에서 `MacWallSceneFormats`/`MacWallSceneAudit` module로
  교체됐으며 기존 Core format/audit 구현은 제거했습니다.
- focused Scene 검증은 25 tests, 전체 검증은 267 tests로 실패 없이
  통과했습니다.

### S1: Format Layer Hardening

상태: 구현 완료. 세부 기록은
`docs/implemented/2026-07-29-scene-format-layer-hardening.md`에 있습니다.

- `MacWallSceneFormats`와 `MacWallSceneAudit`을 독립 target으로 분리했습니다.
- package 전체 loading을 file descriptor/`pread` 기반 bounded random-access
  archive로 교체했습니다.
- `PKGV0008`, `PKGV0018`, `PKGV0023`과 미확인 numeric version evidence를
  parse/report합니다.
- `TEXB0001`부터 `TEXB0004`, multi-image/mipmap, video/animation/trailing
  metadata를 보존합니다.
- software decoder는 선택된 image/mip만 읽고 LZ4, RGBA/RG/R8,
  DXT1/DXT3/DXT5를 bounded decode합니다.
- deterministic/path-redacted Audit schema 2와 S0 aggregate fixture gate를
  구현했습니다.
- Core render plan, App consumer, 기존 `scene-info`를 새 모듈로 전환하고
  기존 Core format/audit 구현을 제거했습니다.
- focused Formats 49 tests, Audit 17 tests, RenderPlan 2 tests와 전체
  310 tests가 실패 없이 통과했습니다.

### S2: Asset Resolver and Typed Scene Graph

상태: 구현 완료. Local fixture gate `5 tests, 0 failures, 0 skips`와 전체
`swift test` `414 tests, 0 failures, 0 skips`를 기록했습니다. 세부 설계와
실행 계획은 각각
`docs/archive/superpowers/specs/2026-08-03-scene-asset-resolver-typed-graph-design.md`와
`docs/archive/superpowers/plans/2026-08-04-scene-asset-resolver-typed-graph.md`에
보관했고, 결과는
[S2 구현 기록](implemented/2026-08-04-scene-asset-resolver-typed-graph.md)에
정리했습니다.

- S2 resolver는 package-local source를 실제 해석하고 clean-room built-in과
  optional external asset은 provenance/candidate만 보존합니다.
- canonical virtual path와 asset provenance를 기록합니다.
- model, material, pass, texture dependency를 graph로 만듭니다.
- image, text, particle, sound, unknown node를 모두 보존합니다.
- parent cycle을 검증하고 instance/override를 reference로 표현합니다.

### S3: GPU Texture Pipeline

상태: 구현 완료. [구현 기록](implemented/2026-08-06-scene-gpu-texture-pipeline.md)을
기준으로 하며, 완료된 [설계](archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md)와
[실행 계획](archive/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md)은
archive에 보관합니다.

- `MacWallSceneTextures`가 bounded package resource에서 RGBA8/RG8/R8,
  capability-gated BC1/BC2/BC3, encoded ImageIO texture를 private Metal texture로
  준비합니다.
- full static mip chain, physical padding/logical content metadata, top-left origin,
  generation ownership, in-flight dedupe, unowned LRU, memory reservation rollback을
  구현했습니다.
- compact format-0 payload는 전체 mip chain을 기준으로 encoded/storage/raw를
  구분하며, 제출된 Metal resource와 memory reservation은 command completion까지
  유지합니다.
- fixed local fixture 3개는 `197 resources = 188 GPU successes + 9 typed unsupported`
  결과를 deterministic/path-redacted catalog에 기록합니다.
- 최종 S3 코드 commit `9677d1d` 검증: focused S3 10 suites
  `164 tests, 0 failures, 0 skips`; full `swift test`
  `583 tests, 0 failures, 0 skips` (XCTest `107.902s`).
- renderer, Desktop Scene, fallback, animation/video, heap/streaming, GUI 검증은
  S3 비범위입니다.

### S4: Headless 2D Metal Renderer

- `MTKView`에 종속되지 않는 headless Scene renderer를 추가합니다.
- Metal device, command queue, render pipeline, quad geometry, orthographic camera, alpha blending을 추가합니다.
- image layer를 stable Z order로 render합니다.
- parent-child transform, instance, opacity, timeline을 평가합니다.
- `Fit`, `Fill`, `Stretch`를 구현합니다.
- 같은 rendered output에서 snapshot을 캡처합니다.

완료 기준:

- `2174863503`이 합리적인 static composition으로 보입니다.
- `2834933421`, `3516106265`가 fixed layer cap 없이 graph로 load됩니다.
- 같은 time/input/property에서 deterministic offscreen frame을 생성합니다.
- Scene snapshot은 실제 Metal output에서 생성할 수 있습니다.

### S5: Native Scene Frame Adapter

- Scene generation manifest와 immutable staging을 추가합니다.
- extension 프로세스 안에서 Scene renderer session을 생성합니다.
- IOSurface-backed `CVPixelBuffer`를 Metal render target으로 사용합니다.
- completed frame을 `AVSampleBufferVideoRenderer`에 enqueue합니다.
- 모든 target Desktop context의 first frame 이후에만 candidate를 commit합니다.
- covered 상태에서는 clock과 renderer를 pause하고 마지막 frame을 유지합니다.

### S6: Effects Render Graph

- offscreen render target과 chained render pass를 추가합니다.
- color adjustment, blur, bloom, blend, shake 계열 effect부터 시작합니다.
- unsupported effect를 layer별로 report합니다.
- effect 하나가 실패해도 전체 Scene을 깨지 않게 skip합니다.
- compatible custom shader에 대한 안전한 translation 전략을 조사합니다.

### S7: Text Layers

- packaged font를 안전하게 load합니다.
- alignment, color, alpha, scale, basic timeline을 가진 text layer를 render합니다.
- missing font fallback behavior를 추가합니다.

### S8: GPU Particle Systems

- GPU-instanced particle을 추가합니다.
- rain, snow, dust, leaf 계열 common system부터 시작합니다.
- renderer, emitter, initializer, operator subset을 점진적으로 구현합니다.
- child system과 cursor control point는 이후 추가합니다.

### S9: Animated Textures, Video, Audio

- GIF 또는 sprite-sheet texture animation을 추가합니다.
- compatible한 경우 AVFoundation 기반 video texture를 추가합니다.
- sound layer와 mute control을 추가합니다.
- audio spectrum input은 ordinary audio playback이 안정화된 뒤 추가합니다.

### S10: Puppet Warp

- mesh geometry, skeleton, weight, animation track을 parse합니다.
- Metal에서 vertex skinning을 구현합니다.
- advanced physics와 inverse kinematics는 basic weighted animation 이후에 다룹니다.

### S11: User Properties and Sandboxed SceneScript

- `project.json`의 item property를 parse합니다.
- 지원 가능한 property type으로 per-item control을 구성합니다.
- explicit API binding을 가진 sandboxed ECMAScript 2018 runtime을 설계합니다.
- `init`, `update`, `applyUserProperties`, resize event부터 시작합니다.
- cursor와 media integration event는 이후 추가합니다.

SceneScript는 execution boundary입니다. 임의 filesystem, process, network access를 얻으면 안 됩니다.

### S12: 3D Models, Lighting, Advanced Shaders and Regression Hardening

- 3D는 별도 renderer capability로 취급합니다.
- model, camera, light, reflection을 점진적으로 추가합니다.
- 흔치 않은 custom shader variant는 unsupported로 둘지 결정합니다.

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

현재 Scene code:

| Path | 현재 책임 |
| --- | --- |
| `Sources/MacWallSceneFormats/` | bounded PKG/TEX format, selected-mip software decode |
| `Sources/MacWallSceneAudit/` | deterministic Audit schema 2와 support policy |
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

- MacWall의 project-authored code 전체는 MIT license를 적용합니다.
- Native Wallpaper Backend와 Scene Engine을 별도 제한 license로 분리하지 않습니다.
- GPL implementation code를 project에 복사하지 않습니다.
- GPL project는 behavior reference와 comparison target으로만 사용합니다.
- MIT-licensed implementation detail을 참고해 적용한 경우 origin을 기록합니다.
- compatible third-party dependency는 원래 license와 notice를 보존합니다.
- Wallpaper Engine shared asset을 bundle하지 않습니다.
- shared asset이 필요하면 사용자가 합법적으로 보유한 local `assets` folder를 직접 복사하고 명시적으로 선택하게 합니다.

## 10. 권장 실행 순서

Product work:

```text
P1 Desktop Fallback Cache (완료)
-> P2 Playback Stability (완료)
-> P2.5 macOS 26 Native Wallpaper Mode Spike (완료)
-> P2.6 Native Wallpaper Backend Promotion (구현 완료 / runtime QA 대기)
-> P2.7 Native Auto-pause 및 Runtime Stability (구현/정적 검증 완료, runtime QA 대기)
-> Native Wallpaper follow-up gates (보류)
-> P3 Web Runtime Completion
```

Scene runtime work:

```text
S0 Format Research and Fixture Catalog (완료)
-> S1 Format Layer Hardening (완료)
-> S2 Asset Resolver and Typed Scene Graph (구현 완료: local fixture 5 tests 및 전체 414 tests, 0 failures)
-> S3 GPU Texture Pipeline (구현 완료: focused 164 tests, full 583 tests, 0 failures/0 skips)
-> S4 Headless 2D Metal Renderer
-> S5 Native Scene Frame Adapter
-> S6 Effects
-> S7 Text
-> S8 Particles
-> S9 Animated Textures, Video, Audio
-> S10 Puppet Warp
-> S11 Properties and SceneScript
-> S12 3D, Advanced Shaders, Regression Hardening
```

첫 offscreen Scene milestone은 S4이고 첫 실제 Desktop milestone은 S5입니다.
S5에서 common 2D Scene은 extension 내부의 실제 Metal output으로 재생되어야
하며 normal playback과 snapshot이 Workshop thumbnail에 기대면 안 됩니다.

## 11. 다음 Planning Session

다음 planning:

1. 별도 사용자 gate에서 Native auto-pause, sleep/wake, 1회 recovery의 실제 Desktop 동작을 확인합니다.
2. S4 Headless 2D Metal Renderer design/spec과 executable implementation plan을
   작성합니다. S4는 S3의 `SceneTextureLease`와 S2 graph contract만 소비합니다.
3. S4 설계 전에는 Desktop Scene, Scene fallback, Native Scene surface,
   animation/video texture, heap/streaming을 시작하지 않습니다.
4. snapshot/export는 `docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md`, BGRA IOSurface memory는 별도 최적화 작업으로 유지합니다.
5. proper Apple signing/provisioning 기반 App Group runtime QA는 release 전 별도 gate로 유지합니다.
