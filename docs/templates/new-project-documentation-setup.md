# New Project Documentation Setup

이 문서는 새 프로젝트를 처음 만들 때 문서 구조를 어떻게 잡을지 정리한 초기 세팅 템플릿입니다.

목표:

- repository root를 깔끔하게 유지
- 개발 기록과 계획을 `docs/` 아래에서 지속적으로 관리
- AI agent / 사람 개발자가 같은 기준으로 작업
- GitHub issue / PR / commit 흐름을 처음부터 고정
- 나중에 프로젝트가 커져도 문서가 흩어지지 않게 함

복사 후 `<PROJECT_NAME>`, `<STACK>`, `<TEST_COMMAND>` 같은 placeholder만 프로젝트에 맞게 바꿉니다.

## 1. 추천 초기 파일 구조

새 repo를 만들면 먼저 아래 구조를 잡습니다.

```text
<PROJECT_ROOT>/
├── README.md
├── README.ko.md                  # 필요할 때만
├── LICENSE
├── CONTRIBUTING.md
├── AGENTS.md
├── .gitignore
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── design_task.md
│   ├── pull_request_template.md
│   └── labels.yml
└── docs/
    ├── README.md
    ├── development-guide.md
    ├── development-roadmap.md
    ├── development-log.md
    ├── specs/
    ├── plans/
    ├── implemented/
    ├── archive/
    └── templates/
```

규칙:

- root에는 외부 사용자가 바로 봐야 하는 문서만 둡니다.
- 개발 과정에서 계속 바뀌는 문서는 `docs/` 아래에 둡니다.
- 완료된 계획은 삭제하지 말고 `docs/archive/`로 보냅니다.
- 큰 기능 완료 기록은 `docs/implemented/`에 따로 남깁니다.

## 2. 폴더별 역할

| Path | 역할 |
| --- | --- |
| `README.md` | GitHub 첫 화면. 설치, 실행, 핵심 기능, 현재 상태 |
| `README.ko.md` | 한국어 사용자 문서가 필요할 때 |
| `LICENSE` | license와 attribution |
| `CONTRIBUTING.md` | issue, branch, PR, review 규칙 |
| `AGENTS.md` | AI coding agent가 반드시 읽을 작업 규칙 |
| `docs/README.md` | docs 디렉터리 index |
| `docs/development-guide.md` | 개발 운영 규칙 |
| `docs/development-roadmap.md` | 현재 방향, phase, 다음 작업 |
| `docs/development-log.md` | 날짜/시간별 작업 기록 |
| `docs/specs/` | 아직 구현 전인 설계 문서 |
| `docs/plans/` | 승인된 실행 계획 |
| `docs/implemented/` | 완료된 큰 기능 기록 |
| `docs/archive/` | 끝난 계획, 과거 문서, 폐기된 설계 |
| `docs/templates/` | 재사용할 문서 템플릿 |

## 3. 처음 만들 파일 순서

초기 세팅은 아래 순서로 진행합니다.

```text
1. README.md
2. LICENSE
3. docs/README.md
4. docs/development-guide.md
5. docs/development-roadmap.md
6. docs/development-log.md
7. AGENTS.md
8. CONTRIBUTING.md
9. .github issue / PR templates
10. 첫 commit
```

이유:

- README와 LICENSE는 repo 정체성을 먼저 고정합니다.
- `docs/` 구조를 먼저 잡아야 이후 계획과 기록이 흩어지지 않습니다.
- `AGENTS.md`는 AI agent가 작업하기 전에 읽는 진입점입니다.
- GitHub template은 issue/PR 흐름이 생기기 전에 깔아두는 편이 좋습니다.

## 4. 초기 README.md

처음 README는 길게 쓰지 않습니다. 프로젝트가 실제로 뭘 하는지, 현재 상태가 뭔지만 명확히 씁니다.

```md
# <PROJECT_NAME>

<PROJECT_NAME> is <ONE_SENTENCE_DESCRIPTION>.

## Status

- Stage: early development
- Stability: experimental
- Target users: <TARGET_USERS>

## Features

- <FEATURE_1>
- <FEATURE_2>
- <FEATURE_3>

## Requirements

- <RUNTIME_OR_PLATFORM>
- <DEPENDENCY>

## Getting Started

```bash
<INSTALL_COMMAND>
<RUN_COMMAND>
```

## Development

```bash
<TEST_COMMAND>
<BUILD_COMMAND>
```

Development docs live in [`docs/`](docs/README.md).

## License

See [`LICENSE`](LICENSE).
```

README에는 아직 확정되지 않은 기능을 확정된 것처럼 쓰지 않습니다. 계획은 `docs/development-roadmap.md`에 둡니다.

