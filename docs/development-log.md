# Development Log

모든 시간은 Asia/Seoul 기준입니다.

## 2026-07-29

### 23:46 KST

- 완료: Scene Engine S1 Format Layer Hardening 실행 계획 작성 및 자체 검수
- 계획:
  - [S1 실행 계획](superpowers/plans/2026-07-29-scene-format-layer-hardening.md)
  - random-access source, PKG archive, TEX inspection, selected-mip decoder,
    Audit v2, local fixture gate, Core/App/CLI migration, 기존 구현 삭제,
    완료 문서 정리의 11개 review gate로 분해
  - 각 구현 task에 RED/GREEN focused test와 독립 local commit 포함
  - Core가 Formats decoder output을 `SceneRenderTexture`로 변환해
    `MacWallApp -> MacWallCore` dependency 방향을 유지하도록 명시
  - S0/S1 완료 문서는 최종 검증 후 archive/implemented 구조로 정리
- 검수:
  - S1 설계의 limit, unsupported evidence, overlap/duplicate 정책,
    Audit schema 2, random-access acceptance를 task에 모두 연결
  - task 간 public type/signature와 fixture helper 사용 일치 확인
  - placeholder 없음, Markdown code fence 짝 일치, `git diff --check` 통과
- 미실행:
  - 코드 구현 및 test 실행
  - `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행
  - S2, Metal, Native Scene surface, Scene fallback, SceneScript/effect 실행
  - package, DMG, notarization, `dist` 작업

### 23:36 KST

- 완료: Scene Engine S1 Format Layer Hardening 설계 문서 작성 및 자체 검수
- 설계:
  - [S1 Format Layer Hardening 설계](superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md)
  - `MacWallSceneFormats`와 `MacWallSceneAudit` target으로 format/audit 책임 분리
  - file descriptor와 `pread` 기반 random-access package source 및 bounded entry 계약
  - PKG/TEX unknown layout evidence 보존, strict descriptor API, selected mip software decode
  - Audit schema 2와 S0 aggregate catalog compatibility gate 분리
  - 새 module 병행 구현, consumer migration, 전체 검증 후 기존 구현 삭제 순서 확정
  - compatibility facade/typealias 없이 새 API로 완전 전환
- 검수:
  - 실제 local PKG/TEX 분포와 S0 audit 결과 재대조
  - overlap warning, duplicate path invalid, unverified PKG version 정책 분리
  - parser structural limit과 decoder allocation limit 분리
  - 문서 code fence, placeholder, 링크 대상 및 `git diff --check` 확인
- 다음:
  - 작성된 설계 문서 검토 승인 후 executable implementation plan 작성
- 미실행:
  - 코드 구현 및 test 실행
  - `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행
  - Metal, Native Scene surface, Scene fallback, SceneScript execution
  - package, DMG, notarization, `dist` 작업

### 22:50 KST

- 완료: Scene Engine S0 Format Research 및 Fixture Catalog 구현
- 구현:
  - schema version 1 `SceneAuditReport`, S0 support policy, canonical JSON encoder
  - allocation 없는 payload skip을 사용하는 bounded TEX metadata reader
  - `TEXB0003`/`TEXB0004` regular/video, multi-image/mipmap, animated texture metadata
  - Scene object, parent/instance, animation, dependency, effect, shader,
    inline SceneScript evidence와 stable invalid diagnostic
  - 실제 Workshop payload 없이 aggregate count만 저장한 local fixture catalog
- local fixture:
  - `PKGV0008`, `PKGV0018`, `PKGV0023` 세 package audit 통과
  - texture container `TEXB0003`/`TEXB0004`, raw format/flag count 일치
  - local fixture test: 1 test에서 fixture 3개 audit, skip 0, failure 0
- 검증:
  - focused Scene suites: `25 tests, 0 failures`
  - 전체 `swift test`: `267 tests, 0 failures`
  - `git diff --check` 통과
  - `git ls-files test` 출력 없음
  - 새 `macwallctl` command 및 thumbnail fallback 구현 없음
  - audit API가 `MacWallCore/Scene`과 tests에만 존재함을 확인
- 범위:
  - S0 구현은 S1 module extraction 전까지 `MacWallCore`에 유지
  - 다음 단계는 S1 Format Layer Hardening
