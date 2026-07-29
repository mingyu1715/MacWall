# Scene Format Layer Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scene.pkg`와 TEX를 package 전체 복사 없이 읽는 `MacWallSceneFormats`, deterministic Audit v2를 생성하는 `MacWallSceneAudit`를 추가하고, 기존 Core format/audit 구현을 호환 facade 없이 완전히 교체한다.

**Architecture:** `MacWallSceneFormats`가 file descriptor와 `pread` 기반 random-access source, PKG index, TEX descriptor, selected-mip software decoder를 소유합니다. `MacWallSceneAudit`는 Formats 위에서 bounded JSON/TEX inspection과 schema 2 report를 담당하고, `MacWallCore`는 Formats를 사용해 기존 `SceneRenderPlan` prototype만 유지합니다. 새 구현을 병행 추가한 뒤 consumer를 전환하고 전체 검증이 통과했을 때 기존 Core 구현을 삭제합니다.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, Darwin `open`/`fstat`/`pread`, XCTest, `JSONSerialization`, existing LZ4/DXT software algorithms.

## Global Constraints

- 설계 기준은 `docs/superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md`입니다.
- 지원 플랫폼은 기존 package 기준인 macOS 14+입니다.
- `MacWallSceneFormats`는 Foundation/Darwin 외에 Audit/Core/AppKit/Metal에 의존하지 않습니다.
- `MacWallSceneAudit`는 `MacWallSceneFormats`에만 의존합니다.
- `MacWallCore`는 `MacWallSceneFormats`에 의존하고 Audit에는 의존하지 않습니다.
- `MacWallApp`는 Formats/Audit에 직접 의존하지 않고 `MacWallCore`의 prototype render model만 소비합니다.
- `macwallctl`은 `MacWallCore`와 `MacWallSceneAudit`에 의존합니다.
- 기존 Core Scene 타입을 re-export하거나 `typealias`로 유지하는 compatibility facade를 만들지 않습니다.
- package 전체 `Data(contentsOf:)`와 package entry 전체 무제한 read API를 만들지 않습니다.
- package size limit은 512 MiB, entry count는 100,000, path는 4,096 bytes, cumulative index는 64 MiB입니다.
- TEX image count는 4,096, mipmap count는 image당 32, animation frame은 100,000, condition string은 1 MiB, cumulative metadata는 16 MiB입니다.
- decode limit은 dimension 16,384, compressed payload 64 MiB, default decoded pixel 18,000,000입니다.
- packaged JSON은 entry당 16 MiB, package audit 누적 64 MiB입니다.
- overlap은 warning/index issue이며 exact duplicate path와 out-of-bounds range는 invalid입니다.
- unknown PKG numeric version은 같은 envelope로 읽고 `unverifiedVersion` issue를 남깁니다.
- unknown TEX version/info/container는 unsupported evidence로 보존하고 corrupt/truncated input과 구분합니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`를 Scene output이나 fallback source로 사용하지 않습니다.
- 실제 Workshop payload는 `test/` local-only read-only fixture로만 사용하고 Git에 추가하지 않습니다.
- GPL implementation과 Wallpaper Engine built-in asset/shader/texture를 복사하지 않습니다.
- 현재 `CALayer` Scene renderer 기능을 확장하지 않습니다.
- S2 asset resolver, typed graph, Metal renderer, Native Scene surface, Scene fallback, effect/SceneScript 실행을 시작하지 않습니다.
- 새 `macwallctl` command를 추가하지 않습니다.
- 자동 검증은 focused `swift test`, 전체 `swift test`, `rg`, `git diff --check`, local fixture read-only inspection만 사용합니다.
- `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행, package, DMG, notarization, `dist` 작업을 하지 않습니다.

---

## File Structure

새 production 파일:

- `Sources/MacWallSceneFormats/SceneFormatError.swift`
  - format 계층의 typed error와 resource limit key
- `Sources/MacWallSceneFormats/SceneByteSource.swift`
  - source protocol, in-memory source, bounded child source
- `Sources/MacWallSceneFormats/SceneFileByteSource.swift`
  - read-only fd ownership, `fstat`, concurrent `pread`
- `Sources/MacWallSceneFormats/SceneBinaryCursor.swift`
  - little-endian scalar, length-prefixed UTF-8, chunked C-string, bounded skip
- `Sources/MacWallSceneFormats/ScenePackage.swift`
  - package version, entry, issue, immutable archive
- `Sources/MacWallSceneFormats/ScenePackageArchiveReader.swift`
  - incremental PKG index parser와 validation
- `Sources/MacWallSceneFormats/SceneTextureDescriptor.swift`
  - parsed/unsupported inspection model과 payload ranges
- `Sources/MacWallSceneFormats/SceneTextureFormatReader.swift`
  - TEXV0005/TEXI0001/TEXB0001...0004/TEXS0001...0003 parser
- `Sources/MacWallSceneFormats/SceneDecodedTexture.swift`
  - software decoder output model
- `Sources/MacWallSceneFormats/SceneTextureSoftwareDecoder.swift`
  - selected mip read, encoded image/raw format decode, crop
- `Sources/MacWallSceneFormats/SceneLZ4BlockDecoder.swift`
  - bounded LZ4 block expansion
- `Sources/MacWallSceneFormats/SceneDXTDecoder.swift`
  - DXT1/DXT3/DXT5 RGBA decode
- `Sources/MacWallSceneAudit/SceneAuditModels.swift`
  - schema 2 report, texture inspection status, diagnostics
- `Sources/MacWallSceneAudit/SceneAuditSupportPolicy.swift`
  - support severity precedence
- `Sources/MacWallSceneAudit/SceneAuditReportEncoder.swift`
  - sorted canonical JSON과 trailing newline
- `Sources/MacWallSceneAudit/SceneJSONInspector.swift`
  - object/dependency/script evidence
- `Sources/MacWallSceneAudit/SceneAuditor.swift`
  - package issue, bounded JSON, texture inspection을 report로 조립

새 test/support 파일:

- `Tests/MacWallSceneTestSupport/RecordingSceneByteSource.swift`
  - read range를 thread-safe하게 기록하는 test-only source
- `Tests/MacWallSceneTestSupport/ScenePackageFixtureBuilder.swift`
  - synthetic PKG table/payload builder
- `Tests/MacWallSceneTestSupport/SceneTextureFixtureBuilder.swift`
  - B0001...B0004, video, animation synthetic TEX builder
- `Tests/MacWallSceneFormatsTests/SceneByteSourceTests.swift`
- `Tests/MacWallSceneFormatsTests/ScenePackageArchiveTests.swift`
- `Tests/MacWallSceneFormatsTests/SceneTextureFormatReaderTests.swift`
- `Tests/MacWallSceneFormatsTests/SceneTextureSoftwareDecoderTests.swift`
- `Tests/MacWallSceneAuditTests/SceneAuditModelsTests.swift`
- `Tests/MacWallSceneAuditTests/SceneAuditorTests.swift`
- `Tests/MacWallSceneAuditTests/SceneLocalFixtureAuditTests.swift`

수정 파일:

- `Package.swift`
  - Formats/Audit/test support/test targets와 dependency 방향 추가
- `Sources/MacWallCore/Scene/SceneRenderPlan.swift`
  - bounded archive/descriptor/decoder 사용, Core-owned render texture model
- `Sources/MacWallApp/Playback/SceneWallpaperView.swift`
  - `SceneRenderTexture` 소비
- `Sources/macwallctl/MacWallCtl.swift`
  - `scene-info`를 Audit v2 canonical output으로 전환
- `Tests/MacWallCoreTests/Fixture.swift`
  - Scene 전용 fixture helper 제거
- `Tests/MacWallCoreTests/ScannerTests.swift`
- `Tests/MacWallCoreTests/LibraryStoreTests.swift`
- `Tests/MacWallCoreTests/SceneRenderPlanTests.swift`
  - 새 test support builder 사용
