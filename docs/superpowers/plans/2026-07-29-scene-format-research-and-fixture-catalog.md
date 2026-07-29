# Scene Format Research and Fixture Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scene.pkg`를 렌더링 전에 안전하게 조사하고, package/TEX/object/dependency/script 기능을 deterministic report로 만드는 internal `SceneAudit` API와 재현 가능한 fixture catalog를 구현한다.

**Architecture:** S0는 기존 `MacWallCore` Scene parser 위에 read-only audit contract를 먼저 고정한다. Texture payload는 decode하지 않고 bounded metadata reader로 순회하며, Scene JSON은 별도 inspector가 object, animation, dependency, script evidence를 수집한다. 최종 `MacWallSceneFormats`/`MacWallSceneAudit` target 분리는 S1에서 수행하므로 이번 단계에서는 `Package.swift` 의존성 변경이나 임시 역방향 target을 만들지 않는다.

**Tech Stack:** Swift 6, Foundation, XCTest, `JSONSerialization`, `Codable`, existing `ScenePackageReader`, local-only Workshop fixtures.

## Global Constraints

- 설계 기준은 `docs/superpowers/specs/2026-07-29-scene-engine-design.md`입니다.
- S0는 internal audit API와 tests만 구현하며 새 `macwallctl` command를 추가하지 않습니다.
- 실제 Workshop `scene.pkg`, texture, shader, screenshot을 Git에 추가하지 않습니다.
- `test/` 아래 local fixture는 read-only compatibility input으로만 사용합니다.
- Git에는 Swift로 생성하는 synthetic fixture와 aggregate JSON catalog만 저장합니다.
- `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`를 Scene output이나 fallback source로 사용하지 않습니다.
- 현재 `CALayer` Scene renderer의 기능을 확장하지 않습니다.
- Metal renderer, Native Scene surface, Scene fallback, effect execution, SceneScript execution을 시작하지 않습니다.
- Wallpaper Engine built-in asset, shader, texture를 repository나 app bundle에 복사하지 않습니다.
- GPL implementation code를 복사하지 않습니다. 외부 project는 format/behavior 비교에만 사용합니다.
- 기존 `ScenePackageReader`, `SceneTextureDecoder`, `SceneRenderPlanBuilder` public behavior와 tests를 보존합니다.
- Unknown version, flag, format, object, dependency를 조용히 제거하지 않고 raw value와 diagnostic을 report합니다.
- Audit output에는 absolute local path, 사용자 이름, package payload를 기록하지 않습니다.
- 자동 검증은 focused `swift test`, 전체 `swift test`, 정적 검색만 사용합니다.
- `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행, package, DMG, notarization, `dist` 작업을 하지 않습니다.

---

## File Structure

새 파일:

- `Sources/MacWallCore/Scene/SceneAuditModels.swift`
  - versioned report model, feature/support enums, canonical JSON encoder
- `Sources/MacWallCore/Scene/SceneTextureMetadata.swift`
  - TEX header/container/image/mipmap/animation metadata만 bounded parse
- `Sources/MacWallCore/Scene/SceneJSONInspector.swift`
  - Scene object, animation, parent/instance, asset reference, script handler evidence 수집
- `Sources/MacWallCore/Scene/SceneAuditor.swift`
  - package, texture, JSON evidence를 정렬하고 support/diagnostic을 report로 조립
- `Tests/MacWallCoreTests/SceneAuditModelsTests.swift`
  - schema, support precedence, canonical JSON determinism
- `Tests/MacWallCoreTests/SceneTextureMetadataTests.swift`
  - TEXB0003/TEXB0004, multi-image/mip, animated, unknown/truncated metadata
- `Tests/MacWallCoreTests/SceneAuditorTests.swift`
  - synthetic package object/dependency/script/invalid input audit
- `Tests/MacWallCoreTests/SceneLocalFixtureAuditTests.swift`
  - local fixture가 있으면 tracked aggregate catalog와 비교
- `Tests/Fixtures/SceneAudit/local-scene-catalog.json`
  - 저작물 payload를 포함하지 않는 fixture별 aggregate 기대값

수정 파일:

- `Sources/MacWallCore/Scene/SceneTexture.swift`
  - 기존 internal binary reader에 allocation 없는 bounded `skip(count:)` 추가
- `Tests/MacWallCoreTests/Fixture.swift`
  - 기존 call site를 보존하면서 versioned PKG와 multi-image TEX synthetic data 생성 지원
- `docs/development-roadmap.md`
  - S0 구현/검증 상태와 다음 S1 gate 기록
- `docs/development-log.md`
  - 구현 내용, fixture 결과, 검증 명령 기록
- `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
  - S0 completion evidence 링크 추가
- `docs/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md`
  - 실행 중 checkbox와 최종 검증 결과 갱신

S0에서는 다음 파일을 수정하지 않습니다.

- `Package.swift`
- `Sources/MacWallApp/Playback/SceneWallpaperView.swift`
- `Sources/MacWallCore/Scene/SceneRenderPlan.swift`
- `MacWallNativeWallpaperExtension/`
- `Sources/MacWallApp/Playback/NativeWallpaperBackend.swift`

---

### Task 1: Versioned Audit Contract와 Canonical JSON

**Files:**

- Create: `Sources/MacWallCore/Scene/SceneAuditModels.swift`
- Create: `Tests/MacWallCoreTests/SceneAuditModelsTests.swift`

**Interfaces:**

