# Native Wallpaper Backend Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the proven macOS 26 native wallpaper spike into the MacWall Main App as a production Video backend while preserving the existing Legacy backend and keeping native playback isolated from desktop-fallback side effects.

**Architecture:** Add an Xcode app container that embeds a production wallpaper extension while continuing to consume the existing local Swift Package. Main App and extension exchange immutable video generations through an App Group store, use generation-aware status/ACK files plus Darwin notifications, and commit a Native replacement only after every active Desktop context has a first frame. A MainActor playback coordinator owns Native/Legacy routing, one-shot Legacy choice, handoff, Stop, and stale-request rejection.

**Tech Stack:** Swift 6, macOS 14+ host app, macOS 26+ Native extension, Apple Silicon, Swift Package Manager, Xcode project, ExtensionFoundation, WallpaperExtensionKit runtime discovery, CAContext, AVFoundation, QuartzCore, App Group containers, XCTest, Bash static guards.

## Global Constraints

- MacWall remains one user-facing app; only playback backends are split.
- Native support is limited to macOS 26+, Apple Silicon, and Video assets in this milestone.
- macOS 25 and earlier, Intel Macs, and Native-unsupported asset kinds continue through the Legacy backend.
- The existing `MacWallNativeWallpaperSpike` remains intact until the production backend has passed a later user-run runtime QA.
- Native playback must not call `DesktopFallbackCoordinator`, apply `desktop-fallback.png`, capture an original wallpaper, or restore one.
- Legacy playback retains the existing NSWindow, fallback, Space refresh, and original-wallpaper restore behavior.
- Native setup UI has exactly three actions: `취소`, `기존 방식으로 재생`, `배경화면 설정 열기`.
- `기존 방식으로 재생` applies only to the current Play request and is never persisted as a preference.
- Native runtime failure must not silently downgrade to Legacy or stop the previous successful playback.
- Native Stop freezes the last frame and keeps the MacWall System Settings wallpaper selected.
- Native replacement is all-or-nothing across all active Desktop contexts.
- Private wallpaper/XPC/CAContext code stays inside the extension target.
- Shared command, status, store, and state-machine code uses public frameworks only.
- Do not change snapshot/export reply behavior, Web, Scene, playback pixel format, IOSurface memory policy, or quality tuning.
- Do not run or automate System Settings, GUI apps, wallpaper selection, Desktop capture, Fullscreen/Space QA, or long performance tests.
- Verification is limited to commands, static inspection, automated tests, unsigned compile gates, codesign inspection when signing is already available, and analysis of user-provided logs.
- Do not run `Scripts/package-app.sh`, create packages or DMGs, notarize, publish, or create/delete/update `dist`.
- Execute in the existing isolated worktree for `feature/native-playback-timing`.

---

## File Structure

### Shared Swift Package

- Modify: `Package.swift`
  - Export `MacWallApp` and `MacWallNativeRuntimeSupport` library products and add the shared test target.
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift`
  - Versioned command/status payloads and fixed protocol constants.
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift`
  - Atomic command/status I/O, immutable generation staging, safe relative-path resolution, and stale generation cleanup.
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeSessionState.swift`
  - Pure transactional multi-context replacement state machine.
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeModelsTests.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeStoreTests.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeSessionStateTests.swift`

### Production Xcode Container

- Create: `MacWall.xcodeproj/project.pbxproj`
  - Host app, wallpaper extension, and Lock Screen saver targets; local Swift Package references.
- Create: `MacWallHostApp/main.swift`
- Create: `MacWallHostApp/Info.plist`
- Create: `MacWallHostApp/MacWallHostApp.entitlements`
- Create: `MacWallNativeWallpaperExtension/Info.plist`
- Create: `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements`
- Create: `MacWallLockScreenSaver/Info.plist`
- Create: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

### Production Wallpaper Extension

- Create: `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallWallpaperExtensionConfiguration.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallWallpaperSettingsViewModel.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallWallpaperXPCProtocols.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallWallpaperXPCIntrospection.swift`
- Create: `MacWallNativeWallpaperExtension/MacWallRemoteContext.swift`
- Create: `MacWallNativeWallpaperExtension/NativeRuntimeDarwinObserver.swift`
- Create: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
- Create: `MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Create: `MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift`
- Create: `MacWallNativeWallpaperExtension/NativeVideoPlaybackTiming.swift`
- Create: `MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift`
- Create: `MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift`

### Main App Playback Integration

- Create: `Sources/MacWallApp/NativeRuntime/NativeRuntimeDarwinNotifier.swift`
- Create: `Sources/MacWallApp/NativeRuntime/NativeRuntimeWaiter.swift`
- Create: `Sources/MacWallApp/Playback/NativeWallpaperEligibility.swift`
- Create: `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`
- Create: `Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift`
- Create: `Sources/MacWallApp/Playback/WallpaperPlaybackCoordinator.swift`
- Create: `Sources/MacWallApp/System/NativeWallpaperSetupPresenter.swift`
- Create: `Sources/MacWallApp/System/WallpaperSettingsController.swift`
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Modify: `Sources/MacWallApp/DesktopFallback/DesktopFallbackCoordinator.swift`
- Modify: `Sources/MacWallApp/System/OriginalDesktopWallpaperStore.swift`
- Create: `Tests/MacWallAppTests/NativeWallpaperEligibilityTests.swift`
- Create: `Tests/MacWallAppTests/NativeWallpaperBackendTests.swift`
- Create: `Tests/MacWallAppTests/WallpaperPlaybackCoordinatorTests.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`
- Modify: `Tests/MacWallAppTests/DesktopFallbackCoordinatorTests.swift`
- Modify: `Tests/MacWallAppTests/OriginalDesktopWallpaperStoreTests.swift`

### Documentation

- Modify: `README.ko.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/development-guide.md`
- Modify: `docs/development-roadmap.md`
- Modify: `docs/development-log.md`

## Fixed Identifiers and Timeouts

```text
Host bundle ID:       io.github.mingyu1715.MacWall
Extension bundle ID:  io.github.mingyu1715.MacWall.NativeWallpaper
App Group:            group.com.mingyu1715.macwall
Darwin notification:  com.mingyu1715.macwall.native-runtime.changed
Protocol schema:      1
Heartbeat interval:   2 seconds
Heartbeat stale age:  5 seconds
Activation probe:     500 milliseconds
Active Play ACK:      5 seconds
Settings-open wait:   120 seconds, cancelled by new Play or Stop
```

The host app keeps deployment target 14.0. The extension has deployment target 26.0 and `com.apple.security.app-sandbox = true`. The host is not newly sandboxed in this phase because current import, conversion, and Lock Screen workflows have not been audited for an app-sandbox migration.

---

### Task 1: Shared Native Runtime Models

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift`
- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeSessionState.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeModelsTests.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeSessionStateTests.swift`

**Interfaces:**

- Produces: `NativeRuntimeConstants`
- Produces: `NativeRuntimeCommand.play(...)` and `NativeRuntimeCommand.stop(...)`
- Produces: `NativeRuntimeStatus`
- Produces: `NativeRuntimeSessionState.beginCandidate(generation:contextIDs:)`
- Produces: `NativeRuntimeSessionState.markReady(generation:contextID:) -> NativeRuntimeSessionDecision`
- Consumed by: App Group store in Task 2, extension session controller in Tasks 4-5, and Main App backend in Task 6.

- [x] **Step 1: Add the shared package target and failing model tests**

Add products/targets to `Package.swift`:

```swift
// Add to products.
.library(name: "MacWallApp", targets: ["MacWallApp"]),
.library(
    name: "MacWallNativeRuntimeSupport",
    targets: ["MacWallNativeRuntimeSupport"]
),

