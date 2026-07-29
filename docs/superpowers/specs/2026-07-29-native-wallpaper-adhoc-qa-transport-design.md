# macOS 26 Native Wallpaper AdHocQA Transport Design

작성일: 2026-07-29

상태: 설계 승인 / 구현 계획 작성 전

## 목적

유효한 Apple development signing identity와 provisioning profile이 없는 로컬 환경에서도 MacWall Main App과 embedded Native Wallpaper Extension 사이의 production runtime protocol을 검증할 수 있는 개발 전용 transport를 추가한다.

현재 확인된 상태:

- WallpaperAgent가 production extension을 발견하고 launch한다.
- `connect`와 `provideSettingsViewModels` handshake가 성공한다.
- Host와 Extension을 ad-hoc signing할 수 있다.
- `group.com.mingyu1715.macwall` App Group 접근은 `NSCocoaErrorDomain 513` / `Operation not permitted`로 실패한다.
- Host와 Extension의 ad-hoc signature에는 유효한 Team Identifier가 없다.

Apple의 `group.` App Group은 provisioning profile authorization이 필요하다. 따라서 entitlement 문자열만 보존한 ad-hoc signature로 production App Group transport를 검증하는 방식은 사용하지 않는다.

참고:

- [Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [App Sandbox temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)

## 핵심 원칙

- 개발용 우회는 `AdHocQA` build configuration과 전용 scheme에서만 활성화한다.
- 일반 `Debug`와 `Release`는 기존 App Group transport만 사용한다.
- App Group 접근 실패를 감지해 개발용 경로로 자동 전환하지 않는다.
- command, status, generation, atomic file replacement protocol은 변경하지 않는다.
- 변경되는 것은 runtime root를 결정하는 transport boundary뿐이다.
- proper Apple signing과 provisioning이 준비되면 production transport를 그대로 검증한다.

## 범위

포함:

- `AdHocQA` 전용 build configuration과 scheme
- 명시적인 runtime transport mode
- QA 전용 shared home-relative runtime root
- Extension의 QA 전용 최소 Sandbox temporary exception
- QA reset/install/status/logs runner
- transport root, protocol round trip, build configuration 분리 검증

제외:

- production App Group identifier 변경
- Debug/Release의 자동 fallback
- Native Wallpaper handshake 또는 frame renderer 변경
- playback timing, video quality, pixel format 최적화
- snapshot/export gate
- Web/Scene native surface
- Legacy backend와 desktop fallback 정책
- Main App UI 및 사용자 동작 변경
- release packaging, DMG, notarization, `dist`
- System Settings 자동 조작과 실제 Desktop 화면 자동 검증

## 접근 방식 비교

### A. Shared home-relative path와 QA 전용 temporary exception

판단: 채택

Host와 Extension이 다음 경로를 공유한다.

```text
~/Library/Application Support/MacWall/NativeRuntimeAdHocQA
```

Host는 sandboxed app이 아니므로 해당 경로를 직접 사용한다. Extension의 `AdHocQA` entitlements에는 위 디렉터리 하나에 대한 home-relative read/write temporary exception만 둔다.

장점:

- 현재 파일 기반 runtime protocol을 그대로 검증한다.
- production 구현과 차이가 runtime root resolution으로 제한된다.
- ad-hoc signing 환경에서도 별도 App Group provisioning 없이 시험할 수 있다.

비용과 위험:

- temporary exception은 개발 검증 전용이며 배포 정책으로 사용할 수 없다.
- macOS의 undocumented 또는 변경된 Sandbox 동작으로 QA gate 자체가 실패할 수 있다.
- 성공하더라도 production App Group 권한 검증을 대체하지 않는다.

### B. Extension app container를 Host가 직접 사용

판단: 사용하지 않음

Extension container 경로는 bundle identifier와 시스템 container 정책에 의존한다. Host가 다른 app container를 직접 접근하면 macOS 버전별 보호 정책이나 사용자 승인에 걸릴 수 있으며, container layout을 transport contract로 노출한다.

### C. 별도 XPC 또는 localhost transport

판단: 사용하지 않음

App Group을 우회할 수 있지만 production과 다른 protocol, lifecycle, 보안 경계를 새로 만든다. 현재 목표는 기존 generation protocol 검증이므로 비용과 차이가 지나치게 크다.

## Build Configuration

구성별 정책은 다음과 같이 고정한다.

| Configuration | Runtime transport | Host App Group | Extension App Group | QA temporary exception |
| --- | --- | --- | --- | --- |
| Debug | `app-group` | 유지 | 유지 | 없음 |
| Release | `app-group` | 유지 | 유지 | 없음 |
| AdHocQA | `development-home` | 제거 | 제거 | Extension에만 추가 |

`AdHocQA`는 `Debug`를 기반으로 만들되 다음을 독립적으로 지정한다.

- Host와 Extension 모두 같은 transport mode build setting 사용
- Host와 Extension 모두 QA 전용 entitlement 파일 사용
- development team과 provisioning profile을 요구하지 않는 ad-hoc signing
- 사용자에게 설치되는 release artifact를 만들지 않음

권장 build setting:

```text
MACWALL_NATIVE_RUNTIME_TRANSPORT = app-group
MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home
```

각 target의 `Info.plist`는 이 값을 `MacWallNativeRuntimeTransport`로 전달한다. runtime은 이 값을 읽어 transport를 명시적으로 선택한다. 값이 없거나 알 수 없는 값이면 초기화에 실패한다.

## Runtime Transport Boundary

Foundation-only `MacWallNativeRuntimeSupport`에 다음 경계를 둔다.

```text
NativeRuntimeTransportMode
├── appGroup
└── developmentHome

NativeRuntimeRootResolving
└── resolveRoot(for:) -> URL

NativeRuntimeStore.live()
└── mode 확인
    └── resolver로 root 결정
        └── 기존 command/status/generation store 생성
```

규칙:

- `appGroup`은 `group.com.mingyu1715.macwall` container URL만 허용한다.
- `developmentHome`은 `AdHocQA`에서만 허용한다.
- home path는 sandbox가 반환하는 container home을 사용하지 않고 POSIX account home resolver로 실제 사용자 home을 구한다.
- home resolver는 protocol로 주입해 단위 테스트에서 임시 디렉터리를 사용한다.
- runtime root 선택 후의 파일명, JSON schema, generation staging, atomic replace 방식은 기존 구현을 그대로 사용한다.
- 어느 mode에서도 root resolution 실패 후 다른 mode를 재시도하지 않는다.

## QA Sandbox Entitlements

Extension의 QA 전용 entitlement는 다음 권한만 가진다.

```text
com.apple.security.app-sandbox = true
com.apple.security.temporary-exception.files.home-relative-path.read-write
  = /Library/Application Support/MacWall/NativeRuntimeAdHocQA/
```

규칙:

- QA Extension entitlement에는 `com.apple.security.application-groups`를 넣지 않는다.
- QA Host entitlement에도 App Group을 넣지 않는다.
- temporary exception은 사용자 home 전체나 `Library/Application Support` 전체에 부여하지 않는다.
- Debug/Release entitlement에는 temporary exception을 넣지 않는다.
- 정적 검사가 위 조건을 위반하면 build/QA를 실패시킨다.

## Data Flow

`AdHocQA`의 Play 요청은 production과 같은 순서를 사용한다.

```text
Host
-> development-home root resolve
-> immutable generation directory 생성
-> source video staging
-> command manifest atomic replace
-> existing notification/wakeup

Extension
-> same development-home root resolve
-> command/generation 읽기
-> native surface와 video runtime 시작
-> status/heartbeat atomic replace

Host
-> matching generation status 읽기
-> ACK 성공 시 playingNative commit
```

transport mode는 directory layout이나 command schema에 기록해 새로운 protocol version을 만들지 않는다. 대신 Host와 Extension 시작 로그에 mode와 resolved root를 각각 기록해 서로 같은 transport를 사용하는지 확인한다.

## 오류 처리

- transport mode가 없거나 알 수 없으면 runtime store 생성을 실패시킨다.
- POSIX account home을 구하지 못하면 runtime store 생성을 실패시킨다.
- QA root 생성이나 read/write가 거부되면 Cocoa error code, operation, mode, root를 기록한다.
- Host와 Extension transport mode가 다르면 generation ACK timeout으로 숨기지 않고 status/log에서 configuration mismatch를 식별할 수 있어야 한다.
- App Group 또는 다른 directory로 자동 fallback하지 않는다.
- 새 Native Play가 실패하면 기존 playback 유지 정책을 변경하지 않는다.
- QA reset은 QA runtime root와 MacWall의 stale QA processes만 정리한다.
- 일반 Stop은 QA cache/runtime root를 삭제하지 않는다.

## Development Runner

production Main App용 전용 QA runner를 추가한다. Spike runner와 이름 및 경로를 구분한다.

예상 명령:

```text
reset
install
status
logs
```

동작:

- `reset`
  - MacWall production QA Extension의 stale process만 종료
  - 이전 QA app registration 정리
  - `NativeRuntimeAdHocQA` 삭제
- `install`
  - `AdHocQA` configuration build
  - Host와 embedded Extension의 signature/entitlements 검증
  - containing app registration
  - 앱이나 System Settings는 자동 실행하지 않음
- `status`
  - app/extension PID
  - selected transport mode와 root
  - latest generation과 status/heartbeat 요약
- `logs`
  - WallpaperAgent와 production Extension bundle identifier
  - transport, generation, status, Sandbox error 중심 필터

runner는 package, archive, DMG, notarization 또는 `dist` 작업을 수행하지 않는다.

## 검증

자동 및 정적 검증:

1. `NativeRuntimeTransportMode` parsing 테스트
2. 주입한 temporary home을 사용하는 root resolver 테스트
3. QA root에서 command/status atomic round trip 테스트
4. 알 수 없는 mode와 root 생성 실패가 fail-closed인지 테스트
5. Xcode project structure 검사
   - `AdHocQA` configuration과 scheme 존재
   - Host/Extension transport 값 일치
   - QA entitlements에 App Group 없음
   - Debug/Release entitlements에 temporary exception 없음
6. QA runner shell syntax와 source guard 검사
7. `AdHocQA` compile 및 embedded appex 위치 확인
8. ad-hoc signature와 실제 signed entitlements 확인
9. `git diff --check`

runtime 로그 검증:

- Host와 Extension이 모두 `transportMode=development-home` 기록
- 두 process가 같은 resolved root 기록
- matching generation command/status 확인
- heartbeat write 성공
- `NSCocoaErrorDomain 513` 미발생
- WallpaperAgent handshake와 native video enqueue 유지

사용자 검증 gate:

- System Settings에서 MacWall wallpaper 선택
- 실제 Desktop video 출력 확인
- Fullscreen -> Desktop red-pill 확인

사용자 검증이 필요하면 자동 조작하지 않고 사용자에게 확인을 요청한 뒤 중단한다.

## 성공 기준

- `AdHocQA` Host가 QA root에 source와 command를 기록한다.
- production Extension이 같은 generation을 읽고 native video를 시작한다.
- Extension의 status와 heartbeat를 Host가 읽는다.
- App Group 관련 `NSCocoaErrorDomain 513`이 재현되지 않는다.
- existing Native Wallpaper handshake, renderer, playback lifecycle을 수정하지 않는다.
- Debug/Release build는 계속 App Group transport만 사용한다.
- QA temporary exception이 production entitlements나 release artifact에 포함되지 않는다.

## 후속 작업

이 설계는 proper signing을 대체하지 않는다.

유효한 Apple signing identity와 provisioning profile이 준비되면:

1. Debug 또는 별도 signed QA configuration에서 App Group transport를 사용한다.
2. Host와 Extension의 Team Identifier와 App Group authorization을 확인한다.
3. 같은 runtime command/status/generation acceptance test를 반복한다.
4. App Group transport가 통과한 뒤에만 production runtime QA를 완료로 판정한다.