- 미실행:
  - `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행
  - Metal, Native Scene surface, Scene fallback, SceneScript execution
  - package, DMG, notarization, `dist` 작업

### 22:30 KST

- 완료: Scene Engine S0 Format Research 및 Fixture Catalog 실행 계획 작성
- 계획:
  - [S0 실행 계획](superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md)
  - versioned audit schema, canonical JSON, bounded TEX metadata, Scene JSON/
    dependency/script inspector, local fixture catalog 순서로 분해
  - 새 CLI 없이 `MacWallCore` internal API와 tests로만 S0를 구현
  - 실제 Workshop fixture는 `test/` local-only로 유지하고 aggregate catalog만 추적
  - S1 module extraction, Metal, Native Scene, fallback, SceneScript execution은 제외
- 라이선스:
  - 전체 MIT 정책 유지
  - GPL code와 Wallpaper Engine built-in asset 복사 금지 유지
- 검증:
  - 승인된 Scene Engine 설계와 현재 Scene parser/test helper의 실제 interface 대조
  - task별 RED/GREEN focused test, commit, 최종 전체 `swift test` 절차 명시
- 미실행:
  - 코드 구현 및 test 실행
  - 앱/GUI/System Settings 실행
  - `swift build`, package, DMG, notarization, `dist` 작업

### 22:21 KST

- 완료: Scene Engine 전체 구조 설계 및 local fixture 기반 format 재검증
- 설계:
  - [Scene Engine 설계](superpowers/specs/2026-07-29-scene-engine-design.md)
  - random-access PKG/TEX format layer, layered asset resolver, typed SceneGraph,
    deterministic runtime, headless Metal render graph으로 책임 분리
  - Native Scene renderer는 Main App이 아니라 WallpaperAgent가 실행한 extension
    프로세스 안에서 동작하도록 process boundary 확정
  - IOSurface-backed `CVPixelBuffer`를 Metal render target으로 사용하고 기존
    `AVSampleBufferDisplayLayer` native surface 경로로 frame을 공급
  - 모든 target Desktop context의 first frame 이후에만 candidate generation을
    commit하는 multi-display transaction 유지
  - 실제 Workshop fixture는 local-only, Git에는 synthetic fixture와 aggregate
    audit metadata만 저장
  - Scene audit은 internal API/test support로 두며 새 CLI command는 추가하지 않음
- 라이선스:
  - project-authored code 전체를 MIT로 확정
  - Native Wallpaper Backend와 Scene Engine의 별도 제한 license 검토 종료
  - MIT가 상업적 사용, 배포, sublicense, 판매를 허용한다는 점을 정책에 명시
  - 원작 notice와 현재 작업자 notice는 기존 `LICENSE`에서 유지
  - GPL code와 Wallpaper Engine built-in asset은 repository/app bundle에 포함하지 않음
- 검증:
  - 세 local Scene fixture의 PKG/TEX/object/effect/script 구조와 기존 parser 한계 재확인
  - Native runtime staging 및 extension-side video frame path와 Scene process 설계 대조
  - Wallpaper Engine 공식 SceneScript/effect/shader 문서와 Apple Metal/Core Video/
    AVSampleBufferDisplayLayer 문서를 기준으로 설계 보강
  - 활성 문서의 구식 라이선스/Scene 단계/CLI 표현 검색 결과 없음
  - 변경 문서의 local Markdown link 검사와 `git diff --check` 통과
- 미실행:
  - 코드 구현 및 test 실행
  - 앱/GUI/System Settings 실행
  - package, DMG, notarization, `dist` 작업

### 21:55 KST

- 완료: Native Playback Timing/Backend feature 브랜치를 Branding 변경이 반영된 현재 브랜치에 통합
- 보존:
  - Native Video backend, AdHocQA transport, 표시 모드, auto-pause 및 runtime recovery
  - MacWall 로고 자산, 메뉴바 마크, 앱 아이콘 및 README 로고
- 검증:
  - 전체 `swift test`: `255 tests, 0 failures`
  - Native Wallpaper/AdHocQA project structure guard 통과
  - Spike dev runner test, SVG XML, package script syntax 및 `git diff --check` 통과
- 제외:
  - 앱 및 GUI 실행 없음
  - package, DMG, notarization, `dist` 작업 없음

### 21:45 KST

- 완료: MacWall 브랜드 로고 자산 정리 및 앱 적용
- 변경:
  - `logo/`를 `brand-board`, `primary-logo`, `symbol`, `app-icon` 유형별로 정리
  - Primary Logo를 밝은 배경용 검정 글자와 어두운 배경용 흰 글자로 분리
  - 모든 심볼의 트랙패드를 단일 투명 홈으로 통일
  - macOS 앱 아이콘 PNG/ICNS 생성
  - 메뉴바의 기존 SF Symbol을 단색 MacWall 벡터 마크로 교체
  - 영문/한글 README 헤더에 라이트/다크 모드 Primary Logo 연결
  - 앱 번들 `Info.plist`에 `CFBundleIconFile`이 포함되도록 패키징 스크립트 갱신
- 검증:
  - 메뉴바 마크 focused test 통과
  - SVG XML, PNG 크기, ICNS 추출, shell 문법 정적 검증
- 제외:
  - 앱 및 GUI 실행 없음
### 20:57 KST

- 완료: Production Native Video Auto-pause 및 Runtime Stability 구현
- 문서: [Native Auto-pause 및 Runtime Stability 구현 기록](implemented/2026-07-29-native-auto-pause-runtime-stability.md)
- 구현:
  - active generation 전용 `playback-control.json`과 stale/duplicate control policy 추가
  - Desktop covered/visible 200ms debounce, sleep 즉시 suspend, wake 500ms 재평가 연결
  - 마지막 frame과 reader/pending sample을 유지하는 가역적 Native frame bridge suspend/resume 구현
  - candidate first-frame 이후 suspension 적용과 실패한 replacement의 기존 active playback 보존
  - generation별 active renderer 1회 transactional recovery와 두 번째 실패 시 terminal freeze 구현
  - Stop ACK 이후 generation staging과 transient display/playback control 정리
- 검증:
  - focused Native runtime/App/backend/coordinator test 전부 통과
  - 전체 `swift test`: 254 tests, 0 failures
  - Native Wallpaper project structure guard 통과
  - Host + embedded Native extension unsigned AdHocQA compile: `BUILD SUCCEEDED`
  - 독립 코드 리뷰에서 발견된 Stop/Play cleanup race를 operation revision과 회귀 테스트로 수정
  - recovery candidate failure를 terminal second failure로 명시하고 follow-up 리뷰에서 Critical/Important 잔여 finding 없음 확인
  - `git diff --check` 통과
- 로컬 commit:
  - `cf18b82 feat(native): stabilize playback lifecycle`
- 미실행:
  - 앱 및 GUI 실행
  - System Settings 조작과 실제 Desktop auto-pause/recovery 확인
  - package, DMG, notarization, `dist`
- 다음:
  - 별도 사용자 runtime QA
  - Scene Engine `S0 Format Research and Fixture Catalog` 설계

### 20:18 KST

- 완료: Production Native Wallpaper의 `Fit` / `Fill` / `Stretch` 실제 Desktop QA
- 사용자 확인:
  - 재생 중 세 표시 모드가 즉시 전환됨
  - 검은 화면, 재생 재시작, 눈에 띄는 끊김 없음
- 로그 확인:
  - `fit`, `fill`, `stretch` update가 active generation에 `active=true`, `candidate=false`로 반영
  - 표시 모드 변경 중 candidate bridge 생성, generation 교체, display-mode update 실패 없음
- QA runner 정리:
  - AdHocQA DerivedData를 repository root의 `tmp/macwall-native-adhoc-qa-dd`로 이동
  - root `tmp/`를 Git ignore 처리
  - `reset`에서 이전 `/tmp/macwall-native-adhoc-qa-dd` 앱 등록도 해제
  - 최초 경로 이동 중 WallpaperAgent가 이전 bundle URL을 유지해 `Invalid bundle record for current process`로 반복 종료한 원인을 확인
  - WallpaperAgent 1회 재시작 후 새 repository-local extension 경로에서 acquire/update/invalidate 정상 동작 확인
- 환경 정리:
  - 설치된 Native Spike extension process 및 LaunchServices 등록 제거
  - Production MacWall extension 등록과 연구용 `MacWallNativeWallpaperSpike/` 소스는 유지
- 검증:
  - AdHocQA runner structure test와 `git diff --check` 통과
  - repository-local AdHocQA build 및 `codesign --verify --deep --strict` 통과
  - `pluginkit`에서 Production extension 1개와 새 경로 확인, Spike extension은 검색 결과 없음

### 19:51 KST

- 완료: Native Wallpaper 재생 중 `Fit` / `Fill` / `Stretch` 실시간 변경 연결
- 구현:
  - `AppViewModel.displayMode` 변경을 playback coordinator까지 전달
  - 활성 Native generation을 대상으로 별도 `display-mode.json` atomic update 발행
  - Play/Stop의 `command.json`을 보존해 extension 재시작 및 Desktop context 재구성 시 원본 재생 정보를 유지
  - Play 전환 중 여러 모드 변경은 마지막 값만 보류하고 새 generation commit 후 적용
  - extension은 target generation이 현재 active/candidate generation과 일치할 때 해당 `AVSampleBufferDisplayLayer.videoGravity`를 비애니메이션 트랜잭션으로 갱신
  - monitor topology 재구성 중에는 active/candidate 양쪽을 함께 갱신하고, Desktop context가 0개면 최신 모드를 보존해 다음 surface 등록에 적용
  - `Fit -> resizeAspect`, `Fill -> resizeAspectFill`, `Stretch -> resize` 매핑 유지
- 검증:
  - 전체 `swift test`: 222 tests, 0 failures
  - display mode policy/backend focused test: 12 tests, 0 failures
  - Native Wallpaper project structure guard 및 Bash syntax 검사 통과
  - 독립 코드 리뷰 후 Critical/Important 잔여 finding 없음
  - `git diff --check` 통과
- 미실행:
  - 앱 및 GUI 실행
  - System Settings 조작과 실제 Desktop 표시 모드 전환 확인
  - package, DMG, notarization, `dist`

### 17:09 KST

- 완료: Native Wallpaper `AdHocQA` development-only runtime transport 구현 및 정적 검증
- 구현:
  - `NativeRuntimeTransportMode`와 POSIX account home 기반 root resolver 추가
  - Host/Extension transport mode 및 resolved root diagnostic 추가
  - Debug/Release와 격리된 `AdHocQA` configuration, scheme, entitlements 추가
  - QA 전용 `reset`, `install`, `status`, `logs` runner 추가
  - production App Group 실패 시 development-home으로 자동 fallback하지 않도록 경계 유지
- 로컬 commit:
  - `b3be7e8 feat(native): resolve AdHocQA runtime transport`
  - `38d482c feat(native): wire configured runtime transport`
  - `db3a9a0 build(native): isolate AdHocQA configuration`
  - `700cae8 chore(native): add AdHocQA development runner`
- 검증:
  - 전체 `swift test`: 208 tests, 0 failures
  - transport/store/backend focused test: 22 tests, 0 failures
  - AdHocQA project/runner structure guard 및 Bash syntax 검사 통과
  - `MacWallAdHocQA` ad-hoc signed build 성공
  - `codesign --verify --deep --strict` 통과
  - Host/Extension 빌드 산출물의 transport 값 `development-home` 확인
  - Host App Group entitlement 없음 확인
  - Extension sandbox와 `/Library/Application Support/MacWall/NativeRuntimeAdHocQA/` home-relative read/write 예외 확인
  - `xcodebuild`가 자동 등록한 `/tmp` 검증 산출물은 즉시 LaunchServices에서 등록 해제하고 dump에서 경로가 사라졌음을 확인
- 미실행:
  - runner `install`과 사용자 runtime 등록 절차
  - System Settings 선택과 실제 Desktop/Fullscreen 검증
  - package, DMG, notarization, `dist`
- 다음:
  - 별도 사용자 gate에서 `reset -> install -> System Settings 선택 -> status/logs -> 화면 확인`
  - AdHocQA 통과 후 proper Apple signing/provisioning 기반 production App Group QA

### 16:36 KST

- 완료: Native Wallpaper `AdHocQA` development-only transport 실행 계획 작성
- 설계: [Native Wallpaper AdHocQA Transport 설계](superpowers/specs/2026-07-29-native-wallpaper-adhoc-qa-transport-design.md)
- 계획: [Native Wallpaper AdHocQA Transport 실행 계획](superpowers/plans/2026-07-29-native-wallpaper-adhoc-qa-transport.md)
- 작업 순서:
  - 명시적인 transport mode와 POSIX account home 기반 root resolver
  - Host/Extension의 mode 및 root diagnostic
  - Debug/Release와 격리된 `AdHocQA` configuration, scheme, entitlements
  - reset/install/status/logs production QA runner
  - focused test, project guard, ad-hoc compile/signature 중심 정적 검증
- 제한:
  - App Group 실패 시 development-home 자동 fallback 없음
  - 실제 System Settings와 Desktop/Fullscreen 확인은 별도 사용자 gate
  - proper Apple signing/provisioning은 후속 production gate
  - 코드, GUI, package, DMG, notarization, `dist` 변경 없음
- 다음:
  - 실행 방식 선택 후 Task 1부터 TDD로 구현

### 16:23 KST

- 완료: Native Wallpaper `AdHocQA` development-only transport 설계 승인 및 문서화
- 설계: [Native Wallpaper AdHocQA Transport 설계](superpowers/specs/2026-07-29-native-wallpaper-adhoc-qa-transport-design.md)
- 결정:
  - `AdHocQA`에서만 `~/Library/Application Support/MacWall/NativeRuntimeAdHocQA` 공유 경로 사용
  - Extension에는 해당 디렉터리 하나로 제한한 Sandbox temporary exception 적용
  - 일반 Debug/Release는 기존 App Group transport 유지
  - App Group 실패 시 development transport로 자동 fallback하지 않음
  - command/status/generation protocol과 Native renderer/lifecycle은 변경하지 않음
  - proper Apple signing/provisioning은 후속 production gate로 유지
- 검증 범위:
  - transport root와 command/status round trip 단위 테스트
  - build configuration 및 entitlement 분리 정적 검사
  - `AdHocQA` compile/signature/로그 검증
  - 실제 System Settings 및 Desktop 화면은 사용자 검증 gate로 분리
- 제한:
  - 코드 구현, GUI 실행, package, DMG, notarization, `dist` 작업 없음
- 다음:
  - 문서 검토 승인 후 executable implementation plan 작성

### 16:16 KST

- 완료: 실패한 ad-hoc production Native Wallpaper QA 환경 정리
- 사용자 확인:
  - MacWall이 아닌 기존 macOS 배경화면으로 전환
- 정리:
  - production/Spike `MacWallNativeWallpaperExtension` process만 종료
  - `WallpaperAgent` process는 유지
  - `/tmp/macwall-native-backend-dd/Build/Products/Debug/MacWall.app` LaunchServices 등록 해제
- 검증:
  - process 목록에 MacWall extension 없음
  - 시스템 로그에서 `io.github.mingyu1715.MacWall`의 `applicationUnregistered` 확인
  - launchd에서 production extension instance 제거 확인
- 변경:
  - 사용자 wallpaper와 `WallpaperAgent`를 강제로 변경하거나 종료하지 않음
  - 코드 변경 없음

### 16:09 KST

- 진행: production Native Wallpaper discovery 및 App Group runtime QA
- 사용자 관측:
  - System Settings의 배경화면 목록에 production `MacWall` 항목 표시
  - `WallpaperAgent` 동작 확인
- 로그 확인:
  - `io.github.mingyu1715.MacWall.NativeWallpaper` extension process 실제 launch
  - `connect`와 `provideSettingsViewModels` 요청 성공
  - production provider가 runtime에 생성되고 update/invalidate 요청 수신
  - 기존 Spike와 production extension이 설정 조회 중 함께 launch됐고, provider 전환 후 Spike runtime은 invalidate됨
- 실패 경계:
  - production extension의 2초 heartbeat status write가 매번 `NSCocoaErrorDomain 513` / `Operation not permitted`로 실패
  - 실패 경로: `~/Library/Group Containers/group.com.mingyu1715.macwall/NativeRuntime`
  - Host/Extension은 ad-hoc signature이며 `TeamIdentifier=not set`
  - `group.` App Group은 provisioning profile authorization이 필요하므로 entitlement 문자열만 ad-hoc signature에 넣어서는 runtime 접근 권한이 생기지 않음
- 판정:
  - WallpaperExtensionKit discovery/launch/handshake: pass
  - production App Group transport: fail due to signing/provisioning
  - Main App Video Play와 generation ACK QA: blocked before execution
  - snapshot `WallpaperExtensionError(2)`는 기존 별도 gate이며 이번 App Group 실패 원인이 아님
- 변경:
  - 코드 수정 없음
  - app/extension registration과 사용자 System Settings 선택 외 package/DMG/notarization/`dist` 작업 없음
- 다음:
  - MacWall 이외의 wallpaper로 전환 후 production/Spike extension process 정리
  - 정식 Apple signing/provisioning을 준비하거나, 명시적인 development-only transport 설계를 별도로 승인받기 전까지 runtime 구현 변경 금지

## 2026-07-28

### 01:05 KST

- 진행: production Native Wallpaper runtime QA signing preflight
- 확인:
  - `security find-identity -v -p codesigning` 결과 유효한 개발용 signing identity 없음
  - Xcode ad-hoc signing override는 Host/Extension의 App Group entitlement 때문에 provisioning profile 요구로 실패
  - 기존 unsigned 산출물의 saver, extension, host를 nested 순서로 수동 ad-hoc signing
  - `codesign --verify --deep --strict` 통과
  - Host와 extension 모두 `group.com.mingyu1715.macwall` entitlement 보존 확인
  - extension의 `com.apple.security.app-sandbox = true` 보존 확인
- 현재 상태:
  - QA artifact: `/tmp/macwall-native-backend-dd/Build/Products/Debug/MacWall.app`
  - `pluginkit` 조회는 이 머신의 기존 문제인 `match: Connection invalid`로 신뢰할 수 없음
  - LaunchServices dump에는 production/spike 등록 항목이 확인되지 않음
- 제한:
  - app/GUI/System Settings 실행 없음
  - extension process 종료, LaunchServices 등록, wallpaper 선택 없음
- 다음:
  - ad-hoc artifact 등록과 production runtime QA를 진행할지 사용자 승인 필요
  - 진행 시 stale extension reset, LaunchServices register, 사용자 System Settings 선택, Main App Video Play, 로그/화면 대조 순서 사용

### 00:59 KST

- 완료: macOS 26 Native Wallpaper Backend production 승격 구현 및 정적 통합 검증
- 설계: [Native Wallpaper Backend 승격 설계](superpowers/specs/2026-07-27-native-wallpaper-backend-promotion-design.md)
- 계획: [Native Wallpaper Backend 승격 실행 계획](superpowers/plans/2026-07-28-native-wallpaper-backend-promotion.md)
- 구현:
  - Foundation-only `MacWallNativeRuntimeSupport` command/status/store/state machine
  - macOS 14+ Host, macOS 26+ Apple Silicon wallpaper extension, Lock Screen saver를 소유하는 Xcode container
  - production extension handshake, remote `CAContext`, Video frame bridge, heartbeat, generation ACK
  - 모든 active Desktop context가 준비된 뒤 교체하는 transactional generation lifecycle
  - Main App Native/Legacy eligibility routing과 실패 시 이전 playback 유지
  - Native 미활성 상태의 `취소` / `기존 방식으로 재생` / `배경화면 설정 열기` 흐름
  - Native/Legacy fallback ownership 분리와 Native Stop 마지막 frame 유지
- 통합 수정:
  - ExtensionKit appex embed destination을 `Contents/PlugIns`에서 `Contents/Extensions`로 수정
  - unsigned build 산출물의 `MacWall.app/Contents/Extensions/MacWallNativeWallpaperExtension.appex` 존재 확인
- 로컬 commit:
  - `6d66843 feat(native): add shared runtime protocol`
  - `f8ce0cd feat(native): add atomic runtime store`
  - `1033c7a build(native): add production app container`
  - `be8f3d8 feat(native): promote wallpaper extension runtime`
  - `d8d1743 feat(native): control extension playback generations`
  - `309c45c feat(playback): coordinate native and legacy backends`
  - `fd0d696 feat(app): guide native wallpaper setup`
  - `6fb4874 fix(playback): isolate native and fallback sessions`
- 검증:
  - focused Native/Legacy/AppViewModel/fallback test groups 통과
  - `swift test` -> `201 tests, 0 failures`
  - `bash -n Tests/ProjectStructure/native_wallpaper_project_tests.sh` 통과
  - `bash Tests/ProjectStructure/native_wallpaper_project_tests.sh` 통과
  - `xcodebuild -project MacWall.xcodeproj -list` 통과
  - `xcodebuild -project MacWall.xcodeproj -scheme MacWallHostApp -configuration Debug -derivedDataPath /tmp/macwall-native-backend-dd CODE_SIGNING_ALLOWED=NO build` 통과
  - `git diff --check` 통과
  - base commit 대비 `Scripts/package-app.sh` 무변경 확인
- 검증 제한:
  - unsigned compile만 수행했으며 signing/codesign 검사는 수행하지 않음
  - 앱/GUI/System Settings를 실행하지 않음
  - production target의 실제 Desktop 출력과 Fullscreen/Space runtime QA는 아직 수행하지 않음
  - package, DMG, notarization, `dist` 작업 없음
- 보류:
  - snapshot/export
  - Native Web/Scene
  - pixel format/BGRA IOSurface memory 최적화
  - production runtime QA 전까지 별도 `implemented/` 완료 기록 생성 및 spike 제거 금지

### 00:16 KST

- 완료: macOS 26 Native Wallpaper Backend production 승격 실행 계획 작성
- 설계: [Native Wallpaper Backend 승격 설계](superpowers/specs/2026-07-27-native-wallpaper-backend-promotion-design.md)
- 계획: [Native Wallpaper Backend 승격 실행 계획](superpowers/plans/2026-07-28-native-wallpaper-backend-promotion.md)
- 작업 순서:
  - Foundation-only shared command/status/state model
  - atomic App Group store와 immutable Video generation staging
  - Xcode host/embedded appex/Lock Screen saver container
  - 검증된 spike handshake와 Video runtime의 production target 승격
  - extension heartbeat, generation ACK, multi-context all-or-nothing replacement
  - Main App Native/Legacy coordinator
  - 3버튼 Native 설정 안내와 one-shot Legacy 선택
  - fallback handoff, Native Stop, stale generation cleanup
  - 명령어/정적 검사/자동 테스트/로그 중심 최종 검증
- 설계 보강:
  - host bundle ID, extension bundle ID, App Group identifier 고정
  - host app은 이번 phase에서 새로 sandboxing하지 않고 extension만 app sandbox 사용
  - Legacy -> Native 성공 handoff는 original wallpaper 복원 없이 managed restore session만 폐기
  - candidate 중 monitor topology 변경은 partial commit 없이 전체 재준비
- 제한:
  - 실제 System Settings, GUI, Desktop 출력, Fullscreen/Space QA는 실행 계획에서 제외
  - snapshot/export, Web, Scene, pixel format/IOSurface 최적화 제외
  - package, DMG, notarization, `dist` 작업 제외
- 다음:
  - 실행 방식 선택 후 Task 1부터 TDD로 구현

## 2026-07-27

### 23:58 KST

- 완료: macOS 26 Native Wallpaper Backend production 승격 설계 승인 및 문서화
- 설계: [Native Wallpaper Backend 승격 설계](superpowers/specs/2026-07-27-native-wallpaper-backend-promotion-design.md)
- 결정:
  - MacWall 앱은 하나로 유지하고 playback 구현만 Native/Legacy backend로 분리
  - Xcode app container가 Main App과 embedded wallpaper extension을 소유하고 기존 Core/App/CLI는 Swift Package로 유지
  - macOS 26+ Apple Silicon Video는 Native 대상, macOS 25 이하/Intel/미지원 format은 Legacy 유지
  - Main App과 extension은 App Group의 immutable generation, atomic manifest, generation-aware ACK로 통신
  - Native wallpaper가 활성화되지 않은 경우 `취소`, `기존 방식으로 재생`, `배경화면 설정 열기` 3버튼 안내 제공
  - `기존 방식으로 재생`은 해당 Play 요청에만 적용
  - Native playback은 Desktop fallback과 original wallpaper restore state를 건드리지 않음
  - Native Stop은 playback clock을 멈추고 마지막 frame과 System Settings 선택을 유지
  - multi-monitor replacement는 모든 active Desktop context가 준비된 뒤 all-or-nothing으로 commit
- 로드맵:
  - P2.5에 playback timing 구현/검증 상태와 BGRA IOSurface memory 후속 과제를 반영
  - P2.6 Native Wallpaper Backend Promotion을 추가
- 검증:
  - 문서 목록 및 핵심 정책 문구 검색 통과
  - `git diff --check` 통과
- 제한:
  - 검증은 명령어, 정적 검사, 자동 테스트, 제공된 로그 분석 범위로 제한
  - 코드, spike runtime, GUI, System Settings, package, DMG, notarization, `dist` 변경 없음
- 다음:
  - 사용자 문서 검토 후 executable implementation plan 작성

### 23:40 KST

- 완료: Native Wallpaper synchronizer/normal human verification 및 4K60 성능 측정
- 실행 조건:
  - H.264, yuv420p, 3840x2160, 60fps, 약 30Mbps, 19.75초 local sample
  - snapshot mode `disabled`, video source `asset`, timing clock `synchronizer`, profile `normal`
- 사용자 관측:
  - 실제 Desktop 출력에 대해 "괜찮음"으로 확인
  - 자연 배속, 끊김, loop 경계, Fullscreen -> Desktop 동작에서 즉시 확인되는 문제 없음
- timing 결과:
  - 정상 구간 lead는 주로 약 0.06~0.15초
  - loop index 0에서 7 이상까지 continuous PTS로 재생
  - 성능 측정 전 구간에서 drop 0, hard reset 0
  - `vmmap` snapshot 시점과 일치해 1~2초 lag/reset이 두 번 발생했으며 이후 즉시 정상 lead로 복귀
  - 진단 도구가 live process를 일시 정지해 만든 측정 간섭으로 판단하고 runtime failure와 분리
- CPU 측정:
  - extension steady CPU 약 7.8%
  - 전용 `VTDecoderXPCService` steady CPU 약 8.0%
  - 합산 약 15.8%이며 macOS `top` 기준 100%가 CPU core 1개
  - `WallpaperAgent`는 측정 구간 0%에 가까움
- 메모리 측정:
  - extension physical footprint 14.6MB, peak 18.4MB
  - 전용 decoder physical footprint 913.4MB, peak 약 1.0GB
  - decoder footprint 중 836.8MB가 39개 IOSurface region
  - 15초 반복 측정에서 decoder footprint가 약 912~915MB로 유지돼 계속 증가하는 누수보다는 큰 bounded buffer pool 형태
  - `ps` RSS는 decoder를 약 29MB로 표시해 IOSurface 비용을 누락하므로 성능 판정에는 `vmmap` physical footprint 사용
- 원인 단서:
  - 입력은 yuv420p지만 `AVAssetReaderTrackOutput`이 4K frame을 `kCVPixelFormatType_32BGRA`로 출력
  - 4K BGRA surface와 VideoToolbox/display layer buffer pool이 높은 IOSurface footprint의 우선 조사 대상
- 판정:
  - synchronizer/normal은 화면 품질과 timing 안정성에서 control-timebase보다 우세
  - CPU 사용량은 낮은 편이지만 약 913MB decoder footprint는 production 기준 최적화 필요
- 다음:
  - reduced profile 비교 전에 BGRA output과 decoder/display buffer pool의 IOSurface 수명 및 대체 pixel format 조사
- 제외:
  - 성능 측정 과정에서 코드 수정 없음
  - GPU 사용률과 package power는 이번 측정에 포함하지 않음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

### 23:31 KST

- 완료: Native Wallpaper Playback Timing control-timebase human verification gate
- 실행 조건:
  - snapshot mode: `disabled`
  - video source: `asset`
  - timing clock: `control-timebase`
  - timing profile: `normal`
  - local sample: 3840x2160 mp4
- 사용자 관측:
  - 실제 Desktop 출력에 대해 "괜찮은 것 같음"으로 확인
  - 자연 배속, 끊김, loop 경계, Fullscreen -> Desktop 동작에서 즉시 확인되는 문제 없음
- 로그 근거:
  - 약 60초 동안 `queuedFrameCount`가 1에서 3591까지 지속 증가
  - 정상 구간 lead는 주로 약 0.06~0.14초이며 renderer는 ready 상태 유지
  - continuous PTS로 loop index 0에서 3까지 진행
  - loop index 2 시작 지연에서 lag 약 0.724초, 단발 reset 및 25 frame drop 발생
  - reset 이후 `droppedFrameCount=25`로 고정되고 queue 증가 및 loop 재생 지속
  - repeated hard reset 및 `asset-repeated-hard-reset` 없음
  - snapshot disabled에 따른 `WallpaperExtensionError(2)`는 예상된 별도 snapshot/export gate
- 판정:
  - control-timebase/normal은 사용자 화면 기준 조건부 통과
  - 단발 loop reset은 synchronizer 비교 결과와 함께 최종 clock 선택 전에 재평가
- 다음:
  - 동일 영상과 normal profile로 synchronizer human verification 및 focused 로그 비교
- 제외:
  - 코드 수정 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

## 2026-07-20

### 21:38 KST

- 진행: Native Wallpaper Playback Timing 실행 계획 Task 5 정적 검증 환경 준비
- 구현:
  - `dev.sh install --video-path <absolute-path>`로 사용자 소유 로컬 영상을 임시 build resource에 전달
  - 입력 경로가 절대 경로이자 기존 regular file인지 확인하고 위반 시 exit 2 반환
  - `MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE`를 CMake `CACHE FILEPATH`로 전환
  - 명시적 영상 경로를 생략한 다음 install에서는 이전 cache 값을 제거해 기본 local sample로 복귀
- TDD:
  - `--video-path` 도움말 계약 부재와 CMake cache reset 부재로 runner test RED 확인
  - timing clock/profile 기본값, 허용값, invalid exit 2, snapshot/video source 기본값, local video path 성공/실패 계약 GREEN
- 문서:
  - control-timebase, synchronizer, reduced profile 비교 명령과 focused timing 로그 필터를 spike README에 추가
  - snapshot disabled 상태의 `WallpaperExtensionError(2)`는 playback acceptance와 별개임을 명시
  - 사용자 영상은 원본을 수정하거나 repository에 포함하지 않고 임시 build resource로만 복사하도록 기록
- 검증:
  - `bash -n` 및 `dev_runner_tests.sh` 통과
  - 임시 CMake Xcode project 생성 통과
  - `MacWallNativeWallpaperRuntimeIdentityTests` focused build 및 executable 통과
  - `git diff --check` 통과
  - isolated worktree에는 기본 local mp4가 없어 CMake warning이 발생했으며 focused test에는 영향 없음
- 커밋:
  - `36cfa60 feat(native): add playback timing verification runner`
- 다음:
  - control-timebase human verification 후 로그를 먼저 분석
  - 이후 synchronizer와 reduced profile을 같은 절차로 비교
  - 사용자 소유 4K/60 및 120fps fixture가 있을 때만 고해상도 gate 수행
- 미검증:
  - 실제 Desktop 자연 배속, 끊김, loop 경계, Fullscreen -> Desktop 빨간약 결과
- 제외:
  - Native Wallpaper runtime install 및 System Settings 조작 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

### 21:30 KST

- 완료: Native Wallpaper Playback Timing 실행 계획 Task 4 continuous loop PTS
- 구현:
  - `NativeVideoSampleRetimer`로 loop별 `assetDuration * loopIndex` offset을 모든 asset sample timing에 적용
  - loop EOF에서 renderer flush와 playback clock seek 없이 reader만 재시작해 PTS를 단조 증가
  - invalid/nonnumeric asset duration, offset, PTS, DTS와 indefinite duration을 enqueue 전에 거부
  - retiming 실패는 raw sample을 enqueue하지 않고 generated fallback으로 전환하며 `osStatus`를 로그에 기록
  - 첫 hard reset은 media-data 요청 중단 후 renderer flush completion에서 generation을 재검사하고 seek/retry
  - 5초 안에 두 번째 hard reset이 발생하면 `asset-repeated-hard-reset`으로 generated fallback 전환
- TDD:
  - retimer/hard-reset 타입 부재 compile failure 확인 후 loop offset, timing offset, 5초 reset boundary 테스트 GREEN
  - nonnumeric timing validation 부재 compile failure 확인 후 invalid offset/PTS 및 indefinite duration 테스트 GREEN
  - 실제 `CVPixelBuffer` 기반 `CMSampleBuffer` copy/retime PTS 검증 추가
- 리뷰:
  - 1차 리뷰의 flush completion ordering과 nonnumeric timing 통과 위험을 수정
  - 재리뷰 결과 Critical/Important issue 없음
  - 남은 sample-buffer 실동작 test Minor도 추가해 focused 실행으로 검증
- 검증:
  - `MacWallNativeWallpaperRuntimeIdentityTests` focused build 및 executable 통과
  - `MacWallNativeWallpaperExtension` target build 통과
  - `dev_runner_tests.sh`, Swift parse, shell syntax, `git diff --check` 통과
  - 전체 `swift test`: 149 tests, 0 failures
- 커밋:
  - `4b402f6 feat(native): keep loop presentation time continuous`
- 다음:
  - Task 5 verification matrix, `--video-path` runner 지원, README 및 최종 개발 로그 정리
- 제외:
  - Native Wallpaper runtime install, System Settings 조작, 실제 Desktop/loop 품질 검증 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

### 21:11 KST

- 완료: Native Wallpaper Playback Timing 실행 계획 Task 3 bounded asset pump
- 구현:
  - asset sample을 host media time 기준 최대 500ms까지만 선행 enqueue
  - renderer backpressure에서는 pending sample을 유지하고, 과도한 선행 sample은 5~500ms 범위로 재예약
  - delayed callback과 loop restart에 generation 검사를 적용해 Stop/fallback 이후 stale enqueue 차단
  - 1초 rate limit의 `nativeVideoTiming` 진단 로그 추가
  - EOF에서 마지막 queued frame의 end PTS까지 기다린 뒤 loop를 재시작해 tail frame 절단 방지
  - synchronizer renderer detach 완료 후에만 generated fallback을 시작해 첫 frame 유실 경쟁 방지
- TDD:
  - bounded pump source guard가 `pendingAssetSampleBuffer` 부재로 실패하는 RED 확인 후 GREEN
  - pending 보존, renderer wait, stale generation, EOF tail wait 회귀 테스트를 추가하고 구현 전 compile failure 확인 후 GREEN
- 리뷰:
  - 1차 리뷰의 EOF tail 절단, asynchronous renderer detach, pump lifecycle test 부족 지적을 수정
  - 재리뷰 결과 Critical/Important issue 없음
- 검증:
  - `MacWallNativeWallpaperRuntimeIdentityTests` focused build 및 executable 통과
  - `MacWallNativeWallpaperExtension` target build 통과
  - `dev_runner_tests.sh`, Swift parse, shell syntax, `git diff --check` 통과
  - 전체 `swift test`: 149 tests, 0 failures
- 커밋:
  - `25d827f feat(native): bound asset frame enqueue timing`
- 다음:
  - Task 4에서 loop별 sample PTS를 asset duration offset으로 retime해 clock seek/flush 기반 임시 loop를 제거
- 제외:
  - Native Wallpaper runtime install, System Settings 조작, 실제 Desktop/화질 검증 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - README 변경 없음: 연구용 spike 내부 timing 동작이며 사용자-facing Main App 동작은 아직 바뀌지 않음
  - package, DMG, notarization, `dist` 작업 없음

### 20:30 KST

- 완료: Native Wallpaper Playback Timing 실행 계획 Task 1~2
- 구현:
  - normal/reduced profile의 deterministic timing policy와 executable test 추가
  - renderer backpressure, buffer lead, late drop, hard reset, reduced cadence 결정 고정
  - `AVSampleBufferVideoRenderer` adapter 추가
  - host-clock `CMTimebase`와 `AVSampleBufferRenderSynchronizer` clock 후보 추가
  - `dev.sh install --timing-clock` / `--timing-profile` 및 generated timing 설정 추가
- TDD:
  - Task 1은 `NativeVideoPlaybackTimingPolicy` 부재 compile failure 확인 후 GREEN
  - Task 2는 `--timing-clock` runner 계약 failure 확인 후 GREEN
- 검증:
  - `MacWallNativeWallpaperRuntimeIdentityTests` focused build 및 executable 통과
  - `dev_runner_tests.sh` 통과
  - 새 AVFoundation/CoreMedia source parse 및 Swift 6 typecheck 통과
  - 전체 `swift test`: 149 tests, 0 failures
  - `git diff --check` 통과
- 커밋:
  - `3021057 test(native): define playback timing policy`
  - `97ecd30 feat(native): add selectable playback clock`
- 다음:
  - Task 3에서 adapter/clock을 `NativeVideoFrameBridge`에 연결하고 bounded asset pump 구현
- 제외:
  - Native Wallpaper runtime install 및 System Settings/화면 검증 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

### 20:14 KST

- 완료: macOS 26 Native Wallpaper Playback Timing 실행 계획 작성
- 문서:
  - [Playback Timing 설계](superpowers/specs/2026-06-19-native-wallpaper-playback-timing.md)
  - [Playback Timing 실행 계획](superpowers/plans/2026-07-20-native-wallpaper-playback-timing.md)
- 결정:
  - 순수 timing policy와 deterministic executable test부터 시작
  - asset path는 `sampleBufferRenderer`와 bounded pump를 사용
  - `controlTimebase`와 `AVSampleBufferRenderSynchronizer`는 runner mode로 분리 비교
  - loop sample은 asset duration offset으로 PTS를 연속 증가
  - reduced mode는 수동 profile만 제공하고 자동 battery/thermal policy는 보류
  - 사용자 소유 4K/60 및 120fps fixture는 `--video-path`로만 검증하고 repository에 포함하지 않음
- 검증:
  - plan placeholder, task/step, code fence, API symbol, scope coverage 검색
  - macOS 26 SDK 기준 AVFoundation/CoreMedia 계획 API `xcrun swiftc -typecheck` 통과
  - `git diff --check`
- 제외:
  - 구현 코드 변경 없음
  - build/test/app/GUI/System Settings 실행 없음
  - snapshot/export, Main App, Scene, Web, fallback 변경 없음
  - package, DMG, notarization, `dist` 작업 없음

## 2026-07-17

### 23:18 KST

- 완료: 기술 작업 재개 전 문서 및 로컬 변경 정리
- 문서:
  - [새 프로젝트 문서 초기 세팅](templates/new-project-documentation-setup.md)
  - [프로젝트 문서 및 Git 운영 템플릿](templates/project-docs-and-git-workflow-template.md)
- 정리:
  - repository 작업 진입점인 `AGENTS.md`를 추적 대상으로 추가
  - 재사용 템플릿을 `docs/README.md`에서 바로 찾을 수 있도록 연결
  - 남은 변경을 Restore on Stop, Fullscreen/WindowServer 실험, Native Wallpaper spike 후속 작업으로 분리해 로컬 commit으로 보존
- 검증:
  - 문서 및 source 목록 검색
  - `git diff --check`
  - shell script와 plist 정적 문법 검사
- 제외:
  - `swift test`, build, 앱/GUI 실행 없음
  - System Settings 조작 없음
  - package, DMG, notarization, `dist` 작업 없음

## 2026-06-19

### 14:41 KST

- 진행: macOS 26 Native Wallpaper Spike 문서 정리 및 playback timing 설계 기록
- 문서:
  - [macOS 26 Native Wallpaper Spike 구현 기록](implemented/2026-06-15-macos-26-native-wallpaper-spike.md)
  - [macOS 26 Native Wallpaper Playback Timing 설계](superpowers/specs/2026-06-19-native-wallpaper-playback-timing.md)
- 정리:
  - 2026-06-07 native wallpaper mode 설계/실행 계획은 spike 성공 기록으로 승격하고 `docs/archive/superpowers/`로 이동
  - 활성 native wallpaper 문서는 snapshot/export gate와 playback timing 설계만 남김
  - roadmap의 P2.5 상태를 “spike 구현 및 수동 검증 완료, production 통합 미시작”으로 정리
- 결정:
  - Main App 통합은 아직 시작하지 않음
  - snapshot/export gate는 별도 활성 작업으로 유지
  - playback timing은 bounded prebuffer + PTS pacing + timebase/synchronizer 비교 방향으로 보류
- 검증:
  - `find docs/superpowers docs/archive/superpowers docs/implemented -maxdepth 3 -type f | sort`로 문서 배치 확인
  - 활성 문서 검색으로 2026-06-07 native wallpaper spike 문서가 archive 참조만 남았는지 확인
  - `git diff --check -- docs` 통과
- 제외:
  - 코드 변경 없음
  - snapshot/export 구현 없음
  - Main App 통합 없음
  - Scene/Web 확장 없음
  - GUI 실행 없음

## 2026-06-18

### 16:05 KST

- 진행: macOS 26 Native Wallpaper video source diagnostic mode 추가
- 배경:
  - `--snapshot-mode disabled`에서도 사용자 관측상 약한 버벅임이 남았습니다.
  - 로그상 `snapshot file written`, `4101`, `4099` 없이도 `nativeVideoBridge enqueued` 간격이 불규칙했고, 최대 약 339ms gap이 관측되었습니다.
  - 따라서 snapshot/export 작업이 아니라 bundled mp4 / `AVAssetReader` / sample buffer pacing / runtime update 중 어느 쪽인지 분리할 필요가 있습니다.
- 변경:
  - `dev.sh install --video-source asset|generated` 옵션 추가
  - 기본값은 기존 동작과 같은 `asset`
  - `generated` mode는 bundled mp4와 `AVAssetReader`를 완전히 우회하고 generated sample buffer probe만 사용
  - generated Swift source `MacWallNativeWallpaperVideoSourceMode.generated.swift` 추가
  - `NativeVideoFrameBridge`가 `videoSourceMode=generated|asset` 로그를 남기고 source를 분기하도록 변경
  - spike README에 Video Source Diagnostic Protocol 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `--video-source MODE` help guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
- 다음 수동 검증:
  - `./dev.sh reset`
  - `./dev.sh install --snapshot-mode disabled --video-source generated`
  - 사용자가 System Settings에서 `MacWall Native Spike` 재선택
  - `videoSourceMode=generated` 로그와 실제 화면 부드러움 확인
- 제외:
  - Pacing 수정 없음
  - mp4 decode/PTS 수정 없음
  - Main App 통합 없음
  - System Settings 조작 없음
  - GUI 앱 실행 없음

### 15:51 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `snapshot-xpc-file-url` unsafe 격리
- 확인:
  - `file-url` mode는 WallpaperAgent `cacheDirectory` 아래에 PNG 파일을 생성하고 `NSURL` reply까지 전송했지만, WallpaperAgent가 `NSCocoaErrorDomain(4101)`로 거부했습니다.
  - 이 경로에서는 extension crash 없이 native video runtime이 유지되었습니다.
  - `snapshot-xpc-file-url` mode는 `WallpaperSnapshotXPC.rawValue = NSURL` reply 이후 `NSCocoaErrorDomain(4099)`, XPC interruption/invalidation, runtime removal을 유발할 수 있었습니다.
  - runtime removal 이후 Desktop native surface가 사라질 수 있으며, 복구에는 safe mode 재설치와 사용자의 System Settings 재선택이 필요했습니다.
- 판단:
  - `file-url`은 safe-rejected candidate입니다.
  - `snapshot-xpc-file-url`은 safe-rejected가 아니라 unsafe / connection-interrupting candidate입니다.
  - 현재 `WallpaperSnapshotXPC.rawValue`에 `NSURL`을 넣는 shape는 WallpaperAgent가 기대하는 snapshot payload가 아닙니다.
- 변경:
  - `dev.sh install --snapshot-mode snapshot-xpc-file-url`은 기본 경로에서 차단합니다.
  - 의도적으로 재현할 때만 `--allow-unsafe-snapshot-xpc`를 붙여 실행할 수 있게 했습니다.
  - spike README, snapshot/export gate spec/plan에 `file-url` / `snapshot-xpc-file-url` matrix 결과와 복구 절차를 반영했습니다.
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `--allow-unsafe-snapshot-xpc` help guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
- 제외:
  - Native video runtime 변경 없음
  - Main App 통합 없음
  - 기존 NSWindow backend / fallback 정책 변경 없음
  - System Settings 조작 없음
  - GUI 앱 실행 없음

## 2026-06-16

### 01:43 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate security scope lifetime 수정
- 확인:
  - 사용자 runtime 로그에서 `cacheHomeURL.startAccessingSecurityScopedResource()`는 `granted=true`를 반환했습니다.
  - 같은 scope 안의 tiny direct write preflight는 `method=direct`로 통과했습니다.
  - 하지만 실제 PNG write는 `NSCocoaErrorDomain Code=513`으로 실패했습니다.
- 원인:
  - `canWriteSnapshotHome()` 내부에서만 security scope를 열고, 함수 return 시 `stopAccessingSecurityScopedResource()`로 닫은 뒤 실제 PNG 파일을 생성/쓰기하고 있었습니다.
  - 따라서 preflight는 scope 안에서 성공했지만 실제 snapshot PNG write는 scope 밖에서 실행되어 513이 발생했습니다.
- 변경:
  - `withSnapshotHomeSecurityScope(...)` helper 추가
  - `makeSnapshotFileURL(...)`의 preflight, IOSurface->PNG 생성, file write 전체를 같은 security scope lifetime 안에서 실행하도록 변경
  - `canWriteSnapshotHome(...)`은 scope를 직접 열고 닫지 않고, caller가 유지하는 scope 안에서 direct/coordinated preflight만 수행하도록 분리
  - source guard에 `withSnapshotHomeSecurityScope` 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `withSnapshotHomeSecurityScope` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 판단:
  - 다음 수동 검증에서 `snapshot file written`이 나오면 cacheDirectory 직접 write 경로가 유효한 것으로 판단할 수 있습니다.
  - 그 다음 판단 지점은 `NSURL` reply 또는 `WallpaperSnapshotXPC.rawValue = NSURL`이 WallpaperAgent snapshot payload로 인정되는지입니다.
- 제외:
  - snapshot response shape 변경 없음
  - video runtime 변경 없음
  - Main App 통합 없음
  - System Settings 조작 없음

### 01:36 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate security-scoped / coordinated write probe 추가
- 배경:
  - `NSAppDataUsageDescription` 추가 후에도 사용 권한 prompt는 나타나지 않았고, `file-url` mode는 여전히 WallpaperAgent cache directory에서 `NSCocoaErrorDomain Code=513`으로 실패했습니다.
  - 따라서 다음 검증 지점은 `cacheHomeURL`이 security-scoped URL인지, 또는 `NSFileCoordinator`를 통해 write가 가능한지 확인하는 것입니다.
- 변경:
  - `cacheHomeURL.startAccessingSecurityScopedResource()` 호출 및 `snapshot home security scope ... granted=<bool>` 로그 추가
  - direct write preflight 실패 시 즉시 denied 캐시하지 않고, `NSFileCoordinator` 기반 coordinated write preflight를 추가 시도
  - coordinated write 성공/실패를 `snapshot home coordinated write preflight ...` 로그로 분리
  - direct/coordinated 모두 실패한 경우에만 `MacWallSnapshotHomeWriteAccessCache`에 denied 저장
  - spike README focused grep에 security scope / coordinated write 로그 키워드 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `snapshot home security scope` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 판단:
  - 이 변경은 권한 해결 확정이 아니라, `cacheDirectory` 직접 write 경로를 유지할 수 있는지 판별하기 위한 마지막 권한 계층 probe입니다.
  - 수동 검증에서 security scope가 false이고 coordinated write도 513이면, WallpaperAgent cache directory 직접 write 방식은 버리고 extension-owned file URL 또는 다른 private snapshot wrapper 후보로 넘어가야 합니다.
- 제외:
  - snapshot payload shape 변경 없음
  - video runtime 변경 없음
  - Main App 통합 없음
  - System Settings 조작 없음

### 01:27 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate App Data permission probe 추가
- 가설:
  - `file-url` candidate의 `NSCocoaErrorDomain Code=513`은 POSIX 권한이 아니라 sandbox/TCC App Data 계층에서 WallpaperAgent container write가 막히는 문제일 가능성이 높음
  - `NSAppDataUsageDescription`이 macOS App Data permission prompt 또는 error code 변화를 유도할 수 있는지 확인 필요
- 변경:
  - containing app `Info.plist`에 `NSAppDataUsageDescription` 추가
  - wallpaper extension `Info.plist`에 `NSAppDataUsageDescription` 추가
  - dev runner source guard가 app/appex 양쪽 usage string 존재를 확인하도록 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `NSAppDataUsageDescription` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `plutil -lint MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpikeApp/Info.plist MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - built app/appex Info.plist 양쪽에서 `NSAppDataUsageDescription` 존재 확인
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md` 통과
- 판단:
  - 이 변경은 권한 해결 확정이 아니라 permission prompt/error 변화 확인용 probe입니다.
  - 실제 결과는 사용자가 System Settings에서 `MacWall Native Spike`를 다시 선택한 뒤 `snapshot home write preflight failed/skipped`, `NSCocoaErrorDomain(513)`, `WallpaperExtensionError(2)` 변화를 확인해야 합니다.
- 제외:
  - entitlement 추가 없음
  - Main App 통합 없음
  - snapshot payload shape 변경 없음
  - video runtime 변경 없음

### 01:06 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate request/response shape probe 추가
- 변경:
  - `acquire.request`, `update.request`, `snapshot.id`에 `shapeProbe` 진단 로그를 추가했습니다.
  - XPC object graph에서 URL/file/cache/path/security token/bookmark/descriptor 후보를 요약해 로그로 출력합니다.
  - private class ivar/method layout을 1회만 기록해 snapshot/export wrapper 추적 근거를 남기도록 했습니다.
  - spike README에 focused grep 명령과 `disabled` mode 우선 검증 규칙을 추가했습니다.
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `logXPCShapeProbe("acquire.request", request)` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode disabled` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 판단:
  - 이 변경은 snapshot/export 성공 후보가 아니라 진단 강화를 위한 gate입니다.
  - 다음 수동 확인은 `disabled` mode에서 `shapeProbe` 로그를 수집해 snapshot/export가 요구하는 URL/token/wrapper 단서를 먼저 확인하는 흐름이 맞습니다.
