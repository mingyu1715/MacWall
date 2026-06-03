# Desktop Fallback Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement P1 desktop fallback caching so supported imported Video, Image, and Web wallpapers keep a representative `Derived/desktop-fallback.png`, reuse it before live playback, and generate it asynchronously without allowing stale results to overwrite the current macOS system wallpaper.

**Architecture:** Add an app-layer `DesktopFallbackCoordinator` around live playback. It applies an existing cache immediately before playback, schedules missing-cache generation after playback, deduplicates automatic work per imported project directory, and uses per-directory generation tokens so only the newest attempt may install a PNG. Completed asynchronous output changes the macOS system wallpaper only when its asset is still active. Video and Image generation runs off the main actor; Image normalization uses ImageIO and CoreGraphics. Web generation uses a dedicated restricted `WKWebView` attached to an invisible off-screen borderless `NSWindow`.

**Tech Stack:** Swift 6, AppKit, AVFoundation, WebKit, ImageIO, CoreGraphics, Swift concurrency, XCTest, SwiftPM.

**Repository note:** This workspace snapshot has no `.git` directory. Run each `git add` / `git commit` step only if Git metadata is restored; otherwise record the skipped commit and continue without initializing a repository.

---

## File Map

**Create**

- `Sources/WorkshopWallpaperBridgeApp/Playback/WebWallpaperContentPolicy.swift`
  - Shared local-only HTTP/HTTPS blocker installation for live Web playback and Web snapshots.
- `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackImageGenerator.swift`
  - Non-main-actor Video frame extraction and ImageIO/CoreGraphics PNG normalization.
- `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/WebDesktopFallbackSnapshotter.swift`
  - Main-actor WebKit rendering session with off-screen borderless window, stabilization delay, timeout, snapshot, and cleanup.
- `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackCoordinator.swift`
  - Cache path, before/after-playback policy, task dedupe, stale-completion check, atomic cache installation, manual Generate and Regenerate.
- `Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackImageGeneratorTests.swift`
- `Tests/WorkshopWallpaperBridgeAppTests/WebWallpaperContentPolicyTests.swift`
- `Tests/WorkshopWallpaperBridgeAppTests/WebDesktopFallbackSnapshotterTests.swift`
- `Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackCoordinatorTests.swift`

**Modify**

- `Sources/WorkshopWallpaperBridgeApp/Playback/RestrictedWebWallpaperView.swift`
  - Replace embedded content-rule compilation with `WebWallpaperContentPolicy`.
- `Sources/WorkshopWallpaperBridgeApp/App/AppViewModel.swift`
  - Apply existing cache before `WallpaperPlayer.shared.play`, schedule missing cache afterward, expose manual actions and Finder opening.
- `Sources/WorkshopWallpaperBridgeApp/UI/ContentView.swift`
  - Add item context-menu commands.
- `Tests/WorkshopWallpaperBridgeAppTests/RestrictedWebWallpaperViewTests.swift`
  - Update shared-policy regression assertions.
- `README.md`
- `README.ko.md`
  - Document automatic fallback reuse, supported source policy, and manual regeneration.

Do not modify Scene parser, Scene renderer, Scene fixtures, or `wwbctl` Scene commands.

---

### Task 1: Extract Shared Local-Only Web Policy

**Files:**
- Create: `Sources/WorkshopWallpaperBridgeApp/Playback/WebWallpaperContentPolicy.swift`
- Modify: `Sources/WorkshopWallpaperBridgeApp/Playback/RestrictedWebWallpaperView.swift`
- Create: `Tests/WorkshopWallpaperBridgeAppTests/WebWallpaperContentPolicyTests.swift`
- Modify: `Tests/WorkshopWallpaperBridgeAppTests/RestrictedWebWallpaperViewTests.swift`

- [ ] **Step 1: Write failing shared-policy tests**

Add tests that assert the new helper source owns the blocker rule and live Web playback calls the helper:

```swift
import XCTest

final class WebWallpaperContentPolicyTests: XCTestCase {
    func testSharedPolicyBlocksRemoteHTTPAndHTTPSRequests() throws {
        let source = try SourceFixture.contents(
            of: "Sources/WorkshopWallpaperBridgeApp/Playback/WebWallpaperContentPolicy.swift"
        )

        XCTAssertTrue(source.contains(#""url-filter":"^https?://.*""#))
        XCTAssertTrue(source.contains("guard error == nil, let ruleList else"))
    }

    func testLiveWebWallpaperUsesSharedPolicy() throws {
        let source = try SourceFixture.contents(
            of: "Sources/WorkshopWallpaperBridgeApp/Playback/RestrictedWebWallpaperView.swift"
        )

        XCTAssertTrue(source.contains("WebWallpaperContentPolicy.install"))
        XCTAssertFalse(source.contains("compileContentRuleList"))
        XCTAssertFalse(source.contains(#""url-filter":"^https?://.*""#))
    }
}
```

Update the existing blocker-compilation test to assert that the helper guards failed compilation instead of checking the view file.

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter WebWallpaperContentPolicyTests
```

Expected: FAIL because `WebWallpaperContentPolicy.swift` does not exist.

- [ ] **Step 3: Add the shared helper and adopt it in live Web playback**

Create:

```swift
import WebKit

enum WebWallpaperContentPolicy {
    static func install(
        into userContentController: WKUserContentController,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let rules = #"""
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "dev.3xhaust.WorkshopWallpaperBridge.BlockRemote",
            encodedContentRuleList: rules
        ) { ruleList, error in
            DispatchQueue.main.async {
                guard error == nil, let ruleList else {
                    completion(false)
                    return
                }
                userContentController.add(ruleList)
                completion(true)
            }
        }
    }
}
```

Replace `RestrictedWebWallpaperView.installRemoteBlockerAndLoad()` internals with:

```swift
WebWallpaperContentPolicy.install(
    into: webView.configuration.userContentController
) { [weak self] installed in
    guard installed, let self else {
        return
    }
    self.webView.loadFileURL(self.url, allowingReadAccessTo: self.readAccessURL)
}
```

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
swift test --filter WebWallpaperContentPolicyTests
swift test --filter RestrictedWebWallpaperViewTests
```

Expected: PASS.

- [ ] **Step 5: Commit when Git metadata exists**

```bash
git add Sources/WorkshopWallpaperBridgeApp/Playback/WebWallpaperContentPolicy.swift \
  Sources/WorkshopWallpaperBridgeApp/Playback/RestrictedWebWallpaperView.swift \
  Tests/WorkshopWallpaperBridgeAppTests/WebWallpaperContentPolicyTests.swift \
  Tests/WorkshopWallpaperBridgeAppTests/RestrictedWebWallpaperViewTests.swift
git commit -m "refactor(web): share local-only wallpaper policy"
```

---

### Task 2: Add Non-Web Desktop Fallback PNG Generation

**Files:**
- Create: `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackImageGenerator.swift`
- Create: `Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackImageGeneratorTests.swift`

- [ ] **Step 1: Write failing generator tests**

Cover Image source selection, Video time selection, unsupported Scene handling, and execution outside the main actor. Use injected operations so tests do not depend on real media decoding:

```swift
final class DesktopFallbackImageGeneratorTests: XCTestCase {
    func testImageGenerationUsesEntrypointAndNeverThumbnail() async throws {
        let asset = makeAsset(
            kind: .image,
            entrypoint: "/tmp/source.png",
            thumbnail: "/tmp/preview.jpg"
        )
        var normalizedURL: URL?
        let generator = DesktopFallbackImageGenerator(
            exportVideoFrame: { _, _, _ in XCTFail("unexpected video path") },
            normalizeImage: { source, output in
                normalizedURL = source
                try Data("png".utf8).write(to: output)
            }
        )

        try await generator.generate(asset: asset, output: outputURL)

        XCTAssertEqual(normalizedURL?.path, "/tmp/source.png")
    }

    func testVideoGenerationRequestsHalfSecondFrame() async throws {
        var requestedSeconds: Double?
        let generator = DesktopFallbackImageGenerator(
            exportVideoFrame: { _, seconds, output in
                requestedSeconds = seconds
                try Data("png".utf8).write(to: output)
            },
            normalizeImage: { _, _ in XCTFail("unexpected image path") }
        )

        try await generator.generate(asset: makeVideoAsset(), output: outputURL)

        XCTAssertEqual(requestedSeconds, 0.5)
    }

    func testSceneGenerationDoesNotUseThumbnail() async {
        await XCTAssertThrowsErrorAsync(
            try await generator.generate(asset: makeSceneAssetWithThumbnail(), output: outputURL)
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
```

Add an actor probe in the injected operation and assert `Thread.isMainThread == false` for Video and Image generation.

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter DesktopFallbackImageGeneratorTests
```

Expected: FAIL because `DesktopFallbackImageGenerator` does not exist.

- [ ] **Step 3: Implement the generator**

Add a `Sendable` generator whose public method dispatches blocking work away from the main actor:

```swift
struct DesktopFallbackImageGenerator: Sendable {
    typealias ExportVideoFrame = @Sendable (URL, Double, URL) throws -> Void
    typealias NormalizeImage = @Sendable (URL, URL) throws -> Void

    private let exportVideoFrame: ExportVideoFrame
    private let normalizeImage: NormalizeImage

    func generate(asset: WallpaperAsset, output: URL) async throws {
        try await Task.detached {
            switch asset.kind {
            case .video:
                guard let input = Self.playableVideoURL(asset.entrypoint) else {
                    throw DesktopFallbackError.unsupportedAsset
                }
                try exportVideoFrame(input, 0.5, output)
            case .image:
                guard let input = Self.imageURL(asset.entrypoint) else {
                    throw DesktopFallbackError.unsupportedAsset
                }
                try normalizeImage(input, output)
            case .web, .scene, .unknown:
                throw DesktopFallbackError.unsupportedAsset
            }
        }.value
    }
}
```

Default operations use `AVAssetImageGenerator` for Video and ImageIO/CoreGraphics (`CGImageSourceCreateWithURL`, `CGImageDestinationCreateWithURL`, `CGImageDestinationAddImage`, `CGImageDestinationFinalize`) for Image PNG conversion. The default Video exporter tries `0.5s`, then `.zero`. The Image normalizer reads only `asset.entrypoint`. Do not use `NSImage` in detached Image conversion work.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
swift test --filter DesktopFallbackImageGeneratorTests
```

Expected: PASS.

- [ ] **Step 5: Commit when Git metadata exists**

```bash
git add Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackImageGenerator.swift \
  Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackImageGeneratorTests.swift
git commit -m "feat(app): generate desktop fallback png for media"
```

---

### Task 3: Add Off-Screen Restricted Web Snapshotter

**Files:**
- Create: `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/WebDesktopFallbackSnapshotter.swift`
- Create: `Tests/WorkshopWallpaperBridgeAppTests/WebDesktopFallbackSnapshotterTests.swift`

- [ ] **Step 1: Write failing Web snapshotter tests**

Use a source-level contract test for AppKit wiring and a value test for defaults:

```swift
final class WebDesktopFallbackSnapshotterTests: XCTestCase {
    func testDefaultsUseHalfSecondStabilizationAndFiveSecondTimeout() {
        let options = WebDesktopFallbackSnapshotter.Options.default

        XCTAssertEqual(options.stabilizationDelay, .milliseconds(500))
        XCTAssertEqual(options.timeout, .seconds(5))
    }

    func testSnapshotterUsesOffscreenBorderlessWindowSharedPolicyAndCleanup() throws {
        let source = try SourceFixture.contents(
            of: "Sources/WorkshopWallpaperBridgeApp/DesktopFallback/WebDesktopFallbackSnapshotter.swift"
        )

        XCTAssertTrue(source.contains("styleMask: [.borderless]"))
        XCTAssertTrue(source.contains("WebWallpaperContentPolicy.install"))
        XCTAssertTrue(source.contains("NSScreen.main?.frame.size"))
        XCTAssertTrue(source.contains("cleanup()"))
        XCTAssertTrue(source.contains("window.close()"))
        XCTAssertTrue(source.contains("webView.removeFromSuperview()"))
    }
}
```

