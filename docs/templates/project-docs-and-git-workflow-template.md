# Project Docs And Git Workflow Template

이 문서는 새 프로젝트에 그대로 복사해서 쓰기 위한 개발 문서 / Git 운영 규칙 템플릿입니다.

복사 후 아래 항목만 프로젝트에 맞게 바꿉니다.

- `<PROJECT_NAME>`
- `<PRIMARY_LANGUAGE_OR_STACK>`
- `<TEST_COMMAND>`
- `<BUILD_COMMAND>`
- `<PACKAGE_OR_RELEASE_COMMAND>`
- `<PROJECT_ARCHITECTURE>`
- 금지하거나 승인 받아야 하는 명령

---

# Agent Guide

이 문서는 `<PROJECT_NAME>` repository에서 AI coding agent와 개발자가 작업할 때 따라야 할 최상위 규칙입니다. 세부 기준은 `docs/development-guide.md`를 우선합니다.

## 먼저 읽을 문서

작업 시작 전 아래 순서로 확인합니다.

1. `docs/development-guide.md`
2. `docs/development-roadmap.md`
3. `docs/development-log.md`
4. 관련 큰 기능이 있으면 `docs/implemented/`
5. 사용자에게 보이는 동작 변경이면 `README.md`와 필요한 언어별 README

## 작업 원칙

- 작업 전 `git status --short --branch`로 현재 branch와 dirty state를 확인합니다.
- 기존 코드 패턴을 먼저 확인하고, 변경 범위를 작게 유지합니다.
- 사용자에게 보이는 동작이 바뀌면 README 갱신 여부를 확인합니다.
- 의미 있는 구현, 정책 변경, 버그 수정, 검증 결과는 `docs/development-log.md`에 기록합니다.
- 큰 기능 완료 기록은 필요하면 `docs/implemented/`에 별도 문서로 남기고 development log에서 링크합니다.
- `docs/README.md`는 문서 탐색용 landing page입니다. 작업 정책은 `docs/development-guide.md`를 우선합니다.
- root에 새 문서를 만들기 전 `docs/` 아래에 두는 편이 맞는지 확인합니다. 예외적으로 agent가 항상 읽어야 하는 지침은 `AGENTS.md`처럼 root에 둡니다.

## Git 작업

- 작업 시작 전 현재 branch, remote, uncommitted changes를 확인합니다.
- 사용자가 commit을 요청하면 관련 파일만 `git add`하고 명확한 commit message로 커밋합니다.
- unrelated/user 변경은 되돌리지 않습니다.
- `git reset --hard`, `git checkout -- <file>`, 강제 push 같은 파괴적 작업은 사용자가 명확히 요청했을 때만 합니다.
- 구현 완료 후에는 변경 파일, 테스트 결과, 남은 risk를 final response에 요약합니다.

## 검증

- 코드 변경은 focused test를 먼저 실행하고, 마지막에 전체 test를 실행합니다.
- 문서만 변경한 경우에는 문서 목록과 관련 문구 검색으로 검증합니다.
- 검증 결과는 final response와 필요 시 `docs/development-log.md`에 남깁니다.

## 명시적 승인 없이 하지 않을 작업

아래 작업은 사용자가 명확히 승인했을 때만 합니다.

- 앱 실행 또는 GUI 실행
- release build
- package 생성
- 배포 산출물 생성
- production deploy
- database migration 적용
- 외부 서비스에 write하는 명령
- destructive command
- 강제 push
- secret/token 변경

---

# Development Guide

이 문서는 `<PROJECT_NAME>`을 개발할 때 지킬 운영 기준을 정리합니다.

## 개발 환경

기본 개발 환경:

- `<PRIMARY_LANGUAGE_OR_STACK>`
- `<RUNTIME_OR_PLATFORM_VERSION>`
- `<PACKAGE_MANAGER_OR_BUILD_TOOL>`

## 아키텍처

`<PROJECT_ARCHITECTURE>`를 간단히 적습니다.

예:

```text
Core
  - Domain logic
  - Parser / Store / Service

App
  - UI
  - State management
  - Platform integration

CLI / Tools
  - Diagnostics
  - Local automation
```

## 문서 역할

repository root는 사용자와 GitHub 공개 운영에 필요한 문서만 둡니다.

- `README.md`: 사용자용 기본 문서
- `README.ko.md`: 한국어 문서가 필요한 경우
- `LICENSE`: license와 attribution
- `CONTRIBUTING.md`: GitHub issue / branch / PR / review 기준
- `AGENTS.md`: AI coding agent 작업 기준
- `.github/`: GitHub issue / PR template, label seed

개발 과정에서 계속 갱신하는 문서는 `docs/` 아래에서 관리합니다.

