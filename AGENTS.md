# Agent Guide

이 문서는 MacWall repository에서 AI coding agent가 작업할 때 따라야 할 최상위 규칙입니다. 세부 기준은 `docs/development-guide.md`를 우선합니다.

## 먼저 읽을 문서

작업 시작 전 아래 순서로 확인합니다.

1. `docs/development-guide.md`
2. `docs/development-roadmap.md`
3. `docs/development-log.md`
4. 관련 큰 기능이 있으면 `docs/implemented/`
5. 사용자에게 보이는 동작 변경이면 `README.ko.md`와 `README.md`

## 개발 환경

기본 개발 환경:

- macOS 14+
- Xcode 16+
- Swift 6

## 아키텍처

- `MacWallCore`
  - Scanner
  - Parser
  - LibraryStore
  - Conversion
- `MacWallApp`
  - SwiftUI/AppKit UI
  - Playback
  - Menu Bar
  - Desktop fallback
- `macwallctl`
  - 진단
  - scan/import 테스트
  - scene 분석 보조

## 작업 원칙

- 작업 전 `git status --short --branch`로 현재 branch와 dirty state를 확인합니다.
- 기존 코드 패턴을 먼저 확인하고, 범위를 작게 유지합니다.
- 사용자에게 보이는 동작이 바뀌면 `README.ko.md`와 `README.md` 갱신 여부를 확인합니다.
- 의미 있는 구현, 정책 변경, 버그 수정, 검증 결과는 `docs/development-log.md`에 Asia/Seoul 시간으로 기록합니다.
- 큰 기능 완료 기록은 필요하면 `docs/implemented/`에 별도 문서로 남기고 log에서 링크합니다.
- `docs/README.md`는 문서 탐색용 landing page입니다. 작업 정책은 `docs/development-guide.md`를 우선합니다.
- root에 새 문서를 만들기 전 `docs/` 아래에 두는 편이 맞는지 확인합니다. 예외적으로 agent가 항상 읽어야 하는 지침은 이 파일처럼 root에 둘 수 있습니다.

## Git 작업

- 작업 시작 전 현재 branch, remote, uncommitted changes를 확인합니다.
- 사용자가 commit을 요청하면 관련 파일만 `git add`하고 명확한 commit message로 커밋합니다.
- unrelated/user 변경은 되돌리지 않습니다.
- `git reset --hard`, `git checkout -- <file>`, 강제 push 같은 파괴적 작업은 사용자가 명확히 요청했을 때만 합니다.
- PR/issue 흐름, branch naming, label 기준은 `docs/development-guide.md`와 `CONTRIBUTING.md`를 따릅니다.
- 구현 완료 후에는 변경 파일, 테스트 결과, 남은 risk를 final response에 요약합니다.

## 검증

- 코드 변경은 focused `swift test --filter ...`를 먼저 실행하고, 마지막에 전체 `swift test`를 실행합니다.
- 문서만 변경한 경우에는 문서 목록과 관련 문구 검색으로 검증합니다.
- 검증 결과는 final response와 필요 시 `docs/development-log.md`에 남깁니다.

## Native Wallpaper Spike

- macOS 26 native wallpaper spike는 `docs/development-guide.md`의 Native Wallpaper Spike 실행 규칙을 따릅니다.
- `open`으로 containing app을 실행/종료하는 것을 테스트 시작/종료 기준으로 삼지 않습니다.
- 재테스트는 항상 `dev reset -> dev install -> 사용자 System Settings 선택 -> 로그 확인 -> 사용자 화면 확인` 순서로 진행합니다.
- System Settings 조작, 실제 Desktop 출력 확인, Fullscreen -> Desktop 빨간약 검증은 사용자가 직접 수행합니다.

## Production Native AdHocQA

- signing/provisioning 전 production runtime 검증은 `Scripts/native-wallpaper-adhoc-qa.sh`만 사용합니다.
- 순서는 `reset -> install -> 사용자 System Settings 선택 -> status/logs -> 사용자 화면 확인`입니다.
- runner는 앱이나 System Settings를 자동으로 열지 않습니다.
- `AdHocQA` 성공을 production App Group 성공으로 기록하지 않습니다.
- `Debug`와 `Release`는 `development-home`으로 자동 fallback하지 않습니다.

## 금지 범위

명시적인 사용자 승인 없이 아래 작업을 하지 않습니다.

- 앱 실행 또는 GUI 실행
- `bash Scripts/package-app.sh`
- package 생성
- DMG 생성
- notarization
- 배포 산출물 생성
- `dist` 생성, 삭제, 갱신
- Steam Workshop crawling/download/auth/DRM 우회 기능
- 원본 Workshop folder 수정
- 로컬 Workshop/sample asset 커밋

## Fallback / Scene 정책

- Workshop thumbnail, `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`는 UI thumbnail이며 `desktop-fallback.png` source로 사용하지 않습니다.
- Scene fallback은 Metal Scene runtime이 실제 Scene frame을 render할 수 있을 때까지 구현하지 않습니다.
- 현재 `CALayer` Scene renderer는 prototype이며 최종 Scene engine으로 확장하지 않습니다.
- Stop Playback은 현재 item의 `desktop-fallback.png` cache 파일을 삭제하지 않습니다.