## 5. 초기 docs/README.md

```md
# Documentation

이 디렉터리는 <PROJECT_NAME>의 개발 문서를 관리합니다.

정책과 작업 기준은 `development-guide.md`를 우선합니다.

## 먼저 볼 문서

- [Development Guide](development-guide.md): 작업 방식, 검증 기준, Git 운영
- [Roadmap](development-roadmap.md): 현재 phase와 다음 작업
- [Development Log](development-log.md): 날짜/시간별 작업 기록

## 문서 구조

- `specs/`: 구현 전 설계
- `plans/`: 승인된 실행 계획
- `implemented/`: 완료된 큰 기능 기록
- `archive/`: 끝난 계획과 과거 문서
- `templates/`: 재사용 템플릿

## 원칙

- root에는 사용자/기여자용 문서만 둔다.
- 개발 중 바뀌는 문서는 `docs/` 아래에서 관리한다.
- 완료된 계획은 `archive/`로 이동한다.
- 큰 기능은 `implemented/`에 완료 기록을 남긴다.
```

## 6. 초기 development-guide.md

```md
# Development Guide

이 문서는 <PROJECT_NAME> 개발 운영 기준을 정리합니다.

## 개발 환경

- <STACK>
- <RUNTIME_VERSION>
- <PACKAGE_MANAGER>

## 아키텍처

```text
<PROJECT_ARCHITECTURE>
```

## 작업 전 확인 순서

1. `git status --short --branch`
2. `docs/development-roadmap.md`
3. `docs/development-log.md`
4. 관련 기능이 있으면 `docs/implemented/`
5. 사용자 동작 변경이면 `README.md` 갱신 여부 확인

## 문서 규칙

- 구현 전 설계는 `docs/specs/`에 둔다.
- 승인된 실행 계획은 `docs/plans/`에 둔다.
- 완료된 큰 기능은 `docs/implemented/`에 기록한다.
- 끝난 계획과 과거 문서는 `docs/archive/`로 이동한다.
- 중요한 결정, 버그 수정, 검증 결과는 `docs/development-log.md`에 남긴다.

## 검증

코드 변경:

```bash
<FOCUSED_TEST_COMMAND>
<TEST_COMMAND>
```

문서 변경:

```bash
rg --files docs README.md CONTRIBUTING.md AGENTS.md LICENSE
rg -n "<검색할 구식 문구>" docs README.md CONTRIBUTING.md AGENTS.md
```

## Git 규칙

- 관련 파일만 stage한다.
- unrelated 변경은 되돌리지 않는다.
- destructive command는 명시적 승인 없이는 실행하지 않는다.
- commit message는 짧고 구체적으로 작성한다.

## 금지 / 승인 필요 작업

명시적 승인 없이 하지 않을 작업:

- production deploy
- release build
- package 생성
- generated artifact 생성/삭제
- database migration 적용
- external API write
- secret/token 변경
- 강제 push
```

## 7. 초기 development-roadmap.md

로드맵은 할 일을 전부 넣는 문서가 아닙니다. “지금 어디까지 왔고 다음 큰 방향이 뭔지”만 관리합니다.

```md
# Development Roadmap

수정일: YYYY-MM-DD

## 제품 정체성

<PROJECT_NAME>은 <PRODUCT_IDENTITY>입니다.

## 현재 상태

### 구현 완료

- <DONE_1>
- <DONE_2>

### 진행 중

- <IN_PROGRESS_1>

### 아직 하지 않음

- <NOT_STARTED_1>
- <NOT_STARTED_2>

## Phase

### P1: <PHASE_NAME>

상태: planned / in progress / implemented

목표:

- <GOAL_1>

제외:

- <OUT_OF_SCOPE_1>

### P2: <PHASE_NAME>

상태: planned

## Suggested Execution Order

```text
P1
-> P2
-> P3
```

## Next Planning Session

1. <NEXT_DESIGN_TASK>
2. <NEXT_PLAN_TASK>
3. <DO_NOT_START_YET>
```

## 8. 초기 development-log.md

처음부터 로그를 둡니다. 나중에 기억으로 복구하려고 하면 거의 항상 틀립니다.

```md
# Development Log

모든 시간은 <TIMEZONE> 기준입니다.

## YYYY-MM-DD

### HH:MM <TZ>

- 시작: repository documentation baseline 생성
- 문서:
  - `README.md`
  - `docs/README.md`
  - `docs/development-guide.md`
  - `docs/development-roadmap.md`
  - `docs/development-log.md`
  - `AGENTS.md`
  - `CONTRIBUTING.md`
- 결정:
  - root에는 사용자/기여자용 문서만 둠
  - 개발 기록과 계획은 `docs/` 아래에서 관리
  - 큰 기능은 specs -> plans -> implemented -> archive 흐름으로 관리
- 검증:
  - `rg --files docs README.md CONTRIBUTING.md AGENTS.md LICENSE`
```