- `docs/README.md`: 문서 index 및 GitHub `docs/` landing page
- `docs/development-roadmap.md`: 현재 방향과 다음 phase
- `docs/development-log.md`: 날짜/시간별 작업 기록
- `docs/specs/`: 활성 설계 문서
- `docs/plans/`: 활성 실행 계획
- `docs/implemented/`: 큰 기능 완료 기록
- `docs/archive/`: 과거 계획과 완료된 계획 보관

## 작업 전 확인 순서

1. `git status --short --branch`로 현재 branch와 dirty state를 확인합니다.
2. `docs/development-roadmap.md`에서 현재 phase와 금지 범위를 확인합니다.
3. `docs/development-log.md`에서 최근 결정과 버그 기록을 확인합니다.
4. 관련 큰 기능이 있으면 `docs/implemented/`의 구현 기록을 확인합니다.
5. 사용자 문서에 영향을 주는 변경이면 README 갱신 여부를 확인합니다.
6. 루트에 새 문서를 추가하기 전에 `docs/README.md` 또는 `docs/archive/`에 두는 편이 맞는지 확인합니다.

## 문서 수정 규칙

사용자에게 보이는 동작이 변경되면 아래 문서 갱신 여부를 반드시 확인합니다.

- `README.md`
- 언어별 README
- 관련 사용법 문서

큰 기능 구현이나 정책 변경은 `docs/development-log.md`에 기록하고, 필요하면 `docs/implemented/`에 별도 완료 기록을 남깁니다.

아직 구현되지 않은 큰 작업은 먼저 `docs/specs/`에 설계를 두고, 승인된 실행 순서는 `docs/plans/`에 둡니다. 완료 후에는 필요한 내용을 `docs/implemented/`로 정리하고 활성 계획은 `docs/archive/`로 이동합니다.

## Development Log 작성 규칙

- 위치: `docs/development-log.md`
- 모든 시간은 프로젝트 기준 timezone으로 기록합니다.
- 의미 있는 개발 결정, 버그 수정, 구현 완료, 검증 결과를 남깁니다.
- 큰 기능은 `docs/implemented/`에 별도 구현 기록을 만들고 log에서 링크합니다.
- 작은 버그 수정, 의심점, 판단은 log에만 남겨도 됩니다.
- GitHub issue나 PR이 있으면 함께 링크합니다.
- commit hash는 필수는 아닙니다. 공개 GitHub 흐름에서는 PR 링크를 우선합니다.

권장 형식:

```md
## 2026-06-23

### 14:30 KST

- 완료: `<FEATURE_NAME>` 구현 정리
- 문서: [구현 기록](implemented/YYYY-MM-DD-feature-name.md)
- 검증: `<TEST_COMMAND>` -> pass
- 결정:
  - `<DECISION_1>`
  - `<DECISION_2>`
- 다음: `<NEXT_WORK>`
- 제외:
  - `<OUT_OF_SCOPE_WORK>`
```

## 테스트와 검증

- 일반 코드 변경은 focused test를 먼저 실행하고, 마지막에 전체 test를 실행합니다.
- 문서 변경은 문서 목록과 활성 문서 검색으로 검증합니다.
- 앱 실행, GUI 실행, package 생성, 배포 산출물 생성은 사용자가 명시적으로 요청했을 때만 실행합니다.
- release 작업이 아닌 일반 개발 작업에서 `dist`, `build`, generated artifact를 함부로 생성, 삭제, 갱신하지 않습니다.

프로젝트별 검증 명령:

```bash
<FOCUSED_TEST_COMMAND>
<TEST_COMMAND>
<BUILD_COMMAND>
```

문서 변경 검증 예:

```bash
rg --files docs README.md CONTRIBUTING.md LICENSE AGENTS.md
rg -n "<확인할-구식-문구-또는-임시-표현>" docs README.md CONTRIBUTING.md AGENTS.md
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
feature/<short-feature-name>
fix/<short-bug-name>
docs/<short-doc-name>
refactor/<short-refactor-name>
release/vX.Y.Z
```

권장 label:

```text
type:bug
type:feature
type:docs
type:refactor
type:test
area:core
area:ui
area:infra
area:docs
area:release
priority:p1
priority:p2
priority:p3
status:needs-design
status:ready
status:blocked
```

`.github/labels.yml`은 GitHub label을 수동 생성하거나 label sync 도구를 사용할 때 기준으로 사용합니다. `gh` CLI나 label sync 도구가 없는 환경에서는 repository 생성 후 GitHub UI에서 같은 이름으로 맞춥니다.

## Git 작업 기준

- 작업 시작 전 branch와 dirty state를 확인합니다.
- commit 요청이 있을 때는 관련 파일만 stage합니다.
- unrelated/user 변경은 되돌리지 않습니다.
- 파괴적 명령은 사용자가 명확히 요청한 경우에만 실행합니다.
- 구현 완료 후 변경 파일과 검증 결과를 final response에 요약합니다.

## License / Attribution

- license와 attribution은 repository root의 `LICENSE`에서 관리합니다.
- 원작자 notice나 third-party attribution이 있으면 제거하거나 축소하지 않습니다.
- 문서에서는 license 전문을 반복하지 말고 `LICENSE`로 링크합니다.

