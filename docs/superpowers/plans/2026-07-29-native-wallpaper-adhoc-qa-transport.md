# macOS 26 Native Wallpaper AdHocQA Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple development signing identity와 provisioning profile이 없는 로컬 환경에서 production Native Wallpaper Host와 Extension의 기존 generation protocol을 검증할 수 있는 `AdHocQA` 전용 transport를 구현한다.

**Architecture:** `MacWallNativeRuntimeSupport`에 명시적인 `app-group` / `development-home` mode와 주입 가능한 root resolver를 둔다. `Debug`와 `Release`는 기존 App Group만 사용하고, 별도 `AdHocQA` configuration은 정확히 한 개의 home-relative QA 디렉터리를 Host와 sandboxed Extension이 공유한다. command/status/generation schema, WallpaperAgent handshake, renderer, playback lifecycle은 변경하지 않는다.

**Tech Stack:** Swift 6, Foundation, Darwin POSIX account lookup, XCTest, Xcode project build configurations, App Sandbox entitlements, Bash, `xcodebuild`, `codesign`, LaunchServices.

## Global Constraints

- Native Wallpaper 지원 범위는 macOS 26 이상, Apple Silicon, Video asset이다.
- `AdHocQA`에서만 `development-home` transport를 활성화한다.
- `Debug`와 `Release`는 `group.com.mingyu1715.macwall` App Group transport만 사용한다.
- App Group 접근 실패 후 development transport로 자동 fallback하지 않는다.
- QA runtime root는 `~/Library/Application Support/MacWall/NativeRuntimeAdHocQA`로 고정한다.
- QA Extension의 temporary exception은 위 디렉터리 하나의 read/write로 제한한다.
- QA Host와 Extension entitlements에는 App Group을 넣지 않는다.
- command/status/generation JSON schema와 atomic staging layout을 변경하지 않는다.
- WallpaperAgent handshake, Native renderer, playback timing, fallback 정책을 변경하지 않는다.
- snapshot/export, Native Web/Scene, video quality 최적화, Main App UI 변경을 포함하지 않는다.
- 앱, GUI, System Settings를 자동 실행하거나 조작하지 않는다.
- `Scripts/package-app.sh`, archive, DMG, notarization, `dist` 작업을 실행하지 않는다.
- 실제 Desktop 출력과 Fullscreen 전환은 구현 완료 후 별도 사용자 검증 gate로 남긴다.

---

## File Structure

새 파일:

- `Sources/MacWallNativeRuntimeSupport/NativeRuntimeTransport.swift`
  - transport mode parsing, POSIX account home lookup, App Group/development root resolution
- `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeTransportTests.swift`
  - mode parsing, fail-closed root selection, QA command/status round trip
- `MacWallHostApp/MacWallHostApp.AdHocQA.entitlements`
  - App Group과 Sandbox 권한이 없는 QA Host entitlements
- `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements`
  - Extension sandbox와 QA root temporary exception만 포함
- `MacWall.xcodeproj/xcshareddata/xcschemes/MacWallAdHocQA.xcscheme`
  - `AdHocQA` configuration만 사용하는 shared scheme
- `Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh`
  - plist, configuration, entitlement, source-boundary 정적 검사
- `Scripts/native-wallpaper-adhoc-qa.sh`
  - production Native QA의 reset/install/status/logs runner
- `Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh`
  - runner syntax, command surface, 금지 동작 source guard

수정 파일:

- `Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift`
  - transport 관련 constant와 fail-closed error cases
- `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift`
  - mode와 resolver를 받는 live store factory
- `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`
  - Host의 configured mode resolution과 diagnostic log
- `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift`
  - Extension의 configured mode resolution과 diagnostic log
- `MacWallHostApp/Info.plist`
  - `MacWallNativeRuntimeTransport` build setting bridge
- `MacWallNativeWallpaperExtension/Info.plist`
  - Host와 동일한 transport build setting bridge
- `MacWall.xcodeproj/project.pbxproj`
  - project/Host/Extension/Saver의 `AdHocQA` configuration과 entitlement wiring
- `docs/development-guide.md`
  - production `AdHocQA` 실행 및 사용자 검증 규칙
- `AGENTS.md`
  - agent가 production QA runner와 fail-closed 정책을 먼저 따르도록 보강
- `docs/development-roadmap.md`
  - P2.6 App Group QA 실패 경계와 AdHocQA 개발 gate 기록
- `docs/development-log.md`
  - 구현, 정적 검증, 남은 production signing gate 기록
- `docs/superpowers/specs/2026-07-29-native-wallpaper-adhoc-qa-transport-design.md`
  - 구현 및 정적 검증 상태 반영

---

### Task 1: Transport Mode 및 Root Resolver

**Files:**

- Create: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeTransport.swift`
- Create: `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeTransportTests.swift`
- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift:3-7,141-149`
- Modify: `Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift:3-20`

**Interfaces:**