- Produces: `SceneAuditReport.schemaVersion == 1`
- Produces: `SceneAuditReportEncoder.encode(_:) throws -> Data`
- Produces: `SceneAuditSupportPolicy.s0`
- Produces: `SceneAuditSupportPolicy.evaluate(features:diagnostics:) -> SceneAuditStatus`
- Consumed by: Tasks 2-4

- [x] **Step 1: Write failing model and encoding tests**

Create `Tests/MacWallCoreTests/SceneAuditModelsTests.swift`:

```swift
import Foundation
import XCTest
@testable import MacWallCore

final class SceneAuditModelsTests: XCTestCase {
    func testS0SupportPolicyUsesStableSeverityPrecedence() {
        let exact = [
            SceneAuditFeatureObservation(
                key: .packageIndex,
                count: 1,
                support: .exact
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: exact,
                diagnostics: []
            ),
            .exact
        )

        let degraded = exact + [
            SceneAuditFeatureObservation(
                key: .imageLayer,
                count: 1,
                support: .degraded
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: degraded,
                diagnostics: []
            ),
            .degraded
        )

        let unsupported = degraded + [
            SceneAuditFeatureObservation(
                key: .particleSystem,
                count: 1,
                support: .unsupported
            )
        ]
        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: unsupported,
                diagnostics: []
            ),
            .unsupported
        )

        XCTAssertEqual(
            SceneAuditSupportPolicy.s0.evaluate(
                features: exact,
                diagnostics: [
                    SceneAuditDiagnostic(
                        severity: .error,
                        code: "package.invalid",
                        path: nil,
                        message: "invalid"
                    )
                ]
            ),
            .invalid
        )
    }

    func testCanonicalEncoderIsStableAndContainsNoAbsolutePath() throws {
        let report = SceneAuditReport(
            package: SceneAuditPackageSummary(
                version: "PKGV0008",
                entryCount: 2
            ),
            canvas: SceneAuditCanvas(width: 1920, height: 1080),
            entryKinds: [
                SceneAuditCount(name: "texture", count: 1),
                SceneAuditCount(name: "json", count: 1)
            ],
            objectKinds: [
                SceneAuditCount(name: "image", count: 1)
            ],
            textures: [],
            dependencies: [],
            scriptHandlers: [],
            features: [
                SceneAuditFeatureObservation(
                    key: .imageLayer,
                    count: 1,
                    support: .degraded
                )
            ],
            diagnostics: [],
            status: .degraded
        )

        let first = try SceneAuditReportEncoder.encode(report)
        let second = try SceneAuditReportEncoder.encode(report)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix(Data([0x0A])))
        let string = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertFalse(string.contains("/Users/"))
        XCTAssertLessThan(
            try XCTUnwrap(string.range(of: #""json""#)?.lowerBound),
            try XCTUnwrap(string.range(of: #""texture""#)?.lowerBound)
        )
    }
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SceneAuditModelsTests
```

Expected: compile failure because `SceneAuditReport` and related types do not exist.

- [x] **Step 3: Add the report model**

Create `Sources/MacWallCore/Scene/SceneAuditModels.swift` with these exact
public model names:

```swift
import Foundation

public enum SceneAuditStatus: String, Codable, Equatable, Sendable {
    case exact
    case degraded
    case unsupported
    case invalid
}

public enum SceneAuditFeatureSupport: String, Codable, Equatable, Sendable {
    case exact
    case degraded
    case unsupported
    case unknown
}

public enum SceneAuditFeatureKey: String, Codable, CaseIterable, Sendable {
    case packageIndex
    case textureMetadata
    case imageLayer
    case textLayer
    case particleSystem
    case soundLayer
    case modelLayer
    case unknownObject
    case parentGraph
    case instance
    case animatedProperty
    case animatedTexture
    case videoTexture
    case effect
    case customShader
    case sceneScript
    case unresolvedAsset
}

public struct SceneAuditFeatureObservation: Codable, Equatable, Sendable {
    public let key: SceneAuditFeatureKey
    public let count: Int
    public let support: SceneAuditFeatureSupport

    public init(
        key: SceneAuditFeatureKey,
        count: Int,
        support: SceneAuditFeatureSupport
    ) {
        self.key = key
        self.count = count
        self.support = support
    }
}

public struct SceneAuditCount: Codable, Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct SceneAuditPackageSummary: Codable, Equatable, Sendable {
    public let version: String?
    public let entryCount: Int

    public init(version: String?, entryCount: Int) {
        self.version = version
        self.entryCount = entryCount
    }
}

public struct SceneAuditCanvas: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum SceneAuditDependencyResolution: String, Codable, Equatable, Sendable {
    case package
    case builtInCandidate
    case unresolved
}

public struct SceneAuditDependency: Codable, Equatable, Sendable {
    public let ownerPath: String
    public let key: String
    public let requestedPath: String
    public let resolvedPath: String?
    public let resolution: SceneAuditDependencyResolution

    public init(
        ownerPath: String,
        key: String,
        requestedPath: String,
        resolvedPath: String?,
        resolution: SceneAuditDependencyResolution
    ) {
        self.ownerPath = ownerPath
        self.key = key
        self.requestedPath = requestedPath
        self.resolvedPath = resolvedPath
        self.resolution = resolution
    }
}

public enum SceneAuditDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct SceneAuditDiagnostic: Codable, Equatable, Sendable {
    public let severity: SceneAuditDiagnosticSeverity
    public let code: String
    public let path: String?
    public let message: String

    public init(
        severity: SceneAuditDiagnosticSeverity,
        code: String,
        path: String?,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}
```

Add the texture model now so Task 2 does not redefine the contract:

```swift
public struct SceneAuditTextureSummary: Codable, Equatable, Sendable {
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
    public let effectiveContainer: String
    public let imageFormatRawValue: Int?
    public let isVideoMP4: Bool
    public let imageCount: Int
    public let mipmapCounts: [Int]
    public let animationVersion: String?
    public let animationFrameCount: Int
}

public struct SceneAuditReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

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

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        package: SceneAuditPackageSummary,
        canvas: SceneAuditCanvas?,
        entryKinds: [SceneAuditCount],
        objectKinds: [SceneAuditCount],
        textures: [SceneAuditTextureSummary],
        dependencies: [SceneAuditDependency],
        scriptHandlers: [SceneAuditCount],
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic],
        status: SceneAuditStatus
    ) {
        self.schemaVersion = schemaVersion
        self.package = package
        self.canvas = canvas
        self.entryKinds = entryKinds.sorted { $0.name < $1.name }
        self.objectKinds = objectKinds.sorted { $0.name < $1.name }
        self.textures = textures.sorted { $0.path < $1.path }
        self.dependencies = dependencies.sorted {
            ($0.ownerPath, $0.key, $0.requestedPath)
                < ($1.ownerPath, $1.key, $1.requestedPath)
        }
        self.scriptHandlers = scriptHandlers.sorted { $0.name < $1.name }
        self.features = features.sorted { $0.key.rawValue < $1.key.rawValue }
        self.diagnostics = diagnostics.sorted {
            ($0.severity.rawValue, $0.code, $0.path ?? "", $0.message)
                < ($1.severity.rawValue, $1.code, $1.path ?? "", $1.message)
        }
        self.status = status
    }
}
```

- [x] **Step 4: Add S0 support policy and canonical encoder**

Append:

```swift
public struct SceneAuditSupportPolicy: Sendable {
    public static let s0 = Self()

    public func evaluate(
        features: [SceneAuditFeatureObservation],
        diagnostics: [SceneAuditDiagnostic]
    ) -> SceneAuditStatus {
        if diagnostics.contains(where: { $0.severity == .error }) {
            return .invalid
        }
        if features.contains(where: {
            $0.support == .unsupported || $0.support == .unknown
        }) {
            return .unsupported
        }
        if diagnostics.contains(where: { $0.severity == .warning }) {
            return .degraded
        }
        if features.contains(where: { $0.support == .degraded }) {
            return .degraded
        }
        return .exact
    }
}

public enum SceneAuditReportEncoder {
    public static func encode(_ report: SceneAuditReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(report)
        data.append(0x0A)
        return data
    }
}
```

- [x] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter SceneAuditModelsTests
```

Expected: `SceneAuditModelsTests` passes.

- [x] **Step 6: Commit the audit contract**

```bash
git add Sources/MacWallCore/Scene/SceneAuditModels.swift Tests/MacWallCoreTests/SceneAuditModelsTests.swift
git commit -m "feat(scene): define audit report contract"
```

---

### Task 2: Bounded TEX Metadata Reader

**Files:**

- Create: `Sources/MacWallCore/Scene/SceneTextureMetadata.swift`
- Create: `Tests/MacWallCoreTests/SceneTextureMetadataTests.swift`
- Modify: `Sources/MacWallCore/Scene/SceneTexture.swift:402-447`
- Modify: `Tests/MacWallCoreTests/Fixture.swift:38-83`

**Interfaces:**

- Consumes: `SceneAuditTextureSummary`
- Produces: `SceneTextureMetadataReader.read(path:data:) throws -> SceneAuditTextureSummary`
- Preserves: `Fixture.texData(width:height:imageFormat:imageData:)`
- Consumed by: `SceneAuditor` in Task 3

- [x] **Step 1: Extend the synthetic TEX builder without breaking existing tests**

Keep the existing `Fixture.texData(width:height:imageFormat:imageData:)`
signature and implement it as a convenience wrapper over:

```swift
struct TextureImageFixture {
    let mipmaps: [Data]
}

static func texData(
    version: String = "TEXV0005",
    infoVersion: String = "TEXI0001",
    format: Int = 0,
    flags: Int = 0,
    width: Int,
    height: Int,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil,
    container: String = "TEXB0003",
    imageFormat: Int = 13,
    isVideoMP4: Bool = false,
    images: [TextureImageFixture],
    animationVersion: String? = nil,
    animationFrameCount: Int = 0
) -> Data
```

For non-video `TEXB0003` and `TEXB0004`, each mip uses:

```text
width Int32
height Int32
lz4Flag Int32 = 0
decompressedSize Int32 = payload.count
byteCount Int32
payload bytes
```

For `TEXB0004`, write `isVideoMP4 ? 1 : 0` after `imageFormat`.
When `isVideoMP4 == true`, write `1`, `2`, a null-terminated `{}` condition,
and `1` before each mip's width and height.

When `animationVersion` is present, append its null-terminated magic and
`animationFrameCount`. Append GIF width and height for `TEXS0003`, then append
exactly 32 zero bytes per frame.

The existing convenience function must continue generating one
`TEXB0003` image with one mip and the same byte layout as before.

- [x] **Step 2: Write failing metadata tests**

Create `Tests/MacWallCoreTests/SceneTextureMetadataTests.swift`:

```swift
import Foundation
import XCTest
@testable import MacWallCore