Add source assertions that terminal results flow through `finish(with:)`, cancellation calls `cancel()`, and the single idempotent `cleanup()` method closes and detaches the temporary rendering resources:

```swift
XCTAssertTrue(source.contains("private func finish(with result: Result<Void, Error>)"))
XCTAssertTrue(source.contains("func cancel()"))
XCTAssertTrue(source.contains("cleanup()"))
XCTAssertTrue(source.contains("window.close()"))
XCTAssertTrue(source.contains("webView.removeFromSuperview()"))
```

Add an integration test that writes a real local HTML document with a solid-color body, calls the snapshotter with a small viewport override, and asserts that the resulting PNG exists and is non-empty:

```swift
@MainActor
func testSnapshotterCapturesRealLocalHTMLIntoPNG() async throws {
    let root = try makeTempDirectory()
    let html = root.appending(path: "index.html")
    let output = root.appending(path: "fallback.png")
    try """
    <!doctype html>
    <html><body style="margin:0;background:#2468ac"></body></html>
    """.write(to: html, atomically: true, encoding: .utf8)
    let snapshotter = WebDesktopFallbackSnapshotter(
        viewportSize: CGSize(width: 160, height: 90)
    )

    try await snapshotter.snapshot(url: html, readAccessURL: root, output: output)

    XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter WebDesktopFallbackSnapshotterTests
```

Expected: FAIL because `WebDesktopFallbackSnapshotter` does not exist.

- [ ] **Step 3: Implement Web snapshot session**

Add:

```swift
@MainActor
struct WebDesktopFallbackSnapshotter {
    struct Options: Equatable {
        let stabilizationDelay: Duration
        let timeout: Duration

        static let `default` = Options(
            stabilizationDelay: .milliseconds(500),
            timeout: .seconds(5)
        )
    }

    func snapshot(url: URL, readAccessURL: URL, output: URL) async throws
}
```

Implementation requirements:

- Resolve viewport from `NSScreen.main?.frame.size`, falling back to `CGSize(width: 1920, height: 1080)`.
- Create `WKWebViewConfiguration` with `.nonPersistent()` data store and disabled automatic JS windows.
- Create a borderless temporary `NSWindow` with an origin outside the visible screen area, set `alphaValue = 0`, `ignoresMouseEvents = true`, and attach the WebView as its content view.
- Call `WebWallpaperContentPolicy.install`.
- Load only the local file URL with `allowingReadAccessTo: readAccessURL`.
- Resume capture from `webView(_:didFinish:)`, sleep `500ms`, then call `takeSnapshot`.
- Race capture against a `5s` timeout.
- Convert the resulting `NSImage` to PNG and write `output`.
- Route success, policy failure, navigation failure, provisional failure, snapshot failure, cancellation, and timeout through one idempotent `cleanup()` method.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
swift test --filter WebDesktopFallbackSnapshotterTests
swift test --filter WebWallpaperContentPolicyTests
```

Expected: PASS.

- [ ] **Step 5: Commit when Git metadata exists**

```bash
git add Sources/WorkshopWallpaperBridgeApp/DesktopFallback/WebDesktopFallbackSnapshotter.swift \
  Tests/WorkshopWallpaperBridgeAppTests/WebDesktopFallbackSnapshotterTests.swift
