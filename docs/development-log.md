# Development Log

모든 시간은 Asia/Seoul 기준입니다.

## 2026-06-15

### 01:18 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate 문서화 및 구현 준비
- 변경:
  - `docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md` 추가
  - `docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 추가
  - snapshot/export를 Desktop native video path와 분리된 gate로 정의
  - 안정 baseline은 `disabled` mode로 고정
  - `dev.sh install --snapshot-mode <mode>` 기반 candidate matrix 실행 절차 정리
  - candidate는 `error`, `empty-object`, `raw-value-retained-iosurface`, `box-retained-iosurface`, `png-data` 순서로 한 번에 하나만 실험하도록 제한
- 기준:
  - 구현 시작 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - System Settings 조작 / GUI 실행 없음
  - release packaging / DMG / notarization / dist 작업 없음
- 다음:
  - Task 1부터 구현 시 generated snapshot probe mode를 추가
  - Task 4까지 완료한 뒤에만 사용자 확인이 필요한 manual runtime matrix 진행

### 01:05 KST

- 진행: macOS 26 Native Wallpaper Spike 검은 화면 원인 분류 및 안정 지점 고정
- 확인:
  - 사용자가 재시작 후 검은 화면이 해소되었음을 확인
  - crash report 기준 `MacWallNativeWallpaperExtension`이 `EXC_BAD_ACCESS` / `SIGSEGV`로 종료됨
  - crash 직전 로그 흐름:
    - `WallpaperSnapshotXPC created rawValue surface=...`
    - `snapshot probe reply`
    - WallpaperAgent `NSCocoaErrorDomain (4101)`
    - extension interruption / `ReportCrash`
  - 따라서 검은 화면은 native video bridge 자체 문제가 아니라 snapshot/export rawValue reply와 encode swizzle 경로가 extension을 죽인 뒤 WallpaperAgent runtime이 깨진 상태로 남은 것으로 분류
  - snapshot probe를 비활성화한 새 프로세스에서는:
    - `WallpaperSnapshotXPC encode swizzle disabled`
    - `snapshot probe disabled`
    - WallpaperAgent snapshot export는 `WallpaperExtensionError (2)`로 실패
    - extension crash 없이 `nativeVideoBridge enqueued`가 계속 기록됨
- 변경:
  - `MacWallSnapshotProbe.isEnabled = false`를 기본값으로 추가
  - snapshot probe 비활성화 시 `WallpaperSnapshotXPC` 객체 생성 / rawValue 주입 / encode swizzle을 실행하지 않도록 차단
  - snapshot 요청에는 nil reply를 유지해 Desktop video acquire path를 보호
  - runner source guard test를 snapshot probe 기본 OFF와 encode swizzle 비활성화 로그를 요구하도록 수정
- 현재 정책:
  - Native video wallpaper path는 유지
  - snapshot/export는 crash-prone으로 분류하고 별도 gate에서 재조사
  - Desktop 출력 안정화가 snapshot/export보다 우선
- 검증:
  - RED: runner source guard test가 `MacWallSnapshotProbe.isEnabled = false` 미구현으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperSpikeApp -configuration Debug -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd build` 통과
- 제외:
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - snapshot/export 해결 완료 주장 없음
  - release packaging / DMG / notarization / dist 작업 없음

### 00:48 KST

- 진행: macOS 26 Native Wallpaper Spike snapshot/export 4101 원인 좁힘 및 응답 shape 수정
- 확인:
  - `snapshot probe`는 호출됨
  - `WallpaperSnapshotXPC` instance 생성과 `snapshot probe reply`까지는 성공함
  - WallpaperAgent는 reply 이후 `NSCocoaErrorDomain (4101)`로 snapshot export를 거부함
  - 따라서 실패 원인은 nil reply나 IOSurface 생성 실패가 아니라 `WallpaperSnapshotXPC` XPC encode/decode shape mismatch로 분류
  - runtime class layout 기준 `WallpaperRemoteContextXPC`는 `box@8`, `WallpaperSnapshotXPC`는 `rawValue@8`
- 변경:
  - `WallpaperSnapshotXPC` 생성 시 `rawValue` ivar가 있으면 `object_setIvar`로 `IOSurface` object를 직접 설정
  - `rawValue`가 없을 때만 `box` ivar / raw offset fallback 사용
  - private class layout 로그에 ivar type encoding 포함
  - XPC allowed classes에 `IOSurface.self` 추가
- 검증:
  - RED: runner source guard test가 `rawValue` ivar lookup / `object_setIvar` / `IOSurface` allowlist 미구현으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike` 통과
  - `xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperSpikeApp -configuration Debug -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd build` 통과
- 남은 확인:
  - 실제 `NSCocoaErrorDomain (4101)` 제거 여부는 System Settings에서 MacWall Native Spike를 재선택한 뒤 WallpaperAgent 로그로 확인 필요
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Fullscreen -> Desktop QA 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

### 00:42 KST

- 진행: macOS 26 Native Wallpaper Spike lifecycle 로그 정리
- 확인:
  - 사용자 관측과 로그 기준으로 native video wallpaper 출력은 유지되고 있었음
  - 이후 `WallpaperAgent`의 runtime removal / invalidate는 사용자가 다른 wallpaper로 전환해서 발생한 정상 cleanup 흐름으로 분류
  - snapshot/export 실패는 이번 재현에서 나타나지 않았고 현재 blocker로 보지 않음
- 변경:
  - `dev.sh logs` 기본 predicate를 더 좁혀 `WallpaperAgent` 쪽은 MacWall extension bundle id가 포함된 이벤트만 표시
  - broad `WallpaperExtensionError` / `Wallpaper Timeline` match를 기본 로그에서 제거해 Apple 기본 wallpaper extension 잡음이 섞이지 않도록 함
  - native wallpaper context role을 `desktop`, `preview`, `unknown`으로 분리
  - acquire / store / stop / remove 로그에 `role`, `contextID`, replacement 여부, previous context 정보를 남김
  - desktop context에만 `NativeVideoFrameBridge`를 붙이고 preview/unknown context는 영상 bridge를 만들지 않도록 명시
- 검증:
  - RED: runner test가 broad `WallpaperExtensionError` / `Wallpaper Timeline` predicate 때문에 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike` 통과
  - `xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperSpikeApp -configuration Debug -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd build` 통과
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Fullscreen -> Desktop QA 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

### 00:27 KST

- 진행: macOS 26 Native Wallpaper Spike snapshot/export gate 진단 보강
- 확인:
  - 최근 extension subsystem 로그에는 snapshot 재현 로그가 남아 있지 않고, XPC invalidation 로그만 확인됨
  - `WallpaperExtensionKit.framework` wrapper는 존재하지만 binary symlink는 현재 시스템에서 dyld shared cache 기반으로 보이며 직접 `strings` / `nm` 분석은 불가
  - 따라서 `WallpaperSnapshotXPC` 구조는 로컬 파일 분석보다 런타임 class introspection 로그로 확인하는 편이 맞음
- 변경:
  - `dev.sh logs` predicate를 좁혀 RunningBoard 같은 무관 로그가 섞이지 않도록 수정
  - `MACWALL_NATIVE_DRY_RUN=1 ./dev.sh logs --last 1m`이 실제 `/usr/bin/log`를 실행하지 않고 command만 출력하도록 수정
  - `WallpaperRemoteContextXPC`와 `WallpaperSnapshotXPC` private class layout을 한 번만 로그로 남기는 runtime introspection 추가
  - `WallpaperSnapshotXPC` surface pointer write offset을 hardcoded `8` 우선이 아니라 `box` ivar offset 우선, 없을 때만 `8` fallback으로 변경