final class SceneTextureMetadataTests: XCTestCase {
    func testReadsTEXB0003ImagesMipsAndUnknownRawValues() throws {
        let data = Fixture.texData(
            format: 777,
            flags: 0x402,
            width: 8,
            height: 8,
            imageWidth: 7,
            imageHeight: 6,
            images: [
                TextureImageFixture(mipmaps: [Data([1]), Data([2])]),
                TextureImageFixture(mipmaps: [Data([3])]),
            ]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/sample.tex",
            data: data
        )

        XCTAssertEqual(metadata.path, "materials/sample.tex")
        XCTAssertEqual(metadata.version, "TEXV0005")
        XCTAssertEqual(metadata.infoVersion, "TEXI0001")
        XCTAssertEqual(metadata.formatRawValue, 777)
        XCTAssertEqual(metadata.flagsRawValue, 0x402)
        XCTAssertEqual(metadata.declaredContainer, "TEXB0003")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0003")
        XCTAssertEqual(metadata.imageCount, 2)
        XCTAssertEqual(metadata.mipmapCounts, [2, 1])
        XCTAssertEqual(metadata.imageWidth, 7)
        XCTAssertEqual(metadata.imageHeight, 6)
    }

    func testTEXB0004NonVideoUsesVersion3MipmapLayout() throws {
        let data = Fixture.texData(
            flags: 2,
            width: 4,
            height: 4,
            container: "TEXB0004",
            imageFormat: -1,
            isVideoMP4: false,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/modern.tex",
            data: data
        )

        XCTAssertEqual(metadata.declaredContainer, "TEXB0004")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0003")
        XCTAssertFalse(metadata.isVideoMP4)
        XCTAssertEqual(metadata.mipmapCounts, [1])
    }

    func testTEXB0004VideoUsesVersion4MipmapLayout() throws {
        let data = Fixture.texData(
            format: 0,
            flags: 32,
            width: 4,
            height: 4,
            container: "TEXB0004",
            imageFormat: -1,
            isVideoMP4: true,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/video.tex",
            data: data
        )

        XCTAssertEqual(metadata.declaredContainer, "TEXB0004")
        XCTAssertEqual(metadata.effectiveContainer, "TEXB0004")
        XCTAssertTrue(metadata.isVideoMP4)
        XCTAssertEqual(metadata.mipmapCounts, [1])
    }

    func testReadsAnimatedTextureFrameMetadata() throws {
        let data = Fixture.texData(
            flags: 4,
            width: 2,
            height: 2,
            images: [TextureImageFixture(mipmaps: [Data([0, 0, 0, 0])])],
            animationVersion: "TEXS0003",
            animationFrameCount: 2
        )

        let metadata = try SceneTextureMetadataReader().read(
            path: "materials/animated.tex",
            data: data
        )

        XCTAssertEqual(metadata.animationVersion, "TEXS0003")
        XCTAssertEqual(metadata.animationFrameCount, 2)
    }

    func testTruncatedMipmapPayloadFailsWithoutDecode() {
        var data = Fixture.texData(
            width: 2,
            height: 2,
            images: [TextureImageFixture(mipmaps: [Data([1, 2, 3, 4])])]
        )
        data.removeLast()

        XCTAssertThrowsError(
            try SceneTextureMetadataReader().read(
                path: "materials/truncated.tex",
                data: data
            )
        ) { error in
            XCTAssertEqual(error as? SceneTextureError, .truncatedTexture)
        }
    }
}
```

- [x] **Step 3: Run metadata tests and verify RED**

Run:

```bash
swift test --filter SceneTextureMetadataTests
```

Expected: compile failure because `SceneTextureMetadataReader` and the extended
fixture types do not exist.

- [x] **Step 4: Add allocation-free binary skipping**

Add to `SceneTextureBinaryReader` in `SceneTexture.swift`:

```swift
mutating func skip(count: Int) throws {
    guard count >= 0, data.count - offset >= count else {
        throw SceneTextureError.truncatedTexture
    }
    offset += count
}
```

Metadata inspection must call `skip(count:)`, not `readData(count:)`, for mip
payloads and animation frame records.

- [x] **Step 5: Implement the metadata reader**

Create `SceneTextureMetadata.swift`.

Declare `SceneTextureMetadataReader` as a public `Sendable` struct with
`public init()` and this exact method:

```swift
public func read(
    path: String,
    data: Data
) throws -> SceneAuditTextureSummary
```

Required limits:

```swift
private static let maximumImageCount = 4_096
private static let maximumMipmapCount = 32
private static let maximumFrameCount = 100_000
private static let animationFrameRecordBytes = 32
```

Required parse order:

```swift
var reader = SceneTextureBinaryReader(data: data)
let version = try reader.readCString(maxLength: 32)
let infoVersion = try reader.readCString(maxLength: 32)
let format = try reader.readInt()
let flags = try reader.readInt()
let textureWidth = try reader.readInt()
let textureHeight = try reader.readInt()
let imageWidth = try reader.readInt()
let imageHeight = try reader.readInt()
_ = try reader.readUInt32()
let declaredContainer = try reader.readCString(maxLength: 32)
let imageCount = try reader.readInt()
```

Container behavior:

- `TEXB0001` and `TEXB0002`: no image-format field.
- `TEXB0003`: read one image-format `Int32`.
- `TEXB0004`: read image-format and `isVideoMP4` `Int32`.
- `TEXB0004` with `isVideoMP4 == false` uses the `TEXB0003` mip layout but
  preserves `declaredContainer == "TEXB0004"`.
- Unknown container throws `.unsupportedContainer`.

For every image, read and validate `mipmapCount`. For each mip:

- Version 1: width, height, byte count, payload skip.
- Version 2/3: width, height, LZ4 flag, decompressed size, byte count, payload skip.
- Effective Version 4 video: two parameter integers, condition JSON C string,
  one parameter integer, then Version 3 dimensions/compression/size/payload.

When `flags & 4 != 0`, read `TEXS0001`, `TEXS0002`, or `TEXS0003`, validate
frame count, read GIF width/height for `TEXS0003`, then skip exactly
`frameCount * 32` bytes with overflow checking.

Do not reject unknown texture format or flag values. Store raw values.

- [x] **Step 6: Run metadata and existing decoder tests**

Run:

```bash
swift test --filter SceneTextureMetadataTests
swift test --filter SceneTextureDecoderTests
```

Expected: both suites pass. Existing texture decode behavior is unchanged.

- [x] **Step 7: Commit metadata inspection**

```bash
git add Sources/MacWallCore/Scene/SceneTexture.swift Sources/MacWallCore/Scene/SceneTextureMetadata.swift Tests/MacWallCoreTests/Fixture.swift Tests/MacWallCoreTests/SceneTextureMetadataTests.swift
git commit -m "feat(scene): inspect texture metadata"
```

---

### Task 3: Scene JSON, Dependency, Script, and Package Auditor

**Files:**

- Create: `Sources/MacWallCore/Scene/SceneJSONInspector.swift`
- Create: `Sources/MacWallCore/Scene/SceneAuditor.swift`
- Create: `Tests/MacWallCoreTests/SceneAuditorTests.swift`

**Interfaces:**

- Consumes: `ScenePackageReader`, `SceneTextureMetadataReader`
- Produces: `SceneAuditor.audit(url:) -> SceneAuditReport`
- Produces: `SceneJSONInspector.inspect(scene:documents:package:) -> SceneJSONAuditEvidence`
- Preserves: `ScenePackageAnalyzer.analyze(url:)`
- Consumed by: local fixture tests in Task 4

- [x] **Step 1: Write failing end-to-end audit tests**

Create `Tests/MacWallCoreTests/SceneAuditorTests.swift` with:

```swift
import Foundation
import XCTest
@testable import MacWallCore