- `README.md`
- `README.ko.md`
- `docs/README.md`
- `docs/development-log.md`
- `docs/development-roadmap.md`
- `docs/superpowers/specs/2026-07-29-scene-engine-design.md`

최종 삭제 파일:

- `Sources/MacWallCore/Scene/ScenePackage.swift`
- `Sources/MacWallCore/Scene/SceneTexture.swift`
- `Sources/MacWallCore/Scene/SceneTextureMetadata.swift`
- `Sources/MacWallCore/Scene/SceneLZ4BlockDecoder.swift`
- `Sources/MacWallCore/Scene/SceneDXTDecoder.swift`
- `Sources/MacWallCore/Scene/SceneAuditModels.swift`
- `Sources/MacWallCore/Scene/SceneAuditor.swift`
- `Sources/MacWallCore/Scene/SceneJSONInspector.swift`
- `Tests/MacWallCoreTests/ScenePackageTests.swift`
- `Tests/MacWallCoreTests/SceneTextureMetadataTests.swift`
- `Tests/MacWallCoreTests/SceneTextureDecoderTests.swift`
- `Tests/MacWallCoreTests/SceneAuditModelsTests.swift`
- `Tests/MacWallCoreTests/SceneAuditorTests.swift`
- `Tests/MacWallCoreTests/SceneLocalFixtureAuditTests.swift`

Core의 `SceneRenderPlan.swift`와 App의 `SceneWallpaperView.swift`는 삭제하지 않습니다.

---

### Task 1: Random-access Source Foundation

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallSceneFormats/SceneFormatError.swift`
- Create: `Sources/MacWallSceneFormats/SceneByteSource.swift`
- Create: `Sources/MacWallSceneFormats/SceneFileByteSource.swift`
- Create: `Sources/MacWallSceneFormats/SceneBinaryCursor.swift`
- Create: `Tests/MacWallSceneTestSupport/RecordingSceneByteSource.swift`
- Create: `Tests/MacWallSceneFormatsTests/SceneByteSourceTests.swift`

**Interfaces:**

- Produces: `SceneByteSource.byteCount`
- Produces: `SceneByteSource.read(range:) throws -> Data`
- Produces: `SceneDataByteSource.init(data:)`
- Produces: `SceneBoundedByteSource.init(parent:range:) throws`
- Produces: `SceneFileByteSource.init(url:) throws`
- Produces: internal `SceneBinaryCursor`
- Consumed by: Tasks 2-7

- [x] **Step 1: Add target skeletons and failing source tests**

Add these target declarations to `Package.swift`:

```swift
.target(name: "MacWallSceneFormats"),
.target(
    name: "MacWallSceneTestSupport",
    dependencies: ["MacWallSceneFormats"],
    path: "Tests/MacWallSceneTestSupport"
),
.testTarget(
    name: "MacWallSceneFormatsTests",
    dependencies: ["MacWallSceneFormats", "MacWallSceneTestSupport"]
),
```

Create `Tests/MacWallSceneFormatsTests/SceneByteSourceTests.swift` with tests
that establish the exact source contract:

```swift
import Foundation
import XCTest
@testable import MacWallSceneFormats
import MacWallSceneTestSupport

final class SceneByteSourceTests: XCTestCase {
    func testBoundedSourceTranslatesChildRanges() throws {
        let recording = RecordingSceneByteSource(
            base: SceneDataByteSource(
                data: Data((0..<16).map(UInt8.init))
            )
        )
        let source = try SceneBoundedByteSource(
            parent: recording,
            range: 4..<12
        )

        XCTAssertEqual(try source.read(range: 2..<5), Data([6, 7, 8]))
        XCTAssertEqual(recording.readRanges, [6..<9])
        XCTAssertThrowsError(try source.read(range: 0..<9))
    }

    func testFileSourceUsesStableOpenFileAndReportsTruncation() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "macwall-source-\(UUID().uuidString)")
        try Data((0..<32).map(UInt8.init)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try SceneFileByteSource(url: url)

        XCTAssertEqual(try source.read(range: 8..<12), Data([8, 9, 10, 11]))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 4)
        try handle.close()
        XCTAssertThrowsError(try source.read(range: 8..<12)) { error in
            XCTAssertEqual(error as? SceneFormatError, .truncated)
        }
    }
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneByteSourceTests
```

Expected: compile failure because `SceneByteSource`,
`SceneDataByteSource`, `SceneBoundedByteSource`, and
`SceneFileByteSource` do not exist.

- [x] **Step 3: Implement typed errors and byte sources**

Define these exact error categories in
`Sources/MacWallSceneFormats/SceneFormatError.swift`:

```swift
public enum SceneResourceLimit: String, Equatable, Sendable {
    case packageBytes
    case entryCount
    case entryPathBytes
    case indexBytes
    case textureMetadataBytes
    case textureDimension
    case compressedPayloadBytes
    case decodedPixels
    case jsonEntryBytes
    case jsonCumulativeBytes
}

public enum SceneFormatError: Error, Equatable, Sendable {
    case io
    case outOfBounds
    case truncated
    case invalidMagic(String)
    case invalidCount(Int64)
    case invalidString
    case invalidPath(String)
    case duplicatePath(String)
    case invalidRange(String)
    case resourceLimit(SceneResourceLimit)
    case unsupportedLayout(String)
    case unsupportedDecode(String)
    case decompressionFailed
}
```

Its `LocalizedError` messages must be generic. Do not include an input URL,
username, errno string, or payload bytes.

Define `SceneByteSource` and the two value sources:

```swift
public protocol SceneByteSource: Sendable {
    var byteCount: UInt64 { get }
    func read(range: Range<UInt64>) throws -> Data
}

public struct SceneDataByteSource: SceneByteSource {
    public let byteCount: UInt64
    public init(data: Data)
    public func read(range: Range<UInt64>) throws -> Data
}

public struct SceneBoundedByteSource: SceneByteSource {
    public let byteCount: UInt64
    public init(
        parent: any SceneByteSource,
        range: Range<UInt64>
    ) throws
    public func read(range: Range<UInt64>) throws -> Data
}
```

`SceneBoundedByteSource` must validate the parent range once, then translate
child ranges with `addingReportingOverflow`. Empty ranges return empty
`Data`.

Implement `SceneFileByteSource` as a final `@unchecked Sendable` class:

```swift
public final class SceneFileByteSource: SceneByteSource, @unchecked Sendable {
    public let byteCount: UInt64
    public init(url: URL) throws
    deinit
    public func read(range: Range<UInt64>) throws -> Data
}
```

Implementation rules:

1. Open with `O_RDONLY | O_CLOEXEC`.
2. Obtain the fixed size with `fstat`.
3. Keep the descriptor open for object lifetime.
4. Read with `pread` in a loop without a shared seek cursor.
5. Retry only `EINTR`.
6. Map other syscall failures to `.io`.
7. Map zero-byte short reads before the requested count to `.truncated`.
8. Close exactly once in `deinit`.

Create internal `SceneBinaryCursor` with these methods:

```swift
struct SceneBinaryCursor {
    let source: any SceneByteSource
    private(set) var offset: UInt64