- 검증:
  - RED: dry-run `logs` test가 sandboxed `/usr/bin/log` 실행 때문에 실패함을 확인
  - RED: snapshot source guard test가 `WallpaperSnapshotXPC` `box` ivar lookup 미구현으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike` 통과
  - `xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperSpikeApp -configuration Debug -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd build` 통과
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Fullscreen -> Desktop QA 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

## 2026-06-14

### 23:55 KST

- 진행: macOS 26 Native Wallpaper Spike dev runner 구축
- 변경:
  - `MacWallNativeWallpaperSpike/dev.sh` 추가
  - `reset`, `install`, `status`, `logs` 명령 제공
  - `reset`은 기본적으로 stale `MacWallNativeWallpaperExtension` process만 정리하고 `WallpaperAgent`는 명시 옵션 없이는 종료하지 않음
  - `install`은 CMake project 생성, Xcode build, codesign verification, LaunchServices registration을 수행
  - `status`는 build path, app path, `WallpaperAgent` / extension process, 최근 session log를 출력
  - `logs`는 `WallpaperAgent`, MacWall extension subsystem, extension bundle id 기준으로 `log show` / `log stream` 지원
  - `MACWALL_NATIVE_DRY_RUN=1`과 `MACWALL_NATIVE_FAKE_PS_FILE`을 추가해 실제 process 변경 없이 runner 동작을 테스트할 수 있게 함
- 문서:
  - `MacWallNativeWallpaperSpike/README.md`
  - `docs/development-guide.md`
- 검증:
  - RED: `MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 runner 미구현 상태에서 실패함을 확인
  - GREEN: runner 구현 후 dry-run 기반 runner test 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `MACWALL_NATIVE_DRY_RUN=1 MacWallNativeWallpaperSpike/dev.sh install` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install` 실제 실행 통과
  - `MacWallNativeWallpaperSpike/dev.sh status` 실행 통과
  - `MacWallNativeWallpaperSpike/dev.sh logs --last 1m` 실행 통과
  - 실제 `reset`은 사용자 화면 상태에 영향을 줄 수 있으므로 dry-run fixture로만 검증
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

## 2026-06-12

### 22:32 KST

- 확정: macOS 26 Native Wallpaper Spike 성공 상태 고정
- 사용자 확인:
  - `WallpaperExtensionKit` path로 third-party `com.apple.wallpaper` extension이 발견되고 실행됨
  - `WallpaperAgent`가 MacWall extension process를 launch함
  - connect handshake, `provideSettingsViewModels`, acquire request가 통과함
  - `CAContext.remoteContext`와 `WallpaperRemoteContextXPC`를 통해 native Desktop wallpaper surface가 생성됨
  - `AVSampleBufferDisplayLayer` 출력이 native Desktop surface에 표시됨
  - bundled sample mp4가 `AVAssetReader`를 통해 실제 Desktop wallpaper로 재생됨
  - Fullscreen -> Desktop 복귀 시 기존 `NSWindow` backend에서 보이던 시스템 배경화면 빨간약 문제가 native path에서 해결됨
- 핵심 발견:
  - 목표는 단순 Video Wallpaper가 아니라 macOS native wallpaper runtime 진입임
  - `WallpaperAgent`는 사실상 frame consumer로 동작할 수 있음
  - 유지할 구조는 `Renderer -> Frame -> Native Wallpaper Backend -> WallpaperAgent`
  - Video, Scene, Web renderer는 이 구조 앞단의 frame producer로 취급해야 함
- 성공 조건:
  - macOS 26+
  - Apple Silicon
  - sandboxed containing app + embedded `com.apple.wallpaper` ExtensionKit appex
  - user가 System Settings에서 MacWall Native Spike를 직접 선택
  - stale extension process를 reset한 뒤 install/register된 빌드를 사용
  - sample mp4 resource가 extension bundle에 포함되어 있음
- 정책:
  - Native Wallpaper Backend는 macOS 26 이상에서만 공식 지원 후보로 둠
  - 기존 `NSWindow` backend는 fallback 용도로 유지
  - 호환성 확대보다 성공 상태 보존과 안정화를 우선
  - `MacWallNativeWallpaperSpike`는 아직 연구용 spike 프로젝트로 유지하고 Main App 통합은 시작하지 않음
  - 라이선스 결정은 아직 확정하지 않고 기능 안정화, 구조 정리, 모듈 분리 이후 결정
  - NativeWallpaperBackend / WallpaperAgent Integration / Native Pipeline / Renderer Pipeline / 향후 Scene Engine은 별도 라이선스 후보 영역으로 기록
  - Core / UI / Settings / Legacy Backend / 공용 인터페이스 / 연결 코드는 MIT 유지 가능 영역으로 기록
- 문서:
  - [라이선스 정책](license-policy.md)
- 남은 문제:
  - snapshot/export 단계의 `WallpaperExtensionError(2)` / `NSCocoaErrorDomain 4101`은 Desktop 출력 성공과 별개로 조사 필요
  - 색감, 배속, 화질 문제는 Color Space, Pixel Format, YUV/RGB 변환, PTS/DTS, timestamp offset, enqueue timing 기준으로 분리 조사
  - dev runner/reset/log/status 도구가 없어 수동 reset/install 절차가 필요
- 다음 우선순위:
  - 현재 spike 상태 git commit 및 tag 생성
  - dev runner/reset 환경 구축
  - snapshot/export 4101 조사
  - 색감/배속/화질 조사

## 2026-06-09

### 02:08 KST

- 진행: macOS 26 Native Wallpaper Spike 실제 mp4 source 테스트 준비
- 변경:
  - `MacWallNativeWallpaperVideoSource`를 추가해 bundled sample mp4 resource를 찾는 경로를 분리했습니다.
  - CMake spike가 `test/3589742531/【哲风壁纸】夕阳花海-短发-等待.mp4`를 찾으면 `macwall-native-wallpaper-sample.mp4`라는 ASCII resource name으로 extension bundle에 조건부 포함합니다.
  - `NativeVideoFrameBridge`를 generated frame source와 asset URL source로 분리했습니다.
  - Desktop/live acquire에서는 bundled mp4가 있으면 `AVURLAsset` + `AVAssetReader` + `AVAssetReaderTrackOutput`으로 sample buffer를 읽어 `AVSampleBufferDisplayLayer`에 enqueue합니다.
  - bundled mp4가 없거나 reader/display layer 실패 시 기존 generated-frame probe로 fallback합니다.
  - preview surface는 기존처럼 단색 preview probe를 유지합니다.
- 검증:
  - RED: `MacWallNativeWallpaperVideoSource` 미구현 상태에서 resolver 테스트가 컴파일 실패하는 것을 확인
  - GREEN: `MacWallNativeWallpaperRuntimeIdentityTests` build 통과
  - GREEN: `/tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperRuntimeIdentityTests` 실행 통과
  - GREEN: `MacWallNativeWallpaperSpikeApp` containing app + embedded appex build 통과
  - GREEN: `codesign --verify --deep --strict /tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperSpikeApp.app` 통과
  - 확인: embedded appex resource에 `macwall-native-wallpaper-sample.mp4`가 71MB로 포함됨
- 사용자 검증 필요:
  - System Settings에서 MacWall Native Spike 재선택 후 실제 mp4 화면 출력 여부 확인
  - 이후 WallpaperAgent / extension 로그로 assetReader start/enqueue 여부 확인
- 제외:
  - 기존 `NSWindow` backend 수정 없음
  - fallback 정책 수정 없음
  - snapshot/export 4101 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

### 01:37 KST

- 진행: macOS 26 Native Wallpaper Spike lifecycle/logging 안정화
- 변경:
  - `MacWallNativeWallpaperRuntimeIdentity`를 추가해 extension process마다 `session`, `pid`, bundle id, executable, build marker를 로그에 남깁니다.
  - `acquire`, `WallpaperAgent` XPC connection accept/invalidation, remote context store/remove, snapshot reply, video bridge attach/start/frame/stop 로그에 runtime/session 식별자를 추가했습니다.
  - `MacWallRemoteWallpaperContext.stop(reason:)`을 idempotent하게 만들어 `invalidate`, XPC invalidation, context replacement, deinit이 겹쳐도 같은 context를 한 번만 정리합니다.
  - context stop 시 video bridge stop, display layer removal, root layer sublayer/background cleanup을 수행합니다.
  - `NativeVideoFrameBridge`도 `bridgeID`와 `didStop`을 가져 중복 stop을 로그로 분리합니다.
  - `MacWallNativeWallpaperRuntimeIdentityTests` executable test target을 CMake spike에 추가했습니다.
- 검증:
  - RED: runtime identity test target이 `MacWallNativeWallpaperRuntimeIdentity` 미구현으로 컴파일 실패하는 것을 확인
  - GREEN: `MacWallNativeWallpaperRuntimeIdentityTests` build 통과
  - GREEN: `/tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperRuntimeIdentityTests` 실행 통과
  - GREEN: `MacWallNativeWallpaperSpikeApp` containing app + embedded appex build 통과
- 제외:
  - 앱 실행 / GUI 실행 없음
  - System Settings 조작 없음
  - fallback 정책 변경 없음
  - 기존 `NSWindow` backend 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음

## 2026-06-08

### 16:48 KST

- 결정: macOS 26 Native Wallpaper Spike 실행 규칙 고정
- 이유:
  - `WallpaperAgent`가 native wallpaper extension process를 소유하므로 containing app을 `open`으로 실행/종료하는 것을 테스트 lifecycle로 볼 수 없습니다.
  - host app 종료 후에도 extension process가 남아 old/new build나 preview/desktop context가 섞여 보일 수 있습니다.
- 규칙:
  - 전용 runner를 만들기 전까지 `dev reset -> dev install -> 사용자 System Settings 선택 -> 로그 확인 -> 사용자 화면 확인 -> 재테스트 전 reset/install` 순서만 사용합니다.
  - `open` 직접 실행/종료는 clean test run으로 인정하지 않습니다.
  - 실제 화면 상태 확인과 Fullscreen -> Desktop 빨간약 검증은 사용자가 직접 수행합니다.
- 문서:
  - `docs/development-guide.md`
  - `AGENTS.md`
  - `MacWallNativeWallpaperSpike/README.md`
  - `docs/superpowers/plans/2026-06-07-macos-26-native-wallpaper-mode-spike.md`

### 01:14 KST

- 진행: macOS 26 native wallpaper remote `CAContext` acquire probe
- 구현:
  - `CAContext.remoteContextWithOptions` / `remoteContext`를 ObjC runtime으로 생성
  - `WallpaperCreationRequestXPC`의 destination size, scale, display id, preview 여부를 Mirror 기반으로 추출
  - 단색/root `CALayer`를 remote `CAContext`에 attach
  - private `WallpaperRemoteContextXPC` class를 생성하고 `contextId`를 `box` ivar 또는 offset 8에 기록
  - acquire 대상 context를 extension process 안에 보관해 조기 deallocation 방지
  - `isChoiceDownloaded` / `canSkipShuffledContent` reply signature를 `NSNumber` 기반으로 수정해 WallpaperAgent XPC signature mismatch를 제거
- 검증:
  - `/opt/homebrew/bin/cmake -S MacWallNativeWallpaperSpike -B /tmp/macwall-native-wallpaper-spike-xcode -G Xcode` -> passed
  - `xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperSpikeApp -configuration Debug -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd clean build` -> `** BUILD SUCCEEDED **`
  - `codesign --verify --deep --strict /tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperSpikeApp.app` -> passed
  - `WallpaperAgent` 재시작 후 acquire 재검증 -> pass
- 로그 근거:
  - `acquire.id: type=WallpaperIDXPC`
  - `acquire.request: type=WallpaperCreationRequestXPC`
  - `remoteContext request size=(1710.0, 1107.0) scale=2.000000 displayID=Optional(1) isPreview=Optional(false)`
  - `CAContext.remoteContextWithOptions created displayID=1`
  - `CAContext.contextId=405224122`
  - `CAContext.layer attached`
  - `WallpaperRemoteContextXPC created contextID=405224122 offset=8`
  - `remoteContext acquire reply contextID=405224122`
  - `Wallpaper Timeline: Acquire Wallpaper ... END`
- 판단:
  - acquire의 nil reply로 발생하던 `WallpaperExtensionError(2)`는 remote context reply 후 사라짐
  - extension process는 acquire 이후에도 유지됨
  - 남은 `WallpaperExtensionError(2)`는 acquire가 아니라 `snapshot` stub이 nil을 반환해서 export snapshot 단계에서 발생
  - 다음 gate는 generated frame bridge 전에 snapshot/export 요구 타입 또는 native surface 표시 여부를 명확히 확인하는 것이 안전
- 범위 준수:
  - `AVSampleBufferDisplayLayer` / video frame bridge는 시작하지 않음
  - 기존 `NSWindow` backend와 fallback 정책은 수정하지 않음
  - release packaging, DMG, notarization 없음

## 2026-06-07

### 20:14 KST

- 시작: macOS 26 Native Wallpaper Mode spike 설계 및 실행 계획
- 배경:
  - Fullscreen -> Desktop 복귀 빨간약은 custom desktop-level `NSWindow`의 lifecycle 문제가 아니라 WindowServer가 native Desktop Picture layer를 먼저 합성하는 문제로 판단
  - AppKit collection behavior, sticky tag, SLS level override, freeze overlay 실험은 해결책으로 부적합
  - fallback PNG를 원하지 않는 경우 남는 유력한 방향은 `WallpaperExtensionKit` / `WallpaperAgent` native wallpaper pipeline 진입
- 문서:
  - [macOS 26 Native Wallpaper Mode 설계](superpowers/specs/2026-06-07-macos-26-native-wallpaper-mode.md)
  - [macOS 26 Native Wallpaper Mode spike 실행 계획](superpowers/plans/2026-06-07-macos-26-native-wallpaper-mode-spike.md)
- 범위:
  - macOS 26 전용 experimental path
  - 기존 `NSWindow` backend 유지
  - 첫 spike는 Video generated frame / `AVSampleBufferDisplayLayer` 중심
  - macOS 14/15, Web, Scene, CAMetalLayer, fallback PNG 정책 변경은 제외
  - SIP 비활성화, Dock/Finder injection, 시스템 DB 직접 수정 금지
- 문서 정리:
  - `docs/superpowers/specs/`와 `docs/superpowers/plans/`를 활성 설계/계획 위치로 사용
  - roadmap에 P2.5 Native Wallpaper Mode Spike를 추가

### 20:56 KST

- 수정: macOS 26 Native Wallpaper Mode spike 우선순위 재정렬
- 이유:
  - 최고 리스크는 frame rendering이 아니라 third-party `com.apple.wallpaper` extension을 `WallpaperAgent`가 허용하는지 여부
  - 이 gate가 막히면 generated frame / video frame 구현 대부분이 의미 없음
- 반영:
  - 계획에 Task 0 `WallpaperAgent Discovery Observation` 추가
  - Apple 기본 wallpaper extension 등록, `WallpaperAgent` bundle, `pluginkit`, log stream, process state 관찰을 먼저 수행하도록 변경
  - Task 3/4의 MacWall minimal extension discovery/load gate를 Task 1/2 app capability probe보다 먼저 검증할 수 있도록 명시
  - third-party extension이 발견/실행되지 않으면 native surface 구현 전 중단

### 22:03 KST

- 조사: macOS 26 WallpaperAgent discovery observation
- 실행 범위:
  - Apple wallpaper extension plist 확인
  - `WallpaperAgent.app` bundle metadata 확인
  - `pluginkit` 등록 조회 시도
  - 최근 `WallpaperAgent` / `com.apple.wallpaper` unified log 조회
  - `WallpaperAgent`와 Apple wallpaper extension process 상태 확인
- 결과:
  - Apple `com.apple.wallpaper` extension plist 확인: pass
    - `NeptuneOneWallpaper`, `WallpaperAerialsExtension`, `WallpaperDynamicExtension`, `WallpaperGradientExtension`, `WallpaperImageExtension`, `WallpaperLegacyExtension`, `WallpaperMacintoshExtension`, `WallpaperMontereyExtension`, `WallpaperSequoiaExtension`, `WallpaperSonomaExtension`, `WallpaperVenturaExtension`
    - `Wallpaper.appex`는 `com.apple.Settings.extension.ui`로 확인되어 wallpaper provider extension이 아니라 settings UI extension으로 분류
  - `WallpaperAgent` bundle 확인: pass
    - `CFBundleIdentifier = com.apple.wallpaper.agent`
    - `LSUIElement = true`
  - `pluginkit` registration 확인: unavailable
    - `pluginkit -m -A -D -vv`가 `match: Connection invalid`를 반환
    - 이번 환경에서는 `pluginkit`을 신뢰 가능한 discovery source로 사용하지 않음
  - `WallpaperAgent` log에서 extension/provider lifecycle 관찰: pass
    - `com.apple.wallpaper:extension-proxy`에서 Apple extension 대상 `handleNotification`, `selectedChoicesDidChange`, `wallpaper(...) invalidate` 관찰
    - `com.apple.wallpaper:runtime-resolver`에서 `ChoiceDescriptor provider=com.apple.wallpaper.choice.image` 및 runtime update/remove 관찰
    - `com.apple.wallpaper:extension`에서 extension process message enqueue/dequeue 관찰
  - `WallpaperAgent` process 확인: pass
    - `WallpaperAgent` process 실행 중
    - Apple wallpaper extension process들이 별도 실행 중이며 `-LaunchArguments` 안에 service name을 포함
- 판단:
  - Apple native wallpaper extension discovery/runtime flow는 filesystem, process, unified log로 관찰 가능
  - 다음 gate는 MacWall minimal `com.apple.wallpaper` extension이 등록, 발견, 실행되는지 확인하는 Task 3/4
  - native surface / generated frame 구현은 third-party extension discovery/load가 확인되기 전까지 시작하지 않음

### 19:15 KST

- 변경: freeze overlay 실험 기본 비활성화
- GUI 관찰:
  - `.screenSaver` level overlay는 전환 화면 전체를 wallpaper snapshot으로 덮는 부작용이 있었음
  - `WallpaperWindowLevel.desktopWallpaper` level overlay는 fullscreen/app 화면을 과하게 덮는 문제는 줄였지만 Fullscreen -> Desktop 복귀 빨간약은 해결하지 못함
- 판정:
  - notification 기반 freeze overlay는 전환 첫 노출보다 늦거나 같은 Desktop 합성 경로에 묶여 있어 핵심 문제를 해결하지 못함
  - 실행 경로에서는 `DesktopTransitionFreezeOverlayExperiment.isEnabled = false`로 비활성화
  - 코드는 향후 pre-armed overlay나 다른 timing 실험 참고용으로만 보관
- 다음 방향:
  - activeSpaceDidChange 후처리 계열은 1차 해결책으로 부적합
  - fallback PNG 유지/개선 또는 전환 이전에 미리 준비되는 overlay 계열만 다음 실험 후보

### 19:08 KST

- 변경: freeze overlay 실험 level을 `.screenSaver`에서 `WallpaperWindowLevel.desktopWallpaper`로 낮춤
- GUI 관찰:
  - `.screenSaver` level overlay는 유지 자체는 되었지만 전환 중 화면 전체를 MacWall wallpaper snapshot으로 덮음
  - 결과적으로 fullscreen/app/window 내용이 사라지고 wallpaper만 보이다가 전환되는 부작용이 생김
- 해석:
  - high-level overlay는 빨간약을 가리는 대신 정상 전환 콘텐츠까지 가리는 방식이라 실사용 완화책으로 부적합
  - 이 결과는 overlay가 표시 가능한지에 대한 feasibility는 확인했지만, `.screenSaver` level 전략은 실패로 판단
- 수정:
  - freeze overlay window level을 기존 wallpaper window와 같은 `WallpaperWindowLevel.desktopWallpaper`로 변경
  - 의도는 앱/Fullscreen window를 덮지 않고 Desktop background layer 구간에서만 보이는지 확인하는 것
- 다음 GUI 확인:
  - fullscreen/app 화면이 overlay에 의해 사라지지 않는지
  - Fullscreen -> Desktop 복귀 빨간약이 줄어드는지
  - 아무 변화가 없다면 notification 기반 desktop-level overlay도 폐기 후보

### 18:57 KST

- 변경: Fullscreen -> Desktop 복귀 빨간약 완화용 freeze overlay feasibility 실험 추가
- 배경:
  - sticky tag, window level/order 계열 실험은 적용 자체 또는 level 유지가 확인되어도 Fullscreen -> Desktop 복귀 빨간약을 줄이지 못했음
  - 현재 가설은 MacWall window/view/player 생존 문제가 아니라 WindowServer/Desktop Space 재합성 타이밍 문제임
- 구현:
  - MacWall own wallpaper window만 `CGWindowListCreateImage`로 snapshot
  - deprecated direct API 호출 warning을 피하기 위해 CoreGraphics symbol을 `dlopen`/`dlsym`으로 동적 로드
  - `activeSpaceDidChangeNotification` 시점에 짧은 `.screenSaver` level `NSPanel` freeze overlay를 표시
  - overlay는 `canJoinAllSpaces`, `fullScreenAuxiliary`, `ignoresMouseEvents`, `nonactivatingPanel` 조합
  - 기본 표시 시간은 450ms이며 timeout 후 자동 close
  - Stop Playback 시 overlay를 즉시 clear
- 범위:
  - Dock/Finder injection 없음
  - SIP 비활성화 요구 없음
  - 시스템 wallpaper DB/설정 변경 없음
  - fallback PNG 적용 로직 변경 없음
  - core playback lifecycle 변경 없음
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchShowsFreezeOverlayOnActiveSpaceChange` -> passed
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `23 tests, 0 failures`
  - `swift test` -> `149 tests, 0 failures`
