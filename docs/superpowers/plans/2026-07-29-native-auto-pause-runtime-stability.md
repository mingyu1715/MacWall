# Native Auto-pause 및 Runtime Stability 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` task-by-task and `superpowers:verification-before-completion` before reporting completion.

**Goal:** production Native Video backend가 Desktop visibility와 sleep/wake에 따라 decode/enqueue를 중단 및 재개하고, active renderer failure를 기존 화면 손실 없이 한 번만 복구하도록 만든다.

**Architecture:** Main App의 visibility controller가 최신 desired suspension을 generation-scoped `playback-control.json`으로 publish한다. Extension은 active generation에는 즉시 반영하고 candidate에는 first-frame commit 후 반영한다. Active renderer failure는 instance identity를 검증한 뒤 동일 generation replacement를 한 번만 시도한다.

**Tech Stack:** Swift 6, AppKit, AVFoundation, QuartzCore, WallpaperExtensionKit private runtime boundary, App Group atomic store, XCTest, Bash source guards.

## 제약

- 이번 계획은 Native Video만 변경한다.
- Scene Engine, Web, snapshot/export, video quality는 시작하지 않는다.
- Legacy fallback과 original wallpaper restore 정책을 변경하지 않는다.
- System Settings 및 GUI를 자동 조작하지 않는다.
- package, DMG, notarization, `dist` 작업을 하지 않는다.
- actual Desktop 결과는 마지막 user-run QA에서만 확인한다.

---

## Task 1: Shared Playback Control 및 Session 상태

**Files:**

- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift`
- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift`
- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeSessionState.swift`
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimePlaybackControlPolicy.swift`
- Modify: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeModelsTests.swift`
- Modify: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeStoreTests.swift`
- Modify: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeSessionStateTests.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimePlaybackControlPolicyTests.swift`

- [ ] `NativeRuntimePlaybackControlUpdate` Codable round-trip test를 추가한다.
- [ ] status의 suspended 진단 필드가 이전 JSON과 호환되는지 테스트한다.
- [ ] `playback-control.json` atomic read/write와 cleanup 테스트를 추가한다.
- [ ] active/candidate/stale generation 적용 결정을 순수 policy로 테스트한다.
- [ ] `NativeRuntimeSessionState.stop()`이 active/candidate 상태를 모두 지우는 테스트를 추가한다.
- [ ] focused test가 RED인 것을 확인한다.
- [ ] 최소 구현으로 GREEN을 만든다.

검증:

```bash
swift test --filter NativeRuntimeModelsTests
swift test --filter NativeRuntimeStoreTests
swift test --filter NativeRuntimeSessionStateTests
swift test --filter NativeRuntimePlaybackControlPolicyTests
```

---

## Task 2: Main App Native Auto-pause Controller

**Files:**

- Create: `Sources/MacWallApp/Playback/NativePlaybackAutoPauseController.swift`
- Modify: `Sources/MacWallApp/Playback/PlaybackScheduler.swift`
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Create: `Tests/MacWallAppTests/NativePlaybackAutoPauseControllerTests.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`

- [ ] fake scheduler를 사용해 visibility 200ms debounce 테스트를 작성한다.
- [ ] 빠른 covered/visible 변화가 마지막 상태 하나만 publish하는지 테스트한다.
- [ ] sleep 즉시 suspend와 wake 500ms 재평가를 테스트한다.
- [ ] option off가 즉시 resume하고 이후 coverage를 무시하는지 테스트한다.
- [ ] Native inactive 및 Legacy active일 때 control을 발행하지 않는지 테스트한다.
- [ ] `AppViewModel`이 Native Play 성공/Stop 성공에만 controller active 상태를 바꾸고 failing transition에서는 기존 상태를 유지하는지 테스트한다.
- [ ] RED 확인 후 visibility monitor, notification, scheduler를 주입 가능한 controller로 구현한다.

검증:

```bash
swift test --filter NativePlaybackAutoPauseControllerTests
swift test --filter AppViewModelTests
```

---

## Task 3: Coordinator 및 Backend Control Publish

**Files:**

- Modify: `Sources/MacWallApp/Playback/WallpaperPlaybackCoordinator.swift`
- Modify: `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`
- Modify: `Tests/MacWallAppTests/WallpaperPlaybackCoordinatorTests.swift`
- Modify: `Tests/MacWallAppTests/NativeWallpaperBackendTests.swift`

- [ ] backend가 active generation을 대상으로 control update를 쓰고 Darwin notification을 보내는 테스트를 추가한다.
- [ ] coordinator가 최신 desired suspension을 기억하는 테스트를 추가한다.
- [ ] active A가 있으면 B 준비 중에도 A에 즉시 control을 보내는 테스트를 추가한다.
- [ ] B 성공 후 최신 state를 B generation에 다시 publish하는 테스트를 추가한다.
- [ ] failing B가 A의 active receipt와 control 상태를 보존하는 테스트를 추가한다.
- [ ] Legacy/no-active 경로가 native control file을 쓰지 않는지 테스트한다.
- [ ] RED 확인 후 최소 API와 구현을 추가한다.

검증:

```bash
swift test --filter NativeWallpaperBackendTests
swift test --filter WallpaperPlaybackCoordinatorTests
```

---

## Task 4: Extension Reversible Suspend 및 Lifecycle 복원

**Files:**

- Modify: `MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Modify: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

