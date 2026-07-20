# macOS 26 Native Wallpaper Playback Timing Design

작성일: 2026-06-19

상태: 설계 승인 / 실행 계획 작성 완료

## 목적

MacWall Native Wallpaper Spike의 Desktop native video runtime은 현재 성공 상태다.

확정된 상태:

- `WallpaperExtensionKit` 경로 사용 가능
- `WallpaperAgent`가 third-party `com.apple.wallpaper` extension launch
- `connect`, `provideSettingsViewModels`, `acquire` handshake 성공
- `WallpaperRemoteContextXPC` + `CAContext.remoteContext` 성공
- `AVSampleBufferDisplayLayer` 기반 실제 mp4 재생 성공
- loop playback 성공
- Fullscreen -> Desktop 복귀 시 기존 `NSWindow` backend의 red-pill 문제 해결 확인

남은 playback 품질 문제:

- 프레임을 너무 빨리 enqueue하면 영상이 배속될 수 있음
- 프레임마다 `sleep`으로 맞추면 decode/read 지연 시 끊김이 생길 수 있음
- 목표는 배속 없이 부드러운 native wallpaper playback

이 문서는 구현을 시작하지 않고, 다음 구현 단계에서 사용할 timing 구조를 고정하기 위한 설계 기록이다.

## 범위

포함:

- bounded prebuffer + PTS pacing 분석
- Producer / Consumer 구조 분석
- `CMSampleBufferRenderSynchronizer` 사용 가능성 분석
- `AVSampleBufferDisplayLayer.controlTimebase` 사용 가능성 분석
- frame drop 정책
- 4K / 60fps / 120fps 환경 고려
- fullscreen, occlusion, battery, thermal, reduced mode 고려

제외:

- snapshot/export gate 수정
- Main App 통합
- Scene Engine 구현
- Web wallpaper 구현
- fallback 정책 변경
- release packaging / DMG / notarization

## 현재 문제 구조

현재 asset playback path는 `AVAssetReader`에서 sample을 읽고 `AVSampleBufferDisplayLayer`로 enqueue한다. 이때 renderer가 받을 수 있는 동안 tight loop로 sample을 계속 넣으면, sample PTS와 wall clock / media time의 관계가 약해져 배속처럼 보일 수 있다.

반대로 sample마다 단순 `sleep(frameDuration)`을 넣으면 decode/read 시간이 누적되어 끊김이 생긴다. 특히 4K, 60fps, 120fps에서는 decode 비용과 scheduling jitter가 커지므로 sleep 기반 pacing은 안정적인 구조가 아니다.

따라서 playback timing은 “프레임마다 기다리기”가 아니라, renderer queue에 media time 기준으로 적당한 양만 앞서 채우는 방식이어야 한다.

## Recommended Architecture

추천 구조:

```text
NativeFrameSource
-> BoundedFramePump
-> PTS Pacing
-> NativeRendererAdapter
-> AVSampleBufferDisplayLayer.sampleBufferRenderer
-> WallpaperAgent native CAContext
```

핵심값:

```text
minBufferLead    = 100ms
targetBufferLead = 300ms
maxBufferLead    = 500ms
lateDropStart    = 100~150ms
hardResetLag     = 500ms+
```

`targetBufferLead`는 정상 상태에서 유지하고 싶은 선행 buffer다. `maxBufferLead`를 넘으면 더 이상 enqueue하지 않고 다음 pump를 예약한다. `minBufferLead` 아래로 내려가면 우선적으로 queue를 채운다.

## Components

### NativePlaybackClock

역할:

- playback media time 제공
- rate / pause / resume 관리
- `CMTimebase` 또는 `CMSampleBufferRenderSynchronizer` 기반 clock 소유

권장:

- 단기 실험은 `AVSampleBufferDisplayLayer.controlTimebase`로 시작 가능
- 장기 구조는 `CMSampleBufferRenderSynchronizer`가 더 적합

이유:

- synchronizer는 `AVQueuedSampleBufferRendering` renderer들을 하나의 timebase로 묶을 수 있음
- 향후 video + overlay, video + scene pass, multi-renderer 구조로 확장 가능
- rate, time observer, pause/resume 모델이 명확함

### NativeFrameSource

역할:

- `AVAssetReader`에서 sample buffer 공급
- 향후 Scene/Web frame source로 확장 가능한 추상 경계

주의:

- 현재처럼 uncompressed BGRA frame을 많이 들고 있으면 4K에서 메모리 사용량이 급증한다.
- 4K BGRA 1프레임은 약 31.6MB다.
- 60fps에서 0.5초를 uncompressed frame queue로 들고 있으면 약 950MB까지 갈 수 있다.

