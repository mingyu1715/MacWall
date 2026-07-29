# macOS 26 Native Auto-pause 및 Runtime Stability 설계

작성일: 2026-07-29

상태: 구현 및 정적 검증 완료 / 사용자 runtime QA 대기

## 목적

production Native Wallpaper backend에 다음 두 기능을 추가한다.

1. Desktop이 다른 앱에 가려지거나 시스템이 잠들 때 native video의 decode/enqueue를 중단하고, Desktop이 다시 보이면 재개한다.
2. 활성 renderer가 실패했을 때 기존 화면을 보존한 채 동일 generation을 한 번만 transactional하게 복구한다.

기존 Legacy backend의 자동 일시정지 경험은 유지하되, Native backend의 프로세스 소유권과 generation protocol에 맞는 별도 제어 경계를 사용한다.

이번 단계에서는 안정적인 video runtime을 먼저 완성한다. Scene Engine은 시작하지 않는다.

## 범위

포함:

- Native Video 자동 일시정지 및 재개
- Desktop visibility, sleep, wake 처리
- generation-scoped playback control
- extension 재시작과 Desktop context 재생성 시 제어 상태 복원
- 활성 renderer의 1회 transactional 복구
- Stop 이후 native runtime 상태 및 staged generation 정리
- 가짜 scheduler를 사용하는 deterministic unit test

제외:

- Scene Engine
- Web native surface
- snapshot/export gate
- pixel format, color space, 화질 및 timing profile 추가 최적화
- Legacy playback 동작 변경
- System Settings 자동 조작
- GUI 자동화, package, DMG, notarization, 배포 산출물

## 기존 구조

```text
AppViewModel
  -> WallpaperPlaybackCoordinator
      -> NativeWallpaperBackend
          -> command.json
          -> display-mode.json
          -> Darwin notification
              -> NativeWallpaperSessionController
                  -> NativeVideoFrameBridge
                  -> NativeVideoPlaybackClock
```

Legacy backend는 `WallpaperPlayer` 내부의 `DesktopVisibilityMonitor`와 debounce를 사용한다. Native backend는 별도 WallpaperAgent process에서 실행되므로 Main App의 `AVPlayer`를 직접 pause할 수 없다.

Native runtime에는 이미 다음 기반이 있다.

- immutable generation staging
- Play/Stop command와 ACK
- multi-context first-frame transactional commit
- generation-scoped display mode update
- `NativeVideoPlaybackClock.start/pause/seek/stop`
- 마지막 frame을 유지하는 freeze

## 접근 방식

### A. App 감지 + 별도 playback control 파일

판단: 채택

Main App이 기존 Desktop visibility 정책과 동일한 기준으로 상태를 감지하고, `playback-control.json`을 원자적으로 기록한다. Extension은 target generation이 현재 active 또는 candidate와 일치할 때만 반영한다.

장점:

- 앱 정책과 extension renderer 책임이 분리된다.
- Play command를 덮어쓰지 않아 extension 재시작 시 원래 재생 요청을 복원할 수 있다.
- generation 검증으로 stale pause/resume을 무시할 수 있다.
- 향후 Video 외 renderer에도 동일한 control protocol을 사용할 수 있다.

### B. pause/resume을 command.json에 추가

판단: 사용하지 않음

pause/resume이 마지막 command를 덮어쓰면 extension 재시작 시 어떤 asset을 복구해야 하는지 잃는다. persistent desired playback과 transient control을 같은 파일에 섞지 않는다.

### C. Extension이 직접 Desktop visibility 감지

판단: 사용하지 않음

WallpaperAgent가 소유하는 sandboxed extension은 일반 앱 visibility와 sleep/wake 정책을 안정적으로 판단하기 어렵다. WindowServer private 상태에 의존하지 않고 Main App의 기존 정책을 재사용한다.

## Playback Control Protocol

새 payload:

```swift
public struct NativeRuntimePlaybackControlUpdate: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let commandID: UUID
    public let targetGeneration: UUID
    public let isSuspended: Bool
    public let createdAt: Date
}
```

저장 위치:

```text
<native-runtime-root>/playback-control.json
```