// Add to targets and update the current MacWallApp entry.
.target(name: "MacWallNativeRuntimeSupport"),
.target(
    name: "MacWallApp",
    dependencies: ["MacWallCore", "MacWallNativeRuntimeSupport"]
),
.testTarget(
    name: "MacWallNativeRuntimeSupportTests",
    dependencies: ["MacWallNativeRuntimeSupport"]
)
```

Write `NativeRuntimeModelsTests` to verify:

```swift
func testPlayCommandRoundTripsAllRequiredFields() throws {
    let generation = UUID()
    let command = NativeRuntimeCommand.play(
        generation: generation,
        assetID: "video-a",
        relativeSourcePath: "Generations/\(generation.uuidString)/source.mp4",
        displayMode: .fill,
        createdAt: Date(timeIntervalSince1970: 100)
    )

    let decoded = try JSONDecoder().decode(
        NativeRuntimeCommand.self,
        from: JSONEncoder().encode(command)
    )

    XCTAssertEqual(decoded, command)
    XCTAssertEqual(decoded.schemaVersion, 1)
    XCTAssertEqual(decoded.kind, .play)
}

func testStopCommandHasNoAssetPayload() {
    let command = NativeRuntimeCommand.stop(
        generation: UUID(),
        createdAt: Date(timeIntervalSince1970: 200)
    )

    XCTAssertEqual(command.kind, .stop)
    XCTAssertNil(command.assetID)
    XCTAssertNil(command.relativeSourcePath)
}
```

Write `NativeRuntimeSessionStateTests` for two displays:

```swift
func testCandidateCommitsOnlyAfterEveryContextIsReady() throws {
    var state = NativeRuntimeSessionState(activeGeneration: UUID())
    let candidate = UUID()
    state.beginCandidate(generation: candidate, contextIDs: ["display-1", "display-2"])

    XCTAssertEqual(
        state.markReady(generation: candidate, contextID: "display-1"),
        .waiting
    )
    XCTAssertEqual(
        state.markReady(generation: candidate, contextID: "display-2"),
        .commit(candidate)
    )
}

func testCandidateFailureKeepsPreviousGeneration() {
    let previous = UUID()
    let candidate = UUID()
    var state = NativeRuntimeSessionState(activeGeneration: previous)
    state.beginCandidate(generation: candidate, contextIDs: ["display-1", "display-2"])

    XCTAssertEqual(state.failCandidate(generation: candidate), .reject(candidate))
    XCTAssertEqual(state.activeGeneration, previous)
    XCTAssertNil(state.candidateGeneration)
}
```

- [x] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter NativeRuntimeModelsTests
swift test --filter NativeRuntimeSessionStateTests
```

Expected: compile failure because the shared model and state-machine types do not exist.

- [x] **Step 3: Implement the versioned models**

Create `NativeRuntimeModels.swift` with these exact public types:

```swift
import Foundation

public enum NativeRuntimeConstants {
    public static let schemaVersion = 1
    public static let appGroupIdentifier = "group.com.mingyu1715.macwall"
    public static let changeNotificationName =
        "com.mingyu1715.macwall.native-runtime.changed"
}

public enum NativeRuntimeCommandKind: String, Codable, Sendable {
    case play
    case stop
}

public enum NativeRuntimeAssetKind: String, Codable, Sendable {
    case video
}

public enum NativeRuntimeDisplayMode: String, Codable, Sendable {
    case fit
    case fill
    case stretch
}

public struct NativeRuntimeCommand: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let kind: NativeRuntimeCommandKind
    public let generation: UUID
    public let assetID: String?
    public let assetKind: NativeRuntimeAssetKind?
    public let relativeSourcePath: String?
    public let displayMode: NativeRuntimeDisplayMode?
    public let createdAt: Date

    public static func play(
        generation: UUID,
        assetID: String,
        relativeSourcePath: String,
        displayMode: NativeRuntimeDisplayMode,
        createdAt: Date
    ) -> Self {
        Self(
            schemaVersion: NativeRuntimeConstants.schemaVersion,
            kind: .play,
            generation: generation,
            assetID: assetID,
            assetKind: .video,
            relativeSourcePath: relativeSourcePath,
            displayMode: displayMode,
            createdAt: createdAt
        )
    }

    public static func stop(generation: UUID, createdAt: Date) -> Self {
        Self(
            schemaVersion: NativeRuntimeConstants.schemaVersion,
            kind: .stop,
            generation: generation,
            assetID: nil,
            assetKind: nil,
            relativeSourcePath: nil,
            displayMode: nil,
            createdAt: createdAt
        )
    }
}

public enum NativeRuntimeStatusState: String, Codable, Sendable {
    case inactive
    case preparing
    case playing
    case stopped
    case failed
}

public struct NativeRuntimeFailure: Codable, Equatable, Sendable {
    public let category: String
    public let code: String
    public let message: String

    public init(category: String, code: String, message: String) {
        self.category = category
        self.code = code
        self.message = message
    }
}

public struct NativeRuntimeStatus: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestedGeneration: UUID?
    public let activeGeneration: UUID?
    public let state: NativeRuntimeStatusState
    public let activeDesktopContextCount: Int
    public let extensionInstanceID: UUID
    public let processIdentifier: Int32
    public let heartbeatAt: Date
    public let failure: NativeRuntimeFailure?

    public init(
        schemaVersion: Int = NativeRuntimeConstants.schemaVersion,
        requestedGeneration: UUID?,
        activeGeneration: UUID?,
        state: NativeRuntimeStatusState,
        activeDesktopContextCount: Int,
        extensionInstanceID: UUID,
        processIdentifier: Int32,
        heartbeatAt: Date,
        failure: NativeRuntimeFailure?
    ) {
        self.schemaVersion = schemaVersion
        self.requestedGeneration = requestedGeneration
        self.activeGeneration = activeGeneration
        self.state = state
        self.activeDesktopContextCount = activeDesktopContextCount
        self.extensionInstanceID = extensionInstanceID
        self.processIdentifier = processIdentifier
        self.heartbeatAt = heartbeatAt
        self.failure = failure
    }
}

public enum NativeRuntimeStoreError: Error, Equatable {
    case appGroupUnavailable
    case unsupportedSchema(Int)
    case invalidCommand
    case invalidSourcePath
    case sourceMissing
    case generationAlreadyExists
    case unsafeSymbolicLink
}
```

- [x] **Step 4: Implement the transactional state machine**

Create `NativeRuntimeSessionState.swift`:

```swift
import Foundation

public enum NativeRuntimeSessionDecision: Equatable, Sendable {
    case waiting
    case commit(UUID)
    case reject(UUID)
    case ignored
}

public struct NativeRuntimeSessionState: Equatable, Sendable {
    public private(set) var activeGeneration: UUID?
    public private(set) var candidateGeneration: UUID?
    public private(set) var targetContextIDs: Set<String> = []
    public private(set) var readyContextIDs: Set<String> = []

    public init(activeGeneration: UUID? = nil) {
        self.activeGeneration = activeGeneration
    }

    public mutating func beginCandidate(
        generation: UUID,
        contextIDs: Set<String>
    ) {
        candidateGeneration = generation
        targetContextIDs = contextIDs
        readyContextIDs = []
    }

    public mutating func markReady(
        generation: UUID,
        contextID: String
    ) -> NativeRuntimeSessionDecision {
        guard candidateGeneration == generation,
              targetContextIDs.contains(contextID) else {
            return .ignored
        }
        readyContextIDs.insert(contextID)
        guard readyContextIDs == targetContextIDs else {
            return .waiting
        }
        activeGeneration = generation
        candidateGeneration = nil
        targetContextIDs = []
        readyContextIDs = []
        return .commit(generation)
    }

    public mutating func failCandidate(
        generation: UUID
    ) -> NativeRuntimeSessionDecision {
        guard candidateGeneration == generation else {
            return .ignored
        }
        candidateGeneration = nil
        targetContextIDs = []
        readyContextIDs = []
        return .reject(generation)
    }
}
```

If `contextIDs` is empty, do not call `beginCandidate`; extension code must publish `inactive` instead.

- [x] **Step 5: Run focused tests and commit**

Run:

```bash
swift test --filter NativeRuntimeModelsTests
swift test --filter NativeRuntimeSessionStateTests
```

Expected: both suites pass.

Commit:

```bash
git add Package.swift Sources/MacWallNativeRuntimeSupport Tests/MacWallNativeRuntimeSupportTests
git commit -m "feat(native): add shared runtime protocol"
```

---

### Task 2: Atomic App Group Store and Safe Video Staging

**Files:**

- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeStoreTests.swift`

**Interfaces:**

- Consumes: `NativeRuntimeCommand`, `NativeRuntimeStatus`, and `NativeRuntimeConstants` from Task 1.
- Produces: `NativeRuntimeStore.live(appGroupIdentifier:)`
- Produces: `stageVideo(sourceURL:generation:) -> String`
- Produces: `writeCommand`, `readCommand`, `writeStatus`, `readStatus`
- Produces: `resolveSourceURL(for:) -> URL`
- Produces: `removeGeneration(_:)` and `removeUnreferencedGenerations(keeping:)`
- Consumed by: Extension in Task 4 and Main App backend in Task 6.

- [x] **Step 1: Write failing store and traversal tests**

Use a test-created root directory. Cover:

```swift
func testStageVideoPublishesImmutableGeneration() throws {
    let root = try makeTemporaryDirectory()
    let source = root.appending(path: "input.mp4")
    try Data([1, 2, 3]).write(to: source)
    let store = NativeRuntimeStore(rootURL: root.appending(path: "group"))
    let generation = UUID()

    let relativePath = try store.stageVideo(
        sourceURL: source,
        generation: generation
    )

    XCTAssertEqual(
        relativePath,
        "Generations/\(generation.uuidString)/source.mp4"
    )
    XCTAssertEqual(
        try Data(contentsOf: store.rootURL.appending(path: relativePath)),
        Data([1, 2, 3])
    )
}

func testResolveRejectsTraversal() throws {
    let store = NativeRuntimeStore(rootURL: try makeTemporaryDirectory())
    let command = NativeRuntimeCommand.play(
        generation: UUID(),
        assetID: "bad",
        relativeSourcePath: "../outside.mp4",
        displayMode: .fill,
        createdAt: Date()
    )

    XCTAssertThrowsError(try store.resolveSourceURL(for: command))
}

func testResolveRejectsAbsolutePath() throws {
    let store = NativeRuntimeStore(rootURL: try makeTemporaryDirectory())
    let command = NativeRuntimeCommand.play(
        generation: UUID(),
        assetID: "bad",
        relativeSourcePath: "/tmp/outside.mp4",
        displayMode: .fill,
        createdAt: Date()
    )

    XCTAssertThrowsError(try store.resolveSourceURL(for: command))
}
```

Define the test helper in `NativeRuntimeStoreTests`:

```swift
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "MacWallNativeRuntimeStoreTests")
        .appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    addTeardownBlock {
        try? FileManager.default.removeItem(at: url)
    }
    return url
}
```

Also test:

- command/status JSON atomic replacement can be read after each write
- command generation must match `Generations/{generation.uuidString}/source.mp4`
- symlink source inside a generation cannot resolve outside `Generations`
- cleanup never removes active/candidate generations
- malformed schema version is rejected

- [x] **Step 2: Run the focused store tests and verify RED**

Run:

```bash
swift test --filter NativeRuntimeStoreTests
```

Expected: compile failure because `NativeRuntimeStore` does not exist.

- [x] **Step 3: Implement paths and atomic JSON I/O**

Create `NativeRuntimeStore` with:

```swift
public struct NativeRuntimeStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func live(
        appGroupIdentifier: String = NativeRuntimeConstants.appGroupIdentifier
    ) throws -> Self {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw NativeRuntimeStoreError.appGroupUnavailable
        }
        return Self(rootURL: container.appending(path: "NativeRuntime"))
    }

    public var commandURL: URL { rootURL.appending(path: "command.json") }
    public var statusURL: URL { rootURL.appending(path: "status.json") }
    public var generationsURL: URL { rootURL.appending(path: "Generations") }

    public func writeCommand(_ command: NativeRuntimeCommand) throws
    public func readCommand() throws -> NativeRuntimeCommand?
    public func writeStatus(_ status: NativeRuntimeStatus) throws
    public func readStatus() throws -> NativeRuntimeStatus?
}
```

Implement a private `writeAtomically(_:to:)` that:

1. creates the destination directory,
2. writes encoded JSON to a UUID-named sibling temporary file,
3. uses `replaceItemAt` when the destination exists,
4. uses `moveItem` when it does not,
5. removes the temporary file on failure.

Reject any payload whose `schemaVersion != NativeRuntimeConstants.schemaVersion`.

- [x] **Step 4: Implement immutable staging and containment checks**

`stageVideo` must:

```text
NativeRuntime/.Staging/{generation.uuidString}/source.mp4
-> atomic directory move
NativeRuntime/Generations/{generation.uuidString}/source.mp4
```

Rules:

- source must be an existing regular file URL
- published generation must not already exist
- no symlink is accepted for the published source
- returned path always uses `/` and the exact generation UUID
- `resolveSourceURL(for:)` checks command kind, asset kind, generation, path components, existence, regular-file status, and resolved containment

Add:

```swift
public func removeGeneration(_ generation: UUID) throws