- Produces: `NativeRuntimeTransportMode.init(configurationValue:) throws`
- Produces: `NativeRuntimeTransportMode.configured(in:) throws`
- Produces: `NativeRuntimeRootResolving.rootURL(for:) throws -> URL`
- Produces: `NativeRuntimeRootResolver.live`
- Produces: `NativeRuntimeStore.live(mode:rootResolver:) throws -> NativeRuntimeStore`
- Preserves: `NativeRuntimeStore.init(rootURL:)` for existing isolated tests

- [ ] **Step 1: Write failing transport tests**

Create `Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeTransportTests.swift` with these cases:

```swift
import Foundation
import XCTest
@testable import MacWallNativeRuntimeSupport

final class NativeRuntimeTransportTests: XCTestCase {
    func testParsesKnownTransportModes() throws {
        XCTAssertEqual(
            try NativeRuntimeTransportMode(configurationValue: "app-group"),
            .appGroup
        )
        XCTAssertEqual(
            try NativeRuntimeTransportMode(configurationValue: "development-home"),
            .developmentHome
        )
    }

    func testMissingTransportConfigurationFailsClosed() {
        XCTAssertThrowsError(
            try NativeRuntimeTransportMode(configurationValue: nil)
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .transportConfigurationMissing
            )
        }
    }

    func testUnknownTransportConfigurationFailsClosed() {
        XCTAssertThrowsError(
            try NativeRuntimeTransportMode(configurationValue: "automatic")
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .unsupportedTransportConfiguration("automatic")
            )
        }
    }

    func testAppGroupModeUsesOnlyAppGroupRoot() throws {
        let temporary = try makeTemporaryDirectory()
        let appGroup = temporary.appending(path: "Group")
        let accountHome = temporary.appending(path: "Home")
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { identifier in
                XCTAssertEqual(identifier, NativeRuntimeConstants.appGroupIdentifier)
                return appGroup
            },
            accountHomeDirectoryURL: { accountHome }
        )

        let store = try NativeRuntimeStore.live(
            mode: .appGroup,
            rootResolver: resolver
        )

        XCTAssertEqual(
            store.rootURL,
            appGroup.appending(path: "NativeRuntime").standardizedFileURL
        )
    }

    func testAppGroupFailureDoesNotUseDevelopmentHome() throws {
        let temporary = try makeTemporaryDirectory()
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: { temporary }
        )

        XCTAssertThrowsError(
            try NativeRuntimeStore.live(
                mode: .appGroup,
                rootResolver: resolver
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .appGroupUnavailable
            )
        }
    }

    func testDevelopmentHomeModeUsesExactQARootAndRoundTripsState() throws {
        let home = try makeTemporaryDirectory()
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: { home }
        )
        let store = try NativeRuntimeStore.live(
            mode: .developmentHome,
            rootResolver: resolver
        )
        let command = NativeRuntimeCommand.stop(
            generation: UUID(),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let status = NativeRuntimeStatus(
            requestedGeneration: command.generation,
            activeGeneration: nil,
            state: .stopped,
            activeDesktopContextCount: 1,
            extensionInstanceID: UUID(),
            processIdentifier: 42,
            heartbeatAt: Date(timeIntervalSince1970: 11),
            failure: nil
        )

        XCTAssertEqual(
            store.rootURL,
            home
                .appending(path: "Library")
                .appending(path: "Application Support")
                .appending(path: "MacWall")
                .appending(path: "NativeRuntimeAdHocQA")
                .standardizedFileURL
        )
        try store.writeCommand(command)
        try store.writeStatus(status)
        XCTAssertEqual(try store.readCommand(), command)
        XCTAssertEqual(try store.readStatus(), status)
    }

    func testDevelopmentHomeFailsWhenAccountHomeIsUnavailable() {
        let resolver = NativeRuntimeRootResolver(
            appGroupContainerURL: { _ in nil },
            accountHomeDirectoryURL: {
                throw NativeRuntimeStoreError.accountHomeUnavailable
            }
        )

        XCTAssertThrowsError(
            try NativeRuntimeStore.live(
                mode: .developmentHome,
                rootResolver: resolver
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeRuntimeStoreError,
                .accountHomeUnavailable
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MacWallNativeRuntimeTransportTests")
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
}
```

- [ ] **Step 2: Run the focused test and verify the new API is absent**

Run:

```bash
swift test --filter NativeRuntimeTransportTests
```

Expected: compile failure naming missing `NativeRuntimeTransportMode` and `NativeRuntimeRootResolver`.

- [ ] **Step 3: Add constants and explicit errors**

Add to `NativeRuntimeConstants`:

```swift
public static let transportInfoDictionaryKey = "MacWallNativeRuntimeTransport"
public static let developmentRuntimeDirectoryComponents = [
    "Library",
    "Application Support",
    "MacWall",
    "NativeRuntimeAdHocQA"
]
```

Extend `NativeRuntimeStoreError`:

```swift
case transportConfigurationMissing
case unsupportedTransportConfiguration(String)
case accountHomeUnavailable
```

Keep the existing `appGroupUnavailable` case as the exact App Group failure.

- [ ] **Step 4: Implement mode parsing and root resolution**

Create `NativeRuntimeTransport.swift` with these concrete types:

```swift
import Darwin
import Foundation

public enum NativeRuntimeTransportMode: String, Sendable {
    case appGroup = "app-group"
    case developmentHome = "development-home"

    public init(configurationValue: String?) throws {
        guard let configurationValue, !configurationValue.isEmpty else {
            throw NativeRuntimeStoreError.transportConfigurationMissing
        }
        guard let mode = Self(rawValue: configurationValue) else {
            throw NativeRuntimeStoreError.unsupportedTransportConfiguration(
                configurationValue
            )
        }
        self = mode
    }

    public static func configured(in bundle: Bundle = .main) throws -> Self {
        try Self(
            configurationValue: bundle.object(
                forInfoDictionaryKey: NativeRuntimeConstants.transportInfoDictionaryKey
            ) as? String
        )
    }
}

public protocol NativeRuntimeRootResolving: Sendable {
    func rootURL(for mode: NativeRuntimeTransportMode) throws -> URL
}

public struct NativeRuntimeRootResolver: NativeRuntimeRootResolving {
    private let appGroupContainerURL:
        @Sendable (String) -> URL?
    private let accountHomeDirectoryURL:
        @Sendable () throws -> URL

    public init(
        appGroupContainerURL: @escaping @Sendable (String) -> URL?,
        accountHomeDirectoryURL: @escaping @Sendable () throws -> URL
    ) {
        self.appGroupContainerURL = appGroupContainerURL
        self.accountHomeDirectoryURL = accountHomeDirectoryURL
    }

    public static var live: Self {
        Self(
            appGroupContainerURL: { identifier in
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: identifier
                )
            },
            accountHomeDirectoryURL: Self.currentAccountHomeDirectoryURL
        )
    }

    public func rootURL(for mode: NativeRuntimeTransportMode) throws -> URL {
        switch mode {
        case .appGroup:
            guard let container = appGroupContainerURL(
                NativeRuntimeConstants.appGroupIdentifier
            ) else {
                throw NativeRuntimeStoreError.appGroupUnavailable
            }
            return container.appending(path: "NativeRuntime")
        case .developmentHome:
            return try NativeRuntimeConstants
                .developmentRuntimeDirectoryComponents
                .reduce(accountHomeDirectoryURL()) { url, component in
                    url.appending(path: component)
                }
        }
    }

    private static func currentAccountHomeDirectoryURL() throws -> URL {
        let queriedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        let capacity = queriedSize > 0 ? Int(queriedSize) : 16_384
        var buffer = [CChar](repeating: 0, count: capacity)

        return try buffer.withUnsafeMutableBufferPointer { pointer in
            var entry = passwd()
            var result: UnsafeMutablePointer<passwd>?
            let status = getpwuid_r(
                getuid(),
                &entry,
                pointer.baseAddress,
                pointer.count,
                &result
            )
            guard status == 0,
                  result != nil,
                  let home = entry.pw_dir else {
                throw NativeRuntimeStoreError.accountHomeUnavailable
            }
            return URL(
                filePath: String(cString: home),
                directoryHint: .isDirectory
            )
        }
    }
}
```

- [ ] **Step 5: Route live store creation through the explicit mode**

Replace the current App Group-only `live` implementation in `NativeRuntimeStore.swift`:

```swift
public static func live() throws -> Self {
    let mode = try NativeRuntimeTransportMode.configured()
    return try live(mode: mode)
}

public static func live(
    mode: NativeRuntimeTransportMode,
    rootResolver: any NativeRuntimeRootResolving = NativeRuntimeRootResolver.live
) throws -> Self {
    Self(rootURL: try rootResolver.rootURL(for: mode))
}
```

There must be no `catch` that retries `.developmentHome`.

- [ ] **Step 6: Run focused support tests**

Run:

```bash
swift test --filter NativeRuntimeTransportTests
swift test --filter NativeRuntimeStoreTests
```

Expected: both test classes pass.

- [ ] **Step 7: Commit the shared transport boundary**

```bash
git add \
  Sources/MacWallNativeRuntimeSupport/NativeRuntimeTransport.swift \
  Sources/MacWallNativeRuntimeSupport/NativeRuntimeModels.swift \
  Sources/MacWallNativeRuntimeSupport/NativeRuntimeStore.swift \
  Tests/MacWallNativeRuntimeSupportTests/NativeRuntimeTransportTests.swift
git commit -m "feat(native): resolve AdHocQA runtime transport"
```

---

### Task 2: Host 및 Extension Runtime Bootstrap

**Files:**

- Create: `Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh`
- Modify: `MacWallHostApp/Info.plist:23-31`
- Modify: `MacWallNativeWallpaperExtension/Info.plist:23-30`
- Modify: `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift:1-4,72-96`
- Modify: `MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift:13-55,152-163`

**Interfaces:**

- Consumes: `NativeRuntimeTransportMode.configured(in:)`
- Consumes: `NativeRuntimeStore.live(mode:rootResolver:)`
- Produces diagnostic log keys: `transportMode` and `root`
- Preserves: injected `NativeWallpaperBackend(store:...)` and `NativeWallpaperSessionController(store:...)`