- GUI 확인:
  - `freezeOverlay operation=snapshot ... result=ok`
  - `freezeOverlay operation=present ... count=...`
  - Fullscreen -> Desktop 복귀 빨간약 변화 여부
  - overlay가 너무 늦게 뜨거나 검은 화면/이전 프레임으로 보이는지
- 한계:
  - `activeSpaceDidChangeNotification` 자체가 전환 첫 프레임보다 늦을 수 있으므로 첫 노출을 완전히 막는 해결책은 아닐 수 있음
  - 이 실험은 high-level freeze panel이 notification 이후 보이는 구간을 가릴 수 있는지 확인하는 단계임

### 18:44 KST

- 변경: SLS window level 실험에서 AppKit `NSWindow.level`도 target level로 설정
- 배경:
  - 이전 실험에서 `SLSSetWindowLevel`은 성공했지만 AppKit/WindowServer 동기화로 기존 `desktopIconWindow - 1` level로 되돌아감
- 구현:
  - window 생성 시 기본 `WallpaperWindowLevel.desktopWallpaper` 설정 후 실험 flag가 켜져 있으면 `NSWindow.Level(rawValue: Int(WindowServerWindowLevelExperiment.targetLevel))`로 재설정
  - `SLSSetWindowLevel`에는 original level로 `WallpaperWindowLevel.desktopWallpaper.rawValue`를 명시 전달
  - window close 시 AppKit `window.level`도 `WallpaperWindowLevel.desktopWallpaper`로 복원 후 SLS level restore 수행
