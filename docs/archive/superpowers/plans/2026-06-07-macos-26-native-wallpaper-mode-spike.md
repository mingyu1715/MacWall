# macOS 26 Native Wallpaper Mode Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove whether MacWall can enter the macOS 26 native wallpaper pipeline through `WallpaperExtensionKit` / `WallpaperAgent` without using desktop-level `NSWindow` as the wallpaper surface.

**Architecture:** Keep the current `NSWindow` playback backend intact and add a macOS 26-only native wallpaper spike behind explicit capability checks. The spike first observes the system `WallpaperAgent` and Apple wallpaper extension discovery flow, then attempts a separate native wallpaper extension that can be registered, discovered, loaded by `WallpaperAgent`, receive a wallpaper request, and display generated frames through `AVSampleBufferDisplayLayer`.

**Tech Stack:** Swift 6, SwiftPM for current app/tests, Xcode project or isolated Xcode spike for ExtensionKit app extension, AppKit, AVFoundation, CoreMedia, private `WallpaperExtensionKit`, `WallpaperAgent`, `AVSampleBufferDisplayLayer`.

---

## Scope

This plan is a spike, not a production feature. It must answer where the macOS 26 native wallpaper path succeeds or fails.

Included:

- WallpaperAgent and Apple wallpaper extension discovery observation.
- Capability probe in the SwiftPM app code.
- Backend selection model that can represent `.windowServerWindow` and `.nativeWallpaper`.
- A native wallpaper extension spike project or target.
- Single generated-frame output.
- Single local video output only after generated-frame output works.
- Diagnostics and development-log updates.

Excluded:

- macOS 14/15 support.
- Web native wallpaper output.
- Scene native wallpaper output.
- CAMetalLayer output.
- fallback PNG policy changes.
- Dock/Finder injection.
- SIP disablement.
- system wallpaper DB mutation.
- release packaging, DMG, notarization.

## File Structure

### SwiftPM app files

- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperCapabilityProbe.swift`
  - Reads OS and system path capabilities through injectable filesystem/process boundaries.
- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperBackend.swift`
  - Defines backend enum, availability report, and errors.
- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperModeController.swift`
  - Chooses native mode only when user setting and capability report allow it.
- Modify: `Sources/MacWallApp/App/AppViewModel.swift`
  - Adds experimental native mode state only after probe tests pass.
- Test: `Tests/MacWallAppTests/NativeWallpaperCapabilityProbeTests.swift`
- Test: `Tests/MacWallAppTests/NativeWallpaperModeControllerTests.swift`

### Native extension spike files

One of the two structures must be chosen at implementation time:

- Preferred if Xcode project is accepted:
  - Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpike.xcodeproj`
  - Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist`
  - Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
  - Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`
