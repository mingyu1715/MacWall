# Native Wallpaper Playback Timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS 26 native asset-video path play at natural speed with bounded buffering, continuous loop timestamps, explicit late-frame handling, and observable timing diagnostics.

**Architecture:** Keep the working `CAContext -> WallpaperRemoteContextXPC -> WallpaperAgent` surface unchanged. Split timing decisions into a deterministic policy, route rendering through `AVSampleBufferDisplayLayer.sampleBufferRenderer`, drive asset timestamps with a selectable playback clock, and replace the current tight reader loop with a single-queue bounded pump. Generated frames remain an immediate-display diagnostic path.

**Tech Stack:** Swift 6, macOS 26, Apple Silicon, AVFoundation, CoreMedia, QuartzCore, CMake-generated Xcode project, Bash dev runner.

## Global Constraints

- Support target is macOS 26+ on Apple Silicon only.
- Work only inside `MacWallNativeWallpaperSpike`; do not integrate the Main App.
- Keep `--snapshot-mode disabled` throughout playback timing verification.
- Do not modify snapshot/export reply shapes, the existing `NSWindow` backend, fallback policy, Scene, or Web runtime.
- Asset playback must not use `kCMSampleAttachmentKey_DisplayImmediately`.
- Generated mode may keep `kCMSampleAttachmentKey_DisplayImmediately` because it is a diagnostic source.
- Use one serial pump first; do not add producer/consumer queues until measured 4K/60 decode latency proves they are needed.
- System Settings selection, actual Desktop output, playback smoothness, and Fullscreen -> Desktop verification are user actions.
- Do not package, create a DMG, notarize, publish, or touch `dist`.
- Execute this plan in an isolated branch/worktree created with `superpowers:using-git-worktrees`.

---

## File Structure

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift`
  - Pure timing thresholds, lead/lag classification, enqueue/wait/drop/reset decisions.
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift`
  - The only wrapper allowed to call `AVSampleBufferVideoRenderer` queue APIs.
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift`
  - `controlTimebase` and `AVSampleBufferRenderSynchronizer` candidates.
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift`
  - Generated clock mode and timing profile selected by `dev.sh`.
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift`
  - Continuous loop PTS calculation and `CMSampleBuffer` timing-copy helper.
- Create: `MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift`
  - Deterministic policy and retiming tests with no sleep or real-time dependency.
- Modify: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
  - Own clock, renderer adapter, pending sample, bounded scheduling, counters, and lifecycle.
- Modify: `MacWallNativeWallpaperSpike/Tests/MacWallNativeWallpaperRuntimeIdentityTests.swift`
  - Invoke the new test suite from the existing executable test target.
- Modify: `MacWallNativeWallpaperSpike/CMakeLists.txt`
  - Include new extension sources and deterministic test sources.
- Modify: `MacWallNativeWallpaperSpike/dev.sh`
  - Generate clock/profile mode and expose diagnostic status.
- Modify: `MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`
  - Verify mode generation, defaults, unsafe scope boundaries, and timing log fields.
- Modify: `MacWallNativeWallpaperSpike/README.md`
  - Add timing runner and human verification protocol.
- Modify: `docs/development-log.md`
  - Record each completed gate and evidence.

## Fixed Runtime Values

Normal profile:

```text
minBufferLead    = 0.100 seconds
targetBufferLead = 0.300 seconds
maxBufferLead    = 0.500 seconds
lateDropStart    = 0.150 seconds
hardResetLag     = 0.500 seconds
minimumFrameInterval = 0
```

Reduced profile:

```text
minBufferLead    = 0.075 seconds
targetBufferLead = 0.150 seconds
maxBufferLead    = 0.250 seconds
lateDropStart    = 0.100 seconds
hardResetLag     = 0.400 seconds
minimumFrameInterval = 1 / 30 seconds
```

Clock modes:

```text
control-timebase
synchronizer
```

The initial generated/default mode is `synchronizer`. If the manual comparison gate shows that it fails while `control-timebase` succeeds, stop execution and amend this plan before changing the default.

---

### Task 1: Deterministic Timing Policy

**Files:**

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift`
- Create: `MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift`
- Modify: `MacWallNativeWallpaperSpike/Tests/MacWallNativeWallpaperRuntimeIdentityTests.swift`
- Modify: `MacWallNativeWallpaperSpike/CMakeLists.txt`

