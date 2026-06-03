# P2 Playback Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize Workshop Wallpaper Bridge live playback across item switching, monitor changes, sleep/wake, Spaces/full-screen transitions, and auto-pause without starting Scene S0 or release work.

**Architecture:** Add a small pure playback state boundary, fake-scheduler-testable debounce, and transactional hidden/staged window replacement. Keep existing Swift target paths (`MacWallApp`, `MacWallCore`, `macwallctl`) because this plan does not rename code.

**Tech Stack:** Swift 6, XCTest, AppKit, AVFoundation, WebKit, `rg`, `swift test`.

---

## Scope

Implement P2 Playback Stability only.

Included:

- Transactional replacement window flow.
- A -> failing B transition stability.
- Fallback/space-refresh/last-played state preservation for failed transitions.
- Fake scheduler for debounce tests.
- Simulated monitor attach/detach and sleep/wake unit/integration tests.
- README check if user-visible behavior text changes.

Excluded:

- Scene S0.
- Scene fallback.
- Metal Scene runtime.
- Web runtime property API.
- `swift build`.
- GUI app launch.
- `bash Scripts/package-app.sh`.
- DMG, notarization, release artifact, `dist` work.
- Steam Workshop download/crawling/auth/DRM behavior.

## File Map

- Create: `Sources/MacWallApp/Playback/PlaybackSessionState.swift`
  - Pure playback session state, active snapshot, generation token, phase transitions.
- Create: `Sources/MacWallApp/Playback/PlaybackScheduler.swift`
  - Production scheduler protocol and cancellable scheduled task.
- Modify: `Sources/MacWallApp/Playback/WallpaperPlayer.swift`
  - Implements `WallpaperPlayerManaging`, transactional replacement, scheduler-backed debounce, screen/window factory injection.
- Create: `Sources/MacWallApp/Playback/WallpaperPlayerManaging.swift`
  - Protocol used by `AppViewModel` tests.
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
  - Inject player, preserve A state on A -> failing B.
- Create: `Tests/MacWallAppTests/PlaybackSessionStateTests.swift`
  - Pure state tests.
- Create: `Tests/MacWallAppTests/PlaybackSchedulerTests.swift`
  - Fake scheduler tests for 300ms/500ms/200ms debounce.
- Modify: `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`
  - Transactional replacement and simulated lifecycle tests.
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`
  - A -> failing B state preservation tests.
- Modify: `README.ko.md`, `README.md`
  - Only if user-visible playback wording changes.
- Modify: `docs/development-log.md`, `docs/development-roadmap.md`
  - P2 progress and completion status.
- Create after implementation: `docs/implemented/2026-06-04-p2-playback-stability.md`
  - Completed implementation record.

## Task 1: Playback Session State

**Files:**

- Create: `Sources/MacWallApp/Playback/PlaybackSessionState.swift`
- Create: `Tests/MacWallAppTests/PlaybackSessionStateTests.swift`

- [ ] **Step 1: Write failing tests for session transitions**

Add `Tests/MacWallAppTests/PlaybackSessionStateTests.swift`:

```swift
import XCTest
@testable import MacWallApp
import MacWallCore

final class PlaybackSessionStateTests: XCTestCase {
    func testStartPlayingStoresSnapshotAndGeneration() {
        var state = PlaybackSessionState()
        let asset = Self.asset(id: "A")

        let snapshot = state.startPlaying(asset: asset, options: .defaults)

        XCTAssertEqual(snapshot.assetId, "A")
        XCTAssertEqual(snapshot.projectDirectory, "/tmp/A")
        XCTAssertEqual(snapshot.phase, .playing)
        XCTAssertEqual(state.activeSnapshot, snapshot)
        XCTAssertEqual(state.generation, snapshot.generation)
    }

    func testSuspendAndResumeAreIdempotent() {
        var state = PlaybackSessionState()
        let asset = Self.asset(id: "A")
        _ = state.startPlaying(asset: asset, options: .defaults)

        state.setSuspended(true)
        state.setSuspended(true)
        XCTAssertEqual(state.activeSnapshot?.phase, .suspended)

        state.setSuspended(false)
        state.setSuspended(false)
        XCTAssertEqual(state.activeSnapshot?.phase, .playing)
    }

