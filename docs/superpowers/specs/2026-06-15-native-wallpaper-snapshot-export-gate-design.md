# macOS 26 Native Wallpaper Snapshot Export Gate Design

작성일: 2026-06-15

상태: 구현 계획 준비

## 목적

macOS 26 Native Wallpaper Spike의 Desktop native surface와 mp4 재생 경로는 유지한 채, WallpaperAgent의 `snapshot` / export 요청에서 남아 있는 `WallpaperExtensionError(2)`와 crash 원인을 분리한다.

이번 gate의 목표는 실제 비디오 프레임 캡처가 아니다. 목표는 WallpaperAgent가 받아들이는 snapshot reply shape를 crash 없이 좁히고, snapshot/export 실패가 native video wallpaper runtime을 깨지 않게 만드는 것이다.

## 현재 기준 상태

확정된 성공:

- `WallpaperExtensionKit` 경로 사용 가능
- third-party `com.apple.wallpaper` extension discovery/load 성공
- `WallpaperAgent`가 `MacWallNativeWallpaperExtension` launch
- `connect`, `provideSettingsViewModels`, `acquire` 성공
- `CAContext.remoteContext`와 `WallpaperRemoteContextXPC` 생성 성공
- `AVSampleBufferDisplayLayer` 기반 mp4 출력 성공
- Fullscreen -> Desktop 복귀 빨간약 해결 확인
- `dev.sh reset/install/status/logs` 기반 개발 runner 추가

남은 문제:

- snapshot/export 요청에서 `WallpaperExtensionError(2)`가 남아 있음
- `WallpaperSnapshotXPC rawValue + IOSurface + encode swizzle` 실험은 extension crash를 유발했음
- crash 후에는 WallpaperAgent runtime이 깨져 검은 화면이 남을 수 있음

현재 안정 baseline:

- `MacWallSnapshotProbe.isEnabled = false`
- `WallpaperSnapshotXPC` encode swizzle 비활성화
- snapshot 요청은 nil reply로 실패하지만 extension crash는 피함
- Desktop video path가 snapshot/export보다 우선

## 범위

포함:

- acquire / update / snapshot / invalidate 로그 분리
- snapshot 요청의 `id`, role, session, pid, reply mode, reply type, error code 추적
- crash-safe snapshot candidate matrix
- `dev.sh`에서 snapshot probe mode를 명시적으로 선택하는 실험 경로
- stale extension process와 old build 혼입 여부 감지
- 실험 결과를 `docs/development-log.md`에 기록

제외:

- 실제 video frame snapshot/export
- Web wallpaper native snapshot
- Scene wallpaper native snapshot
- Main App 통합
- 기존 `NSWindow` backend 수정
- fallback PNG 정책 수정
- 시스템 wallpaper DB 수정
- Dock/Finder injection
- SIP 비활성화
- release packaging / DMG / notarization / dist 작업

## 설계 원칙

1. Desktop native video path를 항상 보호한다.
2. snapshot/export는 독립 gate로 취급한다.
3. 한 번에 하나의 snapshot candidate만 실험한다.
4. crash가 난 candidate는 즉시 기본 경로에서 제거한다.
5. 실제 화면 상태는 사용자가 확인하고, 로그와 충돌하면 사용자 관측을 우선한다.
6. System Settings 조작, Desktop 출력 확인, Fullscreen QA는 자동화하지 않는다.

## Snapshot Candidate Matrix

| Mode | Reply | 목적 | 성공 기준 | 실패 분류 |
| --- | --- | --- | --- | --- |
| `disabled` | `nil, nil` | 안정 baseline | extension crash 없음, video 유지 | `WallpaperExtensionError(2)`는 허용 |
| `error` | `nil, NSError` | nil과 explicit error 차이 확인 | crash 없음, WallpaperAgent error code 변화 확인 | error code만 바뀌면 accepted shape 아님 |
| `empty-object` | empty `WallpaperSnapshotXPC` | object 자체 수용 여부 확인 | crash 없음, 4101/2 변화 확인 | objc lifetime 또는 encode reject |
| `raw-value-retained-iosurface` | `WallpaperSnapshotXPC.rawValue = IOSurface` with retained surface | rawValue lifetime 개선 검증 | crash 없음, 4101 제거 또는 변화 | crash면 rawValue path 폐기 |
| `box-retained-iosurface` | `WallpaperSnapshotXPC.box = retained IOSurface pointer` | box ivar fallback 재검증 | crash 없음, 4101 제거 또는 변화 | crash면 box path 폐기 |
| `png-data` | PNG `Data` wrapped in discovered snapshot field | bitmap payload 가능성 확인 | crash 없음, error code 변화 | request expects private wrapper |
| `file-url` | PNG file written under request `cacheDirectory`, direct `NSURL` reply | WallpaperAgent cache-home export 구조 확인 | crash 없음, 4101 제거 또는 변화 | URL direct reply reject |
| `snapshot-xpc-file-url` | PNG file written under request `cacheDirectory`, `WallpaperSnapshotXPC.rawValue = NSURL` | private wrapper + file URL 구조 확인 | unsafe flag가 있을 때만 실행 | `4099` / XPC invalidation / runtime removal |

`raw-value-retained-iosurface`는 이미 crash-prone으로 확인된 rawValue 경로의 lifetime 개선 실험이다. 기본값으로 되돌리면 안 된다.