    mutating func readInt32() throws -> Int32
    mutating func readUInt32() throws -> UInt32
    mutating func readLengthPrefixedString(
        maximumBytes: UInt64
    ) throws -> String
    mutating func readCString(
        maximumBytes: UInt64,
        chunkBytes: UInt64 = 4_096
    ) throws -> String
    mutating func consume(byteCount: UInt64) throws -> Range<UInt64>
}
```

`readCString` scans at most 4,096 bytes per source read and stops at the first
NUL. `consume` advances after bounds/overflow validation without loading the
consumed payload.

- [x] **Step 4: Implement the thread-safe recording source and run GREEN**

Create `RecordingSceneByteSource` as a test-only wrapper:

```swift
public final class RecordingSceneByteSource:
    SceneByteSource,
    @unchecked Sendable
{
    public init(base: any SceneByteSource)
    public var byteCount: UInt64 { get }
    public var readRanges: [Range<UInt64>] { get }
    public var maximumReadByteCount: UInt64 { get }
    public func resetReadRanges()
    public func read(range: Range<UInt64>) throws -> Data
}
```

Use `NSLock` to protect the range array. Record the range before delegating
to the base source.

Run:

```bash
swift test --filter SceneByteSourceTests
```

Expected: all `SceneByteSourceTests` pass.

- [x] **Step 5: Commit**

```bash
git add Package.swift Sources/MacWallSceneFormats Tests/MacWallSceneTestSupport/RecordingSceneByteSource.swift Tests/MacWallSceneFormatsTests/SceneByteSourceTests.swift
git commit -m "feat(scene): add random access byte sources"
```

---

### Task 2: Versioned PKG Archive

**Files:**

- Create: `Sources/MacWallSceneFormats/ScenePackage.swift`
- Create: `Sources/MacWallSceneFormats/ScenePackageArchiveReader.swift`
- Create: `Tests/MacWallSceneTestSupport/ScenePackageFixtureBuilder.swift`
- Create: `Tests/MacWallSceneFormatsTests/ScenePackageArchiveTests.swift`

**Interfaces:**

- Consumes: Task 1 `SceneByteSource`, `SceneFileByteSource`, `SceneBinaryCursor`
- Produces: `ScenePackageArchiveReader.read(url:)`
- Produces: `ScenePackageArchiveReader.read(source:)`
- Produces: `ScenePackageArchive.source(for:)`
- Produces: `ScenePackageArchive.read(entry:maximumBytes:)`
- Consumed by: Tasks 6-9

- [ ] **Step 1: Write failing archive and malformed-corpus tests**

Create `ScenePackageFixtureEntry` and builder use sites in
`ScenePackageArchiveTests.swift`:

```swift
let bytes = ScenePackageFixtureBuilder.make(
    version: "PKGV0018",
    entries: [
        .init(path: "scene.json", data: Data("{}".utf8)),
        .init(path: "materials/a.tex", data: Data([1, 2, 3]))
    ]
)
let recording = RecordingSceneByteSource(
    base: SceneDataByteSource(data: bytes)
)
let archive = try ScenePackageArchiveReader().read(source: recording)

XCTAssertEqual(archive.version.rawValue, "PKGV0018")
XCTAssertEqual(archive.entries.map(\.path), [
    "scene.json",
    "materials/a.tex"
])
XCTAssertFalse(recording.readRanges.contains(archive.entries[0].payloadRange))
let scene = try archive.read(
    entry: XCTUnwrap(archive.entry(named: "scene.json")),
    maximumBytes: 16
)
XCTAssertEqual(scene, Data("{}".utf8))
```

Add explicit tests for:

- `PKGV0008`, `PKGV0018`, `PKGV0023`
- numeric `PKGV0042` with `.unverifiedVersion("PKGV0042")`
- malformed magic and non-four-digit version
- negative/100,001 entry count
- 4,097-byte path and 64 MiB cumulative index
- empty, absolute, backslash, NUL, empty component, `.`, `..`
- exact duplicate path
- negative/overflow/out-of-file range
- overlapping in-bounds ranges recorded as an issue while reads remain allowed
- an entry read above `maximumBytes` rejected before payload access
- package source above 512 MiB rejected before index parsing

Resource-limit unit tests must assert the production default values, then
inject smaller limits to exercise rejection without allocating 64/512 MiB.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ScenePackageArchiveTests
```

Expected: compile failure because the archive models, reader, and fixture
builder do not exist.

- [ ] **Step 3: Add immutable package models**

Define:

```swift
public struct ScenePackageVersion: Equatable, Sendable {
    public let rawValue: String
    public let numericValue: Int
    public let isVerified: Bool
}

public enum ScenePackageIndexIssue: Equatable, Sendable {
    case unverifiedVersion(String)
    case overlappingEntryRange(firstPath: String, secondPath: String)
}

public struct ScenePackageEntry: Equatable, Sendable {
    public let path: String
    public let relativeOffset: UInt64
    public let byteCount: UInt64
    public let payloadRange: Range<UInt64>
}

public struct ScenePackageArchive: Sendable {
    public let version: ScenePackageVersion
    public let entries: [ScenePackageEntry]
    public let issues: [ScenePackageIndexIssue]

    public func entry(named path: String) -> ScenePackageEntry?
    public func source(
        for entry: ScenePackageEntry
    ) -> SceneBoundedByteSource
    public func read(
        entry: ScenePackageEntry,
        maximumBytes: UInt64
    ) throws -> Data
}
```

The archive keeps the source strongly and builds an exact-case path lookup
dictionary. It must not expose an unbounded `read(entry:)` overload.

- [ ] **Step 4: Implement incremental index parsing and run GREEN**

Define:

```swift
public struct ScenePackageLimits: Equatable, Sendable {
    public var maximumPackageBytes: UInt64 = 512 * 1024 * 1024
    public var maximumEntryCount: Int = 100_000
    public var maximumPathBytes: UInt64 = 4_096
    public var maximumIndexBytes: UInt64 = 64 * 1024 * 1024
}

public struct ScenePackageArchiveReader: Sendable {
    public init(limits: ScenePackageLimits = .init())
    public func read(url: URL) throws -> ScenePackageArchive
    public func read(
        source: any SceneByteSource
    ) throws -> ScenePackageArchive
}
```

Parsing order:

1. Check source size.
2. Read the length-prefixed version and require `PKGV` plus four ASCII digits.
3. Parse signed Int32 entry count, offsets, and lengths before converting.
4. Validate each path without normalization or case folding.
5. Reject duplicate paths while building the table.
6. Record the cursor after the table as payload start.
7. Use checked UInt64 addition for payload ranges.
8. Reject ranges outside source bounds.
9. Sort a copy by range start to find overlaps, but preserve original entry order.
10. Sort issues deterministically by their textual paths.

Implement the fixture builder with exact override fields:

```swift
public struct ScenePackageFixtureEntry {
    public let path: String
    public let data: Data
    public let tableOffset: Int32?
    public let tableLength: Int32?

    public init(
        path: String,
        data: Data,
        tableOffset: Int32? = nil,
        tableLength: Int32? = nil
    )
}

public enum ScenePackageFixtureBuilder {
    public static func make(
        version: String = "PKGV0008",
        entries: [ScenePackageFixtureEntry]
    ) -> Data

    public static func write(
        to url: URL,
        version: String = "PKGV0008",
        sceneJSON: String,
        extraEntries: [ScenePackageFixtureEntry] = []
    ) throws
}
```

Run:

```bash
swift test --filter ScenePackageArchiveTests
```

