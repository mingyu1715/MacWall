# Development Log

모든 시간은 Asia/Seoul 기준입니다.

## 2026-06-04

### 01:30 KST

- 완료: P2 Playback Stability 설계 보강 및 실행 계획 작성
- 문서:
  - `docs/superpowers/specs/2026-06-04-p2-playback-stability-design.md`
  - `docs/superpowers/plans/2026-06-04-p2-playback-stability.md`
- 반영:
  - project 표시명은 `Workshop Wallpaper Bridge`로 통일
  - transactional hidden/staged replacement window flow 명확화
  - A -> failing B 전환 시 A live playback/fallback/space-refresh/lastPlayedAssetId 유지
  - debounce test는 fake scheduler 기반으로 명시
  - monitor/sleep-wake 검증은 GUI 실행 없는 simulated unit/integration 범위로 제한

### 01:24 KST

- 시작: P2 Playback Stability 설계
- 문서:
  - `docs/superpowers/specs/2026-06-04-p2-playback-stability-design.md`
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