규칙:

- 항상 atomic replace로 기록한다.
- `commandID`가 마지막 처리 ID와 같으면 중복 처리하지 않는다.
- target generation이 active/candidate 어느 쪽에도 없으면 stale update로 무시한다.
- Main App은 최신 desired suspension을 메모리에 유지한다.
- 새 Native generation이 커밋되면 최신 desired suspension을 해당 generation에 다시 publish한다.
- Legacy playback에는 이 파일을 사용하지 않는다.

## Auto-pause 정책

기본 timing:

```text
Desktop covered debounce: 200ms
Desktop visible debounce: 200ms
Sleep: immediate suspend
Wake: 500ms 이후 visibility 재평가
```

상태 규칙:

- 옵션이 켜져 있고 Native playback이 active일 때만 visibility를 감시한다.
- 다른 앱이 Desktop을 가리면 200ms 안정화 후 suspend한다.
- Desktop이 다시 보이면 200ms 안정화 후 resume한다.
- sleep 직전에는 즉시 suspend한다.
- wake 후에는 500ms를 기다리고 현재 visibility를 다시 평가한다.
- 옵션을 끄면 즉시 resume control을 보내고 coverage 기반 suspend를 중단한다.
- 같은 상태를 반복해서 publish하지 않는다.
- 실제 video layer와 마지막 frame은 유지한다. decode/read/enqueue만 중단한다.

## Candidate 및 전환 규칙

candidate를 first-frame 전에 suspend하면 readiness가 영원히 오지 않을 수 있다. 따라서 다음 순서를 고정한다.

```text
stage B
-> B renderer 생성
-> 모든 target context에서 first frame 확인
-> B commit
-> 최신 desired suspension을 B에 적용
-> old A cleanup
```

전환 중 Desktop이 가려진 경우:

- 현재 active A는 즉시 suspend할 수 있다.
- candidate B는 first frame을 생성할 때까지 실행한다.
- B가 commit되면 B에 최신 suspended state를 적용한다.
- B가 실패하면 A와 A의 suspended state를 유지한다.

빠른 Play와 stale control:

- control은 target generation이 일치할 때만 적용한다.
- A에 대한 늦은 resume이 B를 깨우지 않는다.
- B가 commit된 후 coordinator가 최신 desired state를 B 대상으로 다시 기록한다.

## Frame Bridge 일시정지

`freezeKeepingLastFrame()`은 terminal failure/Stop용 one-way 동작으로 유지한다.

자동 일시정지는 별도 reversible 상태로 구현한다.

Suspend:

- bridge는 running session으로 유지한다.
- pump generation을 증가시켜 이전 callback을 무효화한다.
- `requestMediaDataWhenReady` 요청을 중단한다.
- playback clock을 pause한다.
- reader와 pending sample은 유지한다.
- layer의 마지막 frame은 유지한다.

Resume:

- playback clock을 현재 media position에서 다시 시작한다.
- 새 pump generation으로 media-data request를 등록한다.
- pending sample부터 pacing을 이어간다.

모든 pump/schedule callback은 running 여부와 suspended 여부를 함께 검증한다.

## Extension Lifecycle 복원

Extension 시작 또는 Desktop context 재생성 시:

1. persisted Play command를 읽는다.
2. 최신 playback control을 읽는다.
3. candidate renderer를 생성한다.
4. first frame을 모든 context에 준비한다.
5. candidate를 commit한다.
6. target generation이 일치하면 persisted suspension을 적용한다.

zero-context 후 monitor topology가 다시 생긴 경우도 같은 순서를 따른다.

## Runtime Failure Recovery

현재 candidate failure와 active renderer failure를 구분한다.

각 renderer callback은 다음 identity를 포함한다.

- generation
- runtime instance ID
- context key

처리:

### Candidate failure

- candidate instance ID가 일치할 때만 처리한다.
- replacement set만 cleanup한다.
- 기존 active playback과 active generation은 유지한다.

이 규칙은 정상 A -> B 전환 candidate 실패에 적용한다. active renderer failure 이후 시작한 recovery candidate 자체가 실패한 경우에는 원래 active bridge가 이미 terminal 상태이므로 같은 generation의 두 번째 failure로 분류해 recovery를 exhaust한다.

