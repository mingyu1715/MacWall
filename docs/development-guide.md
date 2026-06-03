# 개발 가이드

이 문서는 MacWall을 개발할 때 지킬 운영 기준을 정리합니다.

## 문서 역할

repository root는 사용자와 GitHub 공개 운영에 필요한 문서만 둡니다.

- `README.ko.md`: 사용자용 한국어 문서
- `README.md`: 사용자용 영어 문서
- `LICENSE`: 원작 MIT notice와 현재 작업자 notice
- `CONTRIBUTING.md`: GitHub 기여와 협업 기준
- `.github/`: GitHub issue / PR template, label seed

개발 과정에서 계속 갱신하는 문서는 `docs/` 아래에서 관리합니다.

- `docs/README.md`: 문서 index
- `docs/development-roadmap.md`: 현재 방향과 다음 phase
- `docs/development-log.md`: 날짜/시간별 작업 기록
- `docs/implemented/`: 큰 기능 완료 기록
- `docs/archive/`: 과거 계획과 완료된 계획 보관

## 작업 전 확인 순서

1. `docs/development-roadmap.md`에서 현재 phase와 금지 범위를 확인합니다.
2. `docs/development-log.md`에서 최근 결정과 버그 기록을 확인합니다.
3. 관련 큰 기능이 있으면 `docs/implemented/`의 구현 기록을 확인합니다.
4. 사용자 문서에 영향을 주는 변경이면 `README.ko.md`와 `README.md` 갱신 여부를 확인합니다.
5. 루트에 새 문서를 추가하기 전에 `docs/README.md` 또는 `docs/archive/`에 두는 편이 맞는지 확인합니다.

## Development Log 작성 규칙

- 위치: `docs/development-log.md`
- 모든 시간은 Asia/Seoul 기준으로 기록합니다.
- 의미 있는 개발 결정, 버그 수정, 구현 완료, 검증 결과를 남깁니다.
- 큰 기능은 `docs/implemented/`에 별도 구현 기록을 만들고 log에서 링크합니다.
- 작은 버그 수정, 의심점, 판단은 log에만 남겨도 됩니다.
- GitHub issue나 PR이 있으면 함께 링크합니다.
- commit hash는 필수는 아닙니다. 공개 GitHub 흐름에서는 PR 링크를 우선합니다.

권장 형식:

```md
## 2026-06-03

### 19:40 KST
- 완료: P1 Desktop Fallback Cache / Space Refresh 구현 정리
- 문서: [P1 구현 기록](implemented/2026-06-03-p1-desktop-fallback-cache-and-space-refresh.md)
- 검증: `swift test` -> `104 tests, 0 failures`
- 결정:
  - fallback은 Play/Apply의 side effect
  - Scene fallback은 Metal Scene runtime 이후
- 다음: P2 Playback Stability
```

## 테스트와 검증

- 일반 코드 변경은 focused test를 먼저 실행하고, 마지막에 전체 `swift test`를 실행합니다.
- 문서 변경은 문서 목록과 활성 문서 검색으로 검증합니다.
- 앱 실행, GUI 실행, package 생성, DMG 생성, notarization, 배포 산출물 생성은 사용자가 명시적으로 요청했을 때만 실행합니다.
- `dist` 산출물은 release 작업이 아닌 일반 개발 작업에서 생성, 삭제, 갱신하지 않습니다.
- `Tests/`는 Swift test source로 추적합니다. 루트 `/test/`는 로컬 Workshop/sample asset 폴더로 취급하고 Git에 올리지 않습니다.

문서 변경 검증 예:

```bash
rg --files docs README.md README.ko.md CONTRIBUTING.md LICENSE
rg -n "<확인할-구식-문구-또는-임시-표현>" docs README.md README.ko.md CONTRIBUTING.md
```

## GitHub 운영 기준

기본 흐름:

```text
issue
-> branch
-> PR
-> review
-> merge
-> development-log / implemented 문서 갱신
```

브랜치 이름 예:

```text
feature/p2-playback-stability
fix/video-first-play
docs/development-guide
release/v0.3.0
```

권장 label:

```text
type:bug
type:feature
type:docs
type:refactor
area:playback
area:web
area:scene
area:fallback
area:release
priority:p1
priority:p2
status:needs-design
status:ready
status:blocked
```

`.github/labels.yml`은 GitHub label을 수동 생성하거나 label sync 도구를 사용할 때 기준으로 사용합니다. `gh` CLI나 label sync 도구가 없는 환경에서는 repository 생성 후 GitHub UI에서 같은 이름으로 맞춥니다.

## 라이선스와 원작자 notice

이 project는 MIT license를 유지합니다.

원작 project notice, 현재 작업자 notice, 원작 기반 범위 설명은 repository root의 `LICENSE`에서 관리합니다. 다른 문서에서는 라이선스 내용을 반복하지 말고 `LICENSE`로 링크합니다.

기여나 문서 정리 중 `LICENSE`의 attribution을 제거하거나 축소하지 않습니다.

## 금지 범위

- Steam Workshop crawling/download/auth/DRM 우회 기능을 추가하지 않습니다.
- 원본 Workshop folder를 수정하지 않습니다.
- 로컬 Workshop/sample asset을 repository에 커밋하지 않습니다.
- Workshop thumbnail을 `desktop-fallback.png` source로 사용하지 않습니다.
- Scene fallback은 Metal Scene runtime이 실제 Scene frame을 render할 수 있을 때까지 구현하지 않습니다.
- 현재 `CALayer` Scene renderer는 prototype이며 최종 Scene engine으로 확장하지 않습니다.