public func removeUnreferencedGenerations(
    keeping generations: Set<UUID>
) throws
```

Never delete `command.json`, `status.json`, the current command generation, or a caller-provided active/candidate generation.

- [x] **Step 5: Run focused tests and commit**

Run:

```bash
swift test --filter NativeRuntimeStoreTests
swift test --filter MacWallNativeRuntimeSupportTests
```

Expected: pass without real App Group access.

Commit:

```bash
git add Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeStoreTests.swift
git commit -m "feat(native): add atomic runtime store"
```

---

### Task 3: Production Xcode App and Extension Container

**Files:**

- Create: `MacWall.xcodeproj/project.pbxproj`
- Create: `MacWallHostApp/main.swift`
- Create: `MacWallHostApp/Info.plist`
- Create: `MacWallHostApp/MacWallHostApp.entitlements`
- Create: `MacWallNativeWallpaperExtension/Info.plist`
- Create: `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements`
- Create: `MacWallLockScreenSaver/Info.plist`
- Create: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

**Interfaces:**

- Consumes: `MacWallApp` and `MacWallNativeRuntimeSupport` package products.
- Produces: `MacWallHostApp`, `MacWallNativeWallpaperExtension`, and `MacWallLockScreenSaver` Xcode targets.
- Consumed by: Extension source promotion in Task 4.

- [x] **Step 1: Add a failing project-structure guard**

Create a Bash test that fails until all project contracts exist:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/MacWall.xcodeproj/project.pbxproj"

test -f "$PROJECT"
test -f "$ROOT/MacWallHostApp/Info.plist"
test -f "$ROOT/MacWallNativeWallpaperExtension/Info.plist"
test -f "$ROOT/MacWallHostApp/MacWallHostApp.entitlements"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"

grep -q 'io.github.mingyu1715.MacWall' "$PROJECT"
grep -q 'io.github.mingyu1715.MacWall.NativeWallpaper' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.appex' "$PROJECT"
grep -q 'MacWallLockScreenSaver' "$PROJECT"

test "$(plutil -extract EXAppExtensionAttributes.EXExtensionPointIdentifier raw \
  "$ROOT/MacWallNativeWallpaperExtension/Info.plist")" = "com.apple.wallpaper"
test "$(plutil -extract com.apple.security.app-sandbox raw \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements")" = "true"

grep -q 'group.com.mingyu1715.macwall' \
  "$ROOT/MacWallHostApp/MacWallHostApp.entitlements"
grep -q 'group.com.mingyu1715.macwall' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"
```

Run:

```bash
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
```

Expected: fail because the production Xcode container does not exist.

- [x] **Step 2: Add host, extension, and screen saver metadata**

`MacWallHostApp/main.swift`:

```swift
import MacWallApp

MacWallApplication.main()
```

Host plist requirements:

```text
CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)
CFBundleExecutable = $(EXECUTABLE_NAME)
CFBundlePackageType = APPL
LSMinimumSystemVersion = 14.0
LSUIElement = true
NSHighResolutionCapable = true
```

Extension plist requirements:

```text
CFBundleDisplayName = MacWall
CFBundlePackageType = XPC!
EXAppExtensionAttributes.EXExtensionPointIdentifier = com.apple.wallpaper
LSMinimumSystemVersion = 26.0
```

Host entitlements contain only:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.mingyu1715.macwall</string>
</array>
```

Extension entitlements contain:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.mingyu1715.macwall</string>
</array>
```

- [x] **Step 3: Create the Xcode project with exact target boundaries**

Create `MacWall.xcodeproj/project.pbxproj` with:

```text
MacWallHostApp
  product type: com.apple.product-type.application
  PRODUCT_NAME: MacWall
  deployment target: 14.0
  bundle ID: io.github.mingyu1715.MacWall
  local package product: MacWallApp
  embed: MacWallNativeWallpaperExtension.appex
  copy to Resources: MacWall.saver

MacWallNativeWallpaperExtension
  product type: com.apple.product-type.extensionkit-extension
  PRODUCT_NAME: MacWallNativeWallpaperExtension
  deployment target: 26.0
  bundle ID: io.github.mingyu1715.MacWall.NativeWallpaper
  APPLICATION_EXTENSION_API_ONLY = YES
  ENABLE_APP_SANDBOX = YES
  local package product: MacWallNativeRuntimeSupport

MacWallLockScreenSaver
  product type: com.apple.product-type.bundle
  PRODUCT_NAME: MacWall
  deployment target: 14.0
  WRAPPER_EXTENSION = saver
  source: Sources/MacWallLockScreenSaver/MacWallLockScreenSaverView.m
  frameworks: AppKit, AVFoundation, CoreMedia, QuartzCore, ScreenSaver
```

Use `CODE_SIGN_STYLE = Automatic` in project configuration but do not hardcode a development team. Agent compile verification uses `CODE_SIGNING_ALLOWED=NO`.

Do not modify `Scripts/package-app.sh` in this task.

- [x] **Step 4: Run static project verification**

Run:

```bash
bash -n Tests/ProjectStructure/native_wallpaper_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
xcodebuild -project MacWall.xcodeproj -list
plutil -lint MacWallHostApp/Info.plist
plutil -lint MacWallHostApp/MacWallHostApp.entitlements
plutil -lint MacWallNativeWallpaperExtension/Info.plist
plutil -lint MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements
plutil -lint MacWallLockScreenSaver/Info.plist
```

Expected: target list and all static guards pass. Do not launch the app.

- [x] **Step 5: Commit the container gate**

```bash
git add MacWall.xcodeproj MacWallHostApp MacWallNativeWallpaperExtension/Info.plist MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements MacWallLockScreenSaver/Info.plist Tests/ProjectStructure/native_wallpaper_project_tests.sh
git commit -m "build(native): add production app container"
```

---

### Task 4: Promote the Proven Extension Handshake and Video Runtime

**Files:**

- Create: production extension Swift files listed in the File Structure section.
- Modify: `MacWall.xcodeproj/project.pbxproj`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

**Interfaces:**

- Consumes: shared package product and Xcode extension target from Tasks 1-3.
- Produces: stable `com.apple.wallpaper` handshake, `CAContext` creation, Desktop/Preview role parsing, fixed synchronizer/normal asset bridge, and disabled snapshot baseline.
- Consumed by: command/session control in Task 5.

- [x] **Step 1: Extend the static guard and verify RED**

Require these production-only contracts:

```bash
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallRemoteContext.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"

grep -q 'provideSettingsViewModels' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'func acquire' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'snapshotGate.*mode=disabled' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'MacWall' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperSettingsViewModel.swift"
```

Run the guard and confirm it fails because the production extension sources are absent.

- [x] **Step 2: Copy only the proven spike mechanisms into production files**

Use the current spike implementations as the source of truth for:

- ExtensionFoundation entry point and `dlopen` of WallpaperExtensionKit
- XPC protocol selector signatures
- `connect`, `provideSettingsViewModels`, `acquire`, `update`, and `invalidate`
- `CAContext.remoteContext` / `remoteContextWithOptions`
- `contextId`, `setLayer:`, and `WallpaperRemoteContextXPC`
- request introspection for size, scale, display ID, preview flag, and cache home
- `AVSampleBufferDisplayLayer`, renderer adapter, synchronizer clock, bounded pump, continuous loop PTS

Production differences must be explicit:

```text
Settings item display name: MacWall
Bundle source video: removed
Generated-frame fallback: removed from production play path
Timing clock: synchronizer
Timing profile: normal
Snapshot candidate matrix/swizzle: not copied
snapshot reply: nil with "snapshotGate mode=disabled" log
```

Do not modify the spike copies.

- [x] **Step 3: Refactor the production bridge to accept an injected video URL**

The production bridge API is:

```swift
final class NativeVideoFrameBridge: @unchecked Sendable {
    struct Callbacks: Sendable {
        let firstFrameEnqueued: @Sendable () -> Void
        let failed: @Sendable (NativeVideoFrameBridgeError) -> Void
    }

    init(
        videoURL: URL,
        frame: CGRect,
        contentsScale: CGFloat,
        displayMode: NativeRuntimeDisplayMode,
        callbacks: Callbacks
    )

    var layer: AVSampleBufferDisplayLayer { get }
    func start()
    func freezeKeepingLastFrame(reason: String)
    func teardown(reason: String)
}
```