- [ ] **Step 1: Add failing plist and source-boundary guards**

Create the initial `native_wallpaper_adhoc_qa_project_tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PLIST="$ROOT/MacWallHostApp/Info.plist"
EXTENSION_PLIST="$ROOT/MacWallNativeWallpaperExtension/Info.plist"

EXPECTED="\$(MACWALL_NATIVE_RUNTIME_TRANSPORT)"
test "$(plutil -extract MacWallNativeRuntimeTransport raw "$HOST_PLIST")" \
  = "$EXPECTED"
test "$(plutil -extract MacWallNativeRuntimeTransport raw "$EXTENSION_PLIST")" \
  = "$EXPECTED"

grep -q 'NativeRuntimeTransportMode.configured' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
grep -q 'transportMode=' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
grep -q 'NativeRuntimeTransportMode.configured' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'transportMode=' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
```

The escaped dollar sign keeps the literal plist value
`$(MACWALL_NATIVE_RUNTIME_TRANSPORT)` intact.

- [ ] **Step 2: Run the guard and verify it fails**

Run:

```bash
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
```

Expected: syntax passes; execution fails because the plist keys and source bootstrap are absent.

- [ ] **Step 3: Bridge the Xcode setting through both Info.plist files**

Add this exact key/value to both Host and Extension plists:

```xml
<key>MacWallNativeRuntimeTransport</key>
<string>$(MACWALL_NATIVE_RUNTIME_TRANSPORT)</string>
```

- [ ] **Step 4: Add Host transport diagnostics without changing injected tests**

Import `os` and add a static logger to `NativeWallpaperBackend`:

```swift
private static let logger = Logger(
    subsystem: "io.github.mingyu1715.MacWall",
    category: "NativeRuntime"
)
```

Replace only the convenience initializer:

```swift
convenience init() throws {
    let mode = try NativeRuntimeTransportMode.configured()
    let store = try NativeRuntimeStore.live(mode: mode)
    Self.logger.info(
        "nativeRuntime transportMode=\(mode.rawValue, privacy: .public) root=\(store.rootURL.path, privacy: .public)"
    )
    self.init(store: store)
}
```

Do not change `play`, `stop`, generation staging, ACK wait, or fallback ownership.

- [ ] **Step 5: Add Extension bootstrap diagnostics and generic store failure**

Add a private factory to `NativeWallpaperSessionController`:

```swift
private static func makeLiveStore() -> NativeRuntimeStore? {
    do {
        let mode = try NativeRuntimeTransportMode.configured()
        let store = try NativeRuntimeStore.live(mode: mode)
        macWallNativeWallpaperLogger.info(
            "nativeRuntime transportMode=\(mode.rawValue, privacy: .public) root=\(store.rootURL.path, privacy: .public)"
        )
        return store
    } catch {
        macWallNativeWallpaperLogger.error(
            "nativeRuntime store unavailable error=\(String(describing: error), privacy: .public)"
        )
        return nil
    }
}
```

Change the default initializer argument:

```swift
init(
    store: NativeRuntimeStore? =
        NativeWallpaperSessionController.makeLiveStore()
) {
```

Change the nil-store failure from the App Group-specific code/message:

```swift
code: "runtime-store-unavailable",
message: "Native runtime store is unavailable."
```

The injected `store:` path remains unchanged for isolated session tests and future probes.

- [ ] **Step 6: Run focused and source-boundary tests**

Run:

```bash
swift test --filter NativeWallpaperBackendTests
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
```

Expected: focused Swift tests pass; source guard passes.

- [ ] **Step 7: Commit runtime bootstrap wiring**

```bash
git add \
  MacWallHostApp/Info.plist \
  MacWallNativeWallpaperExtension/Info.plist \
  Sources/MacWallApp/Playback/NativeWallpaperBackend.swift \
  MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift \
  Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
git commit -m "feat(native): wire configured runtime transport"
```

---

### Task 3: AdHocQA Xcode Configuration 및 Entitlement 격리

**Files:**

- Create: `MacWallHostApp/MacWallHostApp.AdHocQA.entitlements`
- Create: `MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements`
- Create: `MacWall.xcodeproj/xcshareddata/xcschemes/MacWallAdHocQA.xcscheme`
- Modify: `MacWall.xcodeproj/project.pbxproj:80-185,406-582`
- Modify: `Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh`

**Interfaces:**

- Produces configuration: `AdHocQA`
- Produces scheme: `MacWallAdHocQA`
- Produces setting: `MACWALL_NATIVE_RUNTIME_TRANSPORT=development-home`
- Preserves Debug/Release setting: `MACWALL_NATIVE_RUNTIME_TRANSPORT=app-group`
- Produces Extension QA entitlement for exactly `/Library/Application Support/MacWall/NativeRuntimeAdHocQA/`

- [ ] **Step 1: Expand the project guard before adding configuration**

Append checks for the two QA entitlement files and project/scheme:

```bash
PROJECT="$ROOT/MacWall.xcodeproj/project.pbxproj"
SCHEME="$ROOT/MacWall.xcodeproj/xcshareddata/xcschemes/MacWallAdHocQA.xcscheme"
HOST_QA_ENTITLEMENTS="$ROOT/MacWallHostApp/MacWallHostApp.AdHocQA.entitlements"
EXTENSION_QA_ENTITLEMENTS="$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements"

test -f "$SCHEME"
test -f "$HOST_QA_ENTITLEMENTS"
test -f "$EXTENSION_QA_ENTITLEMENTS"
plutil -lint "$HOST_QA_ENTITLEMENTS"
plutil -lint "$EXTENSION_QA_ENTITLEMENTS"

if /usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups' \
  "$HOST_QA_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "AdHocQA Host must not contain App Group entitlement." >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups' \
  "$EXTENSION_QA_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "AdHocQA Extension must not contain App Group entitlement." >&2
  exit 1
fi

test "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.app-sandbox' \
  "$EXTENSION_QA_ENTITLEMENTS")" = "true"
test "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
  "$EXTENSION_QA_ENTITLEMENTS")" \
  = "/Library/Application Support/MacWall/NativeRuntimeAdHocQA/"

if grep -q \
  'com.apple.security.temporary-exception.files.home-relative-path.read-write' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"; then
  echo "Debug/Release Extension entitlements must not contain QA exception." >&2
  exit 1
fi

grep -q 'name = AdHocQA' "$PROJECT"
grep -q 'MACWALL_NATIVE_RUNTIME_TRANSPORT = app-group' "$PROJECT"
grep -q 'MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home' "$PROJECT"
grep -q 'MacWallHostApp.AdHocQA.entitlements' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.AdHocQA.entitlements' "$PROJECT"
grep -q 'buildConfiguration = "AdHocQA"' "$SCHEME"
```

- [ ] **Step 2: Run the expanded guard and verify missing QA files**

Run:

```bash
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
```

Expected: failure at the first missing QA scheme or entitlement.

- [ ] **Step 3: Create exact QA entitlement files**

Create `MacWallHostApp.AdHocQA.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

Create `MacWallNativeWallpaperExtension.AdHocQA.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
    <array>
        <string>/Library/Application Support/MacWall/NativeRuntimeAdHocQA/</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Add deterministic project file references and configurations**

Use unused project IDs:

```text
A2000000000000000000001F  Host AdHocQA entitlements
A20000000000000000000020  Extension AdHocQA entitlements
A90000000000000000000009  Project AdHocQA
A9000000000000000000000A  Host AdHocQA
A9000000000000000000000B  Extension AdHocQA
A9000000000000000000000C  Saver AdHocQA
```

Add file references to the existing Host and Extension groups. Add the four `XCBuildConfiguration` entries and include them in all four `XCConfigurationList` arrays.

Project `Debug` and `Release` gain:

```text
MACWALL_NATIVE_RUNTIME_TRANSPORT = app-group;
```

Project `AdHocQA` copies Debug settings and uses:

```text
MACOSX_DEPLOYMENT_TARGET = 14.0;
MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home;
SDKROOT = macosx;
SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG ADHOC_QA";
SWIFT_VERSION = 6.0;
```

Host `AdHocQA` copies Host Debug settings except:

```text
CODE_SIGN_ENTITLEMENTS = MacWallHostApp/MacWallHostApp.AdHocQA.entitlements;
CODE_SIGN_IDENTITY = "-";
CODE_SIGN_STYLE = Manual;
```

Extension `AdHocQA` copies Extension Debug settings except:

```text
CODE_SIGN_ENTITLEMENTS = MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements;
CODE_SIGN_IDENTITY = "-";
CODE_SIGN_STYLE = Manual;
```

Saver `AdHocQA` copies Saver Debug settings and uses:

```text
CODE_SIGN_IDENTITY = "-";
CODE_SIGN_STYLE = Manual;
```

Do not alter bundle identifiers, deployment targets, architecture, embed destination, or Debug/Release entitlement paths.

- [ ] **Step 5: Add the shared AdHocQA scheme**

Create `MacWallAdHocQA.xcscheme` with Host target identifier `A50000000000000000000001` and these fixed action configurations:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting="YES"
            buildForRunning="YES"
            buildForProfiling="YES"
            buildForArchiving="NO"
            buildForAnalyzing="YES">
            <BuildableReference
               BuildableIdentifier="primary"
               BlueprintIdentifier="A50000000000000000000001"
               BuildableName="MacWall.app"
               BlueprintName="MacWallHostApp"
               ReferencedContainer="container:MacWall.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration="AdHocQA"
      selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv="YES">
      <Testables/>
   </TestAction>
   <LaunchAction
      buildConfiguration="AdHocQA"
      selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle="0"
      useCustomWorkingDirectory="NO"
      ignoresPersistentStateOnLaunch="NO"
      debugDocumentVersioning="YES"
      debugServiceExtension="internal"
      allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="A50000000000000000000001"
            BuildableName="MacWall.app"
            BlueprintName="MacWallHostApp"
            ReferencedContainer="container:MacWall.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration="AdHocQA"
      shouldUseLaunchSchemeArgsEnv="YES"
      savedToolIdentifier=""
      useCustomWorkingDirectory="NO"
      debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="A50000000000000000000001"
            BuildableName="MacWall.app"
            BlueprintName="MacWallHostApp"
            ReferencedContainer="container:MacWall.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="AdHocQA"/>
   <ArchiveAction
      buildConfiguration="AdHocQA"
      revealArchiveInOrganizer="NO"/>