**Interfaces:**

- Produces: `NativeVideoPlaybackTimingConfiguration.normal`
- Produces: `NativeVideoPlaybackTimingConfiguration.reduced`
- Produces: `NativeVideoPlaybackTimingPolicy.evaluate(samplePTSSeconds:mediaTimeSeconds:rendererReady:lastEnqueuedPTSSeconds:) -> NativeVideoPlaybackEvaluation`
- Consumed by: `NativeVideoFrameBridge` in Task 3 and reduced mode in Task 5.

- [ ] **Step 1: Add failing deterministic tests**

Create `MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift` with tests for normal enqueue, max-lead wait, late drop, hard reset, renderer backpressure, and reduced cadence:

```swift
import Foundation

enum NativeVideoPlaybackTimingTests {
    static func runAll() {
        testNormalSampleEnqueues()
        testLeadBelowMinimumIsReported()
        testFarAheadSampleWaitsTowardTargetLead()
        testLateSampleDrops()
        testSeverelyLateSampleResets()
        testRendererBackpressureDoesNotConsumeSample()
        testReducedProfileDropsExcessCadence()
    }

    private static func testNormalSampleEnqueues() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.25,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .enqueue)
        precondition(abs(result.leadSeconds - 0.25) < 0.000_001)
    }

    private static func testFarAheadSampleWaitsTowardTargetLead() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.80,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        guard case .wait(let seconds) = result.decision else {
            preconditionFailure("expected wait decision")
        }
        precondition(abs(seconds - 0.50) < 0.000_001)
    }

    private static func testLeadBelowMinimumIsReported() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.05,
            mediaTimeSeconds: 0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .enqueue)
        precondition(result.bufferBand == .belowMinimum)
    }

    private static func testLateSampleDrops() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 1.0,
            mediaTimeSeconds: 1.20,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .drop(reason: .late))
    }

    private static func testSeverelyLateSampleResets() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 1.0,
            mediaTimeSeconds: 1.60,
            rendererReady: true,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .reset)
    }

    private static func testRendererBackpressureDoesNotConsumeSample() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .normal).evaluate(
            samplePTSSeconds: 0.25,
            mediaTimeSeconds: 0,
            rendererReady: false,
            lastEnqueuedPTSSeconds: nil
        )
        precondition(result.decision == .waitForRenderer)
    }

    private static func testReducedProfileDropsExcessCadence() {
        let result = NativeVideoPlaybackTimingPolicy(configuration: .reduced).evaluate(
            samplePTSSeconds: 1.01,
            mediaTimeSeconds: 1.0,
            rendererReady: true,
            lastEnqueuedPTSSeconds: 1.0
        )
        precondition(result.decision == .drop(reason: .cadence))
    }
}
```

Call `NativeVideoPlaybackTimingTests.runAll()` from `MacWallNativeWallpaperRuntimeIdentityTests.main()`. Add only the new test file to the existing CMake test target first.

- [ ] **Step 2: Build the focused test target and verify RED**

Run:

```bash
cmake -S MacWallNativeWallpaperSpike -B /tmp/macwall-native-playback-timing-xcode -G Xcode
xcodebuild \
  -project /tmp/macwall-native-playback-timing-xcode/MacWallNativeWallpaperSpike.xcodeproj \
  -scheme MacWallNativeWallpaperRuntimeIdentityTests \
  -configuration Debug \
  build
```

Expected: build fails because `NativeVideoPlaybackTimingPolicy` and related types do not exist.

- [ ] **Step 3: Implement the pure timing policy**

Create `NativeVideoPlaybackTiming.swift`:

```swift
import Foundation

struct NativeVideoPlaybackTimingConfiguration: Equatable, Sendable {
    let minBufferLeadSeconds: Double
    let targetBufferLeadSeconds: Double
    let maxBufferLeadSeconds: Double
    let lateDropStartSeconds: Double
    let hardResetLagSeconds: Double
    let minimumFrameIntervalSeconds: Double

    static let normal = NativeVideoPlaybackTimingConfiguration(
        minBufferLeadSeconds: 0.100,
        targetBufferLeadSeconds: 0.300,
        maxBufferLeadSeconds: 0.500,
        lateDropStartSeconds: 0.150,
        hardResetLagSeconds: 0.500,
        minimumFrameIntervalSeconds: 0
    )

    static let reduced = NativeVideoPlaybackTimingConfiguration(
        minBufferLeadSeconds: 0.075,
        targetBufferLeadSeconds: 0.150,
        maxBufferLeadSeconds: 0.250,
        lateDropStartSeconds: 0.100,
        hardResetLagSeconds: 0.400,
        minimumFrameIntervalSeconds: 1.0 / 30.0
    )
}

enum NativeVideoFrameDropReason: Equatable, Sendable {
    case late
    case cadence
}

enum NativeVideoBufferBand: String, Equatable, Sendable {
    case late
    case belowMinimum
    case target
    case aboveMaximum
}

enum NativeVideoPlaybackDecision: Equatable, Sendable {
    case enqueue
    case wait(seconds: Double)
    case waitForRenderer
    case drop(reason: NativeVideoFrameDropReason)
    case reset
}

struct NativeVideoPlaybackEvaluation: Equatable, Sendable {
    let decision: NativeVideoPlaybackDecision
    let leadSeconds: Double
    let bufferBand: NativeVideoBufferBand

    var lagSeconds: Double { max(-leadSeconds, 0) }
}

struct NativeVideoPlaybackTimingPolicy: Sendable {
    let configuration: NativeVideoPlaybackTimingConfiguration

    func evaluate(
        samplePTSSeconds: Double,
        mediaTimeSeconds: Double,
        rendererReady: Bool,
        lastEnqueuedPTSSeconds: Double?
    ) -> NativeVideoPlaybackEvaluation {
        let lead = samplePTSSeconds - mediaTimeSeconds
        if -lead >= configuration.hardResetLagSeconds {
            return makeEvaluation(decision: .reset, lead: lead)
        }
        if -lead >= configuration.lateDropStartSeconds {
            return makeEvaluation(decision: .drop(reason: .late), lead: lead)
        }
        if let lastEnqueuedPTSSeconds,
           configuration.minimumFrameIntervalSeconds > 0,
           samplePTSSeconds - lastEnqueuedPTSSeconds < configuration.minimumFrameIntervalSeconds {
            return makeEvaluation(decision: .drop(reason: .cadence), lead: lead)
        }
        guard rendererReady else {
            return makeEvaluation(decision: .waitForRenderer, lead: lead)
        }
        if lead > configuration.maxBufferLeadSeconds {
            return makeEvaluation(
                decision: .wait(seconds: lead - configuration.targetBufferLeadSeconds),
                lead: lead
            )
        }
        return makeEvaluation(decision: .enqueue, lead: lead)
    }

    private func makeEvaluation(
        decision: NativeVideoPlaybackDecision,
        lead: Double
    ) -> NativeVideoPlaybackEvaluation {
        let bufferBand: NativeVideoBufferBand
        if lead < 0 {
            bufferBand = .late
        } else if lead < configuration.minBufferLeadSeconds {
            bufferBand = .belowMinimum
        } else if lead > configuration.maxBufferLeadSeconds {
            bufferBand = .aboveMaximum
        } else {
            bufferBand = .target
        }
        return NativeVideoPlaybackEvaluation(
            decision: decision,
            leadSeconds: lead,
            bufferBand: bufferBand
        )
    }
}
```

Add this source to both the extension and focused test targets.

- [ ] **Step 4: Build and run the deterministic tests**

Run the focused build again, then:

```bash
/tmp/macwall-native-playback-timing-xcode/Debug/MacWallNativeWallpaperRuntimeIdentityTests
```