    func testRestoreGenerationRejectsStaleCompletion() {
        var state = PlaybackSessionState()
        let first = state.startPlaying(asset: Self.asset(id: "A"), options: .defaults)
        let second = state.startPlaying(asset: Self.asset(id: "B"), options: .defaults)

        XCTAssertFalse(state.isCurrentGeneration(first.generation))
        XCTAssertTrue(state.isCurrentGeneration(second.generation))
    }

    func testStopReturnsToIdle() {
        var state = PlaybackSessionState()
        _ = state.startPlaying(asset: Self.asset(id: "A"), options: .defaults)

        state.stop()

        XCTAssertNil(state.activeSnapshot)
        XCTAssertEqual(state.phase, .idle)
    }

    private static func asset(id: String) -> WallpaperAsset {
        WallpaperAsset(
            id: id,
            title: id,
            kind: .video,
            supportStatus: .playable,
            source: .localFile,
            projectDirectory: "/tmp/\(id)",
            entrypoint: "/tmp/\(id)/video.mp4",
            thumbnail: nil,
            workshopId: nil,
            redistributionAllowed: false,
            issues: []
        )
    }
}
```

- [ ] **Step 2: Run failing state tests**

Run:

```bash
swift test --filter PlaybackSessionStateTests
```

Expected: compile failure because `PlaybackSessionState`, `PlaybackSessionSnapshot`, and `PlaybackOptions.defaults` do not exist.

- [ ] **Step 3: Implement pure session state**

Create `Sources/MacWallApp/Playback/PlaybackSessionState.swift`:

```swift
import Foundation
import MacWallCore

enum PlaybackSessionPhase: Equatable {
    case idle
    case playing
    case suspended
    case restoring
    case failed
}

struct PlaybackOptions: Equatable {
    let autoPauseWhenCovered: Bool
    let experimentalSceneRendering: Bool
    let webMouseInteractionEnabled: Bool
    let displayMode: WallpaperDisplayMode

    static let defaults = PlaybackOptions(
        autoPauseWhenCovered: true,
        experimentalSceneRendering: false,
        webMouseInteractionEnabled: false,
        displayMode: .fit
    )
}

struct PlaybackSessionSnapshot: Equatable {
    let assetId: WallpaperAsset.ID
    let projectDirectory: String
    let phase: PlaybackSessionPhase
    let generation: UInt64
    let options: PlaybackOptions
}

struct PlaybackSessionState {
    private(set) var activeSnapshot: PlaybackSessionSnapshot?
    private(set) var phase: PlaybackSessionPhase = .idle
    private(set) var generation: UInt64 = 0

    mutating func startPlaying(asset: WallpaperAsset, options: PlaybackOptions) -> PlaybackSessionSnapshot {
        generation &+= 1
        phase = .playing
        let snapshot = PlaybackSessionSnapshot(
            assetId: asset.id,
            projectDirectory: asset.projectDirectory,
            phase: .playing,
            generation: generation,
            options: options
        )
        activeSnapshot = snapshot
        return snapshot
    }

    mutating func setSuspended(_ suspended: Bool) {
        guard var snapshot = activeSnapshot else {
            phase = .idle
            return
        }
        phase = suspended ? .suspended : .playing
        snapshot = PlaybackSessionSnapshot(
            assetId: snapshot.assetId,
            projectDirectory: snapshot.projectDirectory,
            phase: phase,
            generation: snapshot.generation,
            options: snapshot.options
        )
        activeSnapshot = snapshot
    }

    mutating func beginRestoring() -> UInt64? {
        guard activeSnapshot != nil else {
            phase = .idle
            return nil
        }
        generation &+= 1
        phase = .restoring
        return generation
    }

    func isCurrentGeneration(_ candidate: UInt64) -> Bool {
        generation == candidate
    }

    mutating func stop() {
        generation &+= 1
        activeSnapshot = nil
        phase = .idle
    }
}
```

- [ ] **Step 4: Run state tests**

Run:

```bash
swift test --filter PlaybackSessionStateTests
```

Expected: `PlaybackSessionStateTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/MacWallApp/Playback/PlaybackSessionState.swift Tests/MacWallAppTests/PlaybackSessionStateTests.swift
git commit -m "test(playback): add session state model"
```

## Task 2: Fake-Scheduler-Testable Debounce

**Files:**

- Create: `Sources/MacWallApp/Playback/PlaybackScheduler.swift`
- Create: `Tests/MacWallAppTests/PlaybackSchedulerTests.swift`

- [ ] **Step 1: Write failing scheduler tests**

Add `Tests/MacWallAppTests/PlaybackSchedulerTests.swift`:

```swift
import XCTest
@testable import MacWallApp