따라서 queue는 시간 기준뿐 아니라 byte budget도 가져야 한다.

### BoundedFramePump

역할:

- renderer readiness 확인
- 현재 media time과 다음 sample PTS 비교
- lead가 `maxBufferLead`를 넘으면 enqueue 중단
- lag가 커지면 frame drop 후보로 분류

기본 흐름:

```text
while renderer.isReadyForMoreMediaData:
    mediaNow = playbackClock.currentTime
    samplePTS = nextSample.presentationTime
    lead = samplePTS - mediaNow

    if lead > maxBufferLead:
        schedule next pump near target lead
        break

    if lead < -lateDropStart:
        drop late sample
        continue

    enqueue sample
```

이 구조는 decode/read가 빠를 때는 과잉 enqueue를 막고, decode/read가 느릴 때는 renderer queue가 완전히 비지 않게 만든다.

### NativeRendererAdapter

역할:

- `AVSampleBufferDisplayLayer`와 `AVSampleBufferVideoRenderer` 사용부 격리
- enqueue / flush / status / error / readiness 관리

macOS 26 기준 권장:

- visual layer는 `AVSampleBufferDisplayLayer` 유지
- sample enqueue는 가능하면 `displayLayer.sampleBufferRenderer` 사용

Apple SDK header 기준으로 `AVSampleBufferDisplayLayer`의 old queue API는 macOS 15 이후 deprecated 흐름이고, background thread safe enqueue에는 `sampleBufferRenderer` 사용이 권장된다.

### LoopController

역할:

- loop boundary에서 timeline을 유지
- 가능하면 반복마다 `flush()`로 끊지 않고 sample PTS를 loop offset만큼 retime

권장:

```text
loopPTS = originalPTS + loopIndex * assetDuration
```

이렇게 하면 renderer 입장에서는 media timeline이 계속 증가한다. 매 loop마다 timebase를 다시 잡거나 flush하는 방식보다 끊김 가능성이 낮다.

### DropPolicy

wallpaper playback은 모든 frame을 보존하는 것보다 실시간성을 유지하는 것이 중요하다.

권장 정책:

| 상태 | 기준 | 동작 |
| --- | --- | --- |
| 정상 | lag < 1 frame | enqueue 유지 |
| 약한 지연 | lag 1~2 frames | 즉시 enqueue 또는 소량 drop 후보 |
| 눈에 띄는 지연 | lag > 100~150ms | 늦은 sample drop |
| 심각한 지연 | lag > 500ms | reader / clock reset 또는 reduced mode |

늦은 frame을 계속 enqueue하면 영상이 느리게 따라잡는 것처럼 보일 수 있다. wallpaper에서는 이보다 late frame을 버리고 현재 시점에 맞는 frame으로 따라가는 쪽이 낫다.

### QualityPolicy

상태별 정책:

| 상태 | 정책 |
| --- | --- |
| normal | target 300ms lead, source fps 유지 |
| fullscreen app active | native compositor가 red-pill은 해결하므로 playback 유지, 필요 시 낮은 priority |
| occluded | 15~30fps reduced mode 또는 pause 후보 |
| battery mode | max fps 제한, buffer lead 축소 |
| thermal pressure | frame drop 강화, reduced mode 진입 |
| 4K/60fps | byte budget 강제, uncompressed queue 최소화 |
| 4K/120fps | producer/consumer와 drop policy 필수 |

`QualityPolicy`는 spike 단계에서는 로그와 수동 option으로 시작하고, Main App 통합 전까지 자동 정책은 최소화한다.

## Strategy Comparison

### 1. Bounded Prebuffer + PTS Pacing

판단: 1순위

장점:

- 배속 문제를 직접 해결함
- sleep 기반보다 jitter에 강함
- `isReadyForMoreMediaData`와 잘 맞음
- 구현 범위가 비교적 작음

단점:

- media clock 계산과 scheduling이 필요함
- loop retiming 없이는 loop boundary에서 여전히 끊길 수 있음

### 2. Producer / Consumer

판단: 장기적으로 필요

장점:

- decode/read 지연과 render pacing을 분리할 수 있음
- 4K/60fps 이상에서 안정성 확보에 유리
- frame source가 Video/Scene/Web으로 늘어날 때 구조가 유지됨

단점:

- queue memory 관리가 필수
- uncompressed frame을 많이 쌓으면 메모리 사용량이 과도함
- 동기화와 cancellation 복잡도가 올라감

권장:

- 초기 구현은 single serial pump로 시작
- 4K/60fps 검증 이후 bounded producer/consumer로 확장

### 3. CMSampleBufferRenderSynchronizer

판단: 장기 architecture에 적합