- 의도:
  - AppKit이 level을 재동기화하더라도 target level이 유지되는지 확인
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchAppliesDockHostAdjacentLevelWithoutStickyTag` -> passed
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `22 tests, 0 failures`
  - `swift test` -> `148 tests, 0 failures`
- GUI 확인:
  - `window[0] level=-2147483621`로 찍히는지
  - `windowLevelVerify label=100ms-after-apply observedLevel=-2147483621`로 유지되는지
  - active-space-change의 `MacWallWallpaper slsLevel`이 `-2147483621`로 유지되는지
  - Fullscreen -> Desktop 복귀 빨간약 변화 여부
- GUI 관찰:
  - `immediate-after-apply`와 `100ms-after-apply` 모두 `observedLevel=-2147483621` 유지 확인
  - Fullscreen -> Desktop 복귀 빨간약은 그대로 재현됨
  - 첨부 active-space-change slice에는 `MacWallWallpaper` 줄이 빠져 있어 전환 샘플의 MacWall level은 해당 slice만으로 확정할 수 없음
  - 다만 level 유지 성공 후에도 visual issue가 그대로이므로 window level/order 계열은 실사용 개선 가능성이 낮아짐
  - 다음 실험은 freeze overlay feasibility로 전환하는 것이 합리적

### 03:17 KST

- 변경: SLS window level 실험의 유지 여부 진단 보강
- 배경:
  - 실행 초반 `SLSSetWindowLevel`은 `targetLevel=-2147483621 result=ok`로 성공했음
  - 이후 active-space-change window map에서는 MacWall wallpaper window가 다시 `slsLevel=-2147483604`로 관찰됨
  - level set은 성공하지만 AppKit/WindowServer reorder 또는 level synchronization으로 원복될 가능성이 높음
- 구현:
  - `SLSSetWindowLevel` 적용 직후 두 번째 `orderFrontRegardless()` 제거
  - `SLSGetWindowLevel`로 immediate-after-apply level verification 로그 추가
  - 적용 100ms 뒤 `SLSGetWindowLevel` verification 로그 추가
  - restore 시 immediate-after-restore verification 로그 추가
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchAppliesDockHostAdjacentLevelWithoutStickyTag` -> passed
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `22 tests, 0 failures`
  - `swift test` -> `148 tests, 0 failures`