@MainActor
final class PlaybackSchedulerTests: XCTestCase {
    func testScreenChangeDebounceFiresAfter300Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(300)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(299))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testWakeDebounceFiresAfter500Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(500)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(499))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testVisibilityDebounceFiresAfter200Milliseconds() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        scheduler.schedule(after: .milliseconds(200)) {
            fired += 1
        }

        scheduler.advance(by: .milliseconds(199))
        XCTAssertEqual(fired, 0)

        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(fired, 1)
    }

    func testCancelPreventsStaleScheduledTask() {
        let scheduler = TestPlaybackScheduler()
        var fired = 0

        let task = scheduler.schedule(after: .milliseconds(300)) {
            fired += 1
        }
        task.cancel()
        scheduler.advance(by: .milliseconds(300))

        XCTAssertEqual(fired, 0)
    }
}

@MainActor
private final class TestPlaybackScheduler: PlaybackScheduling {
    private struct Entry {
        let id: Int
        let deadline: TimeInterval
        let operation: @MainActor () -> Void
    }

    private var now: TimeInterval = 0
    private var nextId = 0
    private var entries: [Entry] = []
    private var cancelled: Set<Int> = []

    @discardableResult
    func schedule(after delay: PlaybackDelay, _ operation: @escaping @MainActor () -> Void) -> PlaybackScheduledTask {
        nextId += 1
        let id = nextId
        entries.append(Entry(id: id, deadline: now + delay.seconds, operation: operation))
        return PlaybackScheduledTask { [weak self] in
            self?.cancelled.insert(id)
        }
    }

    func advance(by delay: PlaybackDelay) {
        now += delay.seconds
        let ready = entries.filter { $0.deadline <= now }
        entries.removeAll { $0.deadline <= now }
        ready.filter { !cancelled.contains($0.id) }.forEach { $0.operation() }
    }
}
```

- [ ] **Step 2: Run failing scheduler tests**

Run:

```bash
swift test --filter PlaybackSchedulerTests
```

Expected: compile failure because `PlaybackScheduling`, `PlaybackDelay`, and `PlaybackScheduledTask` do not exist.

- [ ] **Step 3: Implement scheduler boundary**

Create `Sources/MacWallApp/Playback/PlaybackScheduler.swift`:

```swift
import Foundation

struct PlaybackDelay: Equatable {
    let seconds: TimeInterval

    static func milliseconds(_ milliseconds: Int) -> PlaybackDelay {
        PlaybackDelay(seconds: TimeInterval(milliseconds) / 1_000)
    }
}

final class PlaybackScheduledTask {
    private let onCancel: () -> Void
    private var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else {
            return
        }
        isCancelled = true
        onCancel()
    }
}

@MainActor
protocol PlaybackScheduling: AnyObject {
    @discardableResult
    func schedule(after delay: PlaybackDelay, _ operation: @escaping @MainActor () -> Void) -> PlaybackScheduledTask
}

@MainActor
final class MainActorPlaybackScheduler: PlaybackScheduling {
    @discardableResult
    func schedule(after delay: PlaybackDelay, _ operation: @escaping @MainActor () -> Void) -> PlaybackScheduledTask {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay.seconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            operation()
        }
        return PlaybackScheduledTask {
            task.cancel()
        }
    }
}
```

- [ ] **Step 4: Run scheduler tests**

Run:

```bash
swift test --filter PlaybackSchedulerTests
```

Expected: `PlaybackSchedulerTests` pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/MacWallApp/Playback/PlaybackScheduler.swift Tests/MacWallAppTests/PlaybackSchedulerTests.swift
git commit -m "test(playback): add deterministic scheduler"
```

## Task 3: Player Protocol And AppViewModel Injection

**Files:**

