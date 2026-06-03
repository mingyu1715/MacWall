# P1 Desktop Fallback Cache 및 Space Refresh 구현 기록

상태: 구현 완료

날짜: 2026-06-03

이 문서는 P1에서 완료한 Desktop Fallback Cache와 Space 변경 후 fallback refresh 구현을 기록합니다. 활성 구현 계획이 아니라 완료된 구현 기록입니다.

## 요약

P1은 Spaces 전환이나 전체화면 전환 중 이전 macOS 시스템 배경화면이 잠깐 보이는 현상을 줄이기 위해, asset별 `Derived/desktop-fallback.png` 캐시를 유지합니다. Video와 Web은 Space 변경 후 현재 live 출력으로 fallback을 갱신할 수 있습니다.

fallback 처리는 Play/Apply의 부수 효과입니다. 주 목적은 live playback 시작이며, fallback cache hit, fallback 생성, snapshot 실패, timeout, wallpaper 적용 실패가 live playback을 막으면 안 됩니다.

## Desktop Fallback Cache

- 각 imported asset은 `Derived/desktop-fallback.png` fallback PNG를 가질 수 있습니다.
- 캐시 경로는 `asset.projectDirectory/Derived/desktop-fallback.png`로 계산합니다.
- 기존 캐시가 있으면 generator를 실행하지 않고 macOS system wallpaper에 적용합니다.
- 캐시가 없어도 Play/Apply를 막지 않습니다. live playback을 먼저 시작하고 fallback 생성은 이후 비동기로 진행합니다.
- fallback 생성이 완료되어도 active asset이 생성 대상과 같을 때만 macOS system wallpaper를 갱신합니다.
- Remove, reimport, manual Regenerate는 이전 generation token을 invalidate합니다.
- 같은 asset에 대한 자동 generation은 dedupe되어, Play/Apply를 반복해도 같은 snapshot 작업을 중복 실행하지 않습니다.

## 지원 대상

| Asset type | P1 fallback source |
| --- | --- |
| Video | 실제 source video의 `0.5s` 근처 프레임 또는 Space refresh 시 live current frame |
| Image | 원본 이미지를 ImageIO/CoreGraphics로 PNG 정규화 |
| Web | restricted `WKWebView` snapshot |
| Scene | P1에서 `desktop-fallback.png` 생성 대상 아님 |

`preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png` 등 Workshop thumbnail은 UI thumbnail 전용입니다. fallback source로 사용하지 않습니다.

## Web Snapshot

- Web fallback 생성은 화면 밖 borderless `NSWindow`와 전용 `WKWebView`를 사용합니다.
- 기본 viewport는 현재 main monitor 크기입니다.
- live Web wallpaper와 같은 local-only remote blocker helper를 사용합니다.
- Web loading 완료 후 500ms 안정화 지연 뒤 snapshot을 생성합니다.
- snapshot timeout은 5초입니다.
- snapshot 실패 또는 timeout 시 live playback은 유지하고 임시 window/WebView는 정리합니다.

## Play / Apply 흐름

구현된 Play/Apply 흐름은 live-first입니다.

```text
선택한 item Play/Apply
-> selected asset 검증
-> WallpaperPlayer.shared.play(...)로 live playback 시작
-> fallback coordination용 active asset 설정
-> fallback cache hit: desktop-fallback.png를 macOS system wallpaper에 적용
-> fallback cache miss: 비동기 generation 예약
```

`VideoWallpaperView`는 view가 window에 attach된 뒤 `player.play()`를 한 번 더 호출해서, 앱 실행 후 첫 Play/Apply에서도 live video playback이 시작되도록 보장합니다.

## Space Refresh

P1에는 Space 변경 후 fallback refresh 경로가 포함됩니다.

```text
NSWorkspace.activeSpaceDidChangeNotification
-> 안정화 지연
-> 현재 active asset 확인
-> live Video/Web 출력 캡처
-> Derived/desktop-fallback.png atomic replace
-> active asset이 아직 같을 때만 system wallpaper 재적용
```

구현된 동작:

- `NSWorkspace.activeSpaceDidChangeNotification`을 감지합니다.
- 500ms 안정화 지연을 사용합니다.
- 20초 throttle을 사용합니다.
- active Video/Web wallpaper만 refresh합니다.
- Video refresh는 현재 live playback frame을 캡처합니다.
- Web refresh는 live `WKWebView` 출력을 캡처합니다.
- Scene/Image는 반복 Space refresh 대상에서 제외합니다.
- Scene fallback은 실제 Scene frame을 render할 수 있는 Metal Scene runtime 이후로 보류합니다.

## UI 및 사용자 정책

Library item context menu에는 다음 항목이 있습니다.

```text
Show in Finder
Generate Desktop Fallback
Regenerate Desktop Fallback
```

Stop Playback은 live wallpaper layer를 중지하고 `Derived/desktop-fallback.png` cache file은 나중에 다시 사용할 수 있도록 보존합니다. 앱이 fallback PNG를 macOS system wallpaper로 적용한 상태라면, 현재 wallpaper가 해당 app-applied fallback과 일치할 때만 적용 전 original macOS wallpaper로 복원합니다. 사용자가 앱 재생 중 macOS 설정에서 wallpaper를 직접 바꾼 경우 Stop Playback은 그 변경을 덮어쓰지 않습니다.

사용자가 원래 macOS wallpaper로 되돌리고 싶다면 macOS System Settings에서 직접 변경해야 합니다.

## 검증 기록

완료된 개발 테스트 검증:

- focused test 통과
- 전체 `swift test` 통과: `104 tests, 0 failures`

P1 검증에서는 앱 실행, GUI 실행, 비테스트 build 명령, package 생성, DMG 생성, notarization, 배포 산출물 생성을 사용하지 않았습니다.

## 남은 작업

다음 활성 제품 phase는 P2 Playback Stability입니다.

이 구현 기록에서 Scene S0, Scene fallback, Metal Scene runtime 작업을 시작하지 않습니다.