- 다음 GUI 확인:
  - `windowLevelVerify label=immediate-after-apply ... observedLevel=...`
  - `windowLevelVerify label=100ms-after-apply ... observedLevel=...`
  - active-space-change의 MacWall `slsLevel`이 어느 시점에서 `-2147483604`로 돌아오는지
- GUI 관찰:
  - SLS level 적용은 성공하지만 곧 기존 AppKit `NSWindow.level` 값으로 다시 동기화됨
  - `desktopWindow + 2` level 유지 실험은 실패
  - 다음은 NSWindow level 자체를 target level로 맞추는 실험 또는 freeze overlay feasibility로 넘어가야 함

### 03:03 KST

- 변경: Fullscreen -> Desktop 복귀 빨간약 조사용 SLS window level 실험 추가
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 구현:
  - 이전 sticky tag 실험은 실제 적용 비활성화
  - MacWall wallpaper own window에만 `SLSSetWindowLevel` 또는 `CGSSetWindowLevel` 적용 시도
  - target level은 `CGWindowLevelForKey(.desktopWindow) + 2`
  - 의도는 기존 `desktopIconWindow - 1`보다 Dock desktop host/backing layer에 가까운 level에서 transition compositor 참여가 달라지는지 확인
  - 적용 성공 시 `close()`에서 원래 NSWindow level로 복원
  - symbol 없음 / 호출 실패 시 로그만 남기고 기존 NSWindow playback 유지
- 범위:
  - Dock/Finder injection 없음
  - SIP 비활성화 요구 없음
  - 시스템 wallpaper 설정/DB 변경 없음
  - fallback PNG 로직 변경 없음
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchAppliesDockHostAdjacentLevelWithoutStickyTag` -> passed
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `22 tests, 0 failures`
  - `swift test` -> `148 tests, 0 failures`
- GUI 확인 포인트:
  - `windowLevel operation=applyDockHostAdjacentLevel ... result=ok`
  - active-space-change window map에서 MacWall `slsLevel`이 `desktopWindow + 2`로 바뀌는지
  - Fullscreen -> Desktop 복귀 빨간약 변화 여부
- GUI 관찰:
  - Fullscreen -> Desktop 복귀 빨간약은 그대로 재현됨
  - 첨부 로그에서 MacWall wallpaper window `cgLayer`/`slsLevel`은 계속 `-2147483604`
  - target인 `desktopWindow + 2` 근처 level로 실제 변경된 증거가 없음
  - pasted slice 안에는 `windowLevel operation=applyDockHostAdjacentLevel` 로그도 보이지 않음
  - 이후 추가 로그에서 `SLSSetWindowLevel` 자체는 `result=ok`였음이 확인됨
  - 현재 판정은 "level set 성공 후 active-space-change 전/중에 기존 level로 되돌아감" 가능성이 더 높음

### 02:54 KST

- 완료: Fullscreen -> Desktop 복귀 빨간약 조사용 sticky window tag 실험 코드 추가
- 변경:
  - MacWall wallpaper own window에만 `SLSSetWindowTags` low word `1 << 11` 적용을 시도합니다.
  - wallpaper window `close()` 시 적용된 sticky tag를 `SLSClearWindowTags`로 정리합니다.
  - SkyLight symbol이 없거나 private API 호출이 실패하면 로그만 남기고 기존 NSWindow playback은 유지합니다.
- 범위:
  - Dock/Finder injection 없음
  - SIP 비활성화 요구 없음
  - 시스템 wallpaper 설정/DB 변경 없음
  - fallback PNG 로직 변경 없음
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchCanApplyAndClearOwnWindowStickyTag` -> passed
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `21 tests, 0 failures`
  - `swift test` -> `147 tests, 0 failures`
- GUI 관찰:
  - Fullscreen -> Desktop 복귀 빨간약은 그대로 재현됨
  - sticky tag `1 << 11` 단독 적용은 transition compositor 참여 개선에 효과 없음
  - 다음 실험은 무작위 tag 복사가 아니라 window order/level 관계 또는 freeze overlay feasibility로 분리해야 함

### 02:41 KST

- 변경: SwiftUI `Publishing changes from within view updates is not allowed` 경고 완화
- 근거:
  - 첨부 로그의 WebContent sandbox/TCC/RunningBoard 메시지는 WKWebView/WebContent sandbox 환경에서 나오는 시스템 로그 성격이 강함
  - 앱 코드 수정 후보는 SwiftUI publish 경고이며, `ContentView`/`StatusMenu`가 `@Published` ViewModel property와 `List(selection:)` setter를 view update 중 즉시 갱신하는 경로가 있었음
- 구현:
  - `viewDeferredBinding` helper 추가
  - `ContentView`의 Toggle, Picker, List selection model write를 deferred main-actor update로 변경
  - `StatusMenu` Toggle model write도 같은 helper로 변경
  - `WallpaperDisplayMode`를 `Sendable`로 명시
- 검증:
  - `swift test --filter SwiftUIViewBindingTests` -> 통과
  - `swift test --filter AppViewModelTests` -> `19 tests, 0 failures`
  - `swift test` -> `146 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI 콘솔 로그 재확인

### 02:35 KST

- 변경: Fullscreen -> Desktop 복귀 빨간약 조사 1단계 read-only WindowServer map 진단 추가
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 범위:
  - active Space 변경 시 기존 playback/window/renderer 샘플 로그에 WindowServer window map 로그 추가
  - Dock, Finder, Desktop/Wallpaper/Picture 명칭 window, desktop level band, MacWall wallpaper window 후보를 필터링해 출력
  - 각 후보의 `windowNumber`, owner, name, CG layer, SLS level, SLS iterator level, SLS tags, SLS attributes, SLS spaces, onscreen, alpha, bounds 출력
  - SkyLight private symbol은 `dlopen`/`dlsym`으로 런타임에만 조회하며 실패 시 `unavailable`로 남김
- 하지 않음:
  - sticky tag 적용 없음
  - window level/sublevel/order 변경 없음
  - fallback PNG 적용 로직 변경 없음
  - 사용자 wallpaper 설정 변경 없음
  - 앱 실행 / GUI QA 없음
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchLogsSpaceReturnWindowAndRendererDiagnostics` -> 통과
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `20 tests, 0 failures`
  - `swift test` -> `145 tests, 0 failures`
- 다음 확인:
  - 실제 GUI 전환 QA에서 `windowMapSummary`와 `windowMap[...]` 로그를 비교해 Dock/Finder/Desktop Picture/MacWall z-order, Space membership, tags 관계 확인

## 2026-06-06

### 02:10 KST

- 변경: Fullscreen -> Desktop 복귀 빨간약 원인 분리용 playback/window 진단 로그 추가
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 가설:
  - 현재는 WindowServer/Desktop 복귀 재합성 지연 가설이 가장 유력
  - 확인 대상은 window/view/renderer/frame progression이 복귀 중 계속 살아있는지 여부
- 구현:
  - `NSWorkspace.activeSpaceDidChangeNotification` 수신 시 즉시, 100ms, 300ms, 800ms, 1500ms 샘플 로그 출력
  - player/session/window count/app occlusion 상태 출력
  - 각 wallpaper window의 `windowNumber`, `isVisible`, `isOnActiveSpace`, `occlusionState`, level, collection behavior, content attach 상태 출력
  - `CGWindowListCopyWindowInfo`로 WindowServer dictionary의 `kCGWindowLayer`, `kCGWindowIsOnscreen`, alpha, owner, bounds 출력
  - Video renderer는 AVPlayer rate/timeControlStatus/currentTime/itemStatus/AVPlayerLayer 상태 출력
  - Web renderer는 WKWebView 상태와 `requestAnimationFrame` counter 출력