final class SceneAuditorTests: XCTestCase {
    func testAuditsObjectsTexturesDependenciesAndScripts() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        let texture = Fixture.texData(
            format: 4,
            flags: 2,
            width: 4,
            height: 4,
            images: [TextureImageFixture(mipmaps: [Data(repeating: 0, count: 16)])]
        )
        let sceneJSON = """
        {
          "general": {
            "orthogonalprojection": { "width": 1920, "height": 1080 }
          },
          "objects": [
            {
              "id": 1,
              "name": "background",
              "image": "models/background.json",
              "effects": [{"file": "effects/missing/effect.json"}]
            },
            {
              "id": 2,
              "parent": 1,
              "particle": "particles/snow.json",
              "script": "export function update() {}"
            },
            {
              "id": 3,
              "instance": 1,
              "mystery": "unknown"
            }
          ]
        }
        """
        try Fixture.writeScenePackage(
            to: packageURL,
            sceneJSON: sceneJSON,
            extraEntries: [
                (
                    path: "models/background.json",
                    data: Data(#"{"material":"materials/background.json"}"#.utf8)
                ),
                (
                    path: "materials/background.json",
                    data: Data(
                        #"{"passes":[{"shader":"genericimage4","textures":["background"]}]}"#.utf8
                    )
                ),
                (path: "materials/background.tex", data: texture),
            ]
        )

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.package.version, "PKGV0007")
        XCTAssertEqual(report.package.entryCount, 4)
        XCTAssertEqual(report.canvas, SceneAuditCanvas(width: 1920, height: 1080))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: report.objectKinds.map {
                ($0.name, $0.count)
            }),
            ["image": 1, "particle": 1, "unknown": 1]
        )
        XCTAssertEqual(report.textures.map(\.formatRawValue), [4])
        XCTAssertTrue(report.features.contains {
            $0.key == .parentGraph && $0.count == 1
        })
        XCTAssertTrue(report.features.contains {
            $0.key == .instance && $0.count == 1
        })
        XCTAssertEqual(
            report.scriptHandlers,
            [SceneAuditCount(name: "update", count: 1)]
        )
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "models/background.json"
                && $0.resolution == .package
        })
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "genericimage4"
                && $0.resolution == .builtInCandidate
        })
        XCTAssertTrue(report.dependencies.contains {
            $0.requestedPath == "effects/missing/effect.json"
                && $0.resolution == .unresolved
        })
        XCTAssertEqual(report.status, .unsupported)
    }

    func testInvalidPackageReturnsInvalidReportInsteadOfThrowing() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        try Data("not-a-package".utf8).write(to: packageURL)

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.status, .invalid)
        XCTAssertNil(report.package.version)
        XCTAssertEqual(report.package.entryCount, 0)
        XCTAssertEqual(report.diagnostics.first?.severity, .error)
        XCTAssertEqual(
            report.diagnostics.first?.code,
            "package.invalid-string-length"
        )
        XCTAssertFalse(
            report.diagnostics.first?.message.contains(root.path) ?? true
        )
    }

    func testUnsafeEntryPathBecomesStableInvalidDiagnostic() throws {
        let root = try Fixture.makeTempDirectory()
        let packageURL = root.appending(path: "scene.pkg")
        try Fixture.scenePackageData(entries: [
            (path: "../escape.json", data: Data())
        ]).write(to: packageURL)

        let report = SceneAuditor().audit(url: packageURL)

        XCTAssertEqual(report.status, .invalid)
        XCTAssertEqual(
            report.diagnostics.map(\.code),
            ["package.unsafe-entry-path"]
        )
        XCTAssertFalse(
            report.diagnostics[0].message.contains("../escape.json")
        )
    }

    func testAuditJSONIsIndependentOfPackageEntryOrdering() throws {
        let root = try Fixture.makeTempDirectory()
        let firstURL = root.appending(path: "first.pkg")
        let secondURL = root.appending(path: "second.pkg")
        let scene = Data(#"{"objects":[]}"#.utf8)
        let material = Data(#"{"passes":[]}"#.utf8)
        try Fixture.scenePackageData(entries: [
            (path: "scene.json", data: scene),
            (path: "materials/a.json", data: material),
        ]).write(to: firstURL)
        try Fixture.scenePackageData(entries: [
            (path: "materials/a.json", data: material),
            (path: "scene.json", data: scene),
        ]).write(to: secondURL)

        let first = try SceneAuditReportEncoder.encode(
            SceneAuditor().audit(url: firstURL)
        )
        let second = try SceneAuditReportEncoder.encode(
            SceneAuditor().audit(url: secondURL)
        )

        XCTAssertEqual(first, second)
    }
}
```

- [x] **Step 2: Run auditor tests and verify RED**

Run:

```bash
swift test --filter SceneAuditorTests
```

Expected: compile failure because `SceneAuditor` and `SceneJSONInspector` do not
exist.

- [x] **Step 3: Implement JSON evidence collection**

Create `SceneJSONInspector.swift` with an internal Sendable evidence model:

```swift
struct SceneJSONAuditEvidence: Sendable {
    var canvas: SceneAuditCanvas?
    var objectKinds: [String: Int] = [:]
    var featureCounts: [SceneAuditFeatureKey: Int] = [:]
    var dependencies: [SceneAuditDependency] = []
    var scriptHandlers: [String: Int] = [:]
    var diagnostics: [SceneAuditDiagnostic] = []
}
```

`SceneJSONInspector.inspect(scene:documents:package:)` receives parsed
`scene.json`, every successfully parsed packaged JSON keyed by owner path, and
the package index. It must:

1. Read integer canvas dimensions from
   `general.orthogonalprojection.width/height`.
2. Classify each top-level object exactly once in this order:
   `image`, `text`, `particle`, `sound`, `model`, otherwise `unknown`.
3. Count `parent`, `instance` or `instanceoverride`.
4. Recursively detect dictionaries containing `animation`.
5. Recursively collect inline strings under a `script` key from every parsed
   JSON document.
6. Count handler names with:

```swift
let handlerPattern =
    #"(?:export\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#
```

7. Collect asset references from every parsed JSON document, preserving its
   owner path, only for this key allowlist:

```swift
private static let assetReferenceKeys: Set<String> = [
    "effect",
    "file",
    "font",
    "image",
    "material",
    "model",
    "particle",
    "shader",
    "sound",
    "texture",
    "textures",
]
```

Array values under `textures` are inspected item by item. Other arbitrary
strings are not treated as paths.

Feature count semantics:

- `.effect`: packaged effect definition JSON count, not layer usage count.
- `.customShader`: packaged `.vert` and `.frag` entry count.
- `.sceneScript`: inline value count under `script` keys, not handler count.
- `.parentGraph`: top-level object count containing `parent`.
- `.instance`: top-level object count containing `instance` or
  `instanceoverride`.
- `.animatedProperty`: object count containing at least one nested
  `animation`.
- `.unresolvedAsset`: unresolved dependency count.

Dependency resolution rules for S0:

- Exact package path exists: `.package`.
- Texture basename `background`: try `materials/background.tex`,
  `background.tex`, then raw path.
- Shader name without slash or extension: `.builtInCandidate`.
- Path beginning `util/`, `models/util/`, `shaders/` and absent from package:
  `.builtInCandidate`.
- Every other absent candidate: `.unresolved`.

Do not read optional external Wallpaper Engine assets in S0.
Every `.unresolved` dependency increments `.unresolvedAsset`.

- [x] **Step 4: Implement package-level orchestration**

Create `SceneAuditor.swift`:

```swift
public struct SceneAuditor: Sendable {
    private let packageReader: ScenePackageReader
    private let textureReader: SceneTextureMetadataReader
    private let supportPolicy: SceneAuditSupportPolicy

    public init(
        packageReader: ScenePackageReader = ScenePackageReader(),
        textureReader: SceneTextureMetadataReader = SceneTextureMetadataReader(),
        supportPolicy: SceneAuditSupportPolicy = .s0
    ) {
        self.packageReader = packageReader
        self.textureReader = textureReader
        self.supportPolicy = supportPolicy
    }

    public func audit(url: URL) -> SceneAuditReport {
        do {
            return try audit(package: packageReader.read(url: url))
        } catch {
            return invalidReport(for: error)
        }
    }
}
```

The valid path must:

- Require `scene.json`.
- Parse every `.json` entry with `JSONSerialization`; malformed auxiliary JSON
  creates `json.malformed` warning and continues, while malformed `scene.json`
  is an error.
- Classify package entries by lowercased extension:
  `json`, `texture`, `vertexShader`, `fragmentShader`, `font`, `audio`,
  `video`, `other`.
- Add `.effect` using packaged `effects/**/*.json` definition count.
- Add `.customShader` using packaged `.vert` plus `.frag` entry count.
- Call `SceneTextureMetadataReader` for every `.tex`.
- Convert a texture metadata failure into a
  `texture.metadata-invalid` warning with package-relative path and add one
  `.textureMetadata` observation with `.unknown` support for each failure.
- Preserve raw format/flag values in successful summaries.
- Add `.animatedTexture` for texture flags containing bit `4` and
  `.videoTexture` for flags containing bit `32` or `isVideoMP4 == true`.
- Merge JSON evidence from `SceneJSONInspector`.
- Add one `.textureMetadata` feature per readable texture.
- Assign S0 feature support:
  - `packageIndex`, `textureMetadata`: `.exact`
  - `imageLayer`, `animatedProperty`: `.degraded`
  - text, particle, sound, model, unknown, parent, instance, animated/video
    texture, effect, custom shader, SceneScript, unresolved asset:
    `.unsupported`
- Use `SceneAuditSupportPolicy` for overall status.
- Never include `url.path` or `error.localizedDescription` if it contains an
  absolute input path. Map errors to stable code and generic message.

Map `ScenePackageError` to these stable codes:

| Error | Code |
| --- | --- |
| `unsupportedMagic` | `package.unsupported-magic` |
| `packageTooLarge` | `package.too-large` |
| `invalidEntryCount` | `package.invalid-entry-count` |
| `invalidStringLength` | `package.invalid-string-length` |
| `truncatedPackage` | `package.truncated` |
| `unsafeEntryPath` | `package.unsafe-entry-path` |
| `invalidEntryRange` | `package.invalid-entry-range` |
| `missingSceneJSON` | `scene.missing-json` |
| `malformedSceneJSON` | `scene.malformed-json` |
| every other error | `package.io` |

Do not put associated path/magic/count values into invalid diagnostic messages.
The invalid report shape is:

```swift
SceneAuditReport(
    package: SceneAuditPackageSummary(version: nil, entryCount: 0),
    canvas: nil,
    entryKinds: [],
    objectKinds: [],
    textures: [],
    dependencies: [],
    scriptHandlers: [],
    features: [],
    diagnostics: [
        SceneAuditDiagnostic(
            severity: .error,
            code: stableCode(for: error),
            path: nil,
            message: "Scene package audit failed."
        )
    ],
    status: .invalid
)
```

- [x] **Step 5: Run focused Scene audit regression**

Run:

```bash
swift test --filter SceneAuditorTests
swift test --filter ScenePackageTests
swift test --filter SceneRenderPlanTests
```

Expected: all focused tests pass and existing Scene parsing behavior remains
unchanged.

- [x] **Step 6: Commit the package auditor**

```bash
git add Sources/MacWallCore/Scene/SceneJSONInspector.swift Sources/MacWallCore/Scene/SceneAuditor.swift Tests/MacWallCoreTests/SceneAuditorTests.swift
git commit -m "feat(scene): audit package features"
```

---

### Task 4: Local Fixture Catalog와 Compatibility Regression

**Files:**

- Create: `Tests/Fixtures/SceneAudit/local-scene-catalog.json`
- Create: `Tests/MacWallCoreTests/SceneLocalFixtureAuditTests.swift`

**Interfaces:**

- Consumes: `SceneAuditor.audit(url:)`
- Produces: schema-versioned aggregate catalog for three local fixture IDs
- Does not produce: package extraction, copied texture/shader, CLI output

- [x] **Step 1: Add the tracked aggregate catalog**

Create `Tests/Fixtures/SceneAudit/local-scene-catalog.json`:

```json
{
  "fixtures": [
    {
      "entryCount": 107,
      "features": {
        "effect": 7,
        "sceneScript": 0
      },
      "objectKinds": {
        "image": 23,
        "particle": 3,
        "sound": 2
      },
      "packageVersion": "PKGV0008",
      "textureContainers": {
        "TEXB0003": 37
      },
      "textureFlags": {
        "0": 1,
        "2": 32,
        "7": 4
      },
      "textureFormats": {
        "0": 37
      },
      "workshopID": "2174863503"
    },
    {
      "entryCount": 387,
      "features": {
        "effect": 16,
        "sceneScript": 2
      },
      "objectKinds": {
        "image": 88,
        "particle": 3,
        "sound": 5,
        "text": 2
      },
      "packageVersion": "PKGV0018",
      "textureContainers": {
        "TEXB0003": 136
      },
      "textureFlags": {
        "0": 2,
        "2": 133,
        "34": 1
      },
      "textureFormats": {
        "0": 78,
        "8": 39,
        "9": 19
      },
      "workshopID": "2834933421"
    },
    {
      "entryCount": 125,
      "features": {
        "effect": 12,
        "instance": 31,
        "parentGraph": 53,
        "sceneScript": 119
      },
      "objectKinds": {
        "image": 49,
        "particle": 7,
        "sound": 1,
        "text": 11,
        "unknown": 1
      },
      "packageVersion": "PKGV0023",
      "textureContainers": {
        "TEXB0003": 16,
        "TEXB0004": 11
      },
      "textureFlags": {
        "0": 1,
        "2": 22,
        "6": 4
      },
      "textureFormats": {
        "0": 4,
        "4": 18,
        "8": 1,
        "9": 4
      },
      "workshopID": "3516106265"
    }
  ],
  "schemaVersion": 1
}
```

This file contains counts only. Do not add package hash, local path, title,
preview, texture name, shader source, script source, or extracted payload.

- [x] **Step 2: Write the local-only compatibility test**

Create `SceneLocalFixtureAuditTests.swift` with private Codable catalog models.
Resolve repository root from `#filePath`, not current working directory:

```swift
private var repositoryRoot: URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
```

The test must:

1. Decode the tracked catalog.
2. For each fixture, resolve
   `repositoryRoot/test/<workshopID>/scene.pkg`.
3. If no listed fixture exists, throw one `XCTSkip`.
4. If a fixture exists, audit it and compare package version, entry count,
   object counts, texture format, raw flags, declared container counts, and
   listed feature counts.
5. Assert no diagnostic message contains repository root or `/Users/`.
6. Assert the report can be encoded twice to identical bytes.

Use a helper that converts arrays to count dictionaries:

```swift
private func counts(_ values: [SceneAuditCount]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0.count) })
}
```

Feature counts are built from `report.features` using
`feature.key.rawValue`.

- [x] **Step 3: Run local fixture audit**

Run:

```bash
swift test --filter SceneLocalFixtureAuditTests
```

Expected on the current machine: all three local fixtures are audited and
match the tracked aggregate catalog.

Expected on a clean checkout without `test/`: one explicit skipped test, not
a failure.

If an expected count differs, inspect whether the inspector missed a
well-defined JSON shape or whether the catalog research value was wrong.
Fix the parser or catalog using direct fixture evidence; do not weaken the
assertion or add an approximate range.

- [x] **Step 4: Verify no local fixture was staged**

Run:

```bash
git status --short
git ls-files test
```

Expected:

- No path under `test/` is staged or tracked.
- Only `Tests/Fixtures/SceneAudit/local-scene-catalog.json` and the Swift test
  are new for this task.

- [x] **Step 5: Commit the catalog gate**

```bash
git add Tests/Fixtures/SceneAudit/local-scene-catalog.json Tests/MacWallCoreTests/SceneLocalFixtureAuditTests.swift
git commit -m "test(scene): catalog local fixtures"
```

---

### Task 5: Documentation and Final Verification

**Files:**

- Modify: `docs/development-roadmap.md`
- Modify: `docs/development-log.md`
- Modify: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- Modify: `docs/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md`

**Interfaces:**

- Consumes: all S0 implementation and test evidence
- Produces: completed S0 record and explicit S1 next gate
- Preserves: S2+ implementation as unstarted

- [ ] **Step 1: Run all focused Scene tests**

Run:

```bash
swift test --filter SceneAuditModelsTests
swift test --filter SceneTextureMetadataTests
swift test --filter SceneAuditorTests
swift test --filter SceneLocalFixtureAuditTests
swift test --filter ScenePackageTests
swift test --filter SceneTextureDecoderTests
swift test --filter SceneRenderPlanTests
```

Expected: all focused tests pass. Local fixture test audits three fixtures on
the current machine.

- [ ] **Step 2: Run the complete Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Run repository safety and policy checks**

Run:

```bash
git diff --check
git ls-files test
rg -n "macwallctl scene-audit|preview\\.(gif|jpg).*fallback|thumbnail\\.jpg.*fallback|cover\\.png.*fallback" Sources Tests docs AGENTS.md
rg -n "SceneAuditor|SceneTextureMetadataReader|SceneAuditReportEncoder" Sources Tests
```

Expected:

- `git diff --check` prints nothing.
- `git ls-files test` prints nothing.
- No new CLI or thumbnail fallback implementation appears.
- Audit APIs appear only in `MacWallCore` Scene files and tests.

- [ ] **Step 4: Update the plan and design status**

In this plan:

- Mark completed task checkboxes.
- Record exact focused/full test counts.
- Record local fixture pass/skip count.
- Record that no GUI/build/package action ran.

In the design spec, add an `S0 implementation evidence` paragraph linking this
plan and the tracked catalog.

- [ ] **Step 5: Update roadmap and development log**

Roadmap:

- Mark S0 implemented.
- Keep S1 as the next implementation phase.
- State that S0 remains in `MacWallCore` only until S1 extracts
  `MacWallSceneFormats`/`MacWallSceneAudit`.
- Do not mark S2 or Metal work started.

Development log:

- Add KST timestamp.
- Record audit schema version, texture containers/formats, local fixture
  result, exact test count, and static checks.
- Record that no CLI, Metal, Native Scene, fallback, GUI, package, or `dist`
  work ran.

- [ ] **Step 6: Commit final S0 records**

```bash
git add docs/development-roadmap.md docs/development-log.md docs/superpowers/specs/2026-07-29-scene-engine-design.md docs/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md
git commit -m "docs: record scene format audit"
```

- [ ] **Step 7: Verify final implementation state**

Run:

```bash
git status --short --branch
git log --oneline -5
```

Expected:

- Working tree is clean.
- S0 has five focused commits:
  - `feat(scene): define audit report contract`
  - `feat(scene): inspect texture metadata`
  - `feat(scene): audit package features`
  - `test(scene): catalog local fixtures`
  - `docs: record scene format audit`
- No S1/S2/Metal implementation commit exists.

---

## Self-review Checklist

- [ ] Every design requirement assigned to S0 has a task.
- [ ] No CLI command or executable target is added.
- [ ] No real Workshop payload is tracked.
- [ ] TEX audit does not decode mip payloads and uses `skip(count:)` rather
  than creating an additional `Data` copy for each mip.
- [ ] `TEXB0004` non-video and video layouts are distinguished.
- [ ] Unknown raw values survive the report.
- [ ] Absolute local paths cannot enter JSON output.
- [ ] Report arrays and JSON keys are deterministic.
- [ ] Local fixture tests skip cleanly when fixtures are absent.
- [ ] Existing parser/decoder/render-plan tests remain unchanged and pass.
- [ ] S1 module extraction is not accidentally started in S0.
- [ ] Metal, Native Scene, Scene fallback, SceneScript execution remain out of scope.