- 제외:
  - Main App 통합 없음
  - `AVSampleBufferDisplayLayer` / video frame bridge 변경 없음
  - fallback 정책 수정 없음
  - System Settings 조작 없음

### 00:34 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `file-url` preflight runtime 확인
- 확인:
  - 사용자 관측: preflight 적용 후 영상 끊김이 원래처럼 부드러워짐
  - 로그상 첫 snapshot request는 `snapshot home write preflight failed` 후 약 8ms 안에 nil reply로 종료됨
  - 이후 snapshot request는 즉시 nil reply로 빠지는 경로가 확인되어, 이전처럼 큰 PNG 생성/파일 write 실패까지 진행하지 않음
  - `nativeVideoBridge enqueued` 간격이 snapshot 이후에도 큰 장기 stall 없이 유지됨
- 판단:
  - 끊김 원인은 `file-url` candidate가 permission denied될 파일 쓰기 경로에 들어가기 전 큰 snapshot PNG를 만들던 비용이었음
  - preflight/cache mitigation은 runtime 부드러움 회복에 효과 있음
  - 당시에는 `file-url` / `snapshot-xpc-file-url`을 파일 쓰기 권한 차단 상태로 분류했으나, 2026-06-18 결과에서 `file-url`은 safe-rejected, `snapshot-xpc-file-url`은 unsafe / connection-interrupting으로 재분류됨