- 해석 기준:
  - 복귀 중 currentTime/frame counter가 증가하고 window/content가 attached인데 `isOnActiveSpace`, occlusion, CG onscreen/layer가 늦게 바뀌면 WindowServer/Desktop Space 재합성 지연 쪽 근거
  - renderer 시간이 멈추거나 view/window attach가 끊기면 앱 내부 lifecycle 문제로 재조사
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchLogsSpaceReturnWindowAndRendererDiagnostics` -> 통과
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `20 tests, 0 failures`
  - `swift test --filter RestrictedWebWallpaperViewTests` -> `3 tests, 0 failures`
  - `swift test --filter WebDesktopFallbackSnapshotterTests` -> `5 tests, 0 failures`
  - `swift test` -> `145 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI fullscreen swipe QA

### 01:51 KST

- 변경: fullscreen Space 전환 실험 3차
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 변경:
  - wallpaper window `collectionBehavior`에 `.canJoinAllApplications` 추가
  - 유지: `.canJoinAllSpaces`, `.ignoresCycle`, `.fullScreenAuxiliary`
  - 제외 유지: `.stationary`
  - Desktop Fallback runtime side effect 비활성화 유지
- 관찰 기반:
  - `.stationary` 제거 후 Desktop -> Fullscreen 진입은 완전 해결
  - 전환 중 live playback이 멈추지 않고 계속 재생됨
  - Fullscreen -> Desktop 복귀는 아직 미해결
- 의도:
  - desktop-level window가 모든 application Space에 더 강하게 소속될 때 복귀 경로가 개선되는지 확인
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchWallpaperWindowsJoinAllApplications` -> 통과
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `19 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI fullscreen swipe QA

### 01:44 KST

- 변경: fullscreen Space 전환 실험 2차
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 변경:
  - wallpaper window `collectionBehavior`에서 `.stationary` 제거
  - 유지: `.canJoinAllSpaces`, `.ignoresCycle`, `.fullScreenAuxiliary`
- 관찰 기반:
  - Desktop -> Fullscreen 진입은 `.fullScreenAuxiliary`가 끝까지 따라오는 긍정적 결과 확인
  - Fullscreen -> Desktop 복귀에서 빨간약이 남아 `.stationary` 비대칭 영향 가능성을 분리 실험
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testExperimentBranchWallpaperWindowsDoNotUseStationaryCollectionBehavior` -> 통과
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `18 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI fullscreen swipe QA

### 01:40 KST

- 변경: `experiment/fullscreen-auxiliary-window` 브랜치에서 Desktop Fallback runtime side effect 비활성화
- 범위:
  - Play/Apply 성공 후 `desktop-fallback.png` 적용/생성 호출 중단
  - Space Refresh active asset 연결 중단
  - Stop Playback의 original wallpaper restore 호출 중단
  - Restore on Stop UI와 Library Generate/Regenerate fallback 메뉴는 runtime flag 뒤로 숨김
- 의도:
  - Desktop Fallback 없이 `.fullScreenAuxiliary` window behavior만 fullscreen Space 전환에서 실험
