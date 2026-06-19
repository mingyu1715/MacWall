# macOS 26 Native Wallpaper Mode Design

작성일: 2026-06-07

상태: 설계 승인 대기

## 목적

MacWall의 기존 desktop-level `NSWindow` backend와 별도로, macOS 26의 native wallpaper pipeline에 들어가는 실험 backend를 만든다.

현재 Fullscreen -> Desktop 복귀 빨간약은 MacWall window/view/player 생존 문제가 아니라 WindowServer가 Dock/native Desktop Picture layer를 먼저 합성하고 custom desktop window를 나중에 반영하는 문제로 본다. 따라서 목표는 MacWall window를 더 잘 띄우는 것이 아니라 MacWall output을 `WallpaperAgent`가 관리하는 native wallpaper surface로 보내는 것이다.

## 범위

포함:

- WallpaperAgent 동작 관찰과 third-party extension discovery 가능성 검증
- macOS 26 전용 experimental native wallpaper backend
- `WallpaperExtensionKit.framework`와 `com.apple.wallpaper` extension point capability probe
- 별도 `MacWallNativeWallpaperExtension` spike
- Video wallpaper 1개를 native wallpaper surface로 출력하는 최소 경로
- `AVSampleBufferDisplayLayer` 기반 출력 우선 검증
- 실패 지점별 diagnostics

제외:

- macOS 14/15 지원
- Web wallpaper native backend
- Scene wallpaper native backend
- CAMetalLayer 기반 Scene output
- fallback PNG 정책 변경
- 기존 `NSWindow` playback backend 제거
- Dock/Finder injection
- SIP 비활성화 요구
- 시스템 wallpaper DB 직접 수정
- App Store 배포

## 기준 OS

첫 target은 macOS 26 Tahoe 계열이다.

현재 로컬 환경에서 확인된 항목:

- `/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework`
- `/System/Library/CoreServices/WallpaperAgent.app`
- `/System/Library/ExtensionKit/Extensions/*Wallpaper*.appex`
- Apple wallpaper extension들의 `EXExtensionPointIdentifier = com.apple.wallpaper`

macOS 14/15는 native wallpaper extension point의 흔적은 있으나, third-party extension loading과 private request handshake가 macOS 26과 같다는 근거가 부족하므로 이번 설계 대상이 아니다.

## Architecture

```text
MacWall app
├─ Existing NSWindow backend
│  └─ current WallpaperPlayer
│
└─ Native Wallpaper backend (macOS 26 experimental)
   ├─ NativeWallpaperCapabilityProbe
   ├─ NativeWallpaperModeController
   ├─ MacWallNativeWallpaperExtension.appex
   └─ NativeVideoFrameBridge
      └─ AVSampleBufferDisplayLayer
```

기존 backend는 production path로 유지한다. Native backend는 capability probe가 성공하고 사용자가 experimental mode를 켰을 때만 선택한다.

가장 먼저 검증할 것은 rendering surface가 아니라 discovery path다. `WallpaperAgent`가 third-party `com.apple.wallpaper` extension을 발견하고 실행하지 않는다면 native surface 구현 대부분은 의미가 없다. 따라서 spike는 Apple 기본 wallpaper extension과 `WallpaperAgent` 로그를 먼저 관찰하고, 그 다음 MacWall extension discovery/load 여부를 확인한다.

## Components

### NativeWallpaperCapabilityProbe

역할:

- OS major version이 macOS 26 이상인지 확인
- `WallpaperExtensionKit.framework` 존재 확인
- `WallpaperAgent.app` 존재 확인
- `/System/Library/ExtensionKit/Extensions` 아래 `com.apple.wallpaper` extension point 존재 확인
- MacWall bundle 안의 native wallpaper extension 존재 여부 확인

출력:

```swift
struct NativeWallpaperCapabilityReport: Equatable {
    let osSupportsNativeWallpaper: Bool
    let hasWallpaperExtensionKit: Bool
    let hasWallpaperAgent: Bool
    let hasSystemWallpaperExtensionPoint: Bool
    let hasBundledMacWallWallpaperExtension: Bool
    let failureReasons: [String]
}
```

### NativeWallpaperModeController

역할:

- App 쪽 playback backend selection 담당
- native mode가 unavailable이면 기존 `WallpaperPlayer`로 유지
- native mode 실패 시 기존 live playback을 깨지 않고 fallback
- diagnostics에 native mode gate 결과를 남김

### MacWallNativeWallpaperExtension

역할:

- `EXExtensionPointIdentifier = com.apple.wallpaper`를 가진 ExtensionKit extension
- `WallpaperAgent`가 extension을 로드할 수 있는지 확인
- private wallpaper creation/update request를 받아 native wallpaper surface를 확보
- 확보한 surface에 단색 frame, 이후 video frame을 출력