- [ ] source guard에 playback control polling, generation 검증, reversible bridge API 조건을 추가한다.
- [ ] `NativeVideoFrameBridge.setPlaybackSuspended(_:)`를 구현한다.
- [ ] suspend가 media-data request와 clock만 멈추고 reader/pending sample/last frame을 보존하게 한다.
- [ ] resume이 새 pump generation에서 request를 다시 시작하게 한다.
- [ ] active control은 즉시 bridge 전체에 적용한다.
- [ ] candidate control은 state만 저장하고 first-frame commit 이후 적용한다.
- [ ] extension startup과 context rebuild가 persisted Play/control 순서로 복원되는지 source guard로 확인한다.

검증:

```bash
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
```

---

## Task 5: Active Renderer 1회 Transactional Recovery

**Files:**

- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeRecoveryPolicy.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeRecoveryPolicyTests.swift`
- Modify: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

- [ ] generation별 first-failure retry, second-failure exhaust, new-generation reset을 순수 policy test로 작성한다.
- [ ] renderer callback에 generation, instance ID, context identity가 전달되는 source guard를 추가한다.
- [ ] candidate failure와 active failure가 분리되는 guard를 추가한다.
- [ ] 첫 active failure가 old set을 유지한 채 persisted Play로 replacement candidate를 시작하게 한다.
- [ ] replacement commit 후 old set cleanup과 suspension state 적용을 확인한다.
- [ ] 같은 generation의 두 번째 실패가 모든 active bridge를 freeze하고 failed status를 기록하게 한다.
- [ ] stale callback을 무시한다.

검증:

```bash
swift test --filter NativeRuntimeRecoveryPolicyTests
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
```

---

## Task 6: Native Stop Cleanup

**Files:**

- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift`
- Modify: `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`
- Modify: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
- Modify: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeStoreTests.swift`
- Modify: `Tests/MacWallAppTests/NativeWallpaperBackendTests.swift`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

- [ ] Stop이 extension session의 active/candidate instance, generation, suspension state를 clear하는 guard를 추가한다.
- [ ] Stop ACK 전에 generation을 삭제하지 않는 backend test를 추가한다.
- [ ] Stop ACK 후 all generation directories와 transient display/control files를 정리하는 store test를 추가한다.
- [ ] runtime root 및 QA transport 설정이 보존되는지 테스트한다.
- [ ] cleanup 실패가 Stop ACK 결과를 뒤집지 않고 진단 가능한지 구현한다.

검증:

```bash
swift test --filter NativeRuntimeStoreTests
swift test --filter NativeWallpaperBackendTests
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
```

---

## Task 7: 문서 및 최종 정적 검증

**Files:**

- Modify: `README.ko.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/development-log.md`
- Create: `docs/implemented/2026-07-29-native-auto-pause-runtime-stability.md`

- [ ] Native Video의 자동 일시정지 조건과 마지막 frame 유지 정책을 README KO/EN에 반영한다.
- [ ] 구현 결과와 복구 제한을 implemented 문서에 정리한다.
- [ ] KST timestamp와 focused/전체 test 결과를 development log에 기록한다.
- [ ] 활성 설계/계획 링크를 문서 index에 반영한다.
- [ ] focused tests, 전체 `swift test`, source guard를 실행한다.
- [ ] 필요할 때만 AdHocQA compile gate를 실행한다. GUI는 실행하지 않는다.
- [ ] diff와 금지 범위를 최종 검토한다.
- [ ] 변경을 로컬 commit으로 남긴다.

최종 검증:

```bash
swift test
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
git diff --check
rg -n "snapshot|Scene|Web|fallback" \
  Sources/MacWallApp/Playback \
  MacWallNativeWallpaperExtension \
  Sources/MacWallNativeRuntimeSupport
git status --short
```

## User-run Runtime Gate

자동 검증이 모두 끝난 뒤에만 사용자에게 다음 확인을 요청한다.

1. production AdHocQA runner로 reset/install
2. System Settings에서 MacWall 선택
3. Native Video Play
4. Desktop을 다른 앱으로 가린 뒤 로그에서 suspend 확인
5. Desktop 복귀 후 resume과 화면 연속성 확인
6. sleep/wake 및 Fullscreen -> Desktop 확인

화면과 System Settings 조작은 사용자가 직접 수행한다. 결과를 받기 전에는 runtime 성공을 단정하지 않는다.