</Scheme>
```

The runner and verification commands must never invoke `archive`.

- [ ] **Step 6: Validate structure and configuration exposure**

Run:

```bash
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
xcodebuild -project MacWall.xcodeproj -list
xcodebuild -project MacWall.xcodeproj \
  -target MacWallHostApp -configuration AdHocQA -showBuildSettings
xcodebuild -project MacWall.xcodeproj \
  -target MacWallNativeWallpaperExtension \
  -configuration AdHocQA -showBuildSettings
```

Expected:

- `MacWallAdHocQA` appears in the scheme list.
- Host and Extension show `MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home`.
- Host and Extension use their `.AdHocQA.entitlements` paths.
- Debug/Release entitlement files remain unchanged.

- [ ] **Step 7: Commit Xcode QA isolation**

```bash
git add \
  MacWallHostApp/MacWallHostApp.AdHocQA.entitlements \
  MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements \
  MacWall.xcodeproj/project.pbxproj \
  MacWall.xcodeproj/xcshareddata/xcschemes/MacWallAdHocQA.xcscheme \
  Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
git commit -m "build(native): isolate AdHocQA configuration"
```

---

### Task 4: Production Native AdHocQA Runner

**Files:**

- Create: `Scripts/native-wallpaper-adhoc-qa.sh`
- Create: `Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh`
- Modify: `docs/development-guide.md:123-173`
- Modify: `AGENTS.md:65-70`

**Interfaces:**

- Produces command: `./Scripts/native-wallpaper-adhoc-qa.sh reset`
- Produces command: `./Scripts/native-wallpaper-adhoc-qa.sh install`
- Produces command: `./Scripts/native-wallpaper-adhoc-qa.sh status`
- Produces command: `./Scripts/native-wallpaper-adhoc-qa.sh logs [duration]`
- Preserves: `MacWallNativeWallpaperSpike/dev.sh` for spike-only verification

- [ ] **Step 1: Write runner source guards**

Create `native_wallpaper_adhoc_qa_runner_tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/Scripts/native-wallpaper-adhoc-qa.sh"

test -x "$RUNNER"
bash -n "$RUNNER"
"$RUNNER" help | grep -q 'reset'
"$RUNNER" help | grep -q 'install'
"$RUNNER" help | grep -q 'status'
"$RUNNER" help | grep -q 'logs'

grep -q 'MacWallAdHocQA' "$RUNNER"
grep -q 'AdHocQA' "$RUNNER"
grep -q 'NativeRuntimeAdHocQA' "$RUNNER"
grep -q 'codesign --verify --deep --strict' "$RUNNER"
grep -q 'lsregister' "$RUNNER"
grep -q 'WallpaperAgent' "$RUNNER"
grep -q 'io.github.mingyu1715.MacWall.NativeWallpaper' "$RUNNER"

if grep -E -q \
  'package-app\.sh|notarytool|create-dmg|xcodebuild .*archive|/dist|open ' \
  "$RUNNER"; then
  echo "AdHocQA runner contains a forbidden release or GUI operation." >&2
  exit 1
fi
```

- [ ] **Step 2: Run the guard and verify the runner is missing**

Run:

```bash
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
```

Expected: syntax passes; execution fails because the runner does not exist or is not executable.

- [ ] **Step 3: Implement fixed paths and safe command dispatch**

Create executable `Scripts/native-wallpaper-adhoc-qa.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="/tmp/macwall-native-adhoc-qa-dd"
APP="$DERIVED_DATA/Build/Products/AdHocQA/MacWall.app"
EXTENSION="$APP/Contents/Extensions/MacWallNativeWallpaperExtension.appex"
QA_ROOT="$HOME/Library/Application Support/MacWall/NativeRuntimeAdHocQA"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION_EXECUTABLE="MacWallNativeWallpaperExtension"
EXTENSION_BUNDLE_ID="io.github.mingyu1715.MacWall.NativeWallpaper"

usage() {
  cat <<'EOF'
Usage: native-wallpaper-adhoc-qa.sh <command>
  reset             Stop stale production QA extension, unregister app, clear QA runtime
  install           Build/sign/verify/register AdHocQA app without opening GUI
  status            Show matching processes and latest QA command/status
  logs [duration]   Show WallpaperAgent and production extension logs (default: 3m)
  help              Show this message
EOF
}

case "${1:-help}" in
  reset) reset_qa ;;
  install) install_qa ;;
  status) status_qa ;;
  logs) logs_qa "${2:-3m}" ;;
  help|-h|--help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