장점:

- renderer timing을 명확히 관리 가능
- multiple renderer 동기화 가능
- rate / pause / resume / time observer 모델이 좋음

단점:

- 단일 video layer만 있는 spike에는 다소 무거움
- WallpaperAgent remote CAContext 환경에서 실제 동작 검증 필요

권장:

- playback runtime으로 승격할 때 `NativePlaybackClock` 내부 구현 후보로 둔다.
- 단기 spike에서는 `controlTimebase`와 비교 실험한다.

### 4. layer.controlTimebase

판단: 단기 실험 가치 높음

장점:

- 단일 layer timing 제어로는 가장 작은 변경
- playback rate 제어와 drift 보정 실험이 쉬움

단점:

- SDK 흐름상 `AVSampleBufferRenderSynchronizer` 쪽이 더 정식 구조에 가까움
- `sampleBufferRenderer`와 함께 쓸 때의 실제 동작 확인 필요

권장:

- 첫 구현 gate에서 비교 실험한다.
- 성공하면 단기 안정화에 사용하고, 장기적으로 synchronizer 전환 가능성을 유지한다.

## Implementation Gates

아직 구현하지 않는다. 다음에 다시 시작할 때는 아래 순서로 진행한다.

### Gate 1: Timing Diagnostics

추가 로그:

- `samplePTS`
- `mediaNow`
- `lead`
- `lag`
- `rendererReady`
- `loopIndex`
- `droppedFrameCount`
- `queuedFrameCount`

목표:

- 현재 배속이 실제로 lead 과잉인지 확인
- loop boundary에서 flush / reset이 끊김을 만드는지 확인

### Gate 2: Bounded Pump

변경:

- tight loop enqueue 제거
- `maxBufferLead` 기준으로 enqueue 중단
- next pump scheduling 추가

성공 기준:

- asset mp4가 배속되지 않음
- generated mode와 비슷한 부드러움 유지
- Fullscreen -> Desktop red-pill 해결 상태 유지

### Gate 3: Timebase / Synchronizer Comparison

비교:

- `AVSampleBufferDisplayLayer.controlTimebase`
- `CMSampleBufferRenderSynchronizer`

성공 기준:

- rate 1.0에서 drift 없음
- pause/resume 가능
- late frame drop과 충돌 없음

### Gate 4: Loop Retiming

변경:

- loop마다 sample PTS에 `loopIndex * assetDuration` offset 적용
- 가능하면 loop boundary flush 최소화

성공 기준:

- loop 시 검은 화면, 멈춤, 속도 변화 없음

### Gate 5: Drop / Reduced Mode

변경:

- `lateDropStart`
- `hardResetLag`
- battery / thermal / reduced mode policy

성공 기준:

- 4K/60fps에서 슬로모션 catch-up 대신 실시간성 유지
- 120fps source에서 과도한 memory 증가 없음

## Source Notes

근거로 확인한 SDK header:

- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVSampleBufferDisplayLayer.h`
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVQueuedSampleBufferRendering.h`
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVSampleBufferRenderSynchronizer.h`
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreMedia.framework/Headers/CMSync.h`

중요한 SDK 관찰:

- `AVSampleBufferDisplayLayer`는 `sampleBufferRenderer`를 제공한다.
- old `AVQueuedSampleBufferRendering` queue API는 deprecated 흐름이다.
- `AVSampleBufferRenderSynchronizer`는 여러 `AVQueuedSampleBufferRendering` renderer를 하나의 timebase로 동기화한다.
- `kCMSampleAttachmentKey_DisplayImmediately`는 timed playback path와 같이 쓰면 timing 제어를 우회할 수 있으므로 debug/generated immediate mode에만 둔다.

## Current Recommendation

다음 작업 재개 시 1차 구현은 아래 조합으로 시작한다.

```text
BoundedFramePump
+ PTS lead/lag diagnostics
+ controlTimebase or synchronizer comparison
+ no DisplayImmediately for asset playback
+ loop PTS retiming
```

Producer / Consumer 구조는 바로 넣지 않는다. 먼저 bounded pump로 현재 배속 문제를 잡고, 4K/60fps 검증에서 decode/read 지연이 실제 병목으로 확인될 때 bounded producer/consumer로 확장한다.

이 설계의 핵심은 MacWall Native Wallpaper Runtime을 단순 video player가 아니라 frame consumer pipeline으로 유지하는 것이다.

```text
Renderer
-> FrameSource
-> Timing / Pacing
-> Native Wallpaper Backend
-> WallpaperAgent
```

이 구조를 유지하면 Video, Scene, Web이 나중에 들어와도 timing과 native backend를 공유할 수 있다.
