# 기여 가이드

MacWall에 기여할 때의 기본 기준입니다.

세부 개발 운영 기준은 [docs/development-guide.md](docs/development-guide.md)를 우선합니다.

## 작업 흐름

```text
issue
-> branch
-> PR
-> review
-> merge
```

큰 기능은 먼저 `docs/development-roadmap.md`의 방향과 맞는지 확인합니다. 완료 후에는 `docs/development-log.md`를 갱신하고, 큰 기능이면 `docs/implemented/`에 구현 기록을 추가합니다.

## 브랜치 이름

```text
feature/p2-playback-stability
fix/video-first-play
docs/development-guide
release/v0.3.0
```

## PR에 포함할 내용

- 변경 요약
- 검증 결과
- 관련 issue 링크
- 문서 갱신 여부
- 사용자에게 보이는 동작 변화

코드 변경 PR은 가능한 focused test와 전체 `swift test` 결과를 포함합니다.

문서만 변경한 PR은 문서 목록과 활성 문서 검색 결과를 포함합니다.

## 라이선스

이 project는 MIT license입니다. 원작 project notice와 현재 작업자 notice는 [LICENSE](LICENSE)에 정리되어 있습니다.

기여자는 `LICENSE`의 원작자 notice와 현재 작업자 notice를 제거하거나 축소하면 안 됩니다. 원작 기반 범위 설명도 `LICENSE`에서 관리합니다.

## 금지 범위

- Steam Workshop download/crawling 기능을 추가하지 않습니다.
- Steam authentication 또는 DRM 우회를 구현하지 않습니다.
- 원본 Workshop folder를 수정하지 않습니다.
- 제작자 asset을 업로드, 공유, 재배포하지 않습니다.
- Workshop thumbnail을 desktop fallback source로 사용하지 않습니다.
- Scene fallback은 Metal Scene runtime이 실제 Scene frame을 render할 수 있을 때까지 구현하지 않습니다.

## Release 관련 작업

package 생성, DMG 생성, notarization, 배포 산출물 생성은 release 작업에서만 다룹니다.

일반 개발 PR에서는 명시적인 요청 없이 앱 실행, GUI 실행, package 생성, DMG 생성, notarization, `dist` 산출물 생성/삭제/갱신을 하지 않습니다.