```

Define functions above the `case` statement. Do not call `open`, AppleScript, or System Settings URLs.

- [ ] **Step 4: Implement process filtering and reset**

Only terminate an Extension process whose command path belongs to the stable QA app:

```bash
matching_extension_pids() {
  while read -r pid; do
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command" in
      *"$APP/Contents/Extensions/"*) printf '%s\n' "$pid" ;;
    esac
  done < <(pgrep -x "$EXTENSION_EXECUTABLE" 2>/dev/null || true)
}

reset_qa() {
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid"
  done < <(matching_extension_pids)

  if [[ -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  fi

  expected="$HOME/Library/Application Support/MacWall/NativeRuntimeAdHocQA"
  [[ "$QA_ROOT" == "$expected" ]] || {
    echo "Refusing to clear unexpected QA root: $QA_ROOT" >&2
    exit 1
  }
  rm -rf "$QA_ROOT"
}
```

This must not kill `WallpaperAgent` or the Spike Extension from a different app path.

- [ ] **Step 5: Implement install, signature verification, status, and logs**

`install_qa`:

```bash
install_qa() {
  if [[ -n "$(matching_extension_pids)" ]]; then
    echo "Stale production QA extension is running; run reset first." >&2
    exit 1
  fi

  xcodebuild \
    -project "$ROOT/MacWall.xcodeproj" \
    -scheme MacWallAdHocQA \
    -configuration AdHocQA \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    build

  test -d "$APP"
  test -d "$EXTENSION"
  codesign --verify --deep --strict "$APP"
  "$LSREGISTER" -f "$APP"
  printf 'Installed AdHocQA app: %s\n' "$APP"
  printf 'Next: select MacWall in System Settings manually.\n'
}
```

`status_qa`:

```bash
status_qa() {
  printf '%s\n' "WallpaperAgent:"
  pgrep -fl WallpaperAgent || true
  printf '%s\n' "Production AdHocQA extension:"
  matching_extension_pids | while read -r pid; do
    ps -p "$pid" -o pid=,command=
  done
  printf 'transportMode=development-home root=%s\n' "$QA_ROOT"
  for name in command status; do
    file="$QA_ROOT/$name.json"
    if [[ -f "$file" ]]; then
      printf '%s.json:\n' "$name"
      plutil -p "$file"
    fi
  done
}
```

`logs_qa`:

```bash
logs_qa() {
  local duration="$1"
  /usr/bin/log show \
    --last "$duration" \
    --style compact \
    --predicate \
    'process == "WallpaperAgent" OR process == "MacWallNativeWallpaperExtension" OR subsystem == "io.github.mingyu1715.MacWall" OR subsystem == "com.mingyu1715.macwall.native-wallpaper-extension"'
}
```

After creating the file:

```bash
chmod +x Scripts/native-wallpaper-adhoc-qa.sh
chmod +x Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
```

- [ ] **Step 6: Document the exact non-GUI protocol**

Add a `Production Native AdHocQA 실행 규칙` subsection to `docs/development-guide.md`:

```text
1. ./Scripts/native-wallpaper-adhoc-qa.sh reset
2. ./Scripts/native-wallpaper-adhoc-qa.sh install
3. 사용자가 System Settings에서 MacWall 선택
4. ./Scripts/native-wallpaper-adhoc-qa.sh status
5. ./Scripts/native-wallpaper-adhoc-qa.sh logs 3m
6. 사용자가 Desktop 출력과 Fullscreen 전환 확인
```

State explicitly:

- `AdHocQA`는 proper App Group signing을 대체하지 않는다.
- runner는 app/System Settings를 열지 않는다.
- `Debug`/`Release`는 development-home으로 fallback하지 않는다.
- 재검증은 항상 reset 후 install한다.

Add matching concise bullets under `AGENTS.md`의 Native Wallpaper section.

- [ ] **Step 7: Run runner static tests**

Run:

```bash
bash -n Scripts/native-wallpaper-adhoc-qa.sh
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
```

Expected: all commands pass without building, registering, opening, or killing any process.

- [ ] **Step 8: Commit the QA runner and rules**

```bash
git add \
  Scripts/native-wallpaper-adhoc-qa.sh \
  Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh \
  docs/development-guide.md \
  AGENTS.md
git commit -m "chore(native): add AdHocQA development runner"
```

---

### Task 5: Static Integration Verification 및 Documentation

**Files:**

- Modify: `docs/development-roadmap.md:197-250,567-575`
- Modify: `docs/development-log.md`
- Modify: `docs/superpowers/specs/2026-07-29-native-wallpaper-adhoc-qa-transport-design.md:1-5`

**Interfaces:**

- Consumes: all Task 1-4 tests and runner commands
- Produces: implementation status with production signing still pending
- Does not produce: a completed P2.6 implementation record

- [ ] **Step 1: Run focused Swift tests**

Run:

```bash
swift test --filter NativeRuntimeTransportTests
swift test --filter NativeRuntimeStoreTests
swift test --filter NativeWallpaperBackendTests
```

Expected: all focused test classes pass.

- [ ] **Step 2: Run project and runner guards**

Run:

```bash
bash -n Tests/ProjectStructure/native_wallpaper_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_project_tests.sh
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_project_tests.sh
bash -n Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
bash Tests/ProjectStructure/native_wallpaper_adhoc_qa_runner_tests.sh
```

Expected: all syntax and structure guards pass.

- [ ] **Step 3: Verify AdHocQA build settings without launching**

Run:

```bash
xcodebuild -project MacWall.xcodeproj -list
xcodebuild -project MacWall.xcodeproj \
  -target MacWallHostApp -configuration AdHocQA -showBuildSettings
xcodebuild -project MacWall.xcodeproj \
  -target MacWallNativeWallpaperExtension \
  -configuration AdHocQA -showBuildSettings
```

Inspect exact values:

```text
MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home
Host CODE_SIGN_ENTITLEMENTS = MacWallHostApp/MacWallHostApp.AdHocQA.entitlements
Extension CODE_SIGN_ENTITLEMENTS = MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements
```

- [ ] **Step 4: Build and inspect the ad-hoc artifact without registration**

Run:

```bash
xcodebuild \
  -project MacWall.xcodeproj \
  -scheme MacWallAdHocQA \
  -configuration AdHocQA \
  -derivedDataPath /tmp/macwall-native-adhoc-qa-dd \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build
```

Then:

```bash
APP=/tmp/macwall-native-adhoc-qa-dd/Build/Products/AdHocQA/MacWall.app
EXTENSION="$APP/Contents/Extensions/MacWallNativeWallpaperExtension.appex"
test -d "$APP"
test -d "$EXTENSION"
codesign --verify --deep --strict "$APP"
plutil -extract MacWallNativeRuntimeTransport raw "$APP/Contents/Info.plist"
plutil -extract MacWallNativeRuntimeTransport raw "$EXTENSION/Contents/Info.plist"
codesign -d --entitlements :- "$EXTENSION"
```

Expected:

- both built Info.plist values are `development-home`
- Extension has `com.apple.security.app-sandbox = true`
- Extension has the exact QA temporary exception
- Host and Extension do not have `com.apple.security.application-groups`
- no app or GUI is launched
- LaunchServices registration is not performed in this step

- [ ] **Step 5: Run final repository checks**

Run:

```bash
git diff --check
git status --short
```

Confirm `Scripts/package-app.sh`, `dist`, snapshot/export, Native renderer, Legacy fallback files are unchanged unless already listed by this plan.

- [ ] **Step 6: Update active documentation**

In the design document, change the state to:

```text
상태: 구현 및 정적 검증 완료 / AdHocQA runtime 사용자 검증 대기
```

Update P2.6 in `docs/development-roadmap.md` with:

- production WallpaperAgent discovery/handshake passed
- ad-hoc App Group write failed with `NSCocoaErrorDomain 513`
- `AdHocQA` development-home transport implementation and static validation status
- proper Apple signing/provisioning remains the production gate
- P2.6 complete record/archive still waits for signed App Group runtime QA

Prepend an Asia/Seoul timestamped entry to `docs/development-log.md` recording exact test counts and command outcomes. Do not mark App Group production QA as passed.

`README.ko.md` and `README.md` do not change because this is a developer-only build configuration with no Debug/Release user behavior change.

- [ ] **Step 7: Commit final verification records**

```bash
git add \
  docs/development-roadmap.md \
  docs/development-log.md \
  docs/superpowers/specs/2026-07-29-native-wallpaper-adhoc-qa-transport-design.md
git commit -m "docs(native): record AdHocQA transport verification"
```

- [ ] **Step 8: Verify clean implementation state**

Run:

```bash
git status --short --branch
git log -6 --oneline
```

Expected: clean `feature/native-playback-timing` worktree with five implementation commits after this plan commit.

---

## Post-Implementation Human Runtime Gate

Do not execute this gate automatically.

When the user approves runtime validation:

```bash
./Scripts/native-wallpaper-adhoc-qa.sh reset
./Scripts/native-wallpaper-adhoc-qa.sh install
```

Then stop and request:

```text
사용자가 직접 확인해야 합니다. 확인 후 결과를 알려주세요.
```

The user performs:

1. System Settings에서 `MacWall` 선택
2. Main App에서 Video Play
3. Desktop video 출력 확인
4. Fullscreen -> Desktop 전환 확인

After the user reports the screen result, inspect first:

```bash
./Scripts/native-wallpaper-adhoc-qa.sh status
./Scripts/native-wallpaper-adhoc-qa.sh logs 3m
```

Runtime pass requires all of:

- Host and Extension log `transportMode=development-home`
- both log the same QA root
- Extension reads the Host generation command
- Host reads matching playing status and heartbeat
- `nativeVideoBridge enqueued` continues
- `NSCocoaErrorDomain 513` is absent
- user confirms Desktop video and Fullscreen transition

If this gate fails, classify before editing:

- mode/build setting mismatch
- POSIX account home resolution failure
- temporary exception rejected
- QA root read/write failure
- command/status generation mismatch
- WallpaperAgent handshake or Extension lifecycle failure

Proper Apple signing/provisioning remains a separate subsequent gate. `AdHocQA` success must not be recorded as production App Group success.