Expected: exit code `0` with no precondition failure.

- [ ] **Step 5: Commit Task 1**

```bash
git add MacWallNativeWallpaperSpike/CMakeLists.txt \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift \
  MacWallNativeWallpaperSpike/Tests/MacWallNativeWallpaperRuntimeIdentityTests.swift \
  MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift
git commit -m "test(native): define playback timing policy"
```

---

### Task 2: Renderer Adapter and Selectable Playback Clock

**Files:**

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift`
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift`
- Create/generated: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift`
- Modify: `MacWallNativeWallpaperSpike/CMakeLists.txt`
- Modify: `MacWallNativeWallpaperSpike/dev.sh`
- Modify: `MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`

**Interfaces:**

- Produces: `NativeVideoRendererAdapter(displayLayer:)`
- Produces: `NativeVideoPlaybackClock(mode:displayLayer:renderer:)`
- Produces: `MacWallNativeWallpaperTimingConfiguration.clockMode`
- Consumed by: `NativeVideoFrameBridge` in Task 3.

- [ ] **Step 1: Add failing runner/source-guard tests**

Add to `dev_runner_tests.sh`:

```bash
timing_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-clock control-timebase)"
assert_contains "$timing_install_output" "MacWallNativeWallpaperTimingMode.generated.swift"
assert_contains "$timing_install_output" "timing clock: control-timebase"

invalid_timing_output="$(
    MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-clock invalid 2>&1 || true
)"
assert_contains "$invalid_timing_output" "Unknown timing clock: invalid"
```

Add source guards for `sampleBufferRenderer`, `AVSampleBufferRenderSynchronizer`, `CMTimebaseCreateWithSourceClock`, `clockMode`, `synchronizer`, and `controlTimebase`.

- [ ] **Step 2: Run runner tests and verify RED**

Run `bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`.

Expected: failure because `--timing-clock` is unknown.

- [ ] **Step 3: Add generated timing mode support**

Add to `dev.sh`:

```bash
TIMING_CLOCK_DEFAULT="synchronizer"
TIMING_PROFILE_DEFAULT="normal"
TIMING_MODE_FILE="$SCRIPT_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift"
```

Extend `install` with `--timing-clock` and `--timing-profile`. Generate:

```swift
enum MacWallNativeWallpaperTimingClockMode: String, Sendable {
    case controlTimebase = "control-timebase"
    case synchronizer
}

enum MacWallNativeWallpaperTimingProfile: String, Sendable {
    case normal
    case reduced
}

enum MacWallNativeWallpaperTimingConfiguration {
    static let clockMode: MacWallNativeWallpaperTimingClockMode = .synchronizer
    static let profile: MacWallNativeWallpaperTimingProfile = .normal
}
```

Reject values outside the listed modes and print both selected values in dry-run and `status` output.

- [ ] **Step 4: Add the renderer adapter**

Create `NativeVideoRendererAdapter.swift`:

```swift
import AVFoundation
import CoreMedia

final class NativeVideoRendererAdapter: @unchecked Sendable {
    let renderer: AVSampleBufferVideoRenderer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        renderer = displayLayer.sampleBufferRenderer
    }

    var isReadyForMoreMediaData: Bool { renderer.isReadyForMoreMediaData }
    var status: AVQueuedSampleBufferRenderingStatus { renderer.status }
    var error: Error? { renderer.error }

    func enqueue(_ sampleBuffer: CMSampleBuffer) { renderer.enqueue(sampleBuffer) }
    func requestMediaDataWhenReady(on queue: DispatchQueue, block: @escaping @Sendable () -> Void) {
        renderer.requestMediaDataWhenReady(on: queue, using: block)
    }
    func stopRequestingMediaData() { renderer.stopRequestingMediaData() }
    func flush(removeDisplayedImage: Bool) {
        renderer.flush(
            removingDisplayedImage: removeDisplayedImage,
            completionHandler: nil
        )
    }
}
```

After this task, both asset and generated paths use the adapter for queue operations. Do not mix `displayLayer.enqueue(...)` with `sampleBufferRenderer` calls.

- [ ] **Step 5: Add clock candidates**

Create `NativeVideoPlaybackClock.swift` with this surface:

```swift
import AVFoundation
import CoreMedia