## 9. 초기 AGENTS.md

```md
# Agent Guide

이 문서는 <PROJECT_NAME> repository에서 AI coding agent가 작업할 때 따라야 할 최상위 규칙입니다.

세부 기준은 `docs/development-guide.md`를 우선합니다.

## 먼저 읽을 문서

1. `docs/development-guide.md`
2. `docs/development-roadmap.md`
3. `docs/development-log.md`
4. 관련 큰 기능이 있으면 `docs/implemented/`
5. 사용자 동작 변경이면 `README.md`

## 작업 원칙

- 작업 전 `git status --short --branch`를 확인합니다.
- 기존 코드 패턴을 먼저 확인합니다.
- 변경 범위를 작게 유지합니다.
- 사용자에게 보이는 동작이 바뀌면 README 갱신 여부를 확인합니다.
- 의미 있는 결정, 버그 수정, 검증 결과는 `docs/development-log.md`에 기록합니다.
- 큰 기능 완료는 필요하면 `docs/implemented/`에 별도 기록을 남깁니다.

## Git 작업

- 관련 파일만 stage합니다.
- unrelated/user 변경은 되돌리지 않습니다.
- destructive command는 사용자가 명확히 요청했을 때만 실행합니다.
- commit 요청이 있으면 명확한 message로 커밋합니다.

## 검증

- 코드 변경은 focused test 후 전체 test를 실행합니다.
- 문서 변경은 문서 목록과 관련 문구 검색으로 검증합니다.
- 검증 결과는 final response에 요약합니다.

## 승인 없이 하지 않을 작업

- production deploy
- release build
- package 생성
- generated artifact 생성/삭제
- database migration 적용
- external API write
- secret/token 변경
- 강제 push
```

## 10. 초기 CONTRIBUTING.md

```md
# Contributing

## 기본 원칙

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

```text
type: concise summary
```

예:

```text
feat: add import parser
fix: preserve session on failed startup
docs: add development workflow
test: cover invalid config
refactor: split diagnostics
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
- [ ] secret/token/private data가 포함되지 않음
```

## 11. Issue / PR Template

`.github/ISSUE_TEMPLATE/bug_report.md`

```md
# Bug Report

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
```

`.github/ISSUE_TEMPLATE/feature_request.md`

```md
# Feature Request

## 목표

## 배경

## 원하는 동작

## 제외할 범위

## 검증 방법

## 관련 문서 / issue
```

`.github/pull_request_template.md`

```md
## Summary

## Changes

## Verification

## Docs

## Risks / Follow-up

## Checklist

- [ ] Focused test
- [ ] Full test or documented alternative
- [ ] README checked
- [ ] Development log checked
- [ ] No unrelated changes
- [ ] No secrets/private data
```

## 12. 첫 commit 기준

초기 문서 세팅 첫 commit에는 아래만 넣습니다.

```text
README.md
LICENSE
CONTRIBUTING.md
AGENTS.md
docs/
.github/
.gitignore
```

권장 commit message:

```text
docs: establish project documentation workflow
```

첫 commit 전에 확인:

```bash
git status --short
rg --files docs README.md CONTRIBUTING.md AGENTS.md LICENSE .github
git diff --check
```

## 13. 운영 흐름

새 기능을 시작할 때:

```text
idea
-> docs/specs/YYYY-MM-DD-feature-name.md
-> docs/plans/YYYY-MM-DD-feature-name.md
-> implementation
-> tests
-> docs/development-log.md
-> docs/implemented/YYYY-MM-DD-feature-name.md
-> move completed specs/plans to docs/archive/
```

작은 버그 수정:

```text
bug
-> fix
-> focused test
-> docs/development-log.md if meaningful
-> commit
```

문서만 수정:

```text
docs edit
-> rg --files docs ...
-> rg -n "<old phrase>" docs ...
-> git diff --check
-> commit
```

## 14. 핵심 원칙

- README는 사용자에게 보여줄 현재 사실만 적습니다.
- roadmap은 방향과 phase만 적고, 세부 작업장은 아닙니다.
- development log는 기억 보조가 아니라 결정 기록입니다.
- specs는 “무엇을 왜 할지”를 정합니다.
- plans는 “어떤 순서로 구현할지”를 정합니다.
- implemented는 “무엇이 실제로 끝났는지”를 남깁니다.
- archive는 과거 판단을 보존하되 현재 작업 기준에서 제거합니다.
- root 문서는 적게, docs 문서는 체계적으로 둡니다.