- 제외:
  - snapshot/export 성공 주장 없음
  - Main App 통합 없음
  - video quality / timestamp / pixel format 수정 없음

### 00:31 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `file-url` permission preflight 추가
- 확인:
  - `cacheDirectory` parsing 이후 `file-url` mode가 `snapshot request home source=context`까지 도달함
  - snapshot PNG write는 WallpaperAgent cache directory에서 `NSCocoaErrorDomain Code=513` permission denied로 실패함
  - 첫 snapshot attempt는 약 90ms, 다음 attempt는 약 490ms 동안 PNG 생성/파일 write 실패 경로를 탔고, 이후 native video enqueue 간격이 크게 벌어지는 구간이 확인됨
  - 따라서 현재 `file-url` candidate는 snapshot reply shape 검증 전에 sandbox write permission에서 막힌 상태
- 변경:
  - `file-url` / `snapshot-xpc-file-url` snapshot 파일 생성 전에 tiny write preflight를 수행
  - preflight 실패 시 IOSurface/PNG 생성 없이 nil reply로 빠짐
  - 같은 home URL에서 write denied가 확인되면 process lifetime 동안 cached denied로 즉시 skip
  - `snapshot home write preflight failed` / `snapshot home write preflight skipped` 로그 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `snapshot home write preflight failed` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - video quality / timestamp / pixel format 수정 없음