final class NativeVideoPlaybackClock: @unchecked Sendable {
    let mode: MacWallNativeWallpaperTimingClockMode

    init(
        mode: MacWallNativeWallpaperTimingClockMode,
        displayLayer: AVSampleBufferDisplayLayer,
        renderer: AVSampleBufferVideoRenderer
    )

    var currentTime: CMTime { get }
    func start(at time: CMTime)
    func pause()
    func seek(to time: CMTime)
    func stop()
}
```

Implementation requirements:

- `controlTimebase`: create a host-clock-backed `CMTimebase`, assign it to `displayLayer.controlTimebase`, set time to zero, then rate to `1`.
- `synchronizer`: create `AVSampleBufferRenderSynchronizer`, add the renderer, call `setRate(1, time:)`, and use `currentTime()`.
- `pause()`: set rate `0` without losing current time.
- `seek(to:)`: update time while preserving paused/running state.
- `stop()`: set rate `0`; synchronizer mode removes the renderer with `.invalid` time.
- Log mode, start, seek, and stop through the existing logger.

- [ ] **Step 6: Add sources to CMake and verify GREEN**

Run:

```bash
bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh
xcrun swiftc -frontend -parse \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift
```

Expected: runner tests pass and Swift parse exits `0`.

- [ ] **Step 7: Commit Task 2**

```bash
git add MacWallNativeWallpaperSpike/CMakeLists.txt \
  MacWallNativeWallpaperSpike/dev.sh \
  MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift
git commit -m "feat(native): add selectable playback clock"
```

---

### Task 3: Bounded Asset Pump and Timing Diagnostics

**Files:**

- Modify: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Modify: `MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`

**Interfaces:**

- Consumes: `NativeVideoPlaybackTimingPolicy`
- Consumes: `NativeVideoRendererAdapter`
- Consumes: `NativeVideoPlaybackClock`
- Produces log event: `nativeVideoTiming`

- [ ] **Step 1: Add failing bounded-pump guards**

Require `pendingAssetSampleBuffer`, `scheduleAssetPump`, `NativeVideoPlaybackTimingPolicy`, and every required `nativeVideoTiming` field in `dev_runner_tests.sh`. Also assert the asset path no longer contains the current tight-loop line.

- [ ] **Step 2: Run runner tests and verify RED**

Expected: failure on `pendingAssetSampleBuffer`.

- [ ] **Step 3: Add bounded pump state**

Add to `NativeVideoFrameBridge`:

```swift
private let rendererAdapter: NativeVideoRendererAdapter
private let playbackClock: NativeVideoPlaybackClock
private let timingPolicy: NativeVideoPlaybackTimingPolicy
private var pendingAssetSampleBuffer: CMSampleBuffer?
private var assetPumpGeneration: UInt64 = 0
private var queuedFrameCount: Int64 = 0
private var droppedFrameCount: Int64 = 0
private var lastEnqueuedPTSSeconds: Double?
private var lastTimingLogHostTime: CFTimeInterval = 0
```

Construct adapter and clock from the same display layer. Choose `.normal` or `.reduced` from the generated profile.

- [ ] **Step 4: Replace the tight loop with policy evaluation**

Evaluate one retained or newly read sample:

```swift
let sampleBuffer = pendingAssetSampleBuffer ?? assetOutput.copyNextSampleBuffer()
let samplePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
let samplePTSSeconds = CMTimeGetSeconds(samplePTS)
let mediaNowSeconds = CMTimeGetSeconds(playbackClock.currentTime)
let evaluation = timingPolicy.evaluate(
    samplePTSSeconds: samplePTSSeconds,
    mediaTimeSeconds: mediaNowSeconds,
    rendererReady: rendererAdapter.isReadyForMoreMediaData,
    lastEnqueuedPTSSeconds: lastEnqueuedPTSSeconds
)
```

Decision behavior:

```text
enqueue         -> enqueue once, clear pending, increment queued count, continue
wait            -> retain pending, stop request callback, schedule after delay
waitForRenderer -> retain pending and return for renderer callback
drop            -> clear pending, increment dropped count, continue
reset           -> retain pending, preserve displayed image, seek clock, retry
```

Clamp delays to `0.005...0.500` seconds. Delayed callbacks capture `assetPumpGeneration`; stop/fallback increments it so stale callbacks are ignored.

- [ ] **Step 5: Add rate-limited diagnostics**

Log no more than once per second, plus reset/loop events:

```text
nativeVideoTiming bridgeID=<id> samplePTS=<seconds> mediaNow=<seconds> lead=<seconds> lag=<seconds> bufferBand=<value> rendererReady=<bool> loopIndex=<n> droppedFrameCount=<n> queuedFrameCount=<n> decision=<value> clockMode=<value> profile=<value>
```

- [ ] **Step 6: Complete cleanup behavior**

`stop(reason:)` and generated fallback both execute:

```swift
assetPumpGeneration &+= 1
pendingAssetSampleBuffer = nil
rendererAdapter.stopRequestingMediaData()
playbackClock.stop()
```

Start asset playback with `playbackClock.start(at: .zero)` before requesting data.

- [ ] **Step 7: Run automatic checks**

```bash
bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh
xcrun swiftc -frontend -parse MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift
```

Expected: both exit `0`.

- [ ] **Step 8: Commit Task 3**

```bash
git add MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift \
  MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh
git commit -m "feat(native): bound asset frame enqueue timing"
```

---

### Task 4: Continuous Loop PTS and Recovery Policy

**Files:**

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift`
- Modify: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Modify: `MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift`
- Modify: `MacWallNativeWallpaperSpike/CMakeLists.txt`

**Interfaces:**

- Produces: `NativeVideoSampleRetimer.loopOffset(assetDuration:loopIndex:)`
- Produces: `NativeVideoSampleRetimer.retime(_:by:)`
- Consumed before policy evaluation.

- [ ] **Step 1: Add failing retiming tests**

Add `import CoreMedia` and tests:

```swift
private static func testLoopOffsetIsMonotonic() {
    let duration = CMTime(value: 300, timescale: 30)
    precondition(NativeVideoSampleRetimer.loopOffset(assetDuration: duration, loopIndex: 0) == .zero)
    precondition(CMTimeGetSeconds(NativeVideoSampleRetimer.loopOffset(assetDuration: duration, loopIndex: 2)) == 20)
}

private static func testTimingInfoAddsLoopOffset() {
    let timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(value: 15, timescale: 30),
        decodeTimeStamp: .invalid
    )
    let shifted = NativeVideoSampleRetimer.offset(timing, by: CMTime(seconds: 10, preferredTimescale: 600))
    precondition(CMTimeGetSeconds(shifted.presentationTimeStamp) == 10.5)
    precondition(shifted.decodeTimeStamp == .invalid)
}
```

- [ ] **Step 2: Build the focused target and verify RED**

Expected: unresolved `NativeVideoSampleRetimer`.

- [ ] **Step 3: Implement the retimer**

Create `NativeVideoSampleRetimer.swift` with:

```swift
import CoreMedia

enum NativeVideoSampleRetimer {
    static func loopOffset(assetDuration: CMTime, loopIndex: Int64) -> CMTime {
        guard loopIndex > 0 else { return .zero }
        return CMTimeMultiplyByFloat64(assetDuration, multiplier: Double(loopIndex))
    }

    static func offset(_ timing: CMSampleTimingInfo, by offset: CMTime) -> CMSampleTimingInfo {
        CMSampleTimingInfo(
            duration: timing.duration,
            presentationTimeStamp: CMTimeAdd(timing.presentationTimeStamp, offset),
            decodeTimeStamp: timing.decodeTimeStamp.isValid
                ? CMTimeAdd(timing.decodeTimeStamp, offset)
                : .invalid
        )
    }

    static func retime(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) throws -> CMSampleBuffer {
        var entryCount = 0
        try check(CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &entryCount
        ))
        guard entryCount > 0 else {
            throw RetimingError.missingTiming
        }

        var timings = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: entryCount
        )
        let readStatus = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: buffer.count,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: &entryCount
            )
        }
        try check(readStatus)
        timings = timings.map { self.offset($0, by: offset) }

        var result: CMSampleBuffer?
        let createStatus = timings.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: buffer.count,
                sampleTimingArray: buffer.baseAddress!,
                sampleBufferOut: &result
            )
        }
        try check(createStatus)
        guard let result else {
            throw RetimingError.missingResult
        }
        return result
    }

    enum RetimingError: Error {
        case status(OSStatus)
        case missingTiming
        case missingResult
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw RetimingError.status(status)
        }
    }
}
```

- [ ] **Step 4: Integrate continuous loop timestamps**

Store `assetDuration` from the selected video track. Retime every sample by `assetDuration * assetLoopIndex` before timing evaluation.

On reader completion:

- increment `assetLoopIndex`
- restart `AVAssetReader`
- do not flush the renderer
- do not reset the playback clock
- continue with monotonic loop timestamps

On retiming error, log its `OSStatus` and fall back to generated frames. Never enqueue an unretimed loop sample.

- [ ] **Step 5: Complete reset safety**

- Late/cadence drop discards one pending sample and continues.
- Hard reset flushes queued frames without removing the displayed image, seeks to pending PTS, clears `lastEnqueuedPTSSeconds`, and retries once.
- Two hard resets within five seconds trigger generated fallback reason `asset-repeated-hard-reset`.

- [ ] **Step 6: Run focused tests and static checks**

Run the focused test executable plus:

```bash
xcrun swiftc -frontend -parse \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift
git diff --check
```

- [ ] **Step 7: Commit Task 4**

```bash
git add MacWallNativeWallpaperSpike/CMakeLists.txt \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift \
  MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift \
  MacWallNativeWallpaperSpike/Tests/NativeVideoPlaybackTimingTests.swift
git commit -m "feat(native): keep loop presentation time continuous"
```

---

### Task 5: Verification Matrix and Documentation

**Files:**

- Modify: `MacWallNativeWallpaperSpike/dev.sh`
- Modify: `MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh`
- Modify: `MacWallNativeWallpaperSpike/CMakeLists.txt`
- Modify: `MacWallNativeWallpaperSpike/README.md`
- Modify: `docs/development-log.md`

- [ ] **Step 1: Finish runner coverage**

Runner tests verify:

```text
default timing clock = synchronizer
default timing profile = normal
control-timebase accepted
synchronizer accepted
normal accepted
reduced accepted
invalid clock rejected with exit 2
invalid profile rejected with exit 2
explicit local video path accepted
missing local video path rejected with exit 2
snapshot default remains disabled
video source default remains asset
```

Change `MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE` in CMake to a `CACHE FILEPATH` value, retaining the current local sample as its default. Add `dev.sh install --video-path /absolute/path/to/video.mp4`; validate that it is an existing regular file and pass it to CMake as `-DMACWALL_NATIVE_SAMPLE_VIDEO_SOURCE=<path>`. The runner copies the source into the temporary build resource and never edits or commits the original file.

- [ ] **Step 2: Add README commands**

Control timebase run:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source asset --timing-clock control-timebase --timing-profile normal
```

Synchronizer run:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source asset --timing-clock synchronizer --timing-profile normal
```

Focused logs:

```bash
./dev.sh logs --last 3m \
  | grep -E "nativeVideoTiming|nativeVideoBridge asset loop|clockMode|hard-reset|asset-repeated-hard-reset|WallpaperExtensionError|NSCocoaErrorDomain"
```

Document that `WallpaperExtensionError(2)` from disabled snapshot/export is separate from playback acceptance.

- [ ] **Step 3: Run automatic verification**