Expected: all package archive and malformed-corpus tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacWallSceneFormats/ScenePackage.swift Sources/MacWallSceneFormats/ScenePackageArchiveReader.swift Tests/MacWallSceneTestSupport/ScenePackageFixtureBuilder.swift Tests/MacWallSceneFormatsTests/ScenePackageArchiveTests.swift
git commit -m "feat(scene): add versioned package archive"
```

---

### Task 3: Versioned TEX Inspection

**Files:**

- Create: `Sources/MacWallSceneFormats/SceneTextureDescriptor.swift`
- Create: `Sources/MacWallSceneFormats/SceneTextureFormatReader.swift`
- Create: `Tests/MacWallSceneTestSupport/SceneTextureFixtureBuilder.swift`
- Create: `Tests/MacWallSceneFormatsTests/SceneTextureFormatReaderTests.swift`

**Interfaces:**

- Consumes: Task 1 byte source/cursor
- Produces: `SceneTextureFormatReader.inspect(source:path:)`
- Produces: `SceneTextureFormatReader.read(source:path:)`
- Produces: immutable mip payload ranges
- Consumed by: Tasks 4, 6, 8

- [ ] **Step 1: Write failing known/unsupported/corrupt TEX tests**

Create tests that use a recording source and assert:

```swift
let bytes = SceneTextureFixtureBuilder.make(
    formatRawValue: 777,
    flagsRawValue: 0x402,
    textureSize: (8, 8),
    imageSize: (7, 6),
    container: .b0003(imageFormatRawValue: 13),
    images: [
        .init(mipmaps: [
            .init(width: 8, height: 8, payload: Data([1])),
            .init(width: 4, height: 4, payload: Data([2]))
        ]),
        .init(mipmaps: [
            .init(width: 8, height: 8, payload: Data([3]))
        ])
    ]
)
let source = RecordingSceneByteSource(
    base: SceneDataByteSource(data: bytes)
)
let inspection = try SceneTextureFormatReader().inspect(
    source: source,
    path: "materials/sample.tex"
)
guard case .parsed(let descriptor) = inspection else {
    return XCTFail("expected parsed descriptor")
}
XCTAssertEqual(descriptor.declaredContainer, "TEXB0003")
XCTAssertEqual(descriptor.images.map { $0.mipmaps.count }, [2, 1])
XCTAssertFalse(source.readRanges.contains(
    descriptor.images[0].mipmaps[0].payloadRange
))
```

Add cases for:

- B0001, B0002, B0003
- B0004 non-video with `.b0003Compatible`
- B0004 video with four raw video fields and condition string
- multi-image/mipmap payload ranges
- TEXS0001, TEXS0002, TEXS0003 and 32-byte frame record range
- unknown outer version with only outer version evidence
- unknown info version with outer/info evidence
- unknown container with known header and raw container evidence
- unknown animation version mapped to unsupported version evidence
- unknown format and flags retained in a parsed descriptor
- one-byte truncated payload range as `.truncated`
- trailing bytes preserved without invalidation
- image/mipmap/frame/string/cumulative metadata limits
- negative image/mipmap/frame/payload/decompressed counts
- animation frame-range multiplication overflow
- no single C-string scan read above 4,096 bytes

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneTextureFormatReaderTests
```

Expected: compile failure because descriptor and reader types do not exist.

- [ ] **Step 3: Add exact descriptor and unsupported models**

Define these public types:

```swift
public enum SceneTextureInspection: Equatable, Sendable {
    case parsed(SceneTextureDescriptor)
    case unsupported(SceneTextureUnsupportedMetadata)
}

public enum SceneTextureUnsupportedKind: String, Equatable, Sendable {
    case outerVersion
    case infoVersion
    case container
    case animationVersion
}

public struct SceneTextureUnsupportedMetadata: Equatable, Sendable {
    public let path: String
    public let kind: SceneTextureUnsupportedKind
    public let version: String?
    public let infoVersion: String?
    public let declaredContainer: String?
    public let animationVersion: String?
}

public enum SceneTextureMipmapLayout: String, Equatable, Sendable {
    case b0001
    case b0002OrB0003
    case b0004Video
}

public struct SceneTextureVideoMetadata: Equatable, Sendable {
    public let firstParameter: Int32
    public let secondParameter: Int32
    public let condition: String
    public let trailingParameter: Int32
}

public struct SceneTextureMipmapDescriptor: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let isLZ4Compressed: Bool
    public let decompressedByteCount: UInt64?
    public let video: SceneTextureVideoMetadata?
    public let payloadRange: Range<UInt64>
}

public struct SceneTextureImageDescriptor: Equatable, Sendable {
    public let mipmaps: [SceneTextureMipmapDescriptor]
}

public struct SceneTextureAnimationDescriptor: Equatable, Sendable {
    public let version: String
    public let frameCount: Int
    public let gifWidth: Int?
    public let gifHeight: Int?
    public let frameRecordRange: Range<UInt64>
}

public struct SceneTextureDescriptor: Equatable, Sendable {
    public let path: String
    public let version: String
    public let infoVersion: String
    public let formatRawValue: Int
    public let flagsRawValue: Int
    public let textureWidth: Int
    public let textureHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int
    public let declaredContainer: String
    public let mipmapLayout: SceneTextureMipmapLayout
    public let imageFormatRawValue: Int?
    public let isVideoMP4: Bool
    public let images: [SceneTextureImageDescriptor]
    public let animation: SceneTextureAnimationDescriptor?
    public let trailingByteRange: Range<UInt64>?
}
```

- [ ] **Step 4: Implement structural parser and run GREEN**

Define:

```swift
public struct SceneTextureLimits: Equatable, Sendable {
    public var maximumImageCount: Int = 4_096
    public var maximumMipmapCount: Int = 32
    public var maximumAnimationFrameCount: Int = 100_000
    public var maximumConditionBytes: UInt64 = 1 * 1024 * 1024
    public var maximumMetadataBytes: UInt64 = 16 * 1024 * 1024
}

public struct SceneTextureFormatReader: Sendable {
    public init(limits: SceneTextureLimits = .init())
    public func inspect(
        source: any SceneByteSource,
        path: String
    ) throws -> SceneTextureInspection
    public func read(
        source: any SceneByteSource,
        path: String
    ) throws -> SceneTextureDescriptor
}
```

Parsing rules:

1. Require exact `TEXV0005` for a complete parse.
2. Require exact `TEXI0001`.
3. Preserve format, flags, dimensions, and the unknown UInt32 header field by consuming it.
4. B0001 has dimensions/count/payload only.
5. B0002/B0003 have LZ4 flag, decompressed count, byte count, payload.
6. B0003 reads image format before image count.
7. B0004 reads image format and video flag; non-video uses B0003-compatible mip layout without changing declared container.
8. B0004 video reads the four video fields before each mip dimensions.
9. Consume payload ranges without loading bytes.
10. Parse animation only when flag bit 4 is set.
11. Charge 64 metadata bytes per image, 96 per mip, and UTF-8 byte count for every parsed string.
12. Preserve a non-empty final range as `trailingByteRange`.
13. `read` returns `.parsed` content and maps `.unsupported` to `.unsupportedLayout`.

Parser limit tests assert these production defaults, then inject small values
to test the same accounting paths without large allocations.

The synthetic builder must expose explicit container cases:

```swift
public enum SceneTextureFixtureContainer {
    case b0001
    case b0002
    case b0003(imageFormatRawValue: Int32)
    case b0004(imageFormatRawValue: Int32, isVideoMP4: Bool)
}

public struct SceneTextureFixtureMipmap {
    public let width: Int32
    public let height: Int32
    public let isLZ4Compressed: Bool
    public let decompressedByteCount: Int32?
    public let videoFirstParameter: Int32
    public let videoSecondParameter: Int32
    public let videoCondition: String
    public let videoTrailingParameter: Int32
    public let payload: Data

    public init(
        width: Int32,
        height: Int32,
        isLZ4Compressed: Bool = false,
        decompressedByteCount: Int32? = nil,
        videoFirstParameter: Int32 = 1,
        videoSecondParameter: Int32 = 2,
        videoCondition: String = "{}",
        videoTrailingParameter: Int32 = 1,
        payload: Data
    )
}

public struct SceneTextureFixtureImage {
    public let mipmaps: [SceneTextureFixtureMipmap]
    public init(mipmaps: [SceneTextureFixtureMipmap])
}

public struct SceneTextureFixtureAnimation {
    public let version: String
    public let frameCount: Int32
    public let gifWidth: Int32?
    public let gifHeight: Int32?
    public let frameRecords: Data

    public init(
        version: String,
        frameCount: Int32,
        gifWidth: Int32? = nil,
        gifHeight: Int32? = nil,
        frameRecords: Data
    )
}

public enum SceneTextureFixtureBuilder {
    public static func make(
        version: String = "TEXV0005",
        infoVersion: String = "TEXI0001",
        formatRawValue: Int32,
        flagsRawValue: Int32 = 0,
        textureSize: (Int32, Int32),
        imageSize: (Int32, Int32),
        container: SceneTextureFixtureContainer,
        images: [SceneTextureFixtureImage],
        animation: SceneTextureFixtureAnimation? = nil,
        trailingBytes: Data = Data()
    ) -> Data
}
```

Run:

```bash
swift test --filter SceneTextureFormatReaderTests
```

Expected: all structural TEX tests pass without reading mip payload bytes.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacWallSceneFormats/SceneTextureDescriptor.swift Sources/MacWallSceneFormats/SceneTextureFormatReader.swift Tests/MacWallSceneTestSupport/SceneTextureFixtureBuilder.swift Tests/MacWallSceneFormatsTests/SceneTextureFormatReaderTests.swift
git commit -m "feat(scene): add versioned texture inspection"
```

---

### Task 4: Selected-mip Software Decoder

**Files:**

- Create: `Sources/MacWallSceneFormats/SceneDecodedTexture.swift`
- Create: `Sources/MacWallSceneFormats/SceneTextureSoftwareDecoder.swift`
- Create: `Sources/MacWallSceneFormats/SceneLZ4BlockDecoder.swift`
- Create: `Sources/MacWallSceneFormats/SceneDXTDecoder.swift`
- Create: `Tests/MacWallSceneFormatsTests/SceneTextureSoftwareDecoderTests.swift`

**Interfaces:**

- Consumes: Task 3 `SceneTextureDescriptor` and one source
- Produces: `SceneTextureSoftwareDecoder.decode(descriptor:source:imageIndex:mipmapIndex:)`
- Produces: `SceneDecodedTexture`
- Consumed by: Task 8

- [ ] **Step 1: Write failing decode and read-boundary tests**

Create tests for:

```swift
let png = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lz8KWwAAAABJRU5ErkJggg=="
)!
let bytes = SceneTextureFixtureBuilder.make(
    formatRawValue: 13,
    textureSize: (1, 1),
    imageSize: (1, 1),
    container: .b0003(imageFormatRawValue: 13),
    images: [.init(mipmaps: [
        .init(width: 1, height: 1, payload: png),
        .init(width: 1, height: 1, payload: Data([9, 9]))
    ])]
)
let source = RecordingSceneByteSource(
    base: SceneDataByteSource(data: bytes)
)
let descriptor = try SceneTextureFormatReader().read(
    source: source,
    path: "materials/a.tex"
)
source.resetReadRanges()
let decoded = try SceneTextureSoftwareDecoder().decode(
    descriptor: descriptor,
    source: source,
    imageIndex: 0,
    mipmapIndex: 0
)

XCTAssertEqual(decoded.storage, .encodedImage(png))
XCTAssertEqual(source.readRanges, [
    descriptor.images[0].mipmaps[0].payloadRange
])
```

Also test:

- raw RGBA format 0
- DXT5 format 4, DXT3 format 6, DXT1 format 7
- RG88 format 8 and R8 format 9
- LZ4 literal and overlapping match
- malformed LZ4/match offset/decompressed size
- padded texture crop
- invalid image/mip index
- dimension 16,385
- compressed payload 64 MiB + 1
- decoded pixels above 18,000,000
- unknown format
- animated/video descriptor rejected without payload read

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneTextureSoftwareDecoderTests
```

Expected: compile failure because decoder/output types do not exist.

- [ ] **Step 3: Add output model and decoder API**

Define:

```swift
public struct SceneDecodedTexture: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let storage: SceneDecodedTextureStorage
}

public enum SceneDecodedTextureStorage: Equatable, Sendable {
    case encodedImage(Data)
    case rgba(width: Int, height: Int, data: Data)
}

public struct SceneTextureSoftwareDecoder: Sendable {
    public init(
        maximumTextureDimension: Int = 16_384,
        maximumCompressedPayloadBytes: UInt64 = 64 * 1024 * 1024,
        maximumSoftwareDecodedPixels: Int = 18_000_000
    )
    public func decode(
        descriptor: SceneTextureDescriptor,
        source: any SceneByteSource,
        imageIndex: Int,
        mipmapIndex: Int
    ) throws -> SceneDecodedTexture
}
```

The decoder must validate indices, flags, dimensions, compressed range size,
and output pixel count before reading the selected payload.
Limit tests assert the production defaults and inject small limits for
rejection cases.

- [ ] **Step 4: Port bounded decode algorithms and run GREEN**

Move the existing algorithms from:

- `Sources/MacWallCore/Scene/SceneLZ4BlockDecoder.swift`
- `Sources/MacWallCore/Scene/SceneDXTDecoder.swift`
- decode/crop/encoded-image logic in `Sources/MacWallCore/Scene/SceneTexture.swift`

Keep these exact format mappings:

```swift
switch descriptor.formatRawValue {
case 0: decodeRawRGBA()
case 4: decodeDXT5()
case 6: decodeDXT3()
case 7: decodeDXT1()
case 8: decodeRG88()
case 9: decodeR8()
default:
    throw SceneFormatError.unsupportedDecode(
        "texture-format-\(descriptor.formatRawValue)"
    )
}
```

Encoded PNG/JPEG/GIF/WebP signatures bypass raw format conversion after
optional LZ4 expansion. Never read another image or mip to decode the
selected one.

Run:

```bash
swift test --filter SceneTextureSoftwareDecoderTests
```

Expected: all decoder tests pass, including the exact one-range assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacWallSceneFormats/SceneDecodedTexture.swift Sources/MacWallSceneFormats/SceneTextureSoftwareDecoder.swift Sources/MacWallSceneFormats/SceneLZ4BlockDecoder.swift Sources/MacWallSceneFormats/SceneDXTDecoder.swift Tests/MacWallSceneFormatsTests/SceneTextureSoftwareDecoderTests.swift
git commit -m "feat(scene): add selected mip software decoder"
```

---

### Task 5: Audit v2 Contract

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallSceneAudit/SceneAuditModels.swift`
- Create: `Sources/MacWallSceneAudit/SceneAuditSupportPolicy.swift`
- Create: `Sources/MacWallSceneAudit/SceneAuditReportEncoder.swift`
- Create: `Tests/MacWallSceneAuditTests/SceneAuditModelsTests.swift`

**Interfaces:**

- Consumes: `MacWallSceneFormats`
- Produces: `SceneAuditReport.schemaVersion == 2`
- Produces: `SceneAuditSupportPolicy.s1`
- Produces: `SceneAuditReportEncoder.encode(_:)`
- Consumed by: Tasks 6, 7, 9

- [ ] **Step 1: Add Audit targets and failing schema tests**

Add:

```swift
.target(
    name: "MacWallSceneAudit",
    dependencies: ["MacWallSceneFormats"]
),
.testTarget(
    name: "MacWallSceneAuditTests",
    dependencies: [
        "MacWallSceneAudit",
        "MacWallSceneFormats",
        "MacWallSceneTestSupport"
    ]
),
```

Create tests that assert:

```swift
let report = SceneAuditReport.empty(status: .exact)
XCTAssertEqual(report.schemaVersion, 2)
let first = try SceneAuditReportEncoder.encode(report)
let second = try SceneAuditReportEncoder.encode(report)
XCTAssertEqual(first, second)
XCTAssertEqual(first.last, 0x0A)
XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("/Users/"))
```

Also port the existing support precedence assertions for exact, degraded,
unsupported, warning, and error.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneAuditModelsTests
```

Expected: compile failure because the new Audit module has no report types.

- [ ] **Step 3: Define schema 2 models**

Move the S0 feature/dependency/diagnostic enums from Core into Audit and
define the changed texture summary:

```swift
public enum SceneAuditTextureStatus: String, Codable, Sendable {
    case parsed
    case unsupportedVersion
    case unsupportedInfoVersion
    case unsupportedContainer
    case invalid
}