### 00:21 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `cacheDirectory` home lookup 수정
- 확인:
  - reset/install 이후 새 extension process가 실행됨
  - `remoteContext request ... cacheHomeURL=nil`로 새 진단 로그가 정상 출력됨
  - 과거 acquire introspection 로그와 비교한 결과 cache URL field 이름은 `home`이 아니라 `cacheDirectory`였음
  - 따라서 `snapshot request home missing`의 원인은 cache URL 후보 자체 실패가 아니라 parser가 `cacheDirectory` label을 cache home으로 취급하지 않은 것
  - native video frame enqueue는 계속 유지됨
- 변경:
  - `WallpaperCreationRequestXPC` parser가 `cacheDirectory` URL도 `cacheHomeURL`로 저장하도록 수정
  - snapshot id fallback URL 탐색도 `home` / `cacheDirectory` label 모두 인식하도록 수정
  - source guard에 `normalizedLabel.contains("cachedirectory")` 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `normalizedLabel.contains("cachedirectory")` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - video quality / timestamp / pixel format 수정 없음

### 00:08 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `file-url` home lookup 2차 진단 보강
- 확인:
  - `file-url` 재실행 로그에서도 `snapshot request home missing`이 반복됨
  - 해당 로그는 `acquire.request` / `home:` 계열 라인이 grep에서 제외되어, acquire request parser 실패인지 로그 필터 누락인지 아직 분리 불가
  - `NSURL` reply 후보는 여전히 실제로 전송되지 않았고, native video frame enqueue는 계속 유지됨
