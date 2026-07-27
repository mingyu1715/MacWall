# 문서 인덱스

이 디렉터리는 MacWall의 개발 문서를 관리합니다.

이 파일은 GitHub에서 `docs/` 디렉터리를 열 때 자동으로 표시되는 landing page입니다. 정책과 작업 기준은 `development-guide.md`를 우선합니다.

## 먼저 볼 문서

- [개발 로드맵](development-roadmap.md): 현재 구현 상태, 다음 phase, Scene 작업 경계
- [개발 가이드](development-guide.md): 작업 방식, 로그 작성 규칙, 검증 기준, GitHub 운영 원칙
- [개발 로그](development-log.md): 날짜/시간별 작업 기록, 버그, 결정, 검증 결과
- [라이선스 정책](license-policy.md): 최종 확정 전까지의 라이선스 방향과 분리 기준

## 프로젝트 최상위 문서

repository root에는 사용자와 외부 기여자가 바로 확인해야 하는 문서만 둡니다.

- [한국어 README](../README.ko.md): 기본 사용자 문서
- [English README](../README.md): GitHub 기본 표시용 영어 문서
- [CONTRIBUTING](../CONTRIBUTING.md): GitHub issue / branch / PR / review 기준
- [LICENSE](../LICENSE): 원작 MIT notice, 현재 작업자 notice, attribution
- [AGENTS](../AGENTS.md): AI coding agent 작업 기준

개발 기록, roadmap, 완료 구현 기록은 `docs/` 아래에서 함께 관리합니다.

## 완료 기록

큰 기능이 완료되면 `implemented/` 아래에 별도 구현 기록을 남깁니다.

- [P1 Desktop Fallback Cache 및 Space Refresh 구현 기록](implemented/2026-06-03-p1-desktop-fallback-cache-and-space-refresh.md)
- [P2 Playback Stability 구현 기록](implemented/2026-06-04-p2-playback-stability.md)
- [macOS 26 Native Wallpaper Spike 구현 기록](implemented/2026-06-15-macos-26-native-wallpaper-spike.md)

작은 버그 수정이나 판단은 [개발 로그](development-log.md)에만 남겨도 됩니다. 큰 기능은 구현 기록을 만들고 개발 로그에서 링크합니다.

## 활성 설계와 계획

진행 중이거나 다음에 실행할 Superpowers 설계/계획은 `superpowers/specs/`와 `superpowers/plans/` 아래에서 관리합니다.

- [macOS 26 Native Wallpaper Snapshot Export Gate 설계](superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md)
- [macOS 26 Native Wallpaper Snapshot Export Gate 실행 계획](superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md)
- [macOS 26 Native Wallpaper Playback Timing 설계](superpowers/specs/2026-06-19-native-wallpaper-playback-timing.md)
- [macOS 26 Native Wallpaper Playback Timing 실행 계획](superpowers/plans/2026-07-20-native-wallpaper-playback-timing.md)
- [macOS 26 Native Wallpaper Backend 승격 설계](superpowers/specs/2026-07-27-native-wallpaper-backend-promotion-design.md)

## 재사용 템플릿

- [새 프로젝트 문서 초기 세팅](templates/new-project-documentation-setup.md): 새 repository를 시작할 때 문서 구조와 생성 순서를 잡는 기준
- [프로젝트 문서 및 Git 운영 템플릿](templates/project-docs-and-git-workflow-template.md): AGENTS, 개발 가이드, 기여 및 GitHub 운영 규칙 모음

## 보관 문서

`archive/`는 과거 계획과 완료된 Superpowers 문서를 보관하는 곳입니다. 현재 작업 기준 문서가 아니므로, 새 작업을 시작할 때는 활성 문서인 roadmap / guide / log를 우선합니다.

루트에서 제거한 중복/과거 문서도 필요하면 `archive/legacy/` 아래에 보관합니다.
