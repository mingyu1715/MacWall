# P2 Playback Stability Design

Status: design/spec, not implemented

Date: 2026-06-04

## Goal

P2는 Workshop Wallpaper Bridge의 live playback을 안정화합니다. 대상은 Spaces/full-screen 전환, monitor attach/detach/resolution change, sleep/wake 복구, library item switching, auto-pause edge case입니다.

P2의 핵심 원칙은 live playback을 primary workflow로 유지하는 것입니다. Desktop fallback은 P1과 동일하게 playback의 side effect이며, fallback cache hit, fallback generation, wallpaper 적용 실패가 live playback 시작이나 전환을 막으면 안 됩니다.

## Non-goals

- Scene S0를 시작하지 않습니다.
- Scene fallback을 구현하지 않습니다.
- Metal Scene runtime을 구현하지 않습니다.
- Web runtime property API를 구현하지 않습니다.
- package, DMG, notarization, release artifact, `dist` 작업을 하지 않습니다.
- GUI 앱 실행을 검증 조건으로 삼지 않습니다.
- Steam Workshop download/crawling/auth/DRM 관련 기능을 추가하지 않습니다.

## Current State

`AppViewModel.playSelected()`는 선택한 library asset을 검증한 뒤 `WallpaperPlayer.shared.play(...)`를 호출합니다. 성공하면 active fallback asset을 설정하고 `DesktopFallbackCoordinator.applyOrGenerate(asset:)`를 호출합니다.

`WallpaperPlayer`는 현재 playback 상태, wallpaper windows, workspace observer, visibility timer, suspension flag를 한 클래스에서 관리합니다. `play(...)`는 기존 windows를 닫고 새 windows를 생성합니다. sleep/wake와 screen parameter change도 같은 player 내부에서 처리합니다.

P1에서 첫 Video Play/Apply 문제는 `VideoWallpaperView.viewDidMoveToWindow()`에서 `player.play()`를 재보장하는 방식으로 해결되었습니다. P2는 이와 별개로 playback state 전환 자체를 더 예측 가능하게 만듭니다.

## Risks In Current Flow

- `WallpaperPlayer.play(...)`가 기존 windows를 먼저 닫은 뒤 새 asset 검증과 window 생성을 진행하면, 새 asset play 실패 시 이전 live playback이 사라질 수 있습니다.
- screen change와 wake 복구가 즉시 reopen을 시도하면 macOS가 screen list를 안정화하기 전 window를 재생성할 수 있습니다.
- lifecycle event가 빠르게 연속 발생할 때 같은 asset reopen이 중복될 수 있습니다.
- `WallpaperPlayer`가 window 생성, state, observer, timer를 모두 들고 있어 테스트가 source-string assertion에 의존하기 쉽습니다.
- AppViewModel은 singleton player를 직접 호출하므로 play success/failure ordering을 unit test로 세밀하게 검증하기 어렵습니다.

## Recommended Approach

P2는 큰 runtime rewrite가 아니라 작은 state boundary를 추가하는 방식으로 진행합니다.

1. `PlaybackSessionState` 같은 순수 state model을 추가합니다.
2. `WallpaperPlayer`는 state model을 사용해 play, stop, suspend, restore, screen-change transition을 일관되게 처리합니다.
3. 새 asset 전환은 transactional하게 처리합니다. replacement windows를 hidden/staged 상태로 먼저 생성하고, 모든 target screen에 대해 생성 성공을 확인한 뒤에만 active session을 교체합니다.
4. monitor change와 wake restore는 짧은 debounce 후 실행합니다.
5. `AppViewModel`에는 testable player protocol을 주입해서 play/fallback/status ordering을 검증합니다.
6. debounce는 fake clock/scheduler를 주입해 unit test에서 실제 sleep timing에 의존하지 않습니다.

이 접근은 `WallpaperPlayer` 전체를 갈아엎지 않고, P2 acceptance criteria에 필요한 안정성만 추가합니다.

## Alternative Approaches

### Approach A: Minimal Patch Inside `WallpaperPlayer`

기존 class에 guard와 debounce만 추가합니다.

장점은 작업량이 가장 작다는 점입니다. 단점은 state가 계속 암묵적이고, P2 이후에도 테스트가 source-string assertion에 머물 가능성이 큽니다.

### Approach B: Small State Boundary

순수 state model과 player protocol을 추가하고, 기존 `WallpaperPlayer`는 window/runtime owner로 유지합니다.

장점은 테스트 가능성과 안정성 개선이 균형 잡힌다는 점입니다. 단점은 기존 singleton 직접 호출 구조를 일부 바꿔야 합니다.

P2 권장안입니다.

### Approach C: Full Playback Runtime Rewrite

window factory, screen provider, lifecycle event bus, playback session controller를 크게 분리합니다.

장점은 장기 구조가 가장 깔끔하다는 점입니다. 단점은 P2 범위를 넘어가며 Scene/Web runtime 작업과 섞일 위험이 큽니다.

P2에서는 선택하지 않습니다.

