# macOS 26 Native Wallpaper Spike 구현 기록

Status: implemented / completed spike

Date: 2026-06-15

## Summary

macOS 26에서 MacWall output을 기존 desktop-level `NSWindow`가 아니라 `WallpaperAgent`가 관리하는 native wallpaper pipeline으로 보낼 수 있음을 확인했다.

가장 중요한 결과는 Video wallpaper 자체보다 아래 구조가 실제로 가능하다는 점이다.

```text
Renderer
-> Frame
-> Native Wallpaper Backend
-> WallpaperAgent
-> Desktop Compositor
```

이 구조에서 `WallpaperAgent`는 사실상 native wallpaper frame consumer 역할을 한다.

## Implemented / Verified

- `WallpaperExtensionKit` path 사용 가능 확인
- third-party `com.apple.wallpaper` extension discovery 확인
- `WallpaperAgent`가 `MacWallNativeWallpaperExtension` process launch 확인
- `connect` handshake 통과
- `provideSettingsViewModels` handshake 통과
- `acquire` request 수신 및 처리 통과
- `CAContext.remoteContext` 생성 성공
- `WallpaperRemoteContextXPC` 생성 및 acquire reply 성공
- static color layer가 실제 Desktop wallpaper surface에 표시됨
- `AVSampleBufferDisplayLayer` 기반 generated frame 출력 성공
- 실제 mp4 playback 성공
- loop playback 성공
- Fullscreen -> Desktop 복귀 시 기존 `NSWindow` backend의 red-pill 문제가 native path에서 해결됨을 사용자 관측으로 확인
- `dev.sh reset/install/status/logs` 기반 native spike 개발 runner 추가
- dev runner protocol 정리:
  - reset
  - install
  - 사용자가 System Settings에서 `MacWall Native Spike` 선택
  - logs/status 확인
  - 사용자 화면 확인
  - 재테스트 전 reset 후 install

## Supported Policy

- 공식 지원 목표는 macOS 26 이상
- Apple Silicon 우선
- Native Wallpaper Backend는 macOS 26 이상에서만 지원 후보로 유지
- 기존 `NSWindow` backend는 fallback / legacy backend로 유지
- 호환성 확대보다 안정성 확보를 우선

## Not Implemented

- Main App 통합
- 일반 사용자용 Native Wallpaper Mode UI
- Web native wallpaper backend
- Scene native wallpaper backend
- CAMetalLayer 기반 Scene output
- snapshot/export 성공 처리
- fallback PNG 정책 변경
- release packaging / DMG / notarization

## Known Follow-ups

### Snapshot / Export Gate

`WallpaperAgent`의 snapshot/export request는 별도 gate로 분리한다.

현재 상태:

- Desktop native video runtime은 snapshot/export와 별개로 동작 가능
- nil snapshot reply는 `WallpaperExtensionError(2)`를 남김
- 일부 candidate는 `NSCocoaErrorDomain(4101)` safe-rejected
- `snapshot-xpc-file-url` 계열은 XPC interruption/runtime removal을 유발할 수 있어 unsafe로 격리

활성 문서:

- `docs/superpowers/specs/2026-06-15-native-wallpaper-snapshot-export-gate-design.md`
- `docs/superpowers/plans/2026-06-15-native-wallpaper-snapshot-export-gate.md`

### Playback Timing

asset mp4 playback은 실제 출력이 성공했지만, enqueue timing 품질 개선이 필요하다.

현재 판단:

- tight-loop enqueue는 배속/과잉 enqueue를 만들 수 있음
- frame마다 sleep하는 방식은 decode/read 지연 시 끊김을 만들 수 있음
- bounded prebuffer + PTS pacing + timebase/synchronizer 기반 구조가 적합

활성 문서:

- `docs/superpowers/specs/2026-06-19-native-wallpaper-playback-timing.md`

## Verification Notes

사용자 관측으로 확인된 항목:

- static native surface 표시
- generated frame 움직임 표시
- 실제 mp4 움직임 표시
- Fullscreen -> Desktop red-pill 해결

agent가 자동화하지 않은 항목:

- System Settings wallpaper 선택
- 실제 Desktop 출력 확인
- Fullscreen -> Desktop 화면 확인

이 항목들은 macOS 화면 상태가 필요하므로 사용자가 직접 확인하고, agent는 이후 `WallpaperAgent` / extension 로그와 대조한다.

## Archived Planning Docs

초기 native wallpaper mode 설계와 spike 실행 계획은 완료된 spike 기록으로 승격되어 archive로 이동했다.

- `docs/archive/superpowers/specs/2026-06-07-macos-26-native-wallpaper-mode.md`
- `docs/archive/superpowers/plans/2026-06-07-macos-26-native-wallpaper-mode-spike.md`
