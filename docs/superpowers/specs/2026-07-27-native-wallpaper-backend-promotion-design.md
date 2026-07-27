# macOS 26 Native Wallpaper Backend Promotion Design

작성일: 2026-07-27

상태: 설계 승인 / 실행 계획 작성 전

## 목적

`MacWallNativeWallpaperSpike`에서 검증한 macOS native wallpaper runtime을 MacWall Main App의 production playback backend로 승격한다.

검증된 기반:

- `WallpaperExtensionKit` 경로에서 third-party extension discovery와 launch 성공
- `WallpaperAgent`의 `connect`, `provideSettingsViewModels`, `acquire` handshake 성공
- `CAContext.remoteContext`와 `WallpaperRemoteContextXPC`를 통한 Desktop surface 출력 성공
- `AVSampleBufferDisplayLayer` 기반 실제 mp4와 loop playback 성공
- Fullscreen -> Desktop 복귀 시 기존 desktop-level `NSWindow` backend의 red-pill 문제 해결 확인
- bounded PTS pump와 `CMSampleBufferRenderSynchronizer` 기반 normal timing profile 검증

이 설계는 기존 backend를 제거하지 않는다. 하나의 MacWall 앱 안에서 Native와 Legacy playback backend를 분리하고, 지원 조건과 사용자 선택에 따라 명시적으로 전환한다.

## 지원 범위

첫 production milestone:

- macOS 26 이상
- Apple Silicon
- Video asset
- System Settings에서 사용자가 MacWall wallpaper를 선택한 상태

호환성 경로:

- macOS 25 이하: Legacy backend
- Intel Mac: Legacy backend
- 첫 milestone에서 Native가 지원하지 않는 Image/Web 등: 기존 지원 범위에서 Legacy backend
- Native wallpaper가 활성화되지 않은 macOS 26 환경: 사용자 선택 팝업

제외:

- snapshot/export gate 해결
- Web native surface
- Scene Engine 및 Scene native surface
- fallback PNG 정책 변경
- playback quality 및 pixel format 최적화
- release packaging, DMG, notarization, 배포 산출물
- System Settings 자동 조작과 실제 Desktop 화면 자동 검증

## 접근 방식 비교

### A. Xcode App Container + 기존 Swift Package

판단: 채택

- Xcode app target이 containing app과 embedded wallpaper extension을 소유한다.
- 기존 `MacWallCore`, `MacWallApp`, CLI 및 테스트 코드는 Swift Package로 유지한다.
- App Group, app sandbox, appex embedding, signing 관계를 Xcode target에서 관리한다.
- private framework 코드는 extension target 안에 격리한다.

장점:

- ExtensionKit lifecycle과 code signing 구조에 맞다.
- production app과 extension의 versioning 및 embedding 관계가 명확하다.
- 기존 Swift Package 테스트 구조를 유지할 수 있다.

비용:

- Xcode project/container를 새로 관리해야 한다.
- App Group과 signing round trip을 구현 전에 먼저 검증해야 한다.

### B. Shell/CMake 기반 appex 수동 조립

판단: spike 전용으로 유지

- 현재 spike를 가장 빨리 재사용할 수 있다.
- production app에서는 entitlements, embedding, signing, archive 단계가 쉽게 어긋난다.
- 최종 앱 구조로 승격하지 않는다.

### C. 별도 Companion App

판단: 사용하지 않음

- 별도 host app에 wallpaper extension을 유지하고 Main App과 통신할 수 있다.
- 설치 단위, process ownership, versioning, 사용자 경험이 복잡해진다.
- MacWall 단일 앱 목표와 맞지 않는다.

## 상위 Architecture

```text
MacWall Main App
   |
   v
WallpaperPlaybackCoordinator
   |
   +-- LegacyWallpaperBackend
   |      |
   |      +-- existing WallpaperPlayer
   |      +-- DesktopFallbackCoordinator
   |
   +-- NativeWallpaperBackend
          |
          +-- NativeRuntimeStore
          +-- generation command / ACK
          +-- App Group staging
                  |
                  v
MacWallNativeWallpaperExtension
   |
   +-- WallpaperAgent handshake
   +-- Native playback session
   +-- CAContext per Desktop context
   +-- AVSampleBufferDisplayLayer consumers
```

앱은 하나다. Native와 Legacy는 재생 구현 경계만 분리한다.

## Target 및 Module 구조

```text
MacWall.xcodeproj
├── MacWallHostApp
│   └── existing local Swift Package 사용
├── MacWallNativeWallpaperExtension
│   └── embedded appex
└── shared App Group entitlements
```

Swift Package:

```text
Sources/
├── MacWallCore
├── MacWallApp
│   ├── Playback/
│   │   ├── WallpaperPlaybackCoordinator
│   │   ├── LegacyWallpaperBackend
│   │   └── NativeWallpaperBackend
│   └── NativeRuntime/
└── MacWallNativeRuntimeSupport
    ├── Command
    ├── Status
    ├── Generation
    └── AppGroupStore
```

규칙:

- `MacWallNativeRuntimeSupport`는 Foundation-only data/protocol boundary로 유지한다.
- `WallpaperExtensionKit`, `CAContext`, private XPC type은 extension target 밖으로 노출하지 않는다.
- 기존 `WallpaperPlayer`는 Legacy backend 구현으로 보존한다.
- spike는 production backend가 검증될 때까지 삭제하거나 대규모로 정리하지 않는다.
- 기존 수동 app packaging script는 이번 phase에서 수정하거나 실행하지 않는다.

## Backend 선택 정책

`WallpaperPlaybackCoordinator`가 모든 Play/Stop 요청의 단일 진입점이다.

Native eligibility:

```text
macOS >= 26
AND Apple Silicon
AND asset.kind == video
AND native runtime support available
```

선택 규칙:

| 조건 | Backend |
| --- | --- |
| Native eligible + active Desktop context 확인 | Native |
| Native eligible + inactive/unconfigured | 사용자 선택 팝업 |
| 사용자 `기존 방식으로 재생` 선택 | 해당 요청만 Legacy |
| macOS 25 이하 또는 Intel | Legacy |
| Native 미지원 asset kind | Legacy |

Native runtime 실패를 Legacy로 자동 전환하지 않는다. 자동 전환은 backend가 섞인 상태를 숨기고 fallback 적용으로 System Settings의 Native wallpaper 선택을 바꿀 수 있다.

## Native 설정 안내

Native eligible Video의 Play 시 active Desktop context를 확인할 수 없으면 다음 안내를 표시한다.

제목:

```text
Native Wallpaper 설정이 필요합니다
```

설명:

```text
macOS 26의 Native Wallpaper 방식은 시스템 설정에서 MacWall을 배경화면으로
한 번 선택해야 합니다. Native 방식은 전체 화면과 Space 전환이 자연스럽습니다.
기존 방식은 바로 재생할 수 있지만 전환 중 macOS 배경화면이 잠깐 보일 수 있습니다.
```

버튼:

1. `취소`
   - 새 재생 요청을 취소한다.
   - 현재 재생 상태와 `lastPlayedAssetId`를 변경하지 않는다.
2. `기존 방식으로 재생`
   - 이번 Play 요청에만 Legacy backend를 사용한다.
   - 선택을 영구 설정으로 저장하지 않는다.
3. `배경화면 설정 열기`
   - macOS Wallpaper 설정 pane을 연다.
   - 선택 asset을 pending Native request로 유지한다.
   - staging과 command publish가 완료되고 extension ACK가 오면 Native playback을 확정한다.

System Settings를 여는 동작은 사용자가 버튼을 눌렀을 때만 수행한다. 앱은 wallpaper item을 자동 선택하지 않는다.

## Main App Playback 상태

```text
idle
staging
waitingForNativeACK
playingNative
playingLegacy
stopped
failed
```

규칙:

- Play 요청마다 새로운 generation UUID를 만든다.
- 새 요청이 들어오면 이전 미완료 요청을 invalidate한다.
- 같은 asset의 동일 요청은 dedupe한다.
- staging, file copy/clone, manifest I/O는 MainActor 밖에서 수행한다.
- `lastPlayedAssetId`는 실제 backend가 성공한 뒤에만 갱신한다.
- 새 요청이 실패해도 기존 Native 또는 Legacy playback은 유지한다.
- UI state는 stale generation의 completion이나 ACK를 무시한다.

## Native Play 흐름

Native wallpaper가 활성화된 경우:

```text
selected Video 검증
-> immutable generation directory 생성
-> source video staging
-> command manifest atomic replace
-> Darwin notification
-> matching generation ACK 대기
-> 모든 active Desktop context가 first frame ready
-> extension atomic replacement
-> playing ACK
-> Main App active backend/lastPlayedAssetId commit
```

Native wallpaper가 활성화되지 않은 경우:

```text
selected Video 검증
-> 설정 안내 표시
   ├── 취소
   ├── 이번 요청 Legacy
   └── 설정 열기
       -> pending request 준비
       -> user가 MacWall 선택
       -> extension acquire
       -> matching generation ACK
       -> Native playback commit
```

활성 여부는 persisted boolean 하나로 판단하지 않는다. fresh extension status, active Desktop context 수, generation-aware response를 사용한다.

## App Group Protocol

기본 App Group:

```text
group.com.mingyu1715.macwall
```