## Architecture

### `PlaybackSessionState`

순수 Swift state model입니다. AppKit object를 직접 들지 않습니다.

책임:

- active asset identity 기록
- selected playback options 기록
- lifecycle phase 기록: idle, playing, suspended, restoring, failed
- screen-change/wake restore request dedupe에 필요한 generation token 기록
- stale restore completion 무시 판단

이 model은 unit test로 검증합니다.

### `WallpaperPlayer`

runtime owner입니다. AppKit windows, content views, observer, timer를 관리합니다.

P2 변경 방향:

- asset validation을 window teardown보다 먼저 수행합니다.
- replacement windows는 hidden/staged 상태로 먼저 생성합니다.
- 모든 target screen에 대해 replacement window 생성 성공을 확인합니다.
- 모든 replacement window 생성에 성공하면 replacement set을 show한 뒤 old windows를 close합니다.
- replacement window 생성 중 하나라도 실패하면 replacement set만 cleanup하고 old live playback은 유지합니다.
- multi-monitor partial failure가 duplicate window state나 half-swapped state를 만들면 안 됩니다.
- play 성공 후에만 active session을 갱신합니다.
- play 실패 시 이전 session이 있으면 이전 live playback을 유지합니다.
- stop은 active session, observer, timer, windows를 명확히 정리합니다.
- wake/screen-change restore는 generation token으로 stale 작업을 무시합니다.
- screen-change restore는 짧은 debounce 후 현재 `NSScreen.screens`를 다시 읽습니다.

### `PlaybackScheduler`

debounce와 delayed restore를 담당하는 작은 scheduling boundary입니다.

P2 변경 방향:

- production scheduler는 main actor에서 지정된 delay 후 작업을 실행합니다.
- test scheduler는 fake clock 방식으로 pending work를 저장하고, unit test가 시간을 직접 advance합니다.
- screen-change debounce는 300ms입니다.
- wake debounce는 500ms입니다.
- visibility debounce는 200ms입니다.
- debounce test는 real sleep timing, wall clock, `Task.sleep`에 의존하지 않습니다.

### `AppViewModel`

UI-facing state owner입니다.

P2 변경 방향:

- `WallpaperPlayer.shared` 직접 호출 대신 `WallpaperPlayerManaging` protocol을 주입합니다.
- play 성공 후에만 last played asset preference를 저장합니다.
- play 성공 후에만 fallback coordinator를 호출합니다.
- play 실패 시 이전 session이 없을 때만 fallback active asset을 clear하고, 실패한 새 asset의 fallback을 적용하지 않습니다.
- 기존 asset이 재생 중이고 새 asset play가 실패한 경우, 새 asset 실패 status를 보여주되 기존 player session과 기존 fallback active asset은 유지합니다.
- `WallpaperPlayerManaging`은 현재 active session snapshot을 노출해서 AppViewModel이 실패 후 fallback/space-refresh state를 이전 asset과 일치시킬 수 있게 합니다.

### `DesktopVisibilityMonitor`

auto-pause 판단에 사용하는 pure-ish utility입니다.

P2 변경 방향:

- 기존 ignored owner policy를 유지합니다.
- covered 상태에서 wallpaper window를 숨기지 않는 정책을 유지합니다.
- full-screen/Spaces 전환 중 일시적인 window list 변화가 반복 pause/resume을 만들지 않도록 200ms visibility debounce를 적용합니다.

### `VideoWallpaperView`

Video playback content입니다.

P2 변경 방향:

- window attach 후 `player.play()` 재보장은 유지합니다.
- covered 상태에서는 현재 frame에서 pause합니다.
- resume 시 `player.play()`가 idempotent하게 호출되어도 안전해야 합니다.

### `RestrictedWebWallpaperView`

Web playback content입니다.

P2 변경 방향:

- covered 상태에서도 visible output은 유지합니다.
- CSS animation pause/resume은 유지합니다.
- embedded video는 resume delay를 줄이기 위해 강제로 pause하지 않는 정책을 유지합니다.

## Data Flow

### Play/Apply

```text
AppViewModel.playSelected()
-> selected asset 확인
-> WallpaperPlayer.play(asset, options) -> PlaybackSessionSnapshot
   -> validate asset
   -> create hidden/staged replacement windows for every target screen
   -> verify all target screens have replacement windows
   -> show replacement set
   -> close old windows
   -> update PlaybackSessionState
-> AppViewModel sets active fallback asset
-> DesktopFallbackCoordinator.applyOrGenerate(asset)
-> lastPlayedAssetId 저장
-> status 갱신
```

### Play Failure

```text
AppViewModel.playSelected()
-> WallpaperPlayer.play(asset, options) fails
   -> no new active session
   -> previous session remains if one existed
-> AppViewModel reads current active session snapshot
-> if previous session exists, keep fallback and space-refresh active asset on previous asset
-> if no previous session exists, clear fallback and space-refresh active asset
-> failed asset fallback is not applied
-> lastPlayedAssetId remains the previous active asset id when previous session exists
-> status shows playback error
```

