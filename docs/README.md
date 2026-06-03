# 문서 안내

이 디렉터리는 Workshop Wallpaper Bridge의 개발 문서를 관리합니다.

## 먼저 볼 문서

- [개발 로드맵](development-roadmap.md): 현재 구현 상태, 다음 phase, Scene 작업 경계
- [개발 가이드](development-guide.md): 작업 방식, 로그 작성 규칙, 검증 기준, GitHub 운영 원칙
- [개발 로그](development-log.md): 날짜/시간별 작업 기록, 버그, 결정, 검증 결과

## 프로젝트 최상위 문서

repository root에는 사용자와 외부 기여자가 바로 확인해야 하는 문서만 둡니다.

- [한국어 README](../README.ko.md): 기본 사용자 문서
- [English README](../README.md): GitHub 기본 표시용 영어 문서
- [CONTRIBUTING](../CONTRIBUTING.md): GitHub issue / branch / PR / review 기준
- [LICENSE](../LICENSE): 원작 MIT notice, 현재 작업자 notice, attribution

개발 기록, roadmap, 완료 구현 기록은 `docs/` 아래에서 함께 관리합니다.

## 완료 기록

큰 기능이 완료되면 `implemented/` 아래에 별도 구현 기록을 남깁니다.

- [P1 Desktop Fallback Cache 및 Space Refresh 구현 기록](implemented/2026-06-03-p1-desktop-fallback-cache-and-space-refresh.md)

작은 버그 수정이나 판단은 [개발 로그](development-log.md)에만 남겨도 됩니다. 큰 기능은 구현 기록을 만들고 개발 로그에서 링크합니다.

## 보관 문서

`archive/`는 과거 계획과 완료된 Superpowers 문서를 보관하는 곳입니다. 현재 작업 기준 문서가 아니므로, 새 작업을 시작할 때는 활성 문서인 roadmap / guide / log를 우선합니다.

루트에서 제거한 중복/과거 문서도 필요하면 `archive/legacy/` 아래에 보관합니다.