- Create: `Sources/MacWallApp/Playback/WallpaperPlayerManaging.swift`
- Modify: `Sources/MacWallApp/Playback/WallpaperPlayer.swift`
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`

- [ ] **Step 1: Write failing AppViewModel ordering tests**

Append to `Tests/MacWallAppTests/AppViewModelTests.swift`:

```swift
@MainActor
func testPlaySuccessStoresLastPlayedOnlyAfterPlayerSuccess() throws {
    let defaults = try makeUserDefaults()
    let player = MockWallpaperPlayer()
    let store = LibraryStore(root: try makeTempDirectory())
    let asset = try store.importVideoFile(makeVideoFile())
    let model = AppViewModel(
        store: store,
        loginItemController: MockLoginItemController(),
        userDefaults: defaults,
        wallpaperPlayer: player
    )
    model.selectedLibraryAssetId = asset.id

    model.playSelected()

    XCTAssertEqual(player.playedAssetIds, [asset.id])
    XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), asset.id)
}

@MainActor
func testPlayFailureDoesNotStoreFailedAssetAsLastPlayed() throws {
    let defaults = try makeUserDefaults()
    let player = MockWallpaperPlayer()
    player.playError = TestError.expected
    let store = LibraryStore(root: try makeTempDirectory())
    let asset = try store.importVideoFile(makeVideoFile())
    let model = AppViewModel(
        store: store,
        loginItemController: MockLoginItemController(),
        userDefaults: defaults,
        wallpaperPlayer: player
    )
    model.selectedLibraryAssetId = asset.id

    model.playSelected()

    XCTAssertNil(defaults.string(forKey: "lastPlayedAssetId"))
    XCTAssertTrue(model.status.contains(TestError.expected.localizedDescription))
}
```

Add this helper near existing test helpers:

```swift
private final class MockWallpaperPlayer: WallpaperPlayerManaging {
    var playError: Error?
    var playedAssetIds: [WallpaperAsset.ID] = []
    var activeSessionSnapshot: PlaybackSessionSnapshot?

    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool,
        displayMode: WallpaperDisplayMode
    ) throws -> PlaybackSessionSnapshot {
        if let playError {
            throw playError
        }
        playedAssetIds.append(asset.id)
        let snapshot = PlaybackSessionSnapshot(
            assetId: asset.id,
            projectDirectory: asset.projectDirectory,
            phase: .playing,
            generation: UInt64(playedAssetIds.count),
            options: .defaults
        )
        activeSessionSnapshot = snapshot
        return snapshot
    }

    func stop() {
        activeSessionSnapshot = nil
    }

    func setDisplayMode(_ displayMode: WallpaperDisplayMode) {}
    func setAutoPauseWhenCovered(_ enabled: Bool) {}
    func setExperimentalSceneRendering(_ enabled: Bool) {}
    func setWebMouseInteractionEnabled(_ enabled: Bool) {}
}
```

- [ ] **Step 2: Run failing AppViewModel tests**

Run:

```bash
swift test --filter AppViewModelTests
```

Expected: compile failure because `WallpaperPlayerManaging` and `AppViewModel(... wallpaperPlayer:)` do not exist.

- [ ] **Step 3: Add player protocol**

Create `Sources/MacWallApp/Playback/WallpaperPlayerManaging.swift`:

```swift
import MacWallCore

@MainActor
protocol WallpaperPlayerManaging: AnyObject {
    var activeSessionSnapshot: PlaybackSessionSnapshot? { get }

    @discardableResult
    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool,
        displayMode: WallpaperDisplayMode
    ) throws -> PlaybackSessionSnapshot

    func stop()
    func setDisplayMode(_ displayMode: WallpaperDisplayMode)
    func setAutoPauseWhenCovered(_ enabled: Bool)
    func setExperimentalSceneRendering(_ enabled: Bool)
    func setWebMouseInteractionEnabled(_ enabled: Bool)
}
```

Modify `Sources/MacWallApp/Playback/WallpaperPlayer.swift`:

```swift
@MainActor
final class WallpaperPlayer: WallpaperPlayerManaging {
    static let shared = WallpaperPlayer()
    private var sessionState = PlaybackSessionState()