```bash
bash MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh
cmake -S MacWallNativeWallpaperSpike -B /tmp/macwall-native-playback-timing-xcode -G Xcode
xcodebuild \
  -project /tmp/macwall-native-playback-timing-xcode/MacWallNativeWallpaperSpike.xcodeproj \
  -scheme MacWallNativeWallpaperRuntimeIdentityTests \
  -configuration Debug \
  build
/tmp/macwall-native-playback-timing-xcode/Debug/MacWallNativeWallpaperRuntimeIdentityTests
git diff --check
```

Expected: runner prints `dev runner tests passed`, executable exits `0`, and diff check is clean.

- [ ] **Step 4: Human verification gate - control timebase**

After reset/install, stop and say:

```text
사용자가 직접 확인해야 합니다. 시스템 설정에서 MacWall Native Spike를 선택한 뒤 자연 배속, 끊김, loop 경계 검은 화면, Fullscreen -> Desktop 빨간약 여부를 알려주세요.
```

After the response, inspect logs before changing code. Acceptance evidence:

- lead normally stays within `0.100...0.500` seconds
- no repeated hard reset
- queued count increases
- dropped count does not continuously rise in normal mode
- user reports natural speed and smooth output
- no loop black/stall/speed change
- Fullscreen -> Desktop remains red-pill free

- [ ] **Step 5: Human verification gate - synchronizer**

Repeat with `--timing-clock synchronizer`. Keep it as default only if it meets every acceptance point and is no worse than control timebase. If a mode loses the native surface, restore the last successful mode through reset/install and record the failure without patching around it in the same task.

- [ ] **Step 6: Human verification gate - reduced profile**

Run synchronizer with `--timing-profile reduced`. Confirm cadence drops in logs while playback stays real-time. Do not add automatic battery or thermal observers in the spike.

- [ ] **Step 7: Human verification gate - 4K/60 and 120fps**

When user-owned local fixtures are available, repeat the synchronizer/normal run with:

```bash
./dev.sh reset
./dev.sh install \
  --snapshot-mode disabled \
  --video-source asset \
  --timing-clock synchronizer \
  --timing-profile normal \
  --video-path /absolute/path/to/user-owned-4k60.mp4
```

Run the same protocol for a 120fps fixture. Record lead/lag, drop/reset counts, RSS, and user-visible smoothness. Do not copy either fixture into the repository. If no legal local fixture is available, mark only this high-resolution gate as pending; do not claim 4K/60 or 120fps acceptance.

- [ ] **Step 8: Record and commit results**

Record clock/profile, automatic evidence, both user results, lead/lag range, drop/reset counts, loop result, red-pill result, and untouched scopes in `docs/development-log.md`.

```bash
git add MacWallNativeWallpaperSpike/dev.sh \
  MacWallNativeWallpaperSpike/Tests/dev_runner_tests.sh \
  MacWallNativeWallpaperSpike/CMakeLists.txt \
  MacWallNativeWallpaperSpike/README.md \
  docs/development-log.md
git commit -m "docs(native): record playback timing verification"
```

---

## Final Acceptance

- Asset video runs at natural speed.
- Normal playback is as smooth as the generated diagnostic mode.
- Lead remains bounded instead of growing through the asset.
- Loop PTS increases monotonically without a normal-path flush.
- Loop has no black frame, stall, or speed change.
- Late frames drop instead of producing slow-motion catch-up.
- Repeated hard resets fall back to generated mode without killing the native surface.
- Fullscreen -> Desktop remains free of the legacy red-pill exposure.
- Snapshot mode stays disabled during timing QA.
- Main App, Scene, Web, fallback, package, DMG, notarization, and `dist` remain untouched.

## Deferred Follow-up

- producer/consumer decode queue
- automatic battery/thermal/occlusion policy
- 4K/120 automatic quality scaling
- NativeWallpaperBackend module extraction
- Main App integration
- snapshot/export repair

If later 4K/60 evidence shows decoder starvation while lead stays below `minBufferLead`, create a separate producer/consumer design with an explicit byte budget. A 500ms queue of uncompressed 4K BGRA frames is not acceptable.