초기에는 MacWall library asset 전체를 다루지 않는다. hardcoded local test video 또는 app group/shared container에 복사된 단일 test video로 제한한다.

### NativeVideoFrameBridge

역할:

- `AVPlayerLayer`를 먼저 쓰지 않는다.
- Phosphene 사례와 remote `CAContext` 제약을 기준으로 `AVSampleBufferDisplayLayer`를 우선 사용한다.
- 첫 spike는 decoding pipeline을 단순화하기 위해 단색 `CMSampleBuffer` 또는 generated pixel buffer를 display layer에 넣는 것부터 시작한다.
- 단색 frame 출력이 확인된 뒤 AVAssetReader 기반 video frame push로 확장한다.

## Data Flow

```text
User enables Native Wallpaper Mode
-> CapabilityProbe runs
-> Native mode available
-> App requests native backend play
-> WallpaperAgent loads MacWallNativeWallpaperExtension
-> Extension receives wallpaper creation/update request
-> Extension obtains remote CAContext-backed surface
-> NativeVideoFrameBridge pushes frames into AVSampleBufferDisplayLayer
-> Desktop transition uses native wallpaper surface
```

## Failure Model

각 실패는 별도 판정으로 남긴다.

| Gate | Failure meaning | Next action |
| --- | --- | --- |
| Apple wallpaper extensions are not observable | Diagnostic method is insufficient | Fix observation method first |
| Third-party extension not registered | ExtensionKit packaging or signing failure | Fix bundle/project before rendering |
| WallpaperAgent does not discover extension | `com.apple.wallpaper` may be Apple-only | Stop native path or research entitlement |
| WallpaperAgent discovers but does not launch extension | lifecycle/entitlement/private handshake issue | Inspect logs before rendering |
| Framework missing | OS unsupported | Keep NSWindow backend |
| Extension point missing | OS unsupported or changed | Keep NSWindow backend |
| Bundled extension not discovered | packaging/signing/project issue | Fix bundle/project |
| WallpaperAgent does not load extension | extension point blocks third-party provider | Stop native path |
| Request object cannot be decoded | private API handshake mismatch | Reverse-engineer request shape |
| CAContext unavailable | native surface not exposed | Stop or inspect WallpaperAgent protocol |
| Surface available but frame not visible | layer/render path issue | Test `AVSampleBufferDisplayLayer` details |
| Frame visible but red pill remains | native pipeline hypothesis weakened | Reassess fallback or alternate native path |

## Acceptance Criteria

Spike success:

- Apple wallpaper extension discovery flow is observable.
- MacWall native wallpaper extension is discoverable on macOS 26.
- `WallpaperAgent` loads the extension without SIP disablement or injection.
- Extension receives a wallpaper lifecycle request.
- A generated frame is visible as the desktop wallpaper surface.
- Fullscreen -> Desktop return does not show the previous macOS system wallpaper.

Partial success:

- Extension loads and receives requests, but user must select it in System Settings.
- Static/generated frame works, but video frame push is not stable yet.
- Native output works on one display only.

Failure:

- Third-party `com.apple.wallpaper` extension is not loaded by `WallpaperAgent`.
- Private request types require Apple-only entitlement.
- The extension cannot access or create the remote `CAContext` surface.

## Security And Distribution

- No SIP disablement.
- No Dock/Finder injection.
- No system database mutation.
- No code signing bypass.
- No App Store target.
- Developer ID + notarization remains a release-stage question.
- Native mode is experimental and macOS-version-gated.

Private framework use means minor macOS updates can break the backend. The app must keep the current `NSWindow` backend as a stable fallback path.

## Testing Strategy

Unit tests:

- Capability probe reports unavailable on mocked missing framework.
- Capability probe reports available when mocked paths and extension point are present.
- Backend selection uses native only when OS, framework, extension point, and user setting all allow it.
- Backend selection falls back to existing `WallpaperPlayer` when native startup fails.

Manual macOS 26 GUI QA:

- Check `pluginkit` or system logs for MacWall native wallpaper extension discovery.
- Check `WallpaperAgent` logs for extension lifecycle.
- Verify generated frame output.
- Verify video frame output.
- Verify Fullscreen -> Desktop return.
- Verify multi-monitor behavior only after single-display success.

## Open Risks

- SwiftPM alone does not model a macOS ExtensionKit app extension target. A checked-in Xcode project or separate spike project is likely required.
- Private `WallpaperExtensionKit` symbols are in dyld shared cache and can change.
- `com.apple.wallpaper` may be internal-only for Apple extensions despite the extension point being visible.
- `AVSampleBufferDisplayLayer` may require exact timing and pixel buffer attributes inside the remote context.
- `CAMetalLayer` support remains unproven and is excluded from the first spike.