    var activeSessionSnapshot: PlaybackSessionSnapshot? {
        sessionState.activeSnapshot
    }
}
```

Change `play(...)` signature to return `PlaybackSessionSnapshot` and return the snapshot after successful window replacement:

```swift
@discardableResult
func play(...) throws -> PlaybackSessionSnapshot {
    ...
    let snapshot = sessionState.startPlaying(asset: asset, options: options)
    return snapshot
}
```

- [ ] **Step 4: Inject player into AppViewModel**

Modify `Sources/MacWallApp/App/AppViewModel.swift`:

```swift
private let wallpaperPlayer: WallpaperPlayerManaging
```

In default init:

```swift
wallpaperPlayer = WallpaperPlayer.shared
```

In test init add parameter:

```swift
wallpaperPlayer: WallpaperPlayerManaging = WallpaperPlayer.shared
```

Assign:

```swift
self.wallpaperPlayer = wallpaperPlayer
```

Replace direct singleton calls in AppViewModel:

```swift
wallpaperPlayer.setDisplayMode(displayMode)
wallpaperPlayer.setAutoPauseWhenCovered(autoPauseWhenCovered)
wallpaperPlayer.setExperimentalSceneRendering(experimentalSceneRendering)
wallpaperPlayer.setWebMouseInteractionEnabled(webMouseInteractionEnabled)
wallpaperPlayer.stop()
try wallpaperPlayer.play(...)
```

- [ ] **Step 5: Run AppViewModel focused tests**

Run:

```bash
swift test --filter AppViewModelTests
```

Expected: `AppViewModelTests` pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/MacWallApp/Playback/WallpaperPlayerManaging.swift Sources/MacWallApp/Playback/WallpaperPlayer.swift Sources/MacWallApp/App/AppViewModel.swift Tests/MacWallAppTests/AppViewModelTests.swift
git commit -m "test(playback): inject player into app view model"
```

## Task 4: Transactional Hidden/Staged Window Replacement

**Files:**

- Modify: `Sources/MacWallApp/Playback/WallpaperPlayer.swift`
- Modify: `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`

- [ ] **Step 1: Add source-level transactional replacement tests**

Append to `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`:

```swift
func testTransactionalReplacementStagesAllWindowsBeforeClosingOldWindows() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

    XCTAssertTrue(source.contains("makeStagedReplacementWindows"))
    XCTAssertTrue(source.contains("showReplacementWindows"))
    XCTAssertTrue(source.contains("closeWindows(oldWindows)"))
    XCTAssertTrue(source.contains("cleanupStagedWindows"))
}

func testPartialReplacementFailureDoesNotHalfSwapWindows() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

    XCTAssertTrue(source.contains("catch {"))
    XCTAssertTrue(source.contains("cleanupStagedWindows(replacements)"))
    XCTAssertTrue(source.contains("throw error"))
    XCTAssertFalse(source.contains("windows = replacements"))
}
```

- [ ] **Step 2: Run failing transactional tests**

Run:

```bash
swift test --filter WallpaperPlayerSuspensionTests
```

Expected: tests fail because helper names and ordering do not exist yet.

- [ ] **Step 3: Refactor play/reopen through staged replacement**

Modify `Sources/MacWallApp/Playback/WallpaperPlayer.swift` so `play(...)` validates the asset, creates all replacement windows, then swaps:

```swift
private func replaceWindows(
    asset: WallpaperAsset,
    url: URL,
    displayMode: WallpaperDisplayMode,
    experimentalSceneRendering: Bool,
    webMouseInteractionEnabled: Bool
) throws {
    let oldWindows = windows
    let replacements: [WallpaperWindow]
    do {
        replacements = try makeStagedReplacementWindows(
            asset: asset,
            url: url,
            displayMode: displayMode,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled
        )
    } catch {
        throw error
    }

    showReplacementWindows(replacements)
    windows = replacements
    closeWindows(oldWindows)
}

private func makeStagedReplacementWindows(
    asset: WallpaperAsset,
    url: URL,
    displayMode: WallpaperDisplayMode,
    experimentalSceneRendering: Bool,
    webMouseInteractionEnabled: Bool
) throws -> [WallpaperWindow] {
    var replacements: [WallpaperWindow] = []
    do {
        for screen in NSScreen.screens {
            let window = try WallpaperWindow(
                asset: asset,
                url: url,
                frame: screen.frame,
                displayMode: displayMode,
                experimentalSceneRendering: experimentalSceneRendering,
                webMouseInteractionEnabled: webMouseInteractionEnabled
            )
            replacements.append(window)
        }
        return replacements
    } catch {
        cleanupStagedWindows(replacements)
        throw error
    }
}

private func showReplacementWindows(_ replacements: [WallpaperWindow]) {
    replacements.forEach { $0.show() }
}

private func closeWindows(_ oldWindows: [WallpaperWindow]) {
    oldWindows.forEach { $0.close() }
}

private func cleanupStagedWindows(_ replacements: [WallpaperWindow]) {
    replacements.forEach { $0.close() }
}
```