- 변경:
  - `remoteContext request` summary 로그에 `cacheHomeURL=<url|nil>` 추가
  - `WallpaperCreationRequestXPC` reflection depth를 넓혀 nested home 값을 더 깊게 탐색
  - exact `home` label 대신 `_home`, `homeURL` 같은 변형도 잡도록 `normalizedLabel.contains("home")` matching 적용
  - snapshot id fallback home 탐색 depth도 동일하게 확장
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `cacheHomeURL=\\(` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - video quality / timestamp / pixel format 수정 없음

## 2026-06-15

### 17:47 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate `file-url` home lookup 수정
- 확인:
  - `file-url` runtime 로그에서 snapshot 요청은 들어왔지만 `snapshot request home missing`으로 PNG 파일 생성 전 nil reply가 반환됨
  - WallpaperAgent 결과는 `WallpaperExtensionError(2)`였고, `NSURL` reply 후보 자체는 아직 검증되지 않음
  - native video frame enqueue는 계속 유지됨
- 변경:
  - `WallpaperCreationRequestXPC` parser가 recursive reflection 중 `home` URL을 발견하면 `cacheHomeURL`에 저장
  - `MacWallRemoteWallpaperContext`의 `requestInfo.cacheHomeURL`을 snapshot 파일 생성 시 우선 사용
  - snapshot id에 home이 있는 경우를 대비한 fallback path는 유지
  - `snapshot request home source=context|snapshot-id` 로그 추가
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `cacheHomeURL` guard 미충족으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 제외:
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - `file-url` runtime matrix 재실행 없음