public struct SceneAuditTextureSummary: Codable, Equatable, Sendable {
    public let path: String
    public let status: SceneAuditTextureStatus
    public let version: String?
    public let infoVersion: String?
    public let formatRawValue: Int?
    public let flagsRawValue: Int?
    public let textureWidth: Int?
    public let textureHeight: Int?
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let declaredContainer: String?
    public let mipmapLayout: String?
    public let imageFormatRawValue: Int?
    public let isVideoMP4: Bool?
    public let imageCount: Int?
    public let mipmapCounts: [Int]?
    public let animationVersion: String?
    public let animationFrameCount: Int?
    public let trailingByteCount: UInt64?
}
```

Keep the S0 report fields:

```swift
public struct SceneAuditReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let package: SceneAuditPackageSummary
    public let canvas: SceneAuditCanvas?
    public let entryKinds: [SceneAuditCount]
    public let objectKinds: [SceneAuditCount]
    public let textures: [SceneAuditTextureSummary]
    public let dependencies: [SceneAuditDependency]
    public let scriptHandlers: [SceneAuditCount]
    public let features: [SceneAuditFeatureObservation]
    public let diagnostics: [SceneAuditDiagnostic]
    public let status: SceneAuditStatus

    public static func empty(
        status: SceneAuditStatus
    ) -> SceneAuditReport
}
```

Unknown/unread fields stay `nil`; do not encode invented zero/empty values.

- [ ] **Step 4: Port policy/canonical encoder and run GREEN**

Move support precedence into `SceneAuditSupportPolicy.s1`. Configure
`JSONEncoder` with `.sortedKeys`, sort all semantic arrays before model
construction, and append exactly one newline.

The policy interface is:

```swift
public struct SceneAuditSupportPolicy: Sendable {
    public static let s1: SceneAuditSupportPolicy

    public func evaluate(
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic]
    ) -> SceneAuditStatus
}
```

Run:

```bash
swift test --filter SceneAuditModelsTests
```

Expected: all Audit v2 model and canonical encoding tests pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MacWallSceneAudit Tests/MacWallSceneAuditTests/SceneAuditModelsTests.swift
git commit -m "feat(scene): define audit v2 contract"
```

---

### Task 6: Bounded JSON/TEX Auditor

**Files:**

- Create: `Sources/MacWallSceneAudit/SceneJSONInspector.swift`
- Create: `Sources/MacWallSceneAudit/SceneAuditor.swift`
- Create: `Tests/MacWallSceneAuditTests/SceneAuditorTests.swift`

**Interfaces:**

- Consumes: package archive, texture inspection, Audit v2 models
- Produces: `SceneAuditor.audit(url:) -> SceneAuditReport`
- Produces: `SceneAuditor.audit(source:) -> SceneAuditReport`
- Consumed by: Tasks 7 and 9

- [ ] **Step 1: Write failing synthetic audit and limit tests**

Port the S0 object/dependency/script synthetic package test to
`MacWallSceneAuditTests`, change its default package version to `PKGV0008`,
and assert:

```swift
let report = SceneAuditor().audit(url: packageURL)
XCTAssertEqual(report.schemaVersion, 2)
XCTAssertEqual(report.textures.map(\.status), [.parsed])
XCTAssertTrue(report.features.contains {
    $0.key == .parentGraph && $0.count == 1
})
XCTAssertTrue(report.dependencies.contains {
    $0.requestedPath == "genericimage4"
        && $0.resolution == .builtInCandidate
})
```

Add tests for:

- malformed package becomes `.invalid`, not a thrown error
- duplicate path -> `package.duplicate-entry-path`
- unknown numeric package version -> warning `package.unverified-version`
- overlap -> warning `package.overlapping-entry-range`
- unknown TEX outer/info/container status and matching stable diagnostic
- invalid TEX metadata -> `texture.invalid-metadata`
- trailing TEX range -> `texture.trailing-bytes`
- auxiliary JSON above 16 MiB is skipped with warning
- `scene.json` above 16 MiB makes report invalid
- cumulative JSON above 64 MiB skips deterministic auxiliary entries
- report ordering does not depend on package entry order
- diagnostic message excludes temp directory and `/Users/`

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneAuditorTests
```

Expected: compile failure because the new auditor and inspector do not exist.

- [ ] **Step 3: Port JSON evidence inspection**

Move S0 classification, recursive animation detection, dependency resolution,
built-in candidate classification, and exported function-name inspection into
`MacWallSceneAudit/SceneJSONInspector.swift`.

Use this input contract:

```swift
struct SceneJSONAuditEvidence: Sendable {
    var canvas: SceneAuditCanvas?
    var objectKinds: [String: Int]
    var featureCounts: [SceneAuditFeatureKey: Int]
    var dependencies: [SceneAuditDependency]
    var scriptHandlers: [String: Int]
    var diagnostics: [SceneAuditDiagnostic]
}

struct SceneJSONInspector: Sendable {
    func inspect(
        scene: [String: Any],
        documents: [String: Any],
        packagePaths: Set<String>
    ) -> SceneJSONAuditEvidence
}
```

Do not pass `ScenePackageArchive` into the JSON inspector; it consumes only
path evidence and parsed JSON values.

- [ ] **Step 4: Implement bounded auditor and run GREEN**

Define:

```swift
public struct SceneAuditLimits: Equatable, Sendable {
    public var maximumJSONEntryBytes: UInt64 = 16 * 1024 * 1024
    public var maximumCumulativeJSONBytes: UInt64 = 64 * 1024 * 1024
}

public struct SceneAuditor: Sendable {
    public init(
        packageReader: ScenePackageArchiveReader = .init(),
        textureReader: SceneTextureFormatReader = .init(),
        supportPolicy: SceneAuditSupportPolicy = .s1,
        limits: SceneAuditLimits = .init()
    )

    public func audit(url: URL) -> SceneAuditReport
    public func audit(source: any SceneByteSource) -> SceneAuditReport
}
```

Audit order:

1. Open package and convert package issues to sorted diagnostics.
2. Read `scene.json` first with the 16 MiB limit.
3. Read remaining `.json` entries in path order while charging the 64 MiB cumulative budget.
4. Skip over-limit auxiliary JSON with warning; make over-limit `scene.json` invalid.
5. Inspect `.tex` entries in path order through bounded entry sources.
6. Convert `.parsed` and `.unsupported` inspections to optional Audit summaries.
7. Convert format errors to stable generic diagnostics.
8. Assemble sorted count arrays, dependencies, features, and diagnostics.
9. Evaluate final status with `SceneAuditSupportPolicy.s1`.

Use only these stable diagnostic codes:

```text
package.unverified-version
package.invalid-index
package.duplicate-entry-path
package.overlapping-entry-range
texture.unsupported-version
texture.unsupported-info-version
texture.unsupported-container
texture.invalid-metadata
texture.trailing-bytes
resource.limit-exceeded
```

Run:

```bash
swift test --filter SceneAuditorTests
```

Expected: all synthetic audit, limit, ordering, and path-redaction tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacWallSceneAudit/SceneJSONInspector.swift Sources/MacWallSceneAudit/SceneAuditor.swift Tests/MacWallSceneAuditTests/SceneAuditorTests.swift
git commit -m "feat(scene): add bounded audit pipeline"
```

---

### Task 7: Local Fixture Compatibility Gate

**Files:**

- Create: `Tests/MacWallSceneAuditTests/SceneLocalFixtureAuditTests.swift`
- Keep unchanged: `Tests/Fixtures/SceneAudit/local-scene-catalog.json`

**Interfaces:**

- Consumes: Audit v2 and `RecordingSceneByteSource`
- Produces: local-only regression evidence for three tracked fixture IDs
- Does not produce a runtime API

- [ ] **Step 1: Port the local fixture test with random-access assertions**

Decode the existing schema 1 aggregate catalog unchanged. If none of the
fixture paths exist, throw one `XCTSkip`.

For each available fixture:

```swift
let fileSource = try SceneFileByteSource(url: packageURL)
let recording = RecordingSceneByteSource(base: fileSource)
let report = SceneAuditor().audit(source: recording)

XCTAssertEqual(report.package.version, fixture.packageVersion)
XCTAssertEqual(report.package.entryCount, fixture.entryCount)
XCTAssertEqual(counts(report.objectKinds), fixture.objectKinds)
XCTAssertEqual(
    counted(report.textures.compactMap(\.formatRawValue)),
    fixture.textureFormats
)
XCTAssertEqual(
    counted(report.textures.compactMap(\.flagsRawValue)),
    fixture.textureFlags
)
XCTAssertEqual(
    counted(report.textures.compactMap(\.declaredContainer)),
    fixture.textureContainers
)
XCTAssertFalse(recording.readRanges.contains(0..<recording.byteCount))
XCTAssertLessThanOrEqual(
    recording.maximumReadByteCount,
    16 * 1024 * 1024
)
XCTAssertFalse(report.diagnostics.contains { $0.severity == .error })
XCTAssertTrue(report.textures.allSatisfy {
    $0.trailingByteCount == 0
})
```

Keep the existing feature-count and canonical double-encode assertions.

- [ ] **Step 2: Run the local fixture gate**

Run:

```bash
swift test --filter SceneLocalFixtureAuditTests
```

Expected when fixtures exist: all three fixture reports match the tracked
aggregate catalog with no error diagnostic and no whole-package read.

Expected when fixtures do not exist: one explicit skip and no failure.

- [ ] **Step 3: Run all new format/audit tests**

Run:

```bash
swift test --filter MacWallSceneFormatsTests
swift test --filter MacWallSceneAuditTests
```

Expected: both suites pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/MacWallSceneAuditTests/SceneLocalFixtureAuditTests.swift
git commit -m "test(scene): gate format modules with local fixtures"
```

---

### Task 8: Core Render Plan and App Consumer Migration

**Files:**

- Modify: `Package.swift`
- Modify: `Sources/MacWallCore/Scene/SceneRenderPlan.swift`
- Modify: `Sources/MacWallApp/Playback/SceneWallpaperView.swift`
- Modify: `Tests/MacWallCoreTests/Fixture.swift`
- Modify: `Tests/MacWallCoreTests/ScannerTests.swift`
- Modify: `Tests/MacWallCoreTests/LibraryStoreTests.swift`
- Modify: `Tests/MacWallCoreTests/SceneRenderPlanTests.swift`

**Interfaces:**

- Consumes: Formats package/TEX/decoder APIs
- Produces: Core-owned `SceneRenderTexture`
- Preserves: `SceneRenderPlanBuilder.build`, `buildLayout`, `canBuild`
- Keeps: `MacWallApp -> MacWallCore` dependency only

- [ ] **Step 1: Change Core test dependencies and write a failing render texture assertion**

Change target dependencies:

```swift
.target(
    name: "MacWallCore",
    dependencies: ["MacWallSceneFormats"]
),
.testTarget(
    name: "MacWallCoreTests",
    dependencies: ["MacWallCore", "MacWallSceneTestSupport"]
),
```

Update `SceneRenderPlanTests` to import `MacWallSceneTestSupport`, build its
package with `ScenePackageFixtureBuilder`, and assert:

```swift
let plan = try SceneRenderPlanBuilder().build(url: packageURL)
let texture = try XCTUnwrap(plan.textures["materials/background.tex"])
XCTAssertEqual(texture.storage, .encodedImage(png))
```

The expected compile-time type is `SceneRenderTexture`, not the old
`SceneTexture`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneRenderPlanTests
```

Expected: compile failure because `SceneRenderTexture` and the new Core
dependency migration do not exist.

- [ ] **Step 3: Migrate `SceneRenderPlanBuilder`**

Add `import MacWallSceneFormats` and define a Core prototype output model:

```swift
public struct SceneRenderTexture: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let storage: SceneRenderTextureStorage
}

public enum SceneRenderTextureStorage: Equatable, Sendable {
    case encodedImage(Data)
    case rgba(width: Int, height: Int, data: Data)
}
```

Change `SceneRenderPlan.textures` to
`[String: SceneRenderTexture]`. Convert the Formats result explicitly:

```swift
private static func renderTexture(
    from decoded: SceneDecodedTexture
) -> SceneRenderTexture {
    let storage: SceneRenderTextureStorage
    switch decoded.storage {
    case .encodedImage(let data):
        storage = .encodedImage(data)
    case .rgba(let width, let height, let data):
        storage = .rgba(width: width, height: height, data: data)
    }
    return SceneRenderTexture(
        width: decoded.width,
        height: decoded.height,
        storage: storage
    )
}
```

Replace old package calls with:

```swift
let archive = try ScenePackageArchiveReader().read(url: url)
let sceneEntry = try requiredEntry("scene.json", in: archive)
let sceneData = try archive.read(
    entry: sceneEntry,
    maximumBytes: 16 * 1024 * 1024
)
```

Model/material JSON reads use the same 16 MiB maximum. Texture decode uses:

```swift
let textureEntry = try requiredEntry(texturePath, in: archive)
let source = archive.source(for: textureEntry)
let descriptor = try SceneTextureFormatReader().read(
    source: source,
    path: texturePath
)
let decoded = try SceneTextureSoftwareDecoder().decode(
    descriptor: descriptor,
    source: source,
    imageIndex: 0,
    mipmapIndex: 0
)
```

Keep decoded layer limit 16 and the current model/material resolution
behavior. Do not add parent/effect/instance support.

- [ ] **Step 4: Migrate App and Core fixture call sites**

Change:

```swift
private static func cgImage(
    from texture: SceneRenderTexture
) -> CGImage?
```

in `SceneWallpaperView.swift`; keep the encoded/RGBA conversion behavior
unchanged.

Replace Scene-specific `Fixture` calls in Scanner, LibraryStore, and
SceneRenderPlan tests with:

```swift
try ScenePackageFixtureBuilder.write(...)
SceneTextureFixtureBuilder.make(...)
```

Remove `TextureImageFixture`, `Fixture.writeScenePackage`,
`Fixture.scenePackageData`, and `Fixture.texData` from
`Tests/MacWallCoreTests/Fixture.swift` after all Core call sites are moved.

- [ ] **Step 5: Run focused consumer tests and commit**

Run:

```bash
swift test --filter SceneRenderPlanTests
swift test --filter ScannerTests
swift test --filter LibraryStoreTests
```

Expected: all three suites pass.

Commit:

```bash
git add Package.swift Sources/MacWallCore/Scene/SceneRenderPlan.swift Sources/MacWallApp/Playback/SceneWallpaperView.swift Tests/MacWallCoreTests/Fixture.swift Tests/MacWallCoreTests/ScannerTests.swift Tests/MacWallCoreTests/LibraryStoreTests.swift Tests/MacWallCoreTests/SceneRenderPlanTests.swift
git commit -m "refactor(scene): migrate render plan to format module"
```

---

### Task 9: CLI Audit v2 Migration and User Documentation

**Files:**

- Modify: `Package.swift`
- Modify: `Sources/macwallctl/MacWallCtl.swift`
- Modify: `README.md`
- Modify: `README.ko.md`

**Interfaces:**

- Consumes: `SceneAuditor`, `SceneAuditReportEncoder`
- Preserves: `scene-info <scene.pkg>` command name
- Preserves: `scene-render-info <scene.pkg>` prototype summary
- Adds no command

- [ ] **Step 1: Change CLI dependency and implementation**

Set:

```swift
.executableTarget(
    name: "macwallctl",
    dependencies: ["MacWallCore", "MacWallSceneAudit"]
),
```

Add `import MacWallSceneAudit` and replace only `sceneInfo`:

```swift
private static func sceneInfo(arguments: [String]) throws {
    guard let path = arguments.first else {
        throw CLIError.missingPath
    }
    let report = SceneAuditor().audit(url: URL(filePath: path))
    FileHandle.standardOutput.write(
        try SceneAuditReportEncoder.encode(report)
    )
}
```

Do not pass the report through the CLI's generic `JSONEncoder`.

- [ ] **Step 2: Update README command descriptions**

In both README files, state that:

- `scene-info` outputs deterministic Audit schema 2 JSON
- it records package/TEX support and diagnostics
- it does not execute SceneScript/effects
- `scene-render-info` remains the limited 2D prototype summary

Do not describe Scene as fully playable or add fallback claims.