### Active failure

- stale instance callback은 무시한다.
- 해당 generation의 첫 실패면 persisted Play로 replacement candidate를 다시 만든다.
- old active surfaces는 replacement가 모든 context에서 first frame을 만들 때까지 유지한다.
- replacement가 commit되면 old set을 정리한다.
- 같은 generation에서 두 번째 active failure가 발생하면 재시도하지 않는다.
- 모든 active bridge를 마지막 frame으로 freeze한다.
- status를 `failed`로 기록한다.

복구 횟수는 process lifetime이 아니라 active generation 기준으로 관리한다. 새로운 Play generation이 성공하면 retry budget도 새로 시작한다.

## Stop

Native Stop 순서:

```text
Stop command publish
-> extension ACK 대기
-> active/candidate bridge freeze 및 cleanup
-> active generation / instance / suspension state clear
-> status stopped
-> host가 staged generation과 transient control 파일 정리
```

규칙:

- Desktop의 마지막 native frame은 유지한다.
- System Settings wallpaper 선택은 변경하지 않는다.
- Legacy fallback 및 original wallpaper 상태를 건드리지 않는다.
- Stop ACK 전에 generation 파일을 삭제하지 않는다.
- runtime root 자체와 QA transport 설정은 삭제하지 않는다.

## 상태 및 진단

`NativeRuntimeStatus`는 기존 decoder와 호환되도록 optional/default 필드를 추가한다.

권장 필드:

```text
state: suspended
playbackSuspended: Bool?
lastPlaybackControlCommandID: UUID?
```

필수 로그:

```text
playbackControl event=received/applied/ignored
targetGeneration=<uuid>
activeGeneration=<uuid|nil>
candidateGeneration=<uuid|nil>
suspended=<true|false>

nativeRecovery event=started/committed/rejected/exhausted
generation=<uuid>
instance=<uuid>
attempt=<number>
```

## 테스트 전략

실제 sleep과 `Task.sleep` timing에 의존하지 않는다.

가짜 scheduler로 검증:

- coverage 200ms debounce
- visible 200ms debounce
- wake 500ms delay
- 빠른 visibility 변경 시 마지막 상태만 반영
- option off 시 즉시 resume
- inactive Native playback에서 control 미발행

generation protocol:

- active A 즉시 suspend
- candidate B는 first frame 전 suspend하지 않음
- B commit 후 최신 state 적용
- failing B가 A generation과 suspension을 보존
- stale A control이 B에 적용되지 않음
- extension restart와 context rebuild가 persisted control 복원

failure recovery:

- active renderer 첫 실패에서 transactional retry
- retry candidate 실패 시 old active 유지
- 같은 generation의 두 번째 active failure에서 freeze + failed
- stale failure callback 무시
- Stop이 active/candidate/control runtime state clear

## 검증 경계

자동 검증:

- focused `swift test`
- 전체 `swift test`
- project source guard
- unsigned/AdHocQA compile은 필요할 때만
- runtime log 정적 분석

사용자 검증:

- System Settings에서 MacWall 선택
- Desktop이 가려질 때 정지 여부
- Desktop 복귀 시 부드러운 재개
- Fullscreen/Space 전환
- 실제 화면 및 frame 유지 여부

사용자 확인이 필요한 시점에는 자동 UI 조작 없이 안내 후 멈춘다.

## 완료 조건

- Native Video가 Desktop visibility와 sleep/wake에 따라 deterministic하게 suspend/resume된다.
- candidate first-frame 및 transactional replacement가 auto-pause 때문에 막히지 않는다.
- extension 재시작과 context 재생성 후 Play/control 상태가 복원된다.
- active renderer failure는 동일 generation에서 최대 한 번만 복구를 시도한다.
- 두 번째 실패는 무한 재시작 없이 마지막 frame과 failed status를 유지한다.
- Native Stop 이후 stale active generation이나 staged generation이 남지 않는다.
- Legacy backend, fallback, snapshot/export, Scene에는 동작 변경이 없다.