### 17:14 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate file URL 후보 추가
- 확인된 runtime matrix:
  - `empty-object`: extension crash 없음, `WallpaperSnapshotXPC` reply 전송 성공, WallpaperAgent `NSCocoaErrorDomain(4101)`, native video 유지
  - `raw-value-retained-iosurface`: extension crash 없음, retained `IOSurface` reply 전송 성공, WallpaperAgent `NSCocoaErrorDomain(4101)`, native video 유지
  - `box-retained-iosurface`: extension crash 없음, boxed retained `IOSurface` reply 전송 성공, WallpaperAgent `NSCocoaErrorDomain(4101)`, native video 유지
  - `png-data`: extension crash 없음, `NSConcreteMutableData` reply 전송 성공, WallpaperAgent `NSCocoaErrorDomain(4101)`, native video 유지
- 새 단서:
  - snapshot request introspection에서 WallpaperAgent cache `home` URL이 확인됨
  - 직접 `NSData`/`IOSurface` reply가 모두 4101로 거부되어, snapshot/export가 cache home 아래 파일을 만들고 URL 또는 private wrapper를 반환하는 구조일 가능성이 높음
- 변경:
  - `dev.sh install --snapshot-mode file-url` 추가
  - `dev.sh install --snapshot-mode snapshot-xpc-file-url` 추가
  - `file-url` mode는 snapshot request의 `home` URL 아래에 PNG 파일을 쓰고 `NSURL`을 직접 reply
  - `snapshot-xpc-file-url` mode는 같은 PNG 파일을 쓰고 `WallpaperSnapshotXPC.rawValue = NSURL`로 reply
  - snapshot 파일명은 `wallpaperID`와 UUID를 포함해 stale cache reuse 가능성을 낮춤
  - `snapshot request home`, `snapshot file written`, file URL reply 로그 추가
  - `MacWallNativeWallpaperSpike/README.md` snapshot matrix 갱신