- Fallback if project generation is not ready:
  - Create: `NativeWallpaperSpike/README.md`
  - Create: `NativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist`
  - Create: `NativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
  - Create: `NativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`

The spike must not be wired into normal `swift test` unless the files are valid for SwiftPM. ExtensionKit build verification uses explicit Xcode commands only after user approval.

## Critical Risk Order

The highest-risk assumption is not frame rendering. It is whether third-party `com.apple.wallpaper` extensions are accepted by `WallpaperAgent`.

Therefore the execution order is:

```text
Task 0: Observe Apple WallpaperAgent and extension discovery
-> Task 3/4: Build/register/load a minimal MacWall wallpaper extension
-> Task 1/2: Add app capability/backend selection after the extension path is plausible
-> Task 5+: Native surface and frame rendering
```

If Task 0 cannot observe the Apple flow, improve diagnostics before writing native rendering code. If Task 3/4 proves third-party extensions are not discovered or launched, stop the native path and do not implement Task 5.

## Development Run Protocol

`WallpaperAgent` owns the native wallpaper extension process. For this spike,
launching or quitting the containing app with `open` is not considered a clean
test boundary.

Until a dedicated dev runner exists, every manual native wallpaper test uses
only this sequence:

```text
1. dev reset
2. dev install
3. 사용자가 시스템 설정에서 MacWall Native Spike 선택
4. 로그 확인
5. 사용자 화면 확인
6. 다시 테스트할 때는 반드시 reset 후 install
```

Rules:

- Do not treat containing app quit as extension shutdown.
- Do not use ad-hoc `open` launch/quit as validation evidence.
- Always reset before reinstalling or retesting.
- User-visible screen state is verified by the user, then compared against
  `WallpaperAgent` and extension logs before the next implementation step.

## Task 0: WallpaperAgent Discovery Observation

**Files:**

- Modify: `docs/development-log.md`

- [x] **Step 1: Confirm system wallpaper extension registrations**

Run:

```bash
for plist in /System/Library/ExtensionKit/Extensions/*Wallpaper*.appex/Contents/Info.plist; do
  printf '%s\n' "$plist"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null
  /usr/libexec/PlistBuddy -c 'Print :EXAppExtensionAttributes:EXExtensionPointIdentifier' "$plist" 2>/dev/null
done
```

Expected:

```text
At least one Apple extension prints EXExtensionPointIdentifier com.apple.wallpaper.
Wallpaper.appex may print com.apple.Settings.extension.ui and should not be treated as the wallpaper provider extension.
```

- [x] **Step 2: Confirm WallpaperAgent bundle metadata**

Run:

```bash
plutil -p /System/Library/CoreServices/WallpaperAgent.app/Contents/Info.plist
```

Expected:

```text
"CFBundleIdentifier" => "com.apple.wallpaper.agent"
"LSUIElement" => true
```

- [x] **Step 3: Check pluginkit registration visibility**

Run:

```bash
pluginkit -m -A -D -vv | rg 'com\.apple\.wallpaper|WallpaperAerialsExtension|WallpaperImageExtension|WallpaperDynamicExtension|WallpaperMacintoshExtension'
```

Expected:

```text
Apple wallpaper extensions are visible, or pluginkit returns a connection error that must be recorded.
```

If `pluginkit` returns `match: Connection invalid`, record it and use filesystem + logs as the observation source. Do not continue assuming pluginkit is reliable on this machine.

- [x] **Step 4: Collect WallpaperAgent logs while switching Apple wallpaper**

Run before changing wallpaper in System Settings:

```bash
log stream --style compact --predicate 'process == "WallpaperAgent" OR subsystem CONTAINS "wallpaper"' --info
```

Manual action:

```text
Open System Settings -> Wallpaper.
Select at least one Apple built-in wallpaper provider.
Switch between two Apple wallpapers if possible.
Stop log stream after relevant lines appear.
```

Expected:

```text
Logs identify WallpaperAgent lifecycle, extension/provider selection, request/update/snapshot activity, or useful subsystem/category names.
```

If logs are too noisy, repeat with narrower predicates discovered from the first run.

Observed result on 2026-06-07:

```text
Live wallpaper switching was not required because `/usr/bin/log show --last 30m`
already contained WallpaperAgent extension-proxy, runtime-resolver,
selectedChoicesDidChange, and invalidate lifecycle records.
```

- [x] **Step 5: Capture current WallpaperAgent process state if permitted**

Run:

```bash
ps -axo pid,ppid,comm,args | rg 'WallpaperAgent|Wallpaper'
```

Expected:

```text
WallpaperAgent process appears when wallpaper UI or wallpaper runtime is active.
```

If sandbox or privacy policy blocks `ps`, record the failure and rely on logs/filesystem observations.

- [x] **Step 6: Record Task 0 outcome**

Add an entry to `docs/development-log.md`:

```md
### HH:MM KST

- 조사: macOS 26 WallpaperAgent discovery observation
- 결과:
  - Apple `com.apple.wallpaper` extension plist 확인: pass/fail
  - WallpaperAgent bundle 확인: pass/fail
  - pluginkit registration 확인: pass/fail/unavailable
  - WallpaperAgent log에서 extension/provider lifecycle 관찰: pass/fail
  - WallpaperAgent process 확인: pass/fail/unavailable
- 판단:
  - Apple flow가 관찰되면 MacWall minimal extension discovery/load gate로 진행
  - Apple flow도 관찰되지 않으면 diagnostics를 먼저 보강
```

- [x] **Step 7: Stop condition**

Stop the native wallpaper spike before any rendering work if:

```text
Apple wallpaper extensions cannot be identified.
WallpaperAgent logs cannot be observed at all.
There is no reliable way to tell whether WallpaperAgent discovered a provider.
```

Observed result on 2026-06-07:

```text
Stop condition not triggered. Apple wallpaper extensions, WallpaperAgent logs,
and WallpaperAgent/extension processes were observable. Continue to the MacWall
minimal extension discovery/load gate before native surface work.
```

## Task 1: Capability Probe

**Files:**

- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperBackend.swift`
- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperCapabilityProbe.swift`
- Test: `Tests/MacWallAppTests/NativeWallpaperCapabilityProbeTests.swift`

- [ ] **Step 1: Write failing tests for unavailable and available capability reports**

Create `Tests/MacWallAppTests/NativeWallpaperCapabilityProbeTests.swift`:

```swift
import XCTest
@testable import MacWallApp

final class NativeWallpaperCapabilityProbeTests: XCTestCase {
    func testReportsUnavailableWhenOSMajorVersionIsBelow26() {
        let probe = NativeWallpaperCapabilityProbe(
            osMajorVersion: { 15 },
            fileExists: { _ in true },
            bundledExtensionExists: { true },
            systemWallpaperExtensionPointExists: { true }
        )

        let report = probe.report()

        XCTAssertFalse(report.isAvailable)
        XCTAssertFalse(report.osSupportsNativeWallpaper)
        XCTAssertTrue(report.failureReasons.contains("macOS 26 or later is required."))
    }

    func testReportsUnavailableWhenWallpaperExtensionKitIsMissing() {
        let probe = NativeWallpaperCapabilityProbe(
            osMajorVersion: { 26 },
            fileExists: { path in
                path != NativeWallpaperSystemPath.wallpaperExtensionKit
            },
            bundledExtensionExists: { true },
            systemWallpaperExtensionPointExists: { true }
        )

        let report = probe.report()

        XCTAssertFalse(report.isAvailable)
        XCTAssertFalse(report.hasWallpaperExtensionKit)
        XCTAssertTrue(report.failureReasons.contains("WallpaperExtensionKit.framework is missing."))
    }

    func testReportsAvailableWhenAllRequiredGatesExist() {
        let probe = NativeWallpaperCapabilityProbe(
            osMajorVersion: { 26 },
            fileExists: { _ in true },
            bundledExtensionExists: { true },
            systemWallpaperExtensionPointExists: { true }
        )

        let report = probe.report()

        XCTAssertTrue(report.isAvailable)
        XCTAssertTrue(report.failureReasons.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter NativeWallpaperCapabilityProbeTests
```

Expected:

```text
error: cannot find 'NativeWallpaperCapabilityProbe' in scope
```

- [ ] **Step 3: Add the backend models**

Create `Sources/MacWallApp/NativeWallpaper/NativeWallpaperBackend.swift`:

```swift
import Foundation

enum NativeWallpaperSystemPath {
    static let wallpaperExtensionKit = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework"
    static let wallpaperAgent = "/System/Library/CoreServices/WallpaperAgent.app"
    static let extensionKitExtensions = "/System/Library/ExtensionKit/Extensions"
}

enum WallpaperPlaybackBackend: Equatable {
    case windowServerWindow
    case nativeWallpaper
}

struct NativeWallpaperCapabilityReport: Equatable {
    let osSupportsNativeWallpaper: Bool
    let hasWallpaperExtensionKit: Bool
    let hasWallpaperAgent: Bool
    let hasSystemWallpaperExtensionPoint: Bool
    let hasBundledMacWallWallpaperExtension: Bool
    let failureReasons: [String]

    var isAvailable: Bool {
        osSupportsNativeWallpaper
            && hasWallpaperExtensionKit
            && hasWallpaperAgent
            && hasSystemWallpaperExtensionPoint
            && hasBundledMacWallWallpaperExtension
            && failureReasons.isEmpty
    }
}
```

- [ ] **Step 4: Add the capability probe**

Create `Sources/MacWallApp/NativeWallpaper/NativeWallpaperCapabilityProbe.swift`:

```swift
import Foundation

struct NativeWallpaperCapabilityProbe {
    private let osMajorVersion: () -> Int
    private let fileExists: (String) -> Bool
    private let bundledExtensionExists: () -> Bool
    private let systemWallpaperExtensionPointExists: () -> Bool

    init(
        osMajorVersion: @escaping () -> Int = {
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        },
        fileExists: @escaping (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        bundledExtensionExists: @escaping () -> Bool = {
            Bundle.main.builtInPlugInsURL?
                .appending(path: "MacWallNativeWallpaperExtension.appex")
                .path(percentEncoded: false)
                .isEmpty == false
        },
        systemWallpaperExtensionPointExists: @escaping () -> Bool = {
            NativeWallpaperCapabilityProbe.defaultSystemWallpaperExtensionPointExists()
        }
    ) {
        self.osMajorVersion = osMajorVersion
        self.fileExists = fileExists
        self.bundledExtensionExists = bundledExtensionExists
        self.systemWallpaperExtensionPointExists = systemWallpaperExtensionPointExists
    }

    func report() -> NativeWallpaperCapabilityReport {
        let osSupportsNativeWallpaper = osMajorVersion() >= 26
        let hasWallpaperExtensionKit = fileExists(NativeWallpaperSystemPath.wallpaperExtensionKit)
        let hasWallpaperAgent = fileExists(NativeWallpaperSystemPath.wallpaperAgent)
        let hasSystemWallpaperExtensionPoint = systemWallpaperExtensionPointExists()
        let hasBundledMacWallWallpaperExtension = bundledExtensionExists()

        var failureReasons: [String] = []
        if !osSupportsNativeWallpaper {
            failureReasons.append("macOS 26 or later is required.")
        }
        if !hasWallpaperExtensionKit {
            failureReasons.append("WallpaperExtensionKit.framework is missing.")
        }
        if !hasWallpaperAgent {
            failureReasons.append("WallpaperAgent.app is missing.")
        }
        if !hasSystemWallpaperExtensionPoint {
            failureReasons.append("com.apple.wallpaper extension point is missing.")
        }
        if !hasBundledMacWallWallpaperExtension {
            failureReasons.append("MacWallNativeWallpaperExtension.appex is not bundled.")
        }

        return NativeWallpaperCapabilityReport(
            osSupportsNativeWallpaper: osSupportsNativeWallpaper,
            hasWallpaperExtensionKit: hasWallpaperExtensionKit,
            hasWallpaperAgent: hasWallpaperAgent,
            hasSystemWallpaperExtensionPoint: hasSystemWallpaperExtensionPoint,
            hasBundledMacWallWallpaperExtension: hasBundledMacWallWallpaperExtension,
            failureReasons: failureReasons
        )
    }

    private static func defaultSystemWallpaperExtensionPointExists() -> Bool {
        let root = URL(filePath: NativeWallpaperSystemPath.extensionKitExtensions)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return children.contains { appex in
            let plist = appex.appending(path: "Contents").appending(path: "Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = object as? [String: Any],
                  let attributes = dictionary["EXAppExtensionAttributes"] as? [String: Any],
                  let identifier = attributes["EXExtensionPointIdentifier"] as? String else {
                return false
            }
            return identifier == "com.apple.wallpaper"
        }
    }
}
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
swift test --filter NativeWallpaperCapabilityProbeTests
```

Expected:

```text
Executed 3 tests, with 0 failures
```

- [ ] **Step 6: Commit Task 1**

Only if the user asked for commits:

```bash
git add Sources/MacWallApp/NativeWallpaper Tests/MacWallAppTests/NativeWallpaperCapabilityProbeTests.swift
git commit -m "spike: add native wallpaper capability probe"
```

## Task 2: Backend Selection Boundary

**Files:**

- Create: `Sources/MacWallApp/NativeWallpaper/NativeWallpaperModeController.swift`
- Test: `Tests/MacWallAppTests/NativeWallpaperModeControllerTests.swift`

- [ ] **Step 1: Write failing backend selection tests**

Create `Tests/MacWallAppTests/NativeWallpaperModeControllerTests.swift`:

```swift
import XCTest
@testable import MacWallApp

final class NativeWallpaperModeControllerTests: XCTestCase {
    func testUsesWindowBackendWhenUserSettingIsDisabled() {
        let controller = NativeWallpaperModeController(
            capabilityReport: availableReport,
            nativeModeEnabled: false
        )

        XCTAssertEqual(controller.selectedBackend, .windowServerWindow)
    }

    func testUsesWindowBackendWhenCapabilityIsUnavailable() {
        let controller = NativeWallpaperModeController(
            capabilityReport: unavailableReport,
            nativeModeEnabled: true
        )

        XCTAssertEqual(controller.selectedBackend, .windowServerWindow)
    }

    func testUsesNativeBackendWhenEnabledAndAvailable() {
        let controller = NativeWallpaperModeController(
            capabilityReport: availableReport,
            nativeModeEnabled: true
        )

        XCTAssertEqual(controller.selectedBackend, .nativeWallpaper)
    }

    private var availableReport: NativeWallpaperCapabilityReport {
        NativeWallpaperCapabilityReport(
            osSupportsNativeWallpaper: true,
            hasWallpaperExtensionKit: true,
            hasWallpaperAgent: true,
            hasSystemWallpaperExtensionPoint: true,
            hasBundledMacWallWallpaperExtension: true,
            failureReasons: []
        )
    }

    private var unavailableReport: NativeWallpaperCapabilityReport {
        NativeWallpaperCapabilityReport(
            osSupportsNativeWallpaper: true,
            hasWallpaperExtensionKit: false,
            hasWallpaperAgent: true,
            hasSystemWallpaperExtensionPoint: true,
            hasBundledMacWallWallpaperExtension: true,
            failureReasons: ["WallpaperExtensionKit.framework is missing."]
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter NativeWallpaperModeControllerTests
```

Expected:

```text
error: cannot find 'NativeWallpaperModeController' in scope
```

- [ ] **Step 3: Add the mode controller**

Create `Sources/MacWallApp/NativeWallpaper/NativeWallpaperModeController.swift`:

```swift
struct NativeWallpaperModeController {
    let capabilityReport: NativeWallpaperCapabilityReport
    let nativeModeEnabled: Bool

    var selectedBackend: WallpaperPlaybackBackend {
        guard nativeModeEnabled, capabilityReport.isAvailable else {
            return .windowServerWindow
        }
        return .nativeWallpaper
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter NativeWallpaperModeControllerTests
swift test --filter NativeWallpaperCapabilityProbeTests
```

Expected:

```text
Executed 3 tests, with 0 failures
Executed 3 tests, with 0 failures
```

- [ ] **Step 5: Commit Task 2**

Only if the user asked for commits:

```bash
git add Sources/MacWallApp/NativeWallpaper/NativeWallpaperModeController.swift Tests/MacWallAppTests/NativeWallpaperModeControllerTests.swift
git commit -m "spike: add native wallpaper backend selection"
```

## Task 3: Native Extension Packaging Gate

**Files:**

- Create: `MacWallNativeWallpaperSpike/README.md`
- Create or modify after project choice: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpike.xcodeproj`
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist`

- [x] **Step 1: Add spike README**

Create `MacWallNativeWallpaperSpike/README.md`:

```md
# MacWall Native Wallpaper Spike

This directory is a macOS 26-only private API spike.

Goals:

- Build a third-party ExtensionKit extension with `EXExtensionPointIdentifier = com.apple.wallpaper`.
- Verify whether `WallpaperAgent` discovers and loads the extension.
- Verify whether the extension can receive native wallpaper lifecycle requests.
- Verify whether generated frames can appear as the desktop wallpaper surface.

Non-goals:

- macOS 14/15 support.
- release packaging.
- App Store distribution.
- Dock/Finder injection.
- SIP disablement.
- system wallpaper database mutation.
```

- [x] **Step 2: Add extension Info.plist**

Create `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>MacWall Native Wallpaper</string>
    <key>CFBundleExecutable</key>
    <string>MacWallNativeWallpaperExtension</string>
    <key>CFBundleIdentifier</key>
    <string>com.mingyu1715.macwall.native-wallpaper-extension</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacWallNativeWallpaperExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>EXAppExtensionAttributes</key>
    <dict>
        <key>EXExtensionPointIdentifier</key>
        <string>com.apple.wallpaper</string>
    </dict>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
</dict>
</plist>
```

- [x] **Step 3: Create or import a minimal Xcode project**

Because the main repository is currently SwiftPM-only, this step requires one explicit packaging choice:

```text
Choice A: Add a checked-in Xcode project for MacWall app + native wallpaper extension.
Choice B: Add an isolated MacWallNativeWallpaperSpike Xcode project used only for private API research.
```

For this spike, choose B unless the user explicitly asks to migrate the whole app to Xcode project management.

Implemented choice on 2026-06-07:

```text
Choice B selected.
The spike uses a checked-in CMakeLists.txt to generate an isolated Xcode
project under /tmp for verification. This keeps the main SwiftPM app unchanged
and avoids hand-editing a generated pbxproj during the discovery spike.

The extension bundle id had to be changed to:
com.mingyu1715.macwall.native-wallpaper-spike.extension

Reason: Xcode embedded extension validation requires the extension bundle id
to be prefixed by the containing app bundle id:
com.mingyu1715.macwall.native-wallpaper-spike
```

- [x] **Step 4: Verify plist content without building**

Run:

```bash
plutil -p MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/Info.plist
```

Expected:

```text
"EXExtensionPointIdentifier" => "com.apple.wallpaper"
"LSMinimumSystemVersion" => "26.0"
```

## Task 4: Extension Lifecycle Diagnostics

**Files:**

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements`
- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpikeApp/MacWallNativeWallpaperSpikeApp.entitlements`

- [x] **Step 1: Add lifecycle logging extension skeleton**

Create `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift`:

```swift
import Foundation
import os

private let logger = Logger(
    subsystem: "com.mingyu1715.macwall.native-wallpaper-extension",
    category: "Lifecycle"
)

@main
struct MacWallNativeWallpaperExtension {
    static func main() {
        logger.info("MacWall native wallpaper extension process started")
        RunLoop.main.run()
    }
}
```

- [x] **Step 2: Build the spike extension only after project exists**

Run after Task 3 creates the Xcode project:

```bash
xcodebuild -project MacWallNativeWallpaperSpike/MacWallNativeWallpaperSpike.xcodeproj -scheme MacWallNativeWallpaperExtension -configuration Debug build
```

Expected:

```text
** BUILD SUCCEEDED **
```

Observed on 2026-06-07:

```text
xcodebuild extension target: ** BUILD SUCCEEDED **
xcodebuild containing app target: ** BUILD SUCCEEDED **
embedded appex path:
/tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperSpikeApp.app/Contents/Extensions/MacWallNativeWallpaperExtension.appex

Both host app and appex are ad-hoc signed with:
com.apple.security.app-sandbox = true
```

- [x] **Step 3: Check whether the extension is discoverable**

After installing or running the containing app bundle, run:

```bash
pluginkit -m -A -D -vv | rg 'MacWall|com.apple.wallpaper|native-wallpaper'
```

Expected if discoverable:

```text
com.mingyu1715.macwall.native-wallpaper-extension
com.apple.wallpaper
```

If no MacWall extension appears, classify failure as packaging/discovery failure and do not proceed to frame rendering.

Observed on 2026-06-07:

```text
pluginkit remains unavailable on this machine:
match: Connection invalid

Before entitlements were added, WallpaperAgent/ExtensionKit logs showed:
Extension is not entitled to run in the App Sandbox

This means WallpaperAgent/ExtensionKit did observe at least one MacWall
extension identity, but rejected the unsigned/no-entitlement build.

After adding App Sandbox entitlements and rebuilding, process inspection showed
the containing app running. Follow-up WallpaperAgent log confirmation was blocked
by the local escalation/usage limit, so extension load is not confirmed yet.
Do not proceed to Task 5 until this post-entitlement log/load gate is confirmed.
```

Observed on 2026-06-08:

```text
post-entitlement WallpaperAgent load: pass

Evidence:
- xcodebuild containing app + embedded appex: ** BUILD SUCCEEDED **
- codesign --verify --deep --strict: passed
- host app entitlement: com.apple.security.app-sandbox = true
- appex entitlement: com.apple.security.app-sandbox = true
- WallpaperAgent catalog noticed the extension set changed:
  Received an updated set of 12 Wallpaper extensions
  Wallpaper extension was added: <private>
- WallpaperAgent requested the MacWall extension:
  [com.mingyu1715.macwall.native-wallpaper-spike.extension] provideSettingsViewModels
  [com.mingyu1715.macwall.native-wallpaper-spike.extension] connect
- ExtensionKit launched the process for WallpaperAgent host pid 1609:
  Launching extension com.mingyu1715.macwall.native-wallpaper-spike.extension
  Created new process ExtensionProcess ... pid: 71486
- Process list showed:
  MacWallNativeWallpaperExtension.appex/.../MacWallNativeWallpaperExtension
  -LaunchArguments serviceName=com.mingyu1715.macwall.native-wallpaper-spike.extension
- Lifecycle logger fired:
  [com.mingyu1715.macwall.native-wallpaper-extension:Lifecycle]
  MacWall native wallpaper extension process started

Failure after load:
- WallpaperAgent later reported:
  provideSettingsViewModels: NSCocoaErrorDomain (4099)

Classification:
- discovery: pass
- entitlement: pass
- code signing: pass for local ad-hoc spike
- process launch: pass
- lifecycle logger: pass
- wallpaper request/handshake: failing as expected for the skeleton extension

Next step:
- Do not jump directly to AVSampleBufferDisplayLayer output.
- First implement or stub the private WallpaperExtensionKit request/handshake
  path enough for provideSettingsViewModels/connect to complete cleanly.
- After that, continue to generated frame output.
```

Observed on 2026-06-08 00:35 KST:

```text
private WallpaperExtensionKit request/handshake minimal stub: pass

Implemented:
- Replaced the skeleton RunLoop entry point with an ExtensionFoundation
  AppExtension entry point.
- Added AppExtensionConfiguration.accept(connection:) for WallpaperAgent.
- Added Swift @objc protocols for the private WallpaperExtensionKit XPC
  selectors observed from Phosphene and current WallpaperAgent logs.
- Added minimal reply stubs for lifecycle, settings, choice, download,
  migration, shuffle, debug, and notification selectors.
- provideSettingsViewModels replies with an empty WallpaperSettingsViewModelsXPC
  object created through a local keyed-archive shim.

Evidence:
- WallpaperAgent:
  [com.mingyu1715.macwall.native-wallpaper-spike.extension] connect BEGIN/END
  [com.mingyu1715.macwall.native-wallpaper-spike.extension]
  provideSettingsViewModels BEGIN/END
- MacWallNativeWallpaperExtension:
  MacWall native wallpaper extension process started
  WallpaperExtensionKit loaded
  Accepting WallpaperAgent XPC connection pid=1609
  WallpaperAgent XPC connection accepted
  provideSettingsViewModels stub
  Created empty WallpaperSettingsViewModelsXPC

Classification:
- discovery: pass
- entitlement: pass
- local ad-hoc code signing: pass
- process launch: pass
- connection accept/connect: pass
- provideSettingsViewModels reply: pass
- NSCocoaErrorDomain 4099: not reproduced after the stub
- extension process survival after handshake: pass

Do not start AVSampleBufferDisplayLayer yet.
Next gate:
- Observe the acquire request structure.
- Identify whether WallpaperAgent expects a WallpaperRemoteContextXPC,
  WallpaperSnapshotXPC, or another lifecycle object before native surface work.
- Only after the native surface / remote CAContext gate is understood should
  Task 5 generated frame output begin.
```

Observed on 2026-06-08 00:56 KST:

```text
acquire request observation gate: pass

Implemented:
- provideSettingsViewModels now returns one visible MacWall Native Spike item
  instead of an empty group.
- The extension creates a small local PNG thumbnail in its sandbox temp
  directory for the settings item.
- acquire/update/snapshot/selectedChoicesDidChange and related selectors log
  private XPC object type and Mirror structure.

Evidence:
- WallpaperAgent:
  makeWallpaper for '[extension] com.mingyu1715.macwall.native-wallpaper-spike.extension'
  Wallpaper Timeline: Acquire Wallpaper
- MacWallNativeWallpaperExtension:
  acquire stub
  acquire.id: type=WallpaperIDXPC
  acquire.request: type=WallpaperCreationRequestXPC

Observed request structure:
- id: WallpaperIDXPC
  - box: XPCBox<WallpaperID>
  - rawValue.id: UUID
- request: WallpaperCreationRequestXPC
  - rawValue.descriptor.files: descriptor file URLs from settings item
  - rawValue.descriptor.configuration: choice configuration bytes
  - rawValue.descriptor.optionValues: optional System Settings values
  - rawValue.cacheDirectory: WallpaperAgent extension cache directory
  - rawValue.destination.size: current display size
  - rawValue.destination.colorSpace: display color space
  - rawValue.destination.scaleFactor: display scale
  - rawValue.destination.directDisplayID: display id
  - rawValue.isPreview: true for preview, false for real desktop request
  - rawValue.presentationMode: default
  - rawValue.activityState: active
  - rawValue.systemAppearance: dark
  - rawValue.debugBackgrounds: false

Nil acquire reply result:
- WallpaperAgent reports WallpaperExtensionKit.WallpaperExtensionError (2)
- makeWallpaper fails when acquire replies nil

Phosphene comparison:
- acquire must return WallpaperRemoteContextXPC, not nil.
- The expected sequence is:
  1. Create CAContext.remoteContext(), or remoteContextWithOptions when display
     options are needed.
  2. Attach at least a root CALayer to the CAContext.
  3. Create WallpaperRemoteContextXPC with the CAContext contextId.
  4. Reply to acquire with that WallpaperRemoteContextXPC.
- Phosphene creates WallpaperRemoteContextXPC by allocating the private class
  and writing UInt32 contextId into the `box` ivar, with offset 8 as fallback.

Next gate:
- Do not start AVSampleBufferDisplayLayer yet.
- Implement a remote CAContext/root CALayer/WalpaperRemoteContextXPC reply probe.
- Success criterion: acquire no longer returns WallpaperExtensionError (2), and
  WallpaperAgent proceeds to update/snapshot or keeps the native wallpaper
  context alive.
```

Observed on 2026-06-08 01:14 KST:

```text
remote CAContext acquire reply gate: pass

Implemented:
- Added MacWallRemoteContextProbe for the acquire response path.
- Created CAContext.remoteContextWithOptions when directDisplayID is available,
  with CAContext.remoteContext as fallback.
- Parsed WallpaperCreationRequestXPC destination size, scale factor, display id,
  and preview flag by reflecting the private request object.
- Attached a root CALayer with solid probe colors to the remote CAContext.
- Read CAContext.contextId through ObjC runtime dispatch.
- Created WallpaperRemoteContextXPC by allocating the private class and writing
  the UInt32 context id into the `box` ivar, falling back to offset 8.
- Kept CAContext and root CALayer alive in MacWallRemoteWallpaperContextStore.
- Fixed Bool-like XPC reply signatures for isChoiceDownloaded and
  canSkipShuffledContent to use NSNumber, matching WallpaperAgent's wire
  signature and avoiding XPC connection invalidation.

Evidence:
- Build:
  xcodebuild -project /tmp/macwall-native-wallpaper-spike-xcode/MacWallNativeWallpaperSpike.xcodeproj
  -scheme MacWallNativeWallpaperSpikeApp -configuration Debug
  -derivedDataPath /tmp/macwall-native-wallpaper-spike-dd clean build
  -> ** BUILD SUCCEEDED **
- Signing:
  codesign --verify --deep --strict
  /tmp/macwall-native-wallpaper-spike-xcode/Debug/MacWallNativeWallpaperSpikeApp.app
  -> passed
- WallpaperAgent / extension logs after WallpaperAgent restart:
  acquire.id: type=WallpaperIDXPC
  acquire.request: type=WallpaperCreationRequestXPC
  remoteContext request size=(1710.0, 1107.0) scale=2.000000
  displayID=Optional(1) isPreview=Optional(false)
  CAContext.remoteContextWithOptions created displayID=1
  CAContext.contextId=405224122
  CAContext.layer attached
  WallpaperRemoteContextXPC created contextID=405224122 offset=8
  stored remote context ... contextID=405224122 count=1
  remoteContext acquire reply contextID=405224122
  [com.mingyu1715.macwall.native-wallpaper-spike.extension]
  Wallpaper Timeline: Acquire Wallpaper END
- Process state:
  MacWallNativeWallpaperExtension remained running after acquire.

Classification:
- CAContext.remoteContext creation: pass
- contextId access: pass
- WallpaperRemoteContextXPC creation: pass
- acquire XPC encode/decode: pass
- WallpaperAgent accepted non-nil acquire reply: pass
- previous isChoiceDownloaded reply block signature crash: fixed
- native desktop visual output: not proven from logs alone

Remaining issue:
- WallpaperAgent still calls snapshot/export after acquire.
- Current snapshot stub replies nil, so export snapshot reports
  WallpaperExtensionKit.WallpaperExtensionError (2).
- This is distinct from the previous acquire nil reply failure.

Next gate:
- Do not start AVSampleBufferDisplayLayer yet if snapshot/export keeps causing
  runtime churn.
- First identify the expected snapshot response type or confirm that the remote
  CAContext surface is visibly presented despite snapshot export failures.
- If native surface visibility is confirmed, proceed to generated frame bridge.
- If visibility is blocked by snapshot/export, implement the minimum snapshot
  response stub before Task 5.
```

## Task 5: Generated Frame Bridge

**Files:**

- Create: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`

- [ ] **Step 1: Add generated sample buffer bridge**

Create `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`:

```swift
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

final class NativeVideoFrameBridge {
    let displayLayer = AVSampleBufferDisplayLayer()

    func enqueueSolidFrame(width: Int = 1920, height: Int = 1080) throws {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NativeVideoFrameBridgeError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            memset(baseAddress, 0x44, bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else {
            throw NativeVideoFrameBridgeError.formatDescriptionCreationFailed
        }

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw NativeVideoFrameBridgeError.sampleBufferCreationFailed(sampleStatus)
        }

        displayLayer.enqueue(sampleBuffer)
    }
}

enum NativeVideoFrameBridgeError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionCreationFailed
    case sampleBufferCreationFailed(OSStatus)
}
```

- [ ] **Step 2: Attach display layer only after native wallpaper surface is identified**

Do not attach the display layer to a normal `NSWindow` for this spike. The point is to test `WallpaperAgent` native surface participation, not another AppKit window.

Expected diagnostic before moving on:

```text
WallpaperAgent loaded MacWall extension
MacWall extension received native wallpaper request
Native surface or remote CAContext object identified
```

## Task 6: Native Red-Pill QA

**Files:**

- Modify: `docs/development-log.md`

- [ ] **Step 1: Run single-display manual QA after generated frame is visible**

Manual steps:

```text
1. Enable MacWall Native Wallpaper spike.
2. Select the MacWall native wallpaper provider if System Settings requires manual selection.
3. Confirm generated frame is visible on Desktop.
4. Open a fullscreen app.
5. Swipe Fullscreen -> Desktop.
6. Record whether the previous macOS system wallpaper appears.
```

- [ ] **Step 2: Record the outcome**

Add a development-log entry using this shape:

```md
### HH:MM KST

- 실험: macOS 26 Native Wallpaper Mode generated-frame QA
- 결과:
  - extension discovery: pass/fail
  - WallpaperAgent load: pass/fail
  - native surface request: pass/fail
  - generated frame visible: pass/fail
  - Fullscreen -> Desktop 빨간약: removed/unchanged/changed
- 판단:
  - pass이면 AVSampleBuffer video frame push로 진행
  - fail이면 실패 gate 기준으로 다음 조사 범위 축소
```

- [ ] **Step 3: Stop if generated frame does not affect the transition**

If generated frame is visible as desktop wallpaper but Fullscreen -> Desktop still shows a different Dock/native Desktop Picture layer first, stop this native path and do not implement video output.

## Task 7: Video Frame Push

**Files:**

- Modify: `MacWallNativeWallpaperSpike/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift`

- [ ] **Step 1: Add AVAssetReader only after Task 6 passes**

Extend `NativeVideoFrameBridge` with AVAssetReader-based sample output. Use a local file path supplied by the spike app or hardcoded temporary test path during the spike.

Required acceptance:

```text
Generated frame output works first.
The same display layer receives video CMSampleBuffer values.
Frame timestamps advance.
The desktop wallpaper surface updates without an NSWindow.
```

- [ ] **Step 2: Repeat red-pill QA**

Manual steps:

```text
1. Play a local video through native wallpaper extension.
2. Confirm frame time advances in extension diagnostics.
3. Swipe Fullscreen -> Desktop.
4. Record whether the previous macOS system wallpaper appears.
```

## Task 8: Final Verification

**Files:**

- Modify: `docs/development-log.md`
- Modify: `docs/development-roadmap.md` if the spike proves viable
- Create: `docs/implemented/YYYY-MM-DD-macos-26-native-wallpaper-spike.md` only if the spike reaches generated-frame or video-frame success

- [ ] **Step 1: Run SwiftPM tests for unaffected app code**

Run:

```bash
swift test --filter NativeWallpaperCapabilityProbeTests
swift test --filter NativeWallpaperModeControllerTests
swift test
```

Expected:

```text
0 failures
```

- [ ] **Step 2: Run document hygiene check**

Run:

```bash
rg --files docs README.md README.ko.md CONTRIBUTING.md LICENSE
rg -n "SIP|Dock/Finder injection|시스템 DB" docs/superpowers/specs docs/development-roadmap.md docs/development-log.md
git diff --check
```

Expected:

```text
Only guardrail lines appear for SIP, Dock/Finder injection, and system DB mutation.
git diff --check exits 0.
```

- [ ] **Step 3: Report outcome**

Report one of:

```text
가능: native extension loaded, native surface visible, red-pill removed or materially reduced.
불확실: native extension loaded but surface/video/transition result incomplete.
불가능: third-party extension is not discovered/loaded, or private API requires Apple-only capability.
```

## Execution Notes

- Do not modify existing fallback PNG policy during this spike.
- Do not delete the existing `NSWindow` backend.
- Do not wire native mode as default.
- Do not start Web, Scene, or CAMetalLayer native paths until Video generated-frame and video-frame gates are clear.
- Do not run release packaging, DMG, notarization, or `dist` work.