- [ ] **Step 3: Run compile-through tests and static checks**

Run:

```bash
swift test --filter SceneAuditorTests
swift test --filter SceneRenderPlanTests
rg -n 'scene-info|schema 2|SceneScript|scene-render-info' README.md README.ko.md Sources/macwallctl/MacWallCtl.swift
git diff --check
```

Expected: focused tests pass, both README languages describe schema 2, and
the diff check is clean.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/macwallctl/MacWallCtl.swift README.md README.ko.md
git commit -m "refactor(scene): route scene info through audit v2"
```

---

### Task 10: Remove Superseded Core Format/Audit Implementation

**Files:**

- Delete: the eight old Core source files listed in File Structure
- Delete: the six superseded Core test files listed in File Structure
- Modify: `Package.swift` only if target cleanup is required

**Interfaces:**

- Removes: `ScenePackageReader`, `ScenePackageAnalyzer`,
  `SceneTextureMetadataReader`, `SceneTextureDecoder`, Core `SceneAuditor`
- Keeps: `SceneRenderPlanBuilder`, `SceneRenderPlan`, `SceneRenderTexture`
- Provides no compatibility aliases

- [ ] **Step 1: Verify all old consumers are gone before deletion**

Run:

```bash
rg -n 'ScenePackageReader|ScenePackageAnalyzer|SceneTextureMetadataReader|SceneTextureDecoder|SceneLZ4BlockDecoder|SceneTextureError' Sources Tests --glob '*.swift'
```

Expected: matches exist only in the old Core implementation/test files that
will be deleted. New module names such as
`ScenePackageArchiveReader` and `SceneTextureSoftwareDecoder` are not part
of this result.

- [ ] **Step 2: Delete old files**

Delete exactly:

```text
Sources/MacWallCore/Scene/ScenePackage.swift
Sources/MacWallCore/Scene/SceneTexture.swift
Sources/MacWallCore/Scene/SceneTextureMetadata.swift
Sources/MacWallCore/Scene/SceneLZ4BlockDecoder.swift
Sources/MacWallCore/Scene/SceneDXTDecoder.swift
Sources/MacWallCore/Scene/SceneAuditModels.swift
Sources/MacWallCore/Scene/SceneAuditor.swift
Sources/MacWallCore/Scene/SceneJSONInspector.swift
Tests/MacWallCoreTests/ScenePackageTests.swift
Tests/MacWallCoreTests/SceneTextureMetadataTests.swift
Tests/MacWallCoreTests/SceneTextureDecoderTests.swift
Tests/MacWallCoreTests/SceneAuditModelsTests.swift
Tests/MacWallCoreTests/SceneAuditorTests.swift
Tests/MacWallCoreTests/SceneLocalFixtureAuditTests.swift
```

- [ ] **Step 3: Run structure checks**

Run:

```bash
rg -n 'public (struct|enum) Scene(Package|Texture|Audit)' Sources/MacWallCore
rg -n '@_exported|typealias .*Scene(Package|Texture|Audit)' Sources Package.swift
rg -n 'Data\\(contentsOf:' Sources/MacWallSceneFormats Sources/MacWallSceneAudit Sources/MacWallCore/Scene
```

Expected:

- Core has no package/texture/audit format model declaration
- no compatibility re-export/typealias
- no package-level `Data(contentsOf:)` in the Scene format path

- [ ] **Step 4: Run focused and full test verification**

Run:

```bash
swift test --filter MacWallSceneFormatsTests
swift test --filter MacWallSceneAuditTests
swift test --filter SceneRenderPlanTests
swift test
git diff --check
```

Expected: all focused suites and the full suite pass with zero failures.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/MacWallCore/Scene Tests/MacWallCoreTests Package.swift
git commit -m "refactor(scene): remove legacy format implementation"
```

---

### Task 11: Completion Record and Active-document Cleanup

**Files:**

- Create: `docs/implemented/2026-07-29-scene-format-layer-hardening.md`
- Modify: `docs/development-log.md`
- Modify: `docs/development-roadmap.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- Move: `docs/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md`
- Move: `docs/superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md`
- Move: `docs/superpowers/plans/2026-07-29-scene-format-layer-hardening.md`

**Interfaces:**

- Records: S1 implemented state and exact verification evidence
- Sets: next Scene phase to S2 Asset Resolver and Typed Scene Graph
- Starts no S2 implementation

- [ ] **Step 1: Write the implemented record**

Create the implemented document with:

- status `implemented / completed`
- module/dependency graph
- random-access source behavior
- PKG/TEX contracts and limits
- Audit schema 2 behavior
- Core/App/CLI migration
- deleted old implementation list
- local fixture result
- exact focused/full test counts copied from Task 10 output
- explicit exclusions: S2, Metal, Native Scene, fallback, SceneScript/effects

- [ ] **Step 2: Update roadmap, engine spec, index, and timestamped log**

Obtain the log time with:

```bash
TZ=Asia/Seoul date '+%Y-%m-%d %H:%M KST'
```

Record that exact result in `docs/development-log.md`. Mark S1 implemented
in the roadmap and make S2 the next Scene planning phase. Add the implemented
record to `docs/README.md`.

In the Scene Engine design, link the S1 implemented record without changing
the S2/S3 architecture.

- [ ] **Step 3: Archive completed active documents**

Move:

```bash
git mv docs/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md docs/archive/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md
git mv docs/superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md docs/archive/superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md
git mv docs/superpowers/plans/2026-07-29-scene-format-layer-hardening.md docs/archive/superpowers/plans/2026-07-29-scene-format-layer-hardening.md
```

Update all links to the archived design/plan or the implemented record.
Keep the overall Scene Engine design active.

- [ ] **Step 4: Verify documents and repository state**

Run:

```bash
rg --files docs | sort
rg -n 'S1|Format Layer Hardening|S2|swift build|xcodebuild build|Scene fallback|SceneScript' docs/README.md docs/development-roadmap.md docs/development-log.md docs/implemented docs/superpowers docs/archive/superpowers
git diff --check
git status --short
```

Expected:

- completed S0/S1 execution documents are absent from active plans
- S1 implemented record is indexed
- next Scene work is S2 planning
- no code/test files changed after Task 10 verification
- no `dist` or packaging artifact exists

- [ ] **Step 5: Commit**

```bash
git add docs
git commit -m "docs: record scene format layer implementation"
```

---

## Final Acceptance Checklist

- [ ] `MacWallSceneFormats` and `MacWallSceneAudit` are independent targets.
- [ ] Formats has no Audit/Core/AppKit/Metal dependency.
- [ ] Audit depends only on Formats.
- [ ] Core depends on Formats but not Audit.
- [ ] App still depends on Core rather than Formats/Audit.
- [ ] CLI depends on Core and Audit and adds no command.
- [ ] Scene package paths use bounded random-access reads.
- [ ] No unbounded package entry read API exists.
- [ ] No whole-package `Data(contentsOf:)` exists in the Scene format path.
- [ ] PKGV0008/0018/0023 and unverified numeric versions are covered.
- [ ] Duplicate path, invalid range, overlap, and resource limits are distinct.
- [ ] TEX B0001...B0004, video metadata, animation, and trailing bytes are covered.
- [ ] Unknown version/container/format/flag evidence is not discarded.
- [ ] Decoder reads only the selected mip.
- [ ] Audit output is schema 2, deterministic, and path-redacted.
- [ ] S0 aggregate local fixture catalog still matches.
- [ ] Existing render-plan prototype behavior and 16-layer limit remain.
- [ ] Existing `scene-info` and `scene-render-info` command names remain.
- [ ] Old Core format/audit implementation and tests are removed.
- [ ] No compatibility facade, typealias, or re-export remains.
- [ ] Focused tests pass.
- [ ] Full `swift test` passes with zero failures.
- [ ] No `swift build`, GUI, packaging, notarization, or `dist` operation runs.
- [ ] S2, Metal, Native Scene, Scene fallback, and SceneScript/effect execution are not started.