- 검증:
  - RED: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`가 `Unknown snapshot mode: file-url`로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `git diff --check -- MacWallNativeWallpaperSpike docs/development-log.md docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode file-url` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **`, `codesign --verify --deep --strict`, `lsregister` 완료 확인
- 제외:
  - manual runtime matrix 실행 없음
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - video quality / timestamp / pixel format 수정 없음
  - Web / Scene native 확장 없음

### 16:34 KST

- 진행: macOS 26 Native Wallpaper Snapshot Export Gate 구현 준비 완료
- 변경:
  - `dev.sh install --snapshot-mode <mode>` 추가
  - `MacWallSnapshotProbeMode.generated.swift` generated source 생성 경로 추가
  - generated source를 extension target에 포함
  - snapshot lifecycle summary log를 `snapshotGate` prefix로 분리
  - snapshot candidate matrix 추가:
    - `disabled`
    - `error`
    - `empty-object`
    - `raw-value-retained-iosurface`
    - `box-retained-iosurface`
    - `png-data`
  - crash-prone `WallpaperSnapshotXPC` object encode swizzle은 필요한 candidate에서만 켜지도록 제한
  - retained IOSurface/NSData object store를 추가해 candidate object lifetime을 명시적으로 관리
  - `MacWallNativeWallpaperSpike/README.md`에 Snapshot Export Gate Protocol 추가
- 검증:
  - RED: runner test가 `MacWallSnapshotProbeMode.generated.swift` 미출력으로 실패함을 확인
  - GREEN: `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/dev.sh` 통과
  - `bash -n MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh` 통과
  - `MacWallNativeWallpaperSpike/dev.sh install --snapshot-mode disabled` 통과
  - 위 install 경로에서 `** BUILD SUCCEEDED **` 확인
- 제외:
  - manual runtime matrix 실행 없음
  - System Settings 조작 없음
  - 실제 Desktop 출력 확인 없음
  - Main App 통합 없음
  - 기존 `NSWindow` backend / fallback 정책 수정 없음
  - release packaging / DMG / notarization / dist 작업 없음
- 다음:
  - 사용자가 System Settings에서 확인 가능한 상태가 되면 `disabled` baseline부터 manual matrix 시작
  - 각 candidate는 반드시 `reset -> install --snapshot-mode <mode> -> 사용자 화면 확인 -> logs` 순서로만 진행

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
  - `docs/archive/superpowers/plans/2026-06-07-macos-26-native-wallpaper-mode-spike.md`

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
  - [macOS 26 Native Wallpaper Mode 설계](archive/superpowers/specs/2026-06-07-macos-26-native-wallpaper-mode.md)
  - [macOS 26 Native Wallpaper Mode spike 실행 계획](archive/superpowers/plans/2026-06-07-macos-26-native-wallpaper-mode-spike.md)
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