### Stop Playback

```text
AppViewModel.stopPlayback()
-> WallpaperPlayer.stop()
-> DesktopFallbackCoordinator.clearActiveAsset()
-> DesktopFallbackSpaceRefreshCoordinator.setActiveAsset(nil)
-> lastPlayedAssetId removed
-> desktop-fallback.png cache remains on disk
```

### Monitor Change

```text
NSApplication.didChangeScreenParametersNotification
-> debounce
-> verify same active generation
-> recreate windows for current screens
-> replace windows only if recreation succeeds
-> preserve active asset and fallback state
```

### Sleep/Wake

```text
willSleep
-> suspend current playback content

didWake
-> debounce
-> verify active session
-> recreate windows for current screens
-> resume playback content
```

## Error Handling

- play failure must not call fallback generation for the failed asset.
- replacement window creation failure should not destroy previous playback if previous playback exists.
- multi-monitor replacement partial failure must cleanup only staged replacement windows and must not produce duplicate or half-swapped live windows.
- monitor/wake restore failure should keep the previous state when possible and avoid clearing `lastPlayedAssetId` unless the user explicitly stops playback.
- stop playback always clears active playback and active fallback asset, but never deletes fallback cache files.
- stale restore tasks must be ignored by generation token.
- unsupported Scene fallback remains unsupported in P1/P2.

## Acceptance Criteria

- First Video Play/Apply after app launch starts live playback on the first click.
- Existing fallback cache is applied after live playback starts and never causes an early return from playback flow.
- Switching from asset A to playable asset B creates B live playback and applies/generates B fallback.
- Switching from asset A to failing asset B does not apply B fallback, keeps A live playback, keeps A fallback active asset, keeps A space-refresh active asset, and keeps `lastPlayedAssetId` as A.
- Stop Playback clears active playback and active fallback asset while preserving existing `desktop-fallback.png`.
- monitor attach/detach/resolution change recreates wallpaper windows for current screens after debounce.
- sleep/wake restores the active playable asset after wake.
- monitor attach/detach/resolution change and sleep/wake verification are simulated unit/integration tests only; actual macOS GUI QA remains a follow-up verification that requires separate approval.
- auto-pause pauses media without hiding wallpaper windows.
- covered Video remains visible on the current frame.
- covered Web remains visible and pauses CSS animation without forcibly pausing embedded video.
- Scene S0 and Scene fallback remain untouched.

## Test Strategy

Use tests that do not require GUI app launch.

- `PlaybackSessionStateTests`
  - play success transitions idle -> playing
  - suspend/resume transitions are idempotent
  - restore generation rejects stale completion
  - stop returns to idle
- `WallpaperPlayerSuspensionTests`
  - no `orderOut` path for auto-pause
  - display mode change does not recreate windows
  - screen-change restore uses debounce/generation token
  - replacement windows are created hidden/staged before old window teardown
  - all target screens must succeed before replacement set is shown
  - partial replacement failure cleans staged windows and preserves old windows
- `AppViewModelTests`
  - play success stores `lastPlayedAssetId`
  - play success invokes fallback side effect after player success
  - A -> failing B does not invoke fallback for B
  - A -> failing B keeps A live playback
  - A -> failing B keeps A fallback active asset
  - A -> failing B keeps A space-refresh active asset
  - A -> failing B keeps `lastPlayedAssetId` as A
  - stop clears active fallback asset and last played preference
- `PlaybackSchedulerTests`
  - screen-change debounce fires only after fake clock advances 300ms
  - wake debounce fires only after fake clock advances 500ms
  - visibility debounce fires only after fake clock advances 200ms
  - replacing a pending debounce cancels the stale scheduled task
- `DesktopVisibilityMonitorTests`
  - ignored owner policy remains stable
  - full-screen/system transient windows do not create false blocking where identifiable
- Existing Web/Video tests remain active.

Monitor attach/detach and sleep/wake tests must use injected screen providers, fake window factories, and fake schedulers. They must not launch the GUI app and must not depend on real macOS screen changes. Actual macOS GUI QA is a separate follow-up after explicit approval.

After focused tests pass, run full `swift test`.

## Documentation

If user-visible playback behavior changes, update:

- `README.ko.md`
- `README.md`

When P2 implementation completes, update:

- `docs/development-log.md`
- `docs/development-roadmap.md`
- `docs/implemented/<date>-p2-playback-stability.md`

## Verification Boundaries

Allowed during implementation:

- focused `swift test`
- full `swift test`
- source/document searches with `rg`

Not allowed unless explicitly requested:

- `swift build`
- GUI app launch
- `bash Scripts/package-app.sh`
- DMG creation
- notarization
- release artifact generation
- `dist` creation/deletion/update

## Timing Defaults

P2 uses these fixed implementation defaults:

- screen parameter change debounce: 300ms
- wake restore debounce: 500ms
- visibility transition debounce: 200ms

These timings are implementation defaults, not user-facing settings.