저장 구조:

```text
NativeRuntime/
├── command.json
├── status.json
└── Generations/
    └── <generation-uuid>/
        └── source.mp4
```

### Command

예시:

```json
{
  "schemaVersion": 1,
  "command": "play",
  "generation": "752E91C1-46F4-4A98-81B0-9F0526CE5D29",
  "assetID": "library-asset-id",
  "assetKind": "video",
  "relativeSourcePath": "Generations/752E91C1-46F4-4A98-81B0-9F0526CE5D29/source.mp4",
  "displayMode": "fill",
  "createdAt": "2026-07-27T14:58:00Z"
}
```

명령 종류:

- `play`
- `stop`

규칙:

- App Group root 밖의 절대 경로를 command에 넣지 않는다.
- extension은 정규화된 상대 경로가 App Group generation root 안에 있는지 검증한다.
- source staging 완료 후 manifest를 atomic replace한다.
- Darwin notification은 wake-up signal로만 사용하며 payload를 전달하지 않는다.
- extension launch/acquire 시 notification 유실과 관계없이 current manifest를 다시 읽는다.

### Status / ACK

상태:

- `inactive`
- `preparing`
- `playing`
- `stopped`
- `failed`

필드:

- schema version
- requested generation
- active generation
- state
- active Desktop context count
- extension instance UUID
- extension PID
- heartbeat timestamp
- error category/code

Main App은 같은 generation의 `playing` ACK만 Play 성공으로 인정한다. PID나 extension instance가 바뀌거나 heartbeat가 stale하면 persisted status를 현재 활성 상태로 간주하지 않는다.

## Extension Context 및 Replacement

Extension playback session은 개별 preview/context callback과 분리한다.

```text
connect
-> acquire request 분류
-> Desktop context 등록
-> current command 확인
-> candidate playback session 준비
-> 모든 active Desktop context first frame 준비
-> layer/session swap
-> previous session cleanup
-> playing ACK
```

규칙:

- Preview context는 active Desktop context count에 포함하지 않는다.
- Preview는 production Video decoder를 중복 실행하지 않는 lightweight output을 우선한다.
- candidate 준비 중에는 기존 active session과 layer를 유지한다.
- 하나의 target display라도 준비에 실패하면 candidate 전체를 cleanup한다.
- partial swap이나 일부 monitor만 새 asset을 표시하는 상태를 허용하지 않는다.
- context가 일시 invalidate돼도 decoder를 즉시 폐기하지 않고 짧은 grace period를 둔다.
- reacquire된 Desktop context는 현재 active generation에 연결한다.
- 실패 status에는 failed generation을 기록하되 active generation은 이전 성공 generation으로 유지한다.

## Stop 정책

Native Stop:

- decode와 playback clock 진행을 중지한다.
- 마지막으로 출력된 frame을 유지한다.
- System Settings의 MacWall wallpaper 선택을 유지한다.
- macOS system wallpaper 또는 `desktop-fallback.png`를 적용하지 않는다.
- matching generation의 `stopped` ACK를 기록한다.
- active generation source는 즉시 삭제하지 않는다.

Legacy Stop:

- 기존 `WallpaperPlayer`와 restore/fallback 정책을 유지한다.

Native Stop은 original wallpaper restore와 별개다. Native mode에서는 앱이 `NSWorkspace.setDesktopImageURL`로 system wallpaper를 교체하지 않으므로 restore session을 만들지 않는다.

## Fallback 격리

- Native backend는 `DesktopFallbackCoordinator`를 호출하지 않는다.
- Native backend는 `OriginalDesktopWallpaperStore`를 시작하거나 수정하지 않는다.
- Legacy playback이 성공한 경우에만 기존 fallback side effect를 실행한다.
- Native에서 Legacy로 전환해 fallback PNG를 macOS system wallpaper로 적용하면 Native wallpaper 선택이 해제될 수 있다.
- 그 후 Native Play를 요청하면 active context가 없으므로 설정 안내를 다시 표시한다.
- Native generation 실패 시 fallback PNG를 대신 적용하지 않는다.

## Staging 및 정리

- generation directory는 publish 전까지 extension이 참조하지 않는 임시 위치에서 준비한다.
- 같은 volume에서는 APFS clone/copy 최적화를 사용할 수 있지만 정확성과 sandbox 접근을 우선한다.
- active generation과 candidate generation을 cleanup 대상에서 제외한다.
- candidate 실패 시 해당 generation을 정리한다.
- replacement 성공 후 이전 generation을 지연 정리한다.
- app launch 또는 bounded maintenance 시 command/status에서 참조하지 않는 stale generation만 정리한다.
- source Workshop folder와 imported asset 원본은 수정하지 않는다.

## 오류 처리