Manual matrix 결과 `empty-object`, `raw-value-retained-iosurface`, `box-retained-iosurface`, `png-data`는 모두 extension crash 없이 native video runtime을 유지했지만 WallpaperAgent가 `NSCocoaErrorDomain(4101)`로 거부했다. `png-data`도 `NSConcreteMutableData` reply 전송까지는 성공했으므로, 다음 가설은 snapshot request의 `cacheDirectory` URL 아래에 파일을 생성하고 file URL 또는 private wrapper를 반환하는 방식이다.

추가 matrix 결과 `file-url`은 PNG 파일 생성과 `NSURL` reply 전송까지 성공했지만 `NSCocoaErrorDomain(4101)`로 safe-rejected 되었다. 반면 `snapshot-xpc-file-url`은 `WallpaperSnapshotXPC.rawValue = NSURL` reply 이후 `NSCocoaErrorDomain(4099)`, XPC interruption/invalidation, runtime removal을 유발할 수 있으므로 unsafe candidate로 격리한다. 이 모드는 기본 install 경로에서 차단하고, 명시적인 unsafe 허용 플래그가 있을 때만 재현 실험에 사용한다.

## Probe Mode Configuration

WallpaperAgent가 extension을 직접 launch하므로 runtime environment variable에 의존하지 않는다.

dev runner가 build 전에 generated Swift source를 만든다:

```text
MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallSnapshotProbeMode.generated.swift
```

generated source는 현재 실험 mode만 포함한다:

```swift
enum MacWallSnapshotProbeMode: String, Sendable {
    case disabled
    case error
    case emptyObject = "empty-object"
    case rawValueRetainedIOSurface = "raw-value-retained-iosurface"
    case boxRetainedIOSurface = "box-retained-iosurface"
    case pngData = "png-data"
    case fileURL = "file-url"
    case snapshotXPCFileURL = "snapshot-xpc-file-url"
}

enum MacWallSnapshotProbeConfiguration {
    static let mode: MacWallSnapshotProbeMode = .disabled
}
```

`dev.sh install --snapshot-mode <mode>`가 이 파일을 갱신하고 build/register를 수행한다. 기본값은 `disabled`다.

## Logging Contract

각 lifecycle 요청은 한 줄 summary를 남긴다.

필수 필드:

- `event`
- `session`
- `pid`
- `wallpaperID`
- `role`
- `mode`
- `contextID`
- `replyType`
- `result`
- `errorDomain`
- `errorCode`

예:

```text
snapshotGate event=snapshot-request session=... pid=... wallpaperID=... role=desktop mode=disabled contextID=1432782333
snapshotGate event=snapshot-reply session=... pid=... wallpaperID=... role=desktop mode=disabled replyType=nil result=sent
snapshotGate event=snapshot-agent-error session=... wallpaperID=... errorDomain=WallpaperExtensionKit errorCode=2
```

기존 verbose introspection 로그는 유지하되, gate 판단에는 summary log를 우선 사용한다.

## Failure Model

| Failure | 의미 | 다음 행동 |
| --- | --- | --- |
| extension crash | candidate가 unsafe | mode를 disabled로 되돌리고 crash report 기록 |
| `WallpaperExtensionError(2)` | nil/unsupported reply | candidate 유지하지 않고 다음 candidate로 진행 |
| `NSCocoaErrorDomain 4101` | XPC encode/decode shape mismatch | class layout / allowed classes / encode path 조사 |
| update/invalidate `4099` | extension connection interrupted | 직전 candidate가 `snapshot-xpc-file-url`이면 unsafe로 분류하고 safe baseline으로 복구 |
| screen black after candidate | WallpaperAgent runtime fallout | reset/install 후 baseline 복구 확인 |
| video stops without crash | lifecycle cleanup 또는 invalidation issue | snapshot과 별도 lifecycle bug로 분류 |

## Human Verification Gate

아래 작업은 사용자가 직접 확인한다.

- System Settings에서 `MacWall Native Spike` 선택/재선택
- 실제 Desktop 출력 확인
- 검은 화면 여부 확인
- 영상 움직임 여부 확인
- Fullscreen -> Desktop red-pill 확인

이 경우 agent는 로그 확인 후 사용자에게 확인을 요청하고 응답을 종료한다.

## Acceptance Criteria

Gate 성공:

- `disabled` baseline에서 crash 없이 Desktop video가 유지됨
- candidate별 결과가 logs와 development log에 기록됨
- 최소 하나의 non-nil snapshot reply가 extension crash 없이 WallpaperAgent에 전달됨
- `WallpaperExtensionError(2)`가 제거되거나, 제거 불가 원인이 reply shape mismatch로 명확히 분류됨

Gate 보류:

- 모든 non-nil candidate가 crash 또는 4101로 실패
- Desktop video runtime은 안정 유지
- snapshot/export는 native integration의 blocker가 아니라 export-only limitation으로 기록

Gate 실패:

- `disabled` baseline에서도 extension crash가 재현됨
- snapshot 요청이 Desktop video runtime을 반복적으로 깨뜨림
- reset/install 후에도 stale process나 old build 혼입을 통제할 수 없음

## 다음 단계

이 spec의 implementation plan은 다음 작업만 다룬다.

1. probe mode generated source 추가
2. summary log 추가
3. candidate matrix를 한 번에 하나씩 실행 가능한 구조로 분리
4. dev runner reset/install/logs/status 검증 강화
5. development log 기록

비디오 품질, timestamp, pixel format, 실제 video snapshot export는 이 gate 이후 별도 spec에서 다룬다.