git commit -m "feat(app): capture restricted web fallback snapshots"
```

---

### Task 4: Add Cache Coordinator with Dedupe and Stale-Result Protection

**Files:**
- Create: `Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackCoordinator.swift`
- Create: `Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackCoordinatorTests.swift`

- [ ] **Step 1: Write failing cache-path and existing-cache tests**

Add:

```swift
@MainActor
final class DesktopFallbackCoordinatorTests: XCTestCase {
    func testCacheURLUsesImportedProjectDirectoryInsteadOfAssetId() {
        let asset = makeAsset(id: "plain-id", projectDirectory: "/tmp/Assets/id-cGxhaW4taWQ")

        XCTAssertEqual(
            DesktopFallbackCoordinator.cacheURL(for: asset).path,
            "/tmp/Assets/id-cGxhaW4taWQ/Derived/desktop-fallback.png"
        )
    }

    func testPrepareForPlaybackAppliesExistingCacheWithoutGenerating() throws {
        let fixture = try makeFixture(existingCache: Data("cached".utf8))
        var applied: [URL] = []
        let coordinator = makeCoordinator(
            generate: { _, _ in XCTFail("must not generate") },
            apply: { applied.append($0) }
        )

        coordinator.prepareForPlayback(asset: fixture.asset)
        coordinator.scheduleGenerationIfNeeded(asset: fixture.asset)

        XCTAssertEqual(applied, [fixture.cacheURL])
    }
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```bash
swift test --filter DesktopFallbackCoordinatorTests
```

Expected: FAIL because `DesktopFallbackCoordinator` does not exist.

- [ ] **Step 3: Implement cache path and playback boundary methods**

Add a `@MainActor` coordinator with:

```swift
static func cacheURL(for asset: WallpaperAsset) -> URL {
    URL(filePath: asset.projectDirectory)
        .appending(path: "Derived")
        .appending(path: "desktop-fallback.png")
}

func prepareForPlayback(asset: WallpaperAsset) {
    activeProjectDirectory = projectKey(for: asset)
    let cache = Self.cacheURL(for: asset)
    guard fileManager.fileExists(atPath: cache.path) else {
        return
    }
    try? applyDesktopImage(cache)
}

func scheduleGenerationIfNeeded(asset: WallpaperAsset) {
    guard !fileManager.fileExists(atPath: Self.cacheURL(for: asset).path) else {
        return
    }
    scheduleGeneration(asset: asset, replaceExisting: false, applyWhenCurrent: true)
}
```

- [ ] **Step 4: Write failing dedupe and stale-result tests**

Add async tests:

```swift
func testRepeatedAutomaticRequestsDeduplicatePerProjectDirectory() async throws {
    let gate = AsyncGate()
    var generateCount = 0
    let coordinator = makeCoordinator(generate: { _, output in
        generateCount += 1
        await gate.wait()
        try Data("png".utf8).write(to: output)
    })

    coordinator.scheduleGenerationIfNeeded(asset: asset)
    coordinator.scheduleGenerationIfNeeded(asset: asset)
    await waitUntil { generateCount == 1 }
    gate.open()
    await coordinator.waitForAutomaticGeneration()

    XCTAssertEqual(generateCount, 1)
}

func testCompletedStaleGenerationCachesPngWithoutApplyingIt() async throws {
    let gate = AsyncGate()
    var applied: [URL] = []
    let coordinator = makeCoordinator(
        generate: { _, output in
            await gate.wait()
            try Data("png".utf8).write(to: output)
        },
        apply: { applied.append($0) }
    )

    coordinator.prepareForPlayback(asset: first)
    coordinator.scheduleGenerationIfNeeded(asset: first)
    coordinator.prepareForPlayback(asset: second)
    gate.open()
    await coordinator.waitForAutomaticGeneration()

    XCTAssertTrue(FileManager.default.fileExists(atPath: firstCache.path))
    XCTAssertFalse(applied.contains(firstCache))
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
```

- [ ] **Step 5: Run tests to verify RED**

Run:

```bash
swift test --filter DesktopFallbackCoordinatorTests
```

Expected: FAIL because in-flight dedupe, atomic install, and stale-current checks are not implemented.

- [ ] **Step 6: Implement dedupe, atomic install, and stale-result protection**

Use:

```swift
private var activeProjectDirectory: String?
private var inFlightAutomaticTasks: [String: Task<Void, Never>] = [:]
private var latestGenerationTokens: [String: UUID] = [:]

private func projectKey(for asset: WallpaperAsset) -> String {
    URL(filePath: asset.projectDirectory).standardizedFileURL.path
}
```

Generation requirements:

- Key automatic tasks by standardized imported project-directory path.
- Assign each generation attempt a new token and atomically install output only when it still matches `latestGenerationTokens[key]`.
- Generate into a temporary sibling such as `.desktop-fallback.<UUID>.png`.
- Create `Derived` before generation.
- Dispatch Video/Image work through `DesktopFallbackImageGenerator.generate`, which performs detached work.
- Dispatch Web work through `WebDesktopFallbackSnapshotter.snapshot` on the main actor.
- Install with an atomic filesystem replacement only after generation succeeds.
- After installing, apply the cache only when `activeProjectDirectory == projectKey(for: asset)`.
- Remove the in-flight dictionary entry in a `defer`-equivalent main-actor completion path on success or error.
- Keep prior cache bytes untouched until regeneration succeeds.
- Add `clearActiveAsset()` for Stop Playback and live playback failure.
- Add `invalidate(asset:)` for Remove, reimport, and manual Regenerate. It advances/removes the latest token, cancels any tracked automatic task for that key, and prevents earlier completions from installing PNG output.
- After removing an invalidated task's temporary PNG, remove only empty `Derived` and asset directories so delayed completion cannot recreate a removed library item.

- [ ] **Step 7: Write failing manual regeneration-preservation test**

Add:

```swift
func testFailedManualRegenerationPreservesPreviousCache() async throws {
    let fixture = try makeFixture(existingCache: Data("previous".utf8))
    let coordinator = makeCoordinator(generate: { _, _ in
        throw DesktopFallbackError.generationFailed
    })

    await XCTAssertThrowsErrorAsync(
        try await coordinator.regenerate(asset: fixture.asset)
    )

    XCTAssertEqual(try Data(contentsOf: fixture.cacheURL), Data("previous".utf8))
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
```

- [ ] **Step 8: Run test to verify RED, then implement manual operations**

Run:

```bash
swift test --filter DesktopFallbackCoordinatorTests
```

Expected before implementation: FAIL because `regenerate(asset:)` does not exist.

Implement:

```swift
func generate(asset: WallpaperAsset) async throws
func regenerate(asset: WallpaperAsset) async throws
func hasCache(for asset: WallpaperAsset) -> Bool
```

`generate(asset:)` reuses and applies an existing cache. `regenerate(asset:)` always generates into a temporary sibling, atomically installs it, and applies it only if the asset is current.

Add tests:

```swift
func testStopPlaybackClearKeepsCacheButPreventsLaterApply() async throws
func testInvalidatePreventsOlderGenerationFromInstallingCache() async throws
func testManualRegenerateInvalidatesOlderAutomaticGeneration() async throws
```

- [ ] **Step 9: Run focused tests to verify GREEN**

Run:

```bash
swift test --filter DesktopFallbackCoordinatorTests
```

Expected: PASS.

- [ ] **Step 10: Commit when Git metadata exists**

```bash
git add Sources/WorkshopWallpaperBridgeApp/DesktopFallback/DesktopFallbackCoordinator.swift \
  Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackCoordinatorTests.swift
git commit -m "feat(app): coordinate desktop fallback cache"
```

---

### Task 5: Wire Playback Boundaries and Library Item Commands

**Files:**
- Modify: `Sources/WorkshopWallpaperBridgeApp/App/AppViewModel.swift`
- Modify: `Sources/WorkshopWallpaperBridgeApp/UI/ContentView.swift`
- Modify: `Tests/WorkshopWallpaperBridgeAppTests/AppViewModelTests.swift`
- Create: `Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackMenuTests.swift`

- [ ] **Step 1: Write failing AppViewModel and menu contract tests**

Add source-level playback-order assertions to avoid launching desktop windows during XCTest:

```swift
func testPlaybackAppliesExistingFallbackBeforeLivePlayerAndSchedulesGenerationAfterward() throws {
    let source = try SourceFixture.contents(
        of: "Sources/WorkshopWallpaperBridgeApp/App/AppViewModel.swift"
    )
    let prepare = try XCTUnwrap(source.range(of: "desktopFallbackCoordinator.prepareForPlayback"))
    let play = try XCTUnwrap(source.range(of: "WallpaperPlayer.shared.play"))
    let schedule = try XCTUnwrap(source.range(of: "desktopFallbackCoordinator.scheduleGenerationIfNeeded"))

    XCTAssertLessThan(prepare.lowerBound, play.lowerBound)
    XCTAssertLessThan(play.lowerBound, schedule.lowerBound)
}

func testLibraryItemMenuExposesFinderGenerateRegenerateAndRemove() throws {
    let source = try SourceFixture.contents(
        of: "Sources/WorkshopWallpaperBridgeApp/UI/ContentView.swift"
    )

    XCTAssertTrue(source.contains(#"Button("Show in Finder")"#))
    XCTAssertTrue(source.contains(#"Button("Generate Desktop Fallback")"#))
    XCTAssertTrue(source.contains(#"Button("Regenerate Desktop Fallback")"#))
    XCTAssertTrue(source.contains(#"Button("Remove")"#))
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter DesktopFallbackMenuTests
```

Expected: FAIL because the actions are not wired.

- [ ] **Step 3: Wire coordinator and actions**

In `AppViewModel`:

```swift
private let desktopFallbackCoordinator = DesktopFallbackCoordinator()

private func play(asset: WallpaperAsset, remember: Bool) throws {
    desktopFallbackCoordinator.prepareForPlayback(asset: asset)
    do {
        try WallpaperPlayer.shared.play(
            asset: asset,
            autoPauseWhenCovered: autoPauseWhenCovered,
            experimentalSceneRendering: experimentalSceneRendering,
            webMouseInteractionEnabled: webMouseInteractionEnabled,
            displayMode: displayMode
        )
    } catch {
        desktopFallbackCoordinator.clearActiveAsset()
        throw error
    }
    desktopFallbackCoordinator.scheduleGenerationIfNeeded(asset: asset)
}

func hasDesktopFallback(for asset: WallpaperAsset) -> Bool
func showLibraryAssetInFinder(_ asset: WallpaperAsset)
func generateDesktopFallback(for asset: WallpaperAsset)
func regenerateDesktopFallback(for asset: WallpaperAsset)
```

Also call:

```swift
desktopFallbackCoordinator.clearActiveAsset()
```

from `stopPlayback()`, and call:

```swift
desktopFallbackCoordinator.invalidate(asset: asset)
```

before removing an imported library item, before reimporting the matching scanned asset into its encoded project directory, and before manual Regenerate starts.

Manual actions start `Task` work, set a clear status string, and surface failure text. Finder uses:

```swift
NSWorkspace.shared.activateFileViewerSelecting([
    URL(filePath: asset.projectDirectory)
])
```

In each library-row context menu:

```swift
Button("Show in Finder") {
    model.showLibraryAssetInFinder(asset)
}
if model.hasDesktopFallback(for: asset) {
    Button("Regenerate Desktop Fallback") {
        model.regenerateDesktopFallback(for: asset)
    }
} else {
    Button("Generate Desktop Fallback") {
        model.generateDesktopFallback(for: asset)
    }
}
Button("Remove") {
    model.selectLibraryAssets([asset.id])
    model.removeSelectedLibraryAssets()
}
```

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
swift test --filter DesktopFallbackMenuTests
swift test --filter AppViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit when Git metadata exists**

```bash
git add Sources/WorkshopWallpaperBridgeApp/App/AppViewModel.swift \
  Sources/WorkshopWallpaperBridgeApp/UI/ContentView.swift \
  Tests/WorkshopWallpaperBridgeAppTests/AppViewModelTests.swift \
  Tests/WorkshopWallpaperBridgeAppTests/DesktopFallbackMenuTests.swift
git commit -m "feat(app): wire desktop fallback playback flow"
```

---

### Task 6: Document P1 Behavior

**Files:**
- Modify: `README.md`
- Modify: `README.ko.md`

- [ ] **Step 1: Update docs**

Add this English paragraph in the playback section:

```markdown
To reduce flashes of the previous macOS wallpaper during Spaces and full-screen transitions, the app keeps a per-item `Derived/desktop-fallback.png`. When it already exists, playback applies it immediately before opening the live desktop layer. When it is absent, Video, Image, and Web items generate it once from the real source or rendered Web output after playback starts. Web snapshot failure does not stop live playback. Workshop previews and Scene thumbnails are never used as desktop fallbacks. Use the library item's menu to show its imported folder or regenerate the desktop fallback manually.
```

Add this Korean paragraph in the matching playback section:

```markdown
Spaces 전환이나 전체화면 전환 중 기존 macOS 배경화면이 잠깐 보이는 현상을 줄이기 위해 항목별 `Derived/desktop-fallback.png`를 유지합니다. 파일이 이미 있으면 라이브 데스크톱 레이어를 열기 직전에 즉시 적용합니다. 파일이 없으면 Video, Image, Web 항목에 한해 실제 원본이나 렌더링된 Web 출력에서 재생 시작 후 한 번만 생성합니다. Web snapshot이 실패해도 라이브 재생은 계속됩니다. Workshop 썸네일과 Scene 썸네일은 데스크톱 fallback으로 사용하지 않습니다. 라이브러리 항목 메뉴에서 가져온 폴더를 열거나 데스크톱 fallback을 수동으로 다시 생성할 수 있습니다.
```

Append that Stop Playback stops the live layer but preserves `Derived/desktop-fallback.png` for later reuse.

Add the item-menu labels `Show in Finder`, `Generate Desktop Fallback`, and `Regenerate Desktop Fallback` to the English README and their UI-label references to the Korean README.

- [ ] **Step 2: Verify docs contract**

Run:

```bash
rg -n "desktop-fallback\\.png|Regenerate Desktop Fallback|Workshop preview|Workshop 썸네일" README.md README.ko.md
```

Expected: both README files document cache storage, regeneration, and thumbnail exclusion.

- [ ] **Step 3: Commit when Git metadata exists**

```bash
git add README.md README.ko.md
git commit -m "docs: explain desktop fallback cache"
```

---

### Task 7: Full Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run all XCTest cases**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run debug build**

Run:

```bash
swift build
```

Expected: exit 0.

- [ ] **Step 3: Run CLI scan regression**

Run:

```bash
swift run wwbctl scan test --out /tmp/workshop-wallpaper-bridge-scan.json
```

Expected: exit 0 and `/tmp/workshop-wallpaper-bridge-scan.json` exists.

- [ ] **Step 4: Build package and verify menu-bar contract**

Run:

```bash
bash Scripts/package-app.sh
plutil -extract LSUIElement raw -o - "dist/Workshop Wallpaper Bridge.app/Contents/Info.plist"
```

Expected: package script exits 0 and `plutil` prints `true`.

- [ ] **Step 5: Confirm Scene S0 was not started**

Run:

```bash
rg -n "scene-audit|SceneAudit|MTKView|SceneMetal" Sources Tests
```

Expected: no new Scene S0 or Metal runtime implementation appears.

- [ ] **Step 6: Inspect changed files**

Run:

```bash
find Sources Tests docs README.md README.ko.md -type f -newer docs/superpowers/specs/2026-06-03-desktop-fallback-cache-design.md | sort
```

Expected: changes are limited to P1 files, docs, and tests.