## 프로젝트별 금지 범위

프로젝트마다 아래를 명확히 적습니다.

예:

- production database 직접 수정 금지
- user data 삭제 금지
- external API write 금지
- deploy 금지
- generated release artifact commit 금지
- secret/token commit 금지
- sample/private asset commit 금지

---

# Docs README

이 디렉터리는 `<PROJECT_NAME>`의 개발 문서를 관리합니다.

이 파일은 GitHub에서 `docs/` 디렉터리를 열 때 자동으로 표시되는 landing page입니다. 정책과 작업 기준은 `development-guide.md`를 우선합니다.

## 먼저 볼 문서

- [개발 로드맵](development-roadmap.md): 현재 구현 상태, 다음 phase, 작업 경계
- [개발 가이드](development-guide.md): 작업 방식, 로그 작성 규칙, 검증 기준, GitHub 운영 원칙
- [개발 로그](development-log.md): 날짜/시간별 작업 기록, 버그, 결정, 검증 결과

## 프로젝트 최상위 문서

repository root에는 사용자와 외부 기여자가 바로 확인해야 하는 문서만 둡니다.

- [README](../README.md): 기본 사용자 문서
- [CONTRIBUTING](../CONTRIBUTING.md): GitHub issue / branch / PR / review 기준
- [LICENSE](../LICENSE): license와 attribution
- [AGENTS](../AGENTS.md): AI coding agent 작업 기준

개발 기록, roadmap, 완료 구현 기록은 `docs/` 아래에서 함께 관리합니다.

## 완료 기록

큰 기능이 완료되면 `implemented/` 아래에 별도 구현 기록을 남깁니다.

예:

- `implemented/YYYY-MM-DD-feature-name.md`

작은 버그 수정이나 판단은 [개발 로그](development-log.md)에만 남겨도 됩니다. 큰 기능은 구현 기록을 만들고 개발 로그에서 링크합니다.

## 활성 설계와 계획

진행 중이거나 다음에 실행할 설계/계획은 `specs/`와 `plans/` 아래에서 관리합니다.

- `specs/YYYY-MM-DD-feature-name.md`
- `plans/YYYY-MM-DD-feature-name.md`

## 보관 문서

`archive/`는 과거 계획과 완료된 계획을 보관하는 곳입니다. 현재 작업 기준 문서가 아니므로, 새 작업을 시작할 때는 활성 문서인 roadmap / guide / log를 우선합니다.

---

# CONTRIBUTING Template

## 기본 원칙

- issue 없이 큰 작업을 시작하지 않습니다. 작은 문서 수정이나 명확한 버그 수정은 예외입니다.
- PR은 하나의 목적만 가집니다.
- unrelated formatting, refactor, feature를 한 PR에 섞지 않습니다.
- 사용자에게 보이는 변경은 README 갱신 여부를 확인합니다.
- 큰 기능은 `docs/development-log.md`와 필요 시 `docs/implemented/`를 갱신합니다.

## Branch Naming

```text
feature/<short-feature-name>
fix/<short-bug-name>
docs/<short-doc-name>
refactor/<short-refactor-name>
test/<short-test-name>
release/vX.Y.Z
```

## Commit Message

권장 형식:

```text
type: concise summary
```

예:

```text
feat: add playback timing controller
fix: preserve previous session on failed switch
docs: archive completed roadmap plan
test: cover invalid import manifest
refactor: split parser diagnostics
```

## PR Checklist

- [ ] 변경 범위가 PR 목적과 맞음
- [ ] unrelated/user 변경을 되돌리지 않음
- [ ] focused test 실행
- [ ] 전체 test 또는 합리적인 대체 검증 실행
- [ ] README 갱신 여부 확인
- [ ] `docs/development-log.md` 갱신 여부 확인
- [ ] 큰 기능이면 `docs/implemented/` 기록 여부 확인
- [ ] release/build/generated artifact가 불필요하게 포함되지 않음
- [ ] secret/token/private sample data가 포함되지 않음

## Review 기준

리뷰는 아래 순서로 봅니다.

1. behavioral regression
2. data loss / security / privacy risk
3. missing tests
4. API / architecture consistency
5. readability
6. style

style-only comment는 동작 위험보다 우선하지 않습니다.

---

# GitHub Issue Templates

## Bug Report

```md
## 증상

## 기대 동작

## 재현 절차

1.
2.
3.

## 환경

- OS:
- Version:
- Branch/Commit:

## 로그 / 스크린샷

## 영향 범위

## 추가 메모
```

## Feature Request

```md
## 목표

## 배경

## 원하는 동작

## 제외할 범위

## 검증 방법

## 관련 문서 / issue
```

## Design Task

```md
## 문제

## 현재 구조

## 후보 해결책

## 결정해야 할 것

## 금지 범위

## 산출물
```