- 검증:
  - `swift test --filter AppViewModelTests/testExperimentBranchPlayDoesNotApplyDesktopFallback` -> 통과
  - `swift test --filter AppViewModelTests` -> `19 tests, 0 failures`
  - `swift test --filter DesktopFallbackMenuTests` -> `4 tests, 0 failures`
  - `swift test` -> `142 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI fullscreen swipe QA

### 01:33 KST

- 시작: fullscreen Space 전환 빨간약 완화 실험
- 브랜치: `experiment/fullscreen-auxiliary-window`
- 변경:
  - wallpaper window level은 기존 `desktopIconWindow - 1` 유지
  - `NSWindow.collectionBehavior`에 `.fullScreenAuxiliary` 추가
- 의도:
  - Desktop Fallback 제거가 아니라, fullscreen Space 전환 애니메이션에서 live wallpaper window가 더 자연스럽게 참여하는지 확인
- 검증:
  - `swift test --filter WallpaperPlayerSuspensionTests/testWallpaperWindowsJoinFullScreenSpacesAsAuxiliaryWindows` -> 통과
  - `swift test --filter WallpaperPlayerSuspensionTests` -> `17 tests, 0 failures`
  - `swift test` -> `141 tests, 0 failures`
- 미검증:
  - 앱 실행 / GUI fullscreen swipe QA

### 00:59 KST

- 완료: Restore on Stop original cache 복원 버그 수정
- 원인:
  - restore state는 original wallpaper URL을 저장했지만, 원본 파일이 삭제/이동되면 Stop Playback이 복원할 파일을 찾을 수 없었습니다.
- 수정:
  - fallback 적용 직전 정적 original wallpaper 파일을 `Application Support/MacWall/DesktopWallpaperRestore/Originals`에 복사
  - Stop Playback은 저장된 original URL보다 cached original copy를 우선 사용
  - MacWall `Assets/*/Derived/desktop-fallback.png`는 original wallpaper로 capture하지 않음
- 검증:
  - `swift test --filter OriginalDesktopWallpaperStoreTests/testRestoresFromCachedOriginalWhenOriginalImageFileDisappears` -> 통과
  - `swift test --filter OriginalDesktopWallpaperStoreTests/testDoesNotCaptureMacWallFallbackCacheAsOriginalWallpaper` -> 통과
  - `swift test --filter OriginalDesktopWallpaperStoreTests` -> `10 tests, 0 failures`
  - `swift test --filter DesktopFallbackCoordinatorTests` -> `16 tests, 0 failures`
  - `swift test` -> `140 tests, 0 failures`

## 2026-06-05

### 20:42 KST

- 완료: docs / AGENTS 운영 문서 점검 및 정리
- 변경:
  - `docs/superpowers`에 남아 있던 완료된 P2 Playback Stability spec/plan을 `docs/archive/superpowers/`로 이동
  - `docs/development-roadmap.md`에 Restore on Stop v2 정책 반영
  - P1 구현 기록에 Restore on Stop v2 보강 정책 추가
  - `docs/README.md`를 GitHub `docs/` landing page 겸 문서 인덱스로 명확화
  - `AGENTS.md`와 `docs/development-guide.md`에 `docs/README.md`는 탐색용이고 작업 정책은 development guide가 우선이라는 기준 추가
- 결정:
  - `docs/README.md`는 필수 이름은 아니지만 GitHub directory landing page 자동 표시 장점이 있으므로 유지
- 검증:
  - 문서 파일 목록과 관련 문구 검색
  - `git diff --check` -> 통과

### 20:32 KST

- 완료: Restore on Stop v2 구현
- 구현:
  - Settings / menu bar에 `Restore on Stop` opt-in 추가
  - fallback 적용 직전 active Space + display 기준으로 현재 macOS wallpaper 상태 검사
  - `com.apple.wallpaper.choice.image` 정적 이미지일 때만 original image URL 저장
  - `Macintosh` 같은 macOS 기본/동적 wallpaper provider는 stale `NSWorkspace.desktopImageURL`을 original로 저장하지 않음
  - 동적/기본 wallpaper 감지 시 옵션 활성화 시점과 Play 시점에 경고 표시
  - restore state를 `Application Support/MacWall/DesktopWallpaperRestore/restore-state-v2.json`에 저장
  - 기존 `OriginalDesktopWallpaperStore.records.v1` UserDefaults 기록은 무시/clear
  - Stop Playback 시 current wallpaper가 app-applied fallback과 일치할 때만 저장된 정적 original URL로 자동 복원
  - 다른 item fallback 적용 성공 후 이전 item의 `Derived/desktop-fallback.png` 삭제
  - 이전 item의 늦게 완료된 generation / Space Refresh가 삭제된 cache를 다시 설치하지 않도록 token invalidate
  - Stop Playback은 현재 item의 `desktop-fallback.png` cache 파일을 삭제하지 않음
- 문서:
  - `README.ko.md`
  - `README.md`
- 검증:
  - `swift test --filter OriginalDesktopWallpaperStoreTests` -> `8 tests, 0 failures`
  - `swift test --filter AppViewModelTests` -> `18 tests, 0 failures`
  - `swift test --filter DesktopFallbackCoordinatorTests` -> `16 tests, 0 failures`
  - `swift test --filter DesktopFallbackSpaceRefreshCoordinatorTests` -> `4 tests, 0 failures`
  - `swift test` -> `138 tests, 0 failures`
  - `git diff --check` -> 통과
- 제외:
  - 앱 실행 / GUI 실행
  - `swift build`
  - package / DMG / notarization / dist 작업

## 2026-06-04

### 02:45 KST

- 완료: Stop Playback 시 original macOS wallpaper 복원 정책 구현
- 구현:
  - fallback PNG를 system wallpaper로 적용하기 직전에 screen별 original wallpaper capture
  - screen별 original URL, app-applied fallback URL, managed session 상태를 UserDefaults에 저장
  - Stop Playback 시 current wallpaper가 app-applied fallback과 일치할 때만 original restore
  - 사용자가 macOS 설정에서 wallpaper를 직접 바꾼 경우 Stop이 덮어쓰지 않음
  - `Derived/desktop-fallback.png` cache 파일은 삭제하지 않음
- 검증: `swift test` -> `130 tests, 0 failures`

### 02:09 KST

- 완료: P2 Playback Stability 구현
- 문서: [P2 구현 기록](implemented/2026-06-04-p2-playback-stability.md)
- 구현:
  - transactional hidden/staged replacement window flow
  - A -> failing B 전환 시 A live playback/fallback/space-refresh/lastPlayedAssetId 유지
  - screen-change 300ms, wake 500ms, visibility 200ms debounce
  - fake scheduler 기반 simulated lifecycle coverage
- 확인:
  - README.ko.md / README.md 재생 문구 확인, 사용자-facing 변경 불필요
- 검증: `swift test` -> `121 tests, 0 failures`
- 제외: Scene S0, Scene fallback, GUI QA, packaging/release work

### 01:30 KST

- 완료: P2 Playback Stability 설계 보강 및 실행 계획 작성
- 문서:
  - `docs/archive/superpowers/specs/2026-06-04-p2-playback-stability-design.md`
  - `docs/archive/superpowers/plans/2026-06-04-p2-playback-stability.md`
- 반영:
  - project 표시명은 `Workshop Wallpaper Bridge`로 통일
  - transactional hidden/staged replacement window flow 명확화
  - A -> failing B 전환 시 A live playback/fallback/space-refresh/lastPlayedAssetId 유지
  - debounce test는 fake scheduler 기반으로 명시
  - monitor/sleep-wake 검증은 GUI 실행 없는 simulated unit/integration 범위로 제한

### 01:24 KST

- 시작: P2 Playback Stability 설계
- 문서:
  - `docs/archive/superpowers/specs/2026-06-04-p2-playback-stability-design.md`
- 범위:
  - Spaces/full-screen 전환, monitor 변경, sleep/wake 복구, item switching, auto-pause 안정성
  - Scene S0, Scene fallback, Metal Scene runtime, package/release 작업 제외

### 01:11 KST

- 완료: 개발 가이드에 기본 운영 기준 보강
- 추가:
  - 개발 환경: macOS 14+, Xcode 16+, Swift 6
  - 아키텍처: `MacWallCore`, `MacWallApp`, `macwallctl`
  - 문서 수정 규칙: 사용자에게 보이는 동작 변경 시 `README.ko.md`와 `README.md` 갱신 여부 확인

## 2026-06-03

### 19:40 KST

- 완료: P1 Desktop Fallback Cache / Space Refresh 구현 정리
- 문서: [P1 구현 기록](implemented/2026-06-03-p1-desktop-fallback-cache-and-space-refresh.md)
- 검증: `swift test` -> `104 tests, 0 failures`
- 결정:
  - fallback은 Play/Apply의 side effect로 둡니다.
  - Scene fallback은 Metal Scene runtime이 실제 Scene frame을 render할 수 있을 때까지 보류합니다.
  - Workshop thumbnail은 `desktop-fallback.png` source로 사용하지 않습니다.
- 다음: P2 Playback Stability

### 20:10 KST

- 완료: 문서 구조를 `docs/` 중심으로 정리
- 이동:
  - `plans/development-roadmap.md` -> `docs/development-roadmap.md`
  - 완료된 P1 Superpowers plan/spec -> `docs/archive/superpowers/`
  - 과거 v0.2.1 plan -> `docs/archive/plans/`
- 결정:
  - 활성 roadmap은 `docs/development-roadmap.md`에서 관리합니다.
  - 큰 구현 완료 기록은 `docs/implemented/`에 남깁니다.
  - 과거 계획은 `docs/archive/`에 보관합니다.

### 20:25 KST

- 결정: 개발 문서 운영 기준을 추가하기로 함
- 추가 대상:
  - `docs/README.md`
  - `docs/development-guide.md`
  - `docs/development-log.md`
  - `CONTRIBUTING.md`
- 라이선스 결정:
  - 원작 MIT notice를 유지합니다.
  - 현재 작업자 notice는 `mingyu1715`로 추가합니다.
  - 원작 기반 범위는 `LICENSE`에 짧게 명시합니다.

### 20:44 KST

- 완료: repository root 문서 역할 정리
- 정리:
  - 루트 문서는 `README.ko.md`, `README.md`, `CONTRIBUTING.md`, `LICENSE` 중심으로 유지합니다.
  - 개발 문서와 기록은 `docs/` 아래에서 관리합니다.
  - 오래된 중복 README 성격의 `wallpaperconverter.md`는 `docs/archive/legacy/wallpaperconverter.md`로 이동했습니다.
- 결정:
  - GitHub 세팅 전 기준 문서는 `docs/README.md`와 `docs/development-guide.md`를 우선합니다.

### 21:02 KST

- 완료: 로컬 Git / GitHub 기본 세팅 시작
- 추가:
  - `.github/PULL_REQUEST_TEMPLATE.md`
  - `.github/ISSUE_TEMPLATE/bug_report.md`
  - `.github/ISSUE_TEMPLATE/feature_request.md`
  - `.github/ISSUE_TEMPLATE/documentation.md`
  - `.github/ISSUE_TEMPLATE/config.yml`
  - `.github/labels.yml`
- 결정:
  - CI workflow는 아직 추가하지 않습니다.
  - release/package/DMG/notarization/dist 작업은 release PR에서만 다룹니다.
  - 루트 `/test/`는 로컬 Workshop/sample asset 폴더로 보고 Git 추적에서 제외합니다.
  - Swift test source인 `Tests/`는 추적합니다.

### 21:25 KST

- 완료: project/repository 이름을 `MacWall`로 변경
- 변경:
  - remote URL: `https://github.com/mingyu1715/MacWall.git`
  - package/product: `MacWall`
  - app target: `MacWallApp`
  - core target: `MacWallCore`
  - CLI: `macwallctl`
  - app bundle / screen saver / bundle identifier: `MacWall`, `io.github.mingyu1715.MacWall`
- 유지:
  - `LICENSE`의 원작 MIT notice와 attribution은 유지합니다.
  - `docs/archive/`의 과거 기록은 historical archive로 보고 rename하지 않습니다.
- 검증:
  - `swift test` -> `104 tests, 0 failures`

### 22:19 KST

- 진행: macOS 26 native wallpaper spike Task 3/4
- 추가:
  - `MacWallNativeWallpaperSpike/README.md`
  - `MacWallNativeWallpaperSpike/CMakeLists.txt`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpikeApp/Info.plist`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpikeApp/main.swift`
  - `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpikeApp/MacWallNativeWallpaperSpikeApp.entitlements`
- 결과:
  - CMake로 isolated Xcode project를 `/tmp/macwall-native-wallpaper-spike-xcode`에 생성했습니다.
  - extension target build 통과
  - containing app + embedded ExtensionKit appex build 통과
  - host app / appex 모두 ad-hoc sign + `com.apple.security.app-sandbox = true` 확인
  - `pluginkit`는 계속 `match: Connection invalid`라 discovery source로 사용할 수 없습니다.
  - entitlement 추가 전 로그에서 WallpaperAgent/ExtensionKit가 MacWall extension identity를 보고 `Extension is not entitled to run in the App Sandbox`로 거부하는 것을 확인했습니다.
- 판단:
  - packaging gate는 통과했습니다.
  - WallpaperAgent가 third-party extension identity를 전혀 못 보는 상태는 아닙니다.
  - entitlement 적용 후 load 로그 확인은 로컬 권한/usage limit으로 중단되었습니다.
  - post-entitlement load가 확인되기 전에는 Task 5 generated frame bridge로 넘어가지 않습니다.

## 2026-06-08

### 00:18 KST

- 완료: macOS 26 native wallpaper spike post-entitlement load gate 확인
- 검증:
  - CMake isolated Xcode project 재생성
  - `xcodebuild` containing app + embedded appex clean build 통과
  - `codesign --verify --deep --strict` 통과
  - host app / appex 모두 `com.apple.security.app-sandbox = true` 확인
- 로그 근거:
  - WallpaperAgent catalog가 extension set 변경을 감지했습니다.
  - WallpaperAgent가 `com.mingyu1715.macwall.native-wallpaper-spike.extension`에 `provideSettingsViewModels`와 `connect`를 요청했습니다.
  - ExtensionKit가 WallpaperAgent host pid 1609용으로 MacWall extension process를 launch했습니다.
  - `MacWallNativeWallpaperExtension` process가 `-LaunchArguments serviceName=com.mingyu1715.macwall.native-wallpaper-spike.extension`로 실행됐습니다.
  - lifecycle logger 출력 확인:
    - `[com.mingyu1715.macwall.native-wallpaper-extension:Lifecycle] MacWall native wallpaper extension process started`
- 분류:
  - discovery: pass
  - entitlement: pass
  - local ad-hoc code signing: pass
  - extension process launch: pass
  - lifecycle logger: pass
  - wallpaper request/handshake: fail
- 실패 지점:
  - skeleton extension이 private WallpaperExtensionKit request/handshake를 구현하지 않아 `provideSettingsViewModels`에서 `NSCocoaErrorDomain (4099)`가 발생했습니다.
- 판단:
  - Task 5로 가기 전 native surface/frame output보다 먼저 `provideSettingsViewModels`/`connect` handshake를 최소 stub로 통과시키는 작업이 필요합니다.

### 00:35 KST

- 완료: macOS 26 native wallpaper spike private request/handshake 최소 stub
- 변경:
  - `MacWallNativeWallpaperExtension` entry point를 `ExtensionFoundation.AppExtension` 기반으로 전환했습니다.
  - `WallpaperAgent` XPC connection을 `AppExtensionConfiguration.accept(connection:)`에서 수락하도록 추가했습니다.
  - private WallpaperExtensionKit selector protocol을 Swift `@objc` protocol로 선언했습니다.
  - `provideSettingsViewModels`, `acquire`, `update`, `invalidate`, `snapshot`, choice/download/migration/debug/notification selector에 최소 reply stub를 추가했습니다.
  - `provideSettingsViewModels`는 빈 `WallpaperSettingsViewModelsXPC`를 생성해 응답합니다.
- 검증:
  - CMake isolated Xcode project 재생성 통과
  - `xcodebuild` containing app + embedded appex clean build 통과
  - `codesign --verify --deep --strict` 통과
  - host app / appex 모두 `com.apple.security.app-sandbox = true` 확인
  - Wallpaper 설정 패널을 열어 `WallpaperAgent` 요청을 재유도했습니다.
- 로그 근거:
  - `connect`:
    - `BEGIN - [com.mingyu1715.macwall.native-wallpaper-spike.extension] connect`
    - `END - [com.mingyu1715.macwall.native-wallpaper-spike.extension] connect`
  - `provideSettingsViewModels`:
    - `BEGIN - [com.mingyu1715.macwall.native-wallpaper-spike.extension] provideSettingsViewModels`
    - `END - [com.mingyu1715.macwall.native-wallpaper-spike.extension] provideSettingsViewModels`
  - extension 내부:
    - `Accepting WallpaperAgent XPC connection pid=1609`
    - `WallpaperAgent XPC connection accepted`
    - `provideSettingsViewModels stub`
    - `Created empty WallpaperSettingsViewModelsXPC`
- 분류:
  - discovery: pass
  - entitlement: pass
  - code signing: pass for local ad-hoc spike
  - process launch: pass
  - connection accept/connect: pass
  - `provideSettingsViewModels` reply: pass
  - `NSCocoaErrorDomain 4099`: not reproduced after stub
  - extension process survival after handshake: pass
- 주의:
  - 아직 `AVSampleBufferDisplayLayer`/generated frame bridge는 시작하지 않았습니다.
  - 기존 `NSWindow` backend와 fallback 정책은 수정하지 않았습니다.
  - 다음 단계는 generated frame output 전에 native surface 또는 `WallpaperRemoteContextXPC`를 받는 `acquire` request 구조를 확인하는 것입니다.

### 00:56 KST

- 완료: macOS 26 native wallpaper spike `acquire` request gate 관찰
- 변경:
  - `provideSettingsViewModels`가 빈 group 대신 `MacWall Native Spike` 더미 item 1개를 반환하도록 변경했습니다.
  - settings thumbnail PNG는 extension sandbox temp 영역에 생성합니다.
  - `acquire`, `update`, `snapshot`, `selectedChoicesDidChange`, choice/download/migration/debug selector에 XPC object introspection 로그를 추가했습니다.
- 검증:
  - CMake isolated Xcode project 재생성 통과
  - `xcodebuild` containing app + embedded appex clean build 통과
  - `codesign --verify --deep --strict` 통과
  - System Settings -> Wallpaper에서 MacWall item 선택 후 `log stream`으로 acquire request를 수집했습니다.
- 로그 근거:
  - `provideSettingsViewModels`:
    - `Created WallpaperSettingsViewModelsXPC groups=1`
  - WallpaperAgent:
    - `makeWallpaper for '[extension] com.mingyu1715.macwall.native-wallpaper-spike.extension'`
    - `Wallpaper Timeline: Acquire Wallpaper`
  - extension 내부:
    - `acquire stub`
    - `acquire.id: type=WallpaperIDXPC`
    - `acquire.request: type=WallpaperCreationRequestXPC`
- 확인된 `WallpaperCreationRequestXPC.rawValue` 구조:
  - `descriptor`
    - `files`: settings item descriptor에서 넘긴 thumbnail URL
    - `configuration`: `macwall-native-spike-choice`
    - `optionValues`: System Settings가 추가한 color option 값
  - `cacheDirectory`: `~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.mingyu1715.macwall.native-wallpaper-spike.extension/`
  - `destination`
    - `size`: `(1710.0, 1107.0)`
    - `colorSpace`: Apple RGB
    - `scaleFactor`: `2.0`
    - `directDisplayID`: `1`
  - `isPreview`: preview request에서는 `true`, real desktop request에서는 `false`
  - `presentationMode`: `default`
  - `activityState`: `active`
  - `systemAppearance`: `dark`
  - `debugBackgrounds`: `false`
- 분류:
  - acquire reaches MacWall extension: pass
  - request type identified: `WallpaperCreationRequestXPC`
  - id type identified: `WallpaperIDXPC`
  - expected acquire response: non-nil native wallpaper object required
  - nil acquire reply result: `WallpaperExtensionKit.WallpaperExtensionError (2)`
- Phosphene 비교:
  - acquire reply는 `WallpaperRemoteContextXPC`가 맞습니다.
  - 생성 순서는 `CAContext.remoteContext()` 또는 `remoteContextWithOptions:` -> `caContext.contextId` -> `WallpaperRemoteContextXPC` 생성 -> acquire reply입니다.
  - `WallpaperRemoteContextXPC`는 private class이며, Phosphene은 `box` ivar 또는 offset `8`에 `UInt32 contextId`를 기록해 wrapper를 구성합니다.
- 판단:
  - 다음 gate는 generated frame bridge가 아니라 remote CAContext gate입니다.
  - 최소 다음 실험은 `CAContext.remoteContext` 생성, empty/root `CALayer` 연결, `WallpaperRemoteContextXPC` reply가 `WallpaperExtensionError (2)`를 제거하는지 확인하는 것입니다.
  - 아직 `AVSampleBufferDisplayLayer` 출력은 시작하지 않았습니다.
  - 기존 `NSWindow` backend와 fallback 정책은 수정하지 않았습니다.