| 오류 | 동작 |
| --- | --- |
| Native 미설정 또는 inactive | 3버튼 설정 안내 |
| staging 실패 | 새 요청 실패, 기존 playback 유지 |
| command write 실패 | 새 요청 실패, publish하지 않음 |
| ACK timeout + active context 없음 | 설정 안내 |
| extension explicit failure ACK | 오류 표시, 기존 playback 유지 |
| stale ACK | 무시 |
| multi-monitor partial preparation failure | candidate 전체 cleanup |
| extension process 교체 | instance/heartbeat 재검증 |
| unsupported OS/CPU/kind | Legacy route |

오류 이후 `lastPlayedAssetId`, active backend, 기존 fallback/Native generation은 성공한 이전 상태를 유지한다.

## 검증 범위

이번 승격 작업은 명령어, 정적 검증, 자동 테스트, 제공된 로그 분석까지만 수행한다.

포함:

- focused `swift test`
- 필요한 전체 `swift test`
- backend selection 및 popup action unit test
- temporary directory 기반 App Group store test
- path traversal 및 상대 경로 검증
- atomic manifest replace
- stale generation/ACK 차단
- fake clock/scheduler 기반 heartbeat와 timeout test
- replacement state machine의 all-or-nothing test
- source guard 및 Swift parse
- Xcode target/build setting 정적 검사
- `plutil` 기반 Info.plist/entitlement 검사
- build가 필요한 gate에서 app/appex embedding과 `codesign` 결과 확인
- 사용자가 제공한 WallpaperAgent/Extension 로그 분석

제외:

- agent의 System Settings 조작
- wallpaper 선택/재선택
- GUI 앱 실행
- 실제 화면 캡처
- Fullscreen/Space 전환 수동 QA
- 장시간 성능 측정
- 반복 runtime matrix
- package, DMG, notarization, `dist` 작업

실제 Desktop 영상 출력과 red-pill 회귀 확인은 구현 완료의 자동 acceptance가 아니라 별도 후속 수동 QA로 남긴다.

## Implementation Gates

### Gate 0: App Group Round Trip

- containing app과 embedded appex에 동일 App Group entitlement 설정
- Main App test writer와 extension-side reader가 generation manifest를 왕복
- bundle embedding 및 signing 관계 확인
- 실패하면 Main App playback flow를 수정하지 않고 중단

### Gate 1: Shared Protocol

- Foundation-only command/status model
- schema versioning
- atomic store
- path validation
- stale generation and heartbeat rules

### Gate 2: Extension Runtime Promotion

- spike의 검증된 handshake와 Native Video runtime을 extension target으로 승격
- bundled sample 대신 App Group staged source 사용
- Desktop/Preview context 분리
- transactional generation replacement와 status ACK

### Gate 3: Main App Coordinator

- existing player를 Legacy backend로 감쌈
- async Native backend 추가
- generation-aware request serialization
- successful backend commit 이후 fallback 및 `lastPlayedAssetId` 처리

### Gate 4: Setup Guidance

- Native activation probe
- 3버튼 안내
- one-shot Legacy 선택
- Wallpaper settings open과 pending Native request

### Gate 5: Static and Log Verification

- focused/전체 unit test
- target, entitlement, plist, embedding, codesign 명령 검증
- 제공된 WallpaperAgent/Extension 로그에서 generation과 ACK 확인
- 실제 화면 조작 없이 결과 문서화

## Acceptance Criteria

- MacWall은 하나의 앱으로 유지된다.
- Native와 Legacy backend의 상태와 side effect가 분리된다.
- macOS 26+ Apple Silicon Video는 Native eligibility를 갖는다.
- Native가 활성화되지 않았을 때 3버튼 설명 팝업이 표시된다.
- Legacy 선택은 해당 Play 요청에만 적용된다.
- App Group command와 ACK는 generation-aware이며 stale response를 거부한다.
- 새 Native asset 실패 시 이전 재생이 유지된다.
- 다중 Desktop context 교체는 all-or-nothing이다.
- Native mode는 fallback PNG와 original wallpaper restore state를 변경하지 않는다.
- Native Stop은 마지막 frame과 System Settings 선택을 유지한다.
- private framework 코드는 extension target 안에 격리된다.
- 검증은 명령어, 정적 검사, 자동 테스트, 로그 분석 범위를 넘지 않는다.

## 후속 작업

설계 승인 후 별도의 executable implementation plan을 작성한다. 계획 작성 전에는 Main App 통합 코드를 시작하지 않는다.

후속 phase 후보:

- snapshot/export response gate
- native pixel format 및 IOSurface memory 최적화
- Web renderer frame bridge
- Metal Scene renderer frame bridge
- release signing/notarization 계획