Use this production error surface:

```swift
enum NativeVideoFrameBridgeError: Error, Equatable {
    case sourceUnavailable
    case readerCreationFailed
    case readerFailed
    case rendererFailed
    case sampleRetimingFailed
}
```

Behavior:

- `firstFrameEnqueued` fires once after the first asset sample is accepted.
- asset reader, renderer, or retiming failure calls `failed`; it never changes to generated frames.
- `freezeKeepingLastFrame` stops pumping and clock progress without flushing displayed content or removing the layer.
- `teardown` cancels reader/pump, flushes, and removes the layer.
- display mode maps to `.resizeAspect`, `.resizeAspectFill`, or `.resize`.

- [x] **Step 4: Keep Preview and snapshot behavior isolated**

`MacWallRemoteContext` creates:

- Desktop: root layer only; Task 5 attaches controlled playback.
- Preview: lightweight static MacWall-colored layer; no AVAssetReader.
- Unknown: static layer and no active Desktop count.

`snapshot(withId:reply:)` remains:

```swift
macWallNativeWallpaperLogger.info(
    "snapshotGate event=snapshot-reply mode=disabled replyType=nil result=sent"
)
reply(nil, nil)
```

Do not copy file-url, IOSurface, PNG-data, wrapper, swizzle, cache-home writes, or export experiments.

- [x] **Step 5: Compile without signing and run static guards**

Run:

```bash
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
xcodebuild \
  -project MacWall.xcodeproj \
  -scheme MacWallNativeWallpaperExtension \
  -configuration Debug \
  -derivedDataPath /tmp/macwall-native-backend-dd \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: extension target compiles. No runtime launch or wallpaper selection.

- [x] **Step 6: Commit the promoted runtime**

```bash
git add MacWallNativeWallpaperExtension MacWall.xcodeproj/project.pbxproj Tests/ProjectStructure/native_wallpaper_project_tests.sh
git commit -m "feat(native): promote wallpaper extension runtime"
```

---

### Task 5: Extension Command Observer, Heartbeat, and Transactional Replacement

**Files:**

- Create: `MacWallNativeWallpaperExtension/NativeRuntimeDarwinObserver.swift`
- Create: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
- Modify: `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
- Modify: `MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift`
- Modify: `MacWallNativeWallpaperExtension/MacWallRemoteContext.swift`
- Modify: `MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Modify: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeSessionStateTests.swift`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

**Interfaces:**

- Consumes: `NativeRuntimeStore`, commands, statuses, and transactional state from Tasks 1-2.
- Produces: `NativeWallpaperSessionController.registerDesktopSurface`
- Produces: `unregisterDesktopSurface`
- Produces: `processCurrentCommand`
- Produces: heartbeat/status ACK and freeze-on-Stop behavior.
- Consumed by: Main App activation and Play wait logic in Task 6.

- [x] **Step 1: Add failing state-machine edge tests**

Add tests for:

```swift
func testStaleReadyFromOldGenerationIsIgnored()
func testUnknownContextCannotCommitCandidate()
func testFailureAfterOneReadyContextRejectsWholeCandidate()
func testNewCandidateReplacesOnlyCandidateNotActiveGeneration()
```

Example:

```swift
func testStaleReadyFromOldGenerationIsIgnored() {
    let active = UUID()
    let stale = UUID()
    let current = UUID()
    var state = NativeRuntimeSessionState(activeGeneration: active)
    state.beginCandidate(generation: current, contextIDs: ["display-1"])

    XCTAssertEqual(
        state.markReady(generation: stale, contextID: "display-1"),
        .ignored
    )
    XCTAssertEqual(state.activeGeneration, active)
    XCTAssertEqual(state.candidateGeneration, current)
}
```

Run and confirm RED for any missing transition required by these cases.

- [x] **Step 2: Implement the Darwin observer**

`NativeRuntimeDarwinObserver`:

```swift
final class NativeRuntimeDarwinObserver {
    init(
        name: String = NativeRuntimeConstants.changeNotificationName,
        handler: @escaping @Sendable () -> Void
    )

    func start()
    func stop()
}
```

Use `CFNotificationCenterGetDarwinNotifyCenter`. Pass no object or user info. The callback dispatches onto one serial session queue.

- [x] **Step 3: Implement extension session ownership**

`NativeWallpaperSessionController` owns:

```swift
private var surfaces: [String: NativeDesktopSurface]
private var activeBridges: [String: NativeVideoFrameBridge]
private var candidateBridges: [String: NativeVideoFrameBridge]
private var state = NativeRuntimeSessionState()
private let extensionInstanceID = UUID()
private let store: NativeRuntimeStore
private let queue: DispatchQueue
private var heartbeatTimer: DispatchSourceTimer?
```

On Desktop acquire:

1. register surface using wallpaper ID + display ID as a stable context key,
2. publish fresh status with updated active Desktop count,
3. read and process current command.

On Preview/Unknown acquire:

- do not register as active Desktop,
- do not create a decoder.

On invalidate:

- remove that surface and its candidate/active bridge,
- publish updated count,
- keep remaining displays running.

Represent each registered Desktop output as:

```swift
struct NativeDesktopSurface {
    let key: String
    let rootLayer: CALayer
    let frame: CGRect
    let contentsScale: CGFloat
}
```

If a Desktop context is attached or detached during candidate preparation, reject and teardown that candidate, then reconcile the same command against a new snapshot of all current Desktop context keys. A topology reconciliation may rebuild the current generation even when its command generation was already processed.

Every 2 seconds and whenever the Darwin notification is received:

- read `command.json`,
- process a new generation once,
- write a status with a fresh heartbeat.

- [x] **Step 4: Implement all-or-nothing Play**

For a `play` command:

1. reject schema, kind, generation, and source-path errors as `failed`,
2. publish `preparing`,
3. capture the current nonempty Desktop context key set,
4. build one hidden/zero-opacity candidate layer and bridge per target surface,
5. call `state.beginCandidate`,
6. start every bridge,
7. call `markReady` from each one-time first-frame callback,
8. on `.commit`, use one disabled-actions `CATransaction` to expose all candidate layers and remove prior active layers,
9. teardown old bridges after commit,
10. publish `playing` with matching requested/active generation.

On any bridge failure:

1. call `failCandidate`,
2. teardown every candidate bridge,
3. leave active layers and bridges untouched,
4. publish `failed` with the previous active generation still present.

Never report `playing` when only a subset of contexts is ready.

- [x] **Step 5: Implement freeze-on-Stop and stale-command rejection**

For a matching new `stop` command:

- cancel candidate replacement,
- call `freezeKeepingLastFrame` on active bridges,
- keep root/display layers attached,
- publish `stopped` with the previous active generation,
- record the Stop command generation as requested generation.

Ignore:

- a command generation already processed,
- a callback for a noncandidate generation,
- delayed first-frame/failure callback after cancellation,
- command completion from a previous extension instance.

Do not delete the active generation on Stop.

- [x] **Step 6: Run tests and unsigned extension compile**

Run:

```bash
swift test --filter NativeRuntimeSessionStateTests
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
xcodebuild \
  -project MacWall.xcodeproj \
  -scheme MacWallNativeWallpaperExtension \
  -configuration Debug \
  -derivedDataPath /tmp/macwall-native-backend-dd \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: tests and compile pass. Do not install or select the extension.

- [x] **Step 7: Commit**

```bash
git add MacWallNativeWallpaperExtension Sources/MacWallNativeRuntimeSupport Tests/MacWallNativeRuntimeSupportTests Tests/ProjectStructure/native_wallpaper_project_tests.sh
git commit -m "feat(native): control extension playback generations"
```

---

### Task 6: Main App Native and Legacy Backends

**Files:**

- Create: `Sources/MacWallApp/NativeRuntime/NativeRuntimeDarwinNotifier.swift`
- Create: `Sources/MacWallApp/NativeRuntime/NativeRuntimeWaiter.swift`
- Create: `Sources/MacWallApp/Playback/NativeWallpaperEligibility.swift`
- Create: `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`
- Create: `Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift`
- Create: `Sources/MacWallApp/Playback/WallpaperPlaybackCoordinator.swift`
- Create: `Tests/MacWallAppTests/NativeWallpaperEligibilityTests.swift`
- Create: `Tests/MacWallAppTests/NativeWallpaperBackendTests.swift`
- Create: `Tests/MacWallAppTests/WallpaperPlaybackCoordinatorTests.swift`

**Interfaces:**

- Consumes: current `WallpaperPlayerManaging`, fallback coordinators, shared store/status types, and extension ACK contract.
- Produces: `WallpaperPlaybackCoordinating`
- Produces: `PlaybackStartOutcome.started`, `.nativeSetupRequired`, and `.cancelled`
- Produces: request-scoped `resolveNativeSetup(_:pending:)`
- Consumed by: AppViewModel in Task 7.

- [x] **Step 1: Write failing eligibility and route tests**

Inject environment instead of reading the real machine:

```swift
func testVideoOnMacOS26AppleSiliconIsNativeEligible() {
    let eligibility = NativeWallpaperEligibility(
        environment: .init(macOSMajorVersion: 26, isAppleSilicon: true)
    )
    XCTAssertTrue(eligibility.isEligible(videoAsset))
}

func testVideoOnMacOS25UsesLegacy() {
    let eligibility = NativeWallpaperEligibility(
        environment: .init(macOSMajorVersion: 25, isAppleSilicon: true)
    )
    XCTAssertFalse(eligibility.isEligible(videoAsset))
}

func testWebOnMacOS26UsesLegacy() {
    XCTAssertFalse(nativeEligibility.isEligible(webAsset))
}
```

Coordinator tests must prove:

- fresh active status routes Video to Native
- stale heartbeat returns `.nativeSetupRequired`
- non-Video routes directly to Legacy
- one-shot Legacy resolution does not persist a preference
- native explicit failure preserves previous successful receipt
- same in-flight asset request is deduped
- stale async result cannot replace a newer active receipt

- [x] **Step 2: Add deterministic wait abstractions**

Define:

```swift
protocol NativeRuntimeSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousNativeRuntimeSleeper: NativeRuntimeSleeping {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

protocol NativeRuntimeDateProviding: Sendable {
    func now() -> Date
}
```

`NativeRuntimeWaiter` polls injected `readStatus` every 50ms and checks cancellation. Unit tests use a fake sleeper that advances scripted statuses; no real sleep.

Fixed checks:

```text
fresh heartbeat: now - heartbeatAt <= 5 seconds
activation probe timeout: 500 milliseconds
active Play ACK timeout: 5 seconds
settings-open timeout: 120 seconds
```

- [x] **Step 3: Implement eligibility and Native backend**

`NativeWallpaperBackendManaging`:

```swift
enum NativeWallpaperActivationStatus: Equatable {
    case active(NativeRuntimeStatus)
    case inactive
}

struct NativePlaybackReceipt: Equatable {
    let generation: UUID
    let assetID: WallpaperAsset.ID
    let projectDirectory: String
}

protocol NativeWallpaperBackendManaging: AnyObject {
    func activationStatus() async -> NativeWallpaperActivationStatus
    func play(
        asset: WallpaperAsset,
        displayMode: WallpaperDisplayMode,
        generation: UUID,
        timeout: Duration
    ) async throws -> NativePlaybackReceipt
    func stop(generation: UUID) async throws
}
```

`play`:

1. copy only `asset.entrypoint` into App Group staging on a detached task,
2. publish `NativeRuntimeCommand.play`,
3. post Darwin notification,
4. wait for matching `playing` ACK,
5. accept a fresh matching-generation ACK even if WallpaperAgent relaunched the extension,
6. reject `failed`, status older than the command, mismatched generation, timeout, and cancellation,
7. cleanup failed candidate generation,
8. keep active generation and successful source on success.

`activationStatus`:

1. accept a fresh status with `activeDesktopContextCount > 0`,
2. otherwise post the no-payload Darwin notification,
3. wait up to 500ms for a newer fresh heartbeat,
4. return inactive if no active response arrives.

- [x] **Step 4: Implement Legacy backend with explicit stop reasons**

```swift
enum LegacyPlaybackStopReason {
    case userStop
    case handoffToNative
}

@MainActor
final class LegacyWallpaperBackend {
    func play(
        asset: WallpaperAsset,
        options: PlaybackOptions
    ) throws -> LegacyPlaybackReceipt