Remove old code paths that call `closeWindows()` before replacement window creation in `play(...)` and `reopen(asset:)`.

- [ ] **Step 4: Run transactional tests**

Run:

```bash
swift test --filter WallpaperPlayerSuspensionTests
```

Expected: `WallpaperPlayerSuspensionTests` pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add Sources/MacWallApp/Playback/WallpaperPlayer.swift Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift
git commit -m "fix(playback): stage replacement windows transactionally"
```

## Task 5: Debounced Lifecycle Restore

**Files:**

- Modify: `Sources/MacWallApp/Playback/WallpaperPlayer.swift`
- Modify: `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`
- Modify: `Tests/MacWallAppTests/PlaybackSchedulerTests.swift`

- [ ] **Step 1: Add lifecycle debounce source tests**

Append to `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`:

```swift
func testLifecycleRestoreUsesFixedDebounceDelays() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

    XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(300)"))
    XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(500)"))
    XCTAssertTrue(source.contains("PlaybackDelay.milliseconds(200)"))
    XCTAssertTrue(source.contains("screenRestoreTask?.cancel()"))
    XCTAssertTrue(source.contains("wakeRestoreTask?.cancel()"))
    XCTAssertTrue(source.contains("visibilityTask?.cancel()"))
}

func testRestoreChecksGenerationBeforeReopening() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

    XCTAssertTrue(source.contains("beginRestoring()"))
    XCTAssertTrue(source.contains("isCurrentGeneration"))
}
```

- [ ] **Step 2: Run failing lifecycle tests**

Run:

```bash
swift test --filter WallpaperPlayerSuspensionTests
```

Expected: tests fail because lifecycle tasks and debounce constants are not present.

- [ ] **Step 3: Add scheduler dependency and debounce tasks**

Modify `Sources/MacWallApp/Playback/WallpaperPlayer.swift`:

```swift
private let scheduler: PlaybackScheduling
private var screenRestoreTask: PlaybackScheduledTask?
private var wakeRestoreTask: PlaybackScheduledTask?
private var visibilityTask: PlaybackScheduledTask?

init(scheduler: PlaybackScheduling = MainActorPlaybackScheduler()) {
    self.scheduler = scheduler
}
```

Change screen parameter notification handler:

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in self?.scheduleScreenRestore() }
}
```

Add helpers:

```swift
private func scheduleScreenRestore() {
    screenRestoreTask?.cancel()
    guard let generation = sessionState.beginRestoring() else {
        return
    }
    screenRestoreTask = scheduler.schedule(after: .milliseconds(300)) { [weak self] in
        self?.restoreIfCurrentGeneration(generation)
    }
}

private func scheduleWakeRestore() {
    wakeRestoreTask?.cancel()
    guard let generation = sessionState.beginRestoring() else {
        return
    }
    wakeRestoreTask = scheduler.schedule(after: .milliseconds(500)) { [weak self] in
        self?.restoreIfCurrentGeneration(generation)
    }
}

private func scheduleVisibilityUpdate() {
    visibilityTask?.cancel()
    visibilityTask = scheduler.schedule(after: .milliseconds(200)) { [weak self] in
        self?.updateVisibilityState()
    }
}

private func restoreIfCurrentGeneration(_ generation: UInt64) {
    guard sessionState.isCurrentGeneration(generation), let activeAsset else {
        return
    }
    reopenAfterWake(asset: activeAsset)
}
```

Change didWake handler to `scheduleWakeRestore()` and visibility timer callback to `scheduleVisibilityUpdate()`.

- [ ] **Step 4: Run lifecycle tests**

Run:

```bash
swift test --filter WallpaperPlayerSuspensionTests
swift test --filter PlaybackSchedulerTests
```

Expected: both focused test groups pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add Sources/MacWallApp/Playback/WallpaperPlayer.swift Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift Tests/MacWallAppTests/PlaybackSchedulerTests.swift
git commit -m "fix(playback): debounce lifecycle restore"
```

## Task 6: A -> Failing B State Preservation

**Files:**

- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`

- [ ] **Step 1: Write failing A -> failing B tests**

Append to `Tests/MacWallAppTests/AppViewModelTests.swift`:

```swift
@MainActor
func testSwitchingFromAToFailingBKeepsALastPlayedPreference() throws {
    let defaults = try makeUserDefaults()
    let player = MockWallpaperPlayer()
    let store = LibraryStore(root: try makeTempDirectory())
    let assetA = try store.importVideoFile(makeVideoFile(name: "A.mp4"))
    let assetB = try store.importVideoFile(makeVideoFile(name: "B.mp4"))
    let model = AppViewModel(
        store: store,
        loginItemController: MockLoginItemController(),
        userDefaults: defaults,
        wallpaperPlayer: player
    )

    model.selectedLibraryAssetId = assetA.id
    model.playSelected()
    player.playError = TestError.expected
    model.selectedLibraryAssetId = assetB.id
    model.playSelected()

    XCTAssertEqual(defaults.string(forKey: "lastPlayedAssetId"), assetA.id)
    XCTAssertEqual(player.activeSessionSnapshot?.assetId, assetA.id)
}

@MainActor
func testSwitchingFromAToFailingBDoesNotApplyBFallback() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/App/AppViewModel.swift")

    XCTAssertTrue(source.contains("activeSessionSnapshot"))
    XCTAssertTrue(source.contains("desktopFallbackSpaceRefreshCoordinator.setActiveAsset(previousAsset)"))
    XCTAssertFalse(source.contains("desktopFallbackCoordinator.applyOrGenerate(asset: asset) } catch"))
}
```

- [ ] **Step 2: Run failing A -> failing B tests**

Run:

```bash
swift test --filter AppViewModelTests
```

Expected: one or both tests fail because AppViewModel does not preserve previous active fallback/space-refresh state explicitly.

- [ ] **Step 3: Preserve previous active session on play failure**

Modify `Sources/MacWallApp/App/AppViewModel.swift` in private `play(asset:remember:)`:

```swift
private func play(asset: WallpaperAsset, remember: Bool) throws {
    let previousSession = wallpaperPlayer.activeSessionSnapshot
    do {
        _ = try wallpaperPlayer.play(
            asset: asset,
            autoPauseWhenCovered: autoPauseWhenCovered,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled,
            displayMode: displayMode
        )
    } catch {
        if let previousAsset = activeLibraryAsset(matching: previousSession) {
            desktopFallbackSpaceRefreshCoordinator.setActiveAsset(previousAsset)
        } else {
            desktopFallbackCoordinator.clearActiveAsset()
            desktopFallbackSpaceRefreshCoordinator.setActiveAsset(nil)
        }
        throw error
    }

    desktopFallbackSpaceRefreshCoordinator.setActiveAsset(asset)
    desktopFallbackCoordinator.applyOrGenerate(asset: asset)
    if remember {
        userDefaults.set(asset.id, forKey: PreferenceKey.lastPlayedAssetId)
    }
    ...
}

private func activeLibraryAsset(matching snapshot: PlaybackSessionSnapshot?) -> WallpaperAsset? {
    guard let snapshot else {
        return nil
    }
    return libraryAssets.first {
        $0.id == snapshot.assetId && $0.projectDirectory == snapshot.projectDirectory
    }
}
```

Ensure the failure branch never calls `desktopFallbackCoordinator.applyOrGenerate(asset: asset)` for failed B.

- [ ] **Step 4: Run AppViewModel focused tests**

Run:

```bash
swift test --filter AppViewModelTests
```

Expected: `AppViewModelTests` pass.

- [ ] **Step 5: Commit Task 6**

```bash
git add Sources/MacWallApp/App/AppViewModel.swift Tests/MacWallAppTests/AppViewModelTests.swift
git commit -m "fix(playback): preserve active session on failed switch"
```

## Task 7: Simulated Monitor And Sleep/Wake Coverage

**Files:**

- Modify: `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`
- Modify: `Sources/MacWallApp/Playback/WallpaperPlayer.swift`

- [ ] **Step 1: Add source-level simulated verification tests**

Append to `Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift`:

```swift
func testMonitorAndWakeTestsUseInjectedSchedulerNotRealSleep() throws {
    let source = try SourceFixture.contents(of: "Tests/MacWallAppTests/PlaybackSchedulerTests.swift")

    XCTAssertTrue(source.contains("TestPlaybackScheduler"))
    XCTAssertTrue(source.contains("advance(by: .milliseconds(300))"))
    XCTAssertTrue(source.contains("advance(by: .milliseconds(500))"))
    XCTAssertFalse(source.contains("Task.sleep"))
    XCTAssertFalse(source.contains("Thread.sleep"))
}

func testWallpaperPlayerCanBeConstructedWithSchedulerForSimulation() throws {
    let source = try SourceFixture.contents(of: "Sources/MacWallApp/Playback/WallpaperPlayer.swift")

    XCTAssertTrue(source.contains("init(scheduler: PlaybackScheduling = MainActorPlaybackScheduler())"))
}
```