    func stop(reason: LegacyPlaybackStopReason)
}

struct LegacyPlaybackReceipt: Equatable {
    let snapshot: PlaybackSessionSnapshot
    let restoreSupport: DesktopWallpaperRestoreSupport
}
```

`play` preserves the existing sequence:

```text
WallpaperPlayer.play succeeds
-> Space refresh active asset
-> DesktopFallbackCoordinator.applyOrGenerate
```

On Play failure, restore previous Legacy active fallback/Space-refresh ownership.

`userStop`:

- stop windows,
- clear fallback and Space-refresh active asset,
- restore original wallpaper if current wallpaper still matches the managed fallback.

`handoffToNative`:

- stop windows,
- clear fallback and Space-refresh active asset,
- abandon the managed restore session without applying any wallpaper.

- [x] **Step 5: Implement the coordinator**

Use:

```swift
enum PlaybackBackendKind: Equatable {
    case legacy
    case native
}

struct PlaybackReceipt: Equatable {
    let backend: PlaybackBackendKind
    let assetID: WallpaperAsset.ID
    let projectDirectory: String
    let nativeGeneration: UUID?
    let restoreSupport: DesktopWallpaperRestoreSupport?
}

struct PendingPlaybackRequest: Equatable {
    let requestID: UUID
    let asset: WallpaperAsset
    let options: PlaybackOptions
    let remember: Bool
}

enum PlaybackStartOutcome: Equatable {
    case started(PlaybackReceipt)
    case nativeSetupRequired(PendingPlaybackRequest)
    case cancelled
}

enum NativeWallpaperSetupChoice: Equatable {
    case cancel
    case useLegacyOnce
    case openSettings
}
```

Coordinator methods:

```swift
@MainActor
protocol WallpaperPlaybackCoordinating: AnyObject {
    func play(_ request: PendingPlaybackRequest) async throws -> PlaybackStartOutcome
    func resolveNativeSetup(
        _ choice: NativeWallpaperSetupChoice,
        pending: PendingPlaybackRequest
    ) async throws -> PlaybackStartOutcome
    func stop() async
}
```

Transition rules:

- Native -> Native: extension performs generation transaction.
- Legacy -> Legacy: existing Legacy replacement flow.
- Legacy -> Native: wait for Native ACK, then stop Legacy with `.handoffToNative`.
- Native -> Legacy: start Legacy successfully, then send Native Stop.
- any candidate failure: leave previous backend and receipt active.
- only a successful receipt is visible to AppViewModel.

- [x] **Step 6: Run focused tests and commit**

Run:

```bash
swift test --filter NativeWallpaperEligibilityTests
swift test --filter NativeWallpaperBackendTests
swift test --filter WallpaperPlaybackCoordinatorTests
```

Expected: pass with fake store/status/sleeper; no App Group or GUI dependency.

Commit:

```bash
git add Sources/MacWallApp/NativeRuntime Sources/MacWallApp/Playback Tests/MacWallAppTests/NativeWallpaperEligibilityTests.swift Tests/MacWallAppTests/NativeWallpaperBackendTests.swift Tests/MacWallAppTests/WallpaperPlaybackCoordinatorTests.swift
git commit -m "feat(playback): coordinate native and legacy backends"
```

---

### Task 7: Setup Popup, Wallpaper Settings Opener, and AppViewModel Flow

**Files:**

- Create: `Sources/MacWallApp/System/NativeWallpaperSetupPresenter.swift`
- Create: `Sources/MacWallApp/System/WallpaperSettingsController.swift`
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`

**Interfaces:**

- Consumes: `WallpaperPlaybackCoordinating` and `NativeWallpaperSetupChoice` from Task 6.
- Produces: user-triggered setup resolution, async Play cancellation/dedupe, and success-only `lastPlayedAssetId`.

- [x] **Step 1: Add failing AppViewModel setup-flow tests**

Use mock coordinator, presenter, and settings opener. Cover:

```swift
func testPlayShowsSetupPresenterWhenNativeIsInactive() async
func testCancelKeepsCurrentPlaybackAndLastPlayedID() async
func testUseLegacyOnceResolvesPendingRequestWithoutPersistingBackendChoice() async
func testOpenSettingsOpensWallpaperPaneAndWaitsForNative() async
func testNativeFailureDoesNotChangeLastPlayedID() async
func testSuccessfulNativePlayUpdatesLastPlayedID() async
func testStopCancelsPendingSettingsWait() async
func testAutomaticRestoreDoesNotShowSetupPopup() async
```

The open-settings test asserts call order:

```text
present setup
-> open wallpaper settings
-> resolveNativeSetup(.openSettings)
-> successful receipt
-> lastPlayedAssetId update
```

- [x] **Step 2: Implement the exact 3-button presenter**

Define:

```swift
@MainActor
protocol NativeWallpaperSetupPresenting: AnyObject {
    func presentNativeWallpaperSetup() -> NativeWallpaperSetupChoice
}
```

The production `NSAlert` uses:

```text
messageText:
Native Wallpaper 설정이 필요합니다

informativeText:
macOS 26의 Native Wallpaper 방식은 시스템 설정에서 MacWall을 배경화면으로
한 번 선택해야 합니다. Native 방식은 전체 화면과 Space 전환이 자연스럽습니다.
기존 방식은 바로 재생할 수 있지만 전환 중 macOS 배경화면이 잠깐 보일 수 있습니다.

buttons:
배경화면 설정 열기
기존 방식으로 재생
취소
```

Map first/second/third responses to `.openSettings`, `.useLegacyOnce`, and `.cancel`.

- [x] **Step 3: Implement Wallpaper settings opening**

```swift
@MainActor
protocol WallpaperSettingsOpening {
    @discardableResult
    func openWallpaperSettings() -> Bool
}
```

Production behavior:

```swift
let pane = URL(
    string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
)
if let pane, NSWorkspace.shared.open(pane) {
    return true
}
return NSWorkspace.shared.open(
    URL(fileURLWithPath: "/System/Applications/System Settings.app")
)
```

This runs only after the user presses `배경화면 설정 열기`. Tests use a mock and never call `NSWorkspace`.

- [x] **Step 4: Convert Play to generation-aware async coordination**

In `AppViewModel`:

```swift
private let playbackCoordinator: WallpaperPlaybackCoordinating
private let nativeSetupPresenter: NativeWallpaperSetupPresenting
private let wallpaperSettingsOpener: WallpaperSettingsOpening
private var playbackTask: Task<Void, Never>?
```

`playSelected()`:

1. validate selected asset,
2. cancel the previous pending Play task,
3. create `PendingPlaybackRequest`,
4. await coordinator outcome,
5. if setup is required, present the three-button alert,
6. open settings only for `.openSettings`,
7. resolve the pending request,
8. update `lastPlayedAssetId`, Lock Screen config, and status only after `.started`.

No return path from the setup prompt may call the old private synchronous `play(asset:remember:)`.

- [x] **Step 5: Handle startup restore without an unsolicited popup**

Replace synchronous startup restore with a Task that calls the coordinator using `remember: false`.

If the outcome is `.nativeSetupRequired`:

- do not show an alert,
- do not choose Legacy automatically,
- keep the stored `lastPlayedAssetId`,
- set status to `Native Wallpaper is not active. Press Play to choose a playback method.`

Only user-initiated Play may present setup UI.

- [x] **Step 6: Run focused AppViewModel tests and commit**

Run:

```bash
swift test --filter AppViewModelTests
swift test --filter WallpaperPlaybackCoordinatorTests
```

Expected: all existing and new model tests pass without opening a window.

Commit:

```bash
git add Sources/MacWallApp/App/AppViewModel.swift Sources/MacWallApp/System/NativeWallpaperSetupPresenter.swift Sources/MacWallApp/System/WallpaperSettingsController.swift Tests/MacWallAppTests/AppViewModelTests.swift
git commit -m "feat(app): guide native wallpaper setup"
```

---

### Task 8: Fallback Handoff, Native Stop, and Cleanup

**Files:**

- Modify: `Sources/MacWallApp/DesktopFallback/DesktopFallbackCoordinator.swift`
- Modify: `Sources/MacWallApp/System/OriginalDesktopWallpaperStore.swift`
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
- Modify: `Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift`
- Modify: `Sources/MacWallApp/Playback/WallpaperPlaybackCoordinator.swift`
- Modify: `Tests/MacWallAppTests/DesktopFallbackCoordinatorTests.swift`
- Modify: `Tests/MacWallAppTests/OriginalDesktopWallpaperStoreTests.swift`
- Modify: `Tests/MacWallAppTests/WallpaperPlaybackCoordinatorTests.swift`
- Modify: `Tests/MacWallAppTests/AppViewModelTests.swift`

**Interfaces:**

- Produces: `DesktopFallbackCoordinating.abandonManagedWallpaperSession()`
- Produces: `OriginalDesktopWallpaperManaging.abandonManagedWallpaperSession()`
- Finalizes: backend handoff and Stop semantics.

- [x] **Step 1: Add failing fallback-isolation tests**

Tests must prove:

- Native Play never invokes `applyOrGenerate`
- Legacy Play invokes it only after Legacy player success
- Legacy -> Native handoff clears managed records without calling restore
- Native Stop does not call original wallpaper restore
- Legacy user Stop still restores when current wallpaper matches
- Native Stop does not delete `Derived/desktop-fallback.png`
- new Native generation invalidates/removes only old App Group generation after successful ACK

Original store test:

```swift
func testAbandonManagedSessionRemovesStateWithoutRestoringWallpaper() throws {
    var restoreCalls: [URL] = []
    let store = makeStore(restoreWallpaper: { url, _ in
        restoreCalls.append(url)
    })
    seedManagedRecord(in: store)

    store.abandonManagedWallpaperSession()

    XCTAssertTrue(store.records.isEmpty)
    XCTAssertTrue(restoreCalls.isEmpty)
}
```

- [x] **Step 2: Add explicit managed-session abandonment**

Extend protocols:

```swift
func abandonManagedWallpaperSession()
```

`OriginalDesktopWallpaperStore.abandonManagedWallpaperSession()`:

1. loads every managed record,
2. removes cached original copies owned by those records,
3. removes the persisted restore-state file,
4. never calls `restoreWallpaper`,
5. never deletes any asset `Derived/desktop-fallback.png`.

`DesktopFallbackCoordinator.abandonManagedWallpaperSession()`:

- clears active asset and last-applied ownership,
- cancels automatic refresh/generation tasks that can still apply a fallback,
- delegates to the original store abandonment method.

- [x] **Step 3: Remove the experiment-wide fallback disable switch**

Delete:

```swift
private enum DesktopFallbackRuntime {
    static let isEnabled = false
}
```

Replace branch-wide `DesktopFallbackRuntime.isEnabled` guards with backend ownership:

- Legacy backend owns and executes fallback behavior.
- Native backend never receives the fallback coordinator.
- item-menu generation/regeneration remains available.
- AppViewModel no longer globally disables fallback because it is running on the experiment branch.

Update tests that currently assert “fallback side effects disabled on experiment branch” to assert backend-specific isolation instead.

- [x] **Step 4: Finalize Stop and transition ordering**

`AppViewModel.stopPlayback()`:

1. cancels `playbackTask`,
2. asks coordinator to Stop the active backend,
3. removes `lastPlayedAssetId`,
4. reports `Playback stopped.`

Coordinator:

```text
active Native -> write Stop -> matching stopped ACK or bounded timeout
active Legacy -> Legacy userStop -> existing conditional restore
pending setup -> cancel only; do not restore
no active backend -> no-op
```

If Native Stop ACK times out, keep local active receipt long enough to report the failure but do not run Legacy restore or fallback.

- [x] **Step 5: Run all focused playback/fallback tests**

Run:

```bash
swift test --filter OriginalDesktopWallpaperStoreTests
swift test --filter DesktopFallbackCoordinatorTests
swift test --filter WallpaperPlaybackCoordinatorTests
swift test --filter AppViewModelTests
```

Expected: pass.

- [x] **Step 6: Commit**

```bash
git add Sources/MacWallApp Tests/MacWallAppTests
git commit -m "fix(playback): isolate native and fallback sessions"
```

---

### Task 9: Static Integration Verification and Documentation

**Files:**

- Modify: `README.ko.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/development-guide.md`
- Modify: `docs/development-roadmap.md`
- Modify: `docs/development-log.md`
- Modify: `Tests/ProjectStructure/native_wallpaper_project_tests.sh`

**Interfaces:**

- Consumes: all prior tasks.
- Produces: statically verified implementation state and user/developer documentation.

- [x] **Step 1: Add final source guards**

Require:

```text
MacWallHostApp target embeds MacWallNativeWallpaperExtension.appex
host and extension contain the same App Group
extension point is com.apple.wallpaper
host deployment is 14.0
extension deployment is 26.0
private framework strings exist only under MacWallNativeWallpaperExtension or the existing spike
MacWallApp Native path does not reference DesktopFallbackCoordinator
snapshot/export remains mode=disabled
Scripts/package-app.sh is unchanged by this plan
```

The private-framework scan must exclude `MacWallNativeWallpaperSpike` when checking the new production boundary.

- [x] **Step 2: Run automated and static verification**

Run:

```bash
swift test --filter NativeRuntime
swift test --filter NativeWallpaperEligibilityTests
swift test --filter NativeWallpaperBackendTests
swift test --filter WallpaperPlaybackCoordinatorTests
swift test --filter AppViewModelTests
swift test
bash -n Tests/ProjectStructure/native_wallpaper_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
xcodebuild -project MacWall.xcodeproj -list
xcodebuild \
  -project MacWall.xcodeproj \
  -scheme MacWallHostApp \
  -configuration Debug \
  -derivedDataPath /tmp/macwall-native-backend-dd \
  CODE_SIGNING_ALLOWED=NO \
  build
git diff --check
git diff --exit-code -- Scripts/package-app.sh
```

Expected:

- Swift tests pass
- project guards pass
- host, extension, and embedded products compile without signing
- no app or GUI is launched

If a configured signing identity is already available and no provisioning change is required, additionally inspect a signed developer build with:

```bash
codesign --verify --deep --strict /tmp/macwall-native-backend-dd/Build/Products/Debug/MacWall.app
codesign -d --entitlements :- /tmp/macwall-native-backend-dd/Build/Products/Debug/MacWall.app
codesign -d --entitlements :- /tmp/macwall-native-backend-dd/Build/Products/Debug/MacWall.app/Contents/Extensions/MacWallNativeWallpaperExtension.appex
```

Do not request certificates, change signing accounts, open Xcode UI, or block completion on this optional inspection.

- [x] **Step 3: Update user documentation**

Document in both READMEs:

- Native Video support requires macOS 26+ and Apple Silicon
- the user selects MacWall once in System Settings
- Play shows three choices when Native is inactive
- Legacy remains available for unsupported systems/formats and as a one-shot choice
- Native Stop keeps the final frame
- Native mode does not use desktop-fallback PNG

Do not claim actual Desktop runtime verification for the production target.

- [x] **Step 4: Update developer documentation**

`docs/development-guide.md`:

- add `MacWallNativeRuntimeSupport`
- add Xcode host/appex boundary
- retain the spike reset/install protocol only for spike work
- state that production integration verification is command/static/log only unless separately approved

`docs/development-roadmap.md`:

- set P2.6 to `implementation complete / production runtime QA pending` only if every required command passed
- leave snapshot/export, Web, Scene, and memory optimization as separate work

`docs/development-log.md`:

- record exact commands and pass/fail counts
- record commit hashes
- state explicitly that System Settings and actual Desktop output were not tested

Do not create an `implemented/` completion record until later production runtime QA passes.

- [x] **Step 5: Commit documentation and static gates**

```bash
git add README.ko.md README.md docs Tests/ProjectStructure/native_wallpaper_project_tests.sh
git commit -m "docs(native): document backend integration"
```

- [x] **Step 6: Final clean-state report**

Run:

```bash
git status --short --branch
git log --oneline -10
```

Report:

- changed modules
- test and compile results
- whether signing inspection was available
- production runtime QA still pending
- snapshot/export and BGRA IOSurface memory remain separate

Do not push, package, run the app, or manipulate System Settings.

---

## Deferred Manual QA

This plan intentionally does not execute the following:

```text
install/select production MacWall wallpaper extension
verify actual user-selected Video output
verify first Play after app launch
verify Native <-> Legacy visual handoff
verify multiple physical monitors
verify Fullscreen -> Desktop red-pill result
verify Stop final-frame freeze
```

When the user separately approves that QA, use a short dedicated protocol and analyze WallpaperAgent/Extension logs before changing code. Do not fold that runtime matrix back into this implementation plan.