- [ ] **Step 2: Run simulated verification tests**

Run:

```bash
swift test --filter WallpaperPlayerSuspensionTests
```

Expected: tests pass after Task 5; if they fail, adjust Task 5 implementation to expose the scheduler initializer exactly.

- [ ] **Step 3: Commit Task 7**

```bash
git add Sources/MacWallApp/Playback/WallpaperPlayer.swift Tests/MacWallAppTests/WallpaperPlayerSuspensionTests.swift
git commit -m "test(playback): document simulated lifecycle coverage"
```

## Task 8: Documentation And Verification

**Files:**

- Modify: `README.ko.md`
- Modify: `README.md`
- Modify: `docs/development-log.md`
- Modify: `docs/development-roadmap.md`
- Create: `docs/implemented/2026-06-04-p2-playback-stability.md`

- [ ] **Step 1: Check README impact**

Run:

```bash
rg -n "Playback Behavior|재생 방식|sleep|wake|monitor|auto-pause|Spaces" README.md README.ko.md
```

Expected: playback behavior sections are found. If implementation changes user-visible wording, update both README files in the same commit. If wording does not change, add a development-log note that README changes were checked and not needed.

- [ ] **Step 2: Create completion record**

Create `docs/implemented/2026-06-04-p2-playback-stability.md` with this structure:

```md
# P2 Playback Stability 구현 기록

Status: implemented / completed

Date: 2026-06-04

## Summary

P2 stabilizes live playback transitions for Workshop Wallpaper Bridge without starting Scene S0.

## Implemented

- Transactional hidden/staged replacement window flow.
- A -> failing B state preservation.
- Debounced screen-change, wake, and visibility updates with fake-scheduler-testable timing.
- Simulated unit/integration coverage for monitor and sleep/wake behavior.

## Verification

- `swift test` -> `<final test count>, 0 failures`

## Not Implemented

- Scene S0.
- Scene fallback.
- Metal Scene runtime.
- package/DMG/notarization/release artifact work.
- GUI app QA.
```

- [ ] **Step 3: Update development log and roadmap**

In `docs/development-log.md`, add a 2026-06-04 entry with:

```md
### <time> KST

- 완료: P2 Playback Stability 구현
- 문서: [P2 구현 기록](implemented/2026-06-04-p2-playback-stability.md)
- 검증: `swift test` -> `<final test count>, 0 failures`
- 제외:
  - Scene S0
  - Scene fallback
  - package/DMG/notarization/release artifact
  - GUI app QA
```

In `docs/development-roadmap.md`, mark P2 as implemented and keep next planning direction as P3 Web Runtime Completion unless the user chooses a different next phase.

- [ ] **Step 4: Run full verification**

Run:

```bash
swift test
rg -n "T[O]DO|T[B]D|Workshop[W]allpaper|workshop-wallpaper-[b]ridge|W[W]B|w[w]bctl|dev\\.[3]xhaust" Sources Tests docs README.md README.ko.md CONTRIBUTING.md LICENSE .github --glob '!docs/archive/**'
rg -n "swift build|package-app|dist/|GUI app launch|DMG|notarization" docs README.md README.ko.md CONTRIBUTING.md .github
```

Expected:

- `swift test` exits 0 with 0 failures.
- old project names are not found in active docs/source except historical archive paths if the command includes archive files.
- forbidden release/build commands appear only as explicit "do not run" policy text.

- [ ] **Step 5: Commit final docs**

```bash
git add README.ko.md README.md docs/development-log.md docs/development-roadmap.md docs/implemented/2026-06-04-p2-playback-stability.md
git commit -m "docs: record p2 playback stability completion"
```

## Final Handoff

After all tasks pass:

```bash
git status --short --branch
git log --oneline --decorate -5
```

Expected:

- working tree clean except ignored local files.
- latest commits show P2 implementation and completion record.

Do not run package, DMG, notarization, `dist` mutation, or GUI app QA unless the user explicitly approves a separate release/QA task.
