# Scene S3 GPU Texture Pipeline Implementation Plan

상태: implementation plan ready / implementation not started

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** S2 typed graph의 package texture resource를 bounded read로 준비하고, capability에 따라 raw/BC direct upload 또는 CPU/ImageIO fallback을 선택해 generation-owned immutable private `MTLTexture`로 공개하는 `MacWallSceneTextures` pipeline을 구현한다.

**Architecture:** `MacWallSceneTextures`를 Formats/Assets/Graph 위의 독립 target으로 추가하고 pure planner, bounded payload preparation, ImageIO normalization, direct Metal allocator, generation cache/store를 분리합니다. Store actor는 cache와 ownership만 소유하고 package read, LZ4/CPU decode, ImageIO, GPU completion wait는 actor executor 밖에서 실행합니다. S3는 renderer나 Desktop output을 만들지 않고 S4가 `SceneTextureLease`만 소비하게 합니다.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, Metal, CoreGraphics, ImageIO, XCTest, existing `MacWallSceneFormats`, `MacWallSceneAssets`, `MacWallSceneGraph`.

## Global Constraints

- 설계 기준은 `docs/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`입니다.
- Swift Package compile floor는 macOS 14+와 Swift 6을 유지합니다.
- S3 performance와 actual GPU acceptance는 Apple Silicon을 기준으로 하고, S5 Native Scene output은 macOS 26+ Apple Silicon으로 남깁니다.
- dependency 방향은 `MacWallSceneFormats -> MacWallSceneAssets -> MacWallSceneGraph -> MacWallSceneTextures`입니다.
- Formats/Assets/Graph target에 Metal, AppKit, AVFoundation 의존성을 추가하지 않습니다.
- `MacWallSceneTextures`는 Core/App/Native Wallpaper/CALayer prototype에 의존하지 않습니다.
- BC direct upload은 `MTLDevice.supportsBCTextureCompression == true`일 때만 사용하고 false에서는 existing software RGBA decoder로 fallback합니다.
- S3 production request는 static `images.count == 1`, `imageIndex == 0`만 허용합니다.
- supplied mip chain은 전부 atomic upload하고 mip을 임의로 생성하지 않습니다.
- animation, video, multi-image는 typed unsupported로 반환하고 S9 전에 실행하지 않습니다.
- format `0/8/9`는 RGBA8/RG8/R8 direct, `4/6/7`은 BC3/BC2/BC1 direct 또는 software fallback으로 mapping합니다.
- encoded image는 payload signature를 bounded read로 확인한 뒤 ImageIO/CoreGraphics로 straight RGBA8로 정규화합니다.
- malformed/truncated/extra payload를 fallback으로 숨기지 않고 exact byte-count validation으로 실패합니다.
- texture origin은 `topLeft`로 보존하고 S3에서 vertical flip하지 않습니다.
- default limits는 resident soft 384 MiB, resident hard 512 MiB, staging 128 MiB, decoded CPU 160 MiB, single payload 64 MiB, dimension 16,384, decoded pixels 18,000,000, decode concurrency 2, upload concurrency 2, upload timeout 10 seconds입니다.
- `MTLHeap`, sparse/placement texture, mip streaming, residency set을 S3에서 구현하지 않습니다.
- Scene renderer, Scene fallback, Video/Web, Main App, Native Wallpaper backend을 수정하지 않습니다.
- Workshop thumbnail, `preview.gif`, `preview.jpg`, `thumbnail.jpg`, `cover.png`를 texture/fallback source로 사용하지 않습니다.
- local `test/<id>/scene.pkg`는 read-only fixture로만 사용하고 Git에 추가하지 않습니다.
- 자동 검증은 focused/full `swift test`, `rg`, `git diff --check`, read-only fixture inspection만 사용합니다.
- `swift build`, `xcodebuild build`, 앱/GUI/System Settings 실행, package, DMG, notarization, `dist` 작업을 하지 않습니다.

---

## File Structure

새 production target:

- `Sources/MacWallSceneTextures/SceneTextureModels.swift`
  - public request, lease, error, limit, snapshot model
- `Sources/MacWallSceneTextures/SceneTextureCapabilities.swift`
  - pure GPU capability value와 Metal format mapping
- `Sources/MacWallSceneTextures/SceneTextureLoadPlanner.swift`
  - static texture validation, format/path/mip/content plan
- `Sources/MacWallSceneTextures/SceneTexturePayloadLoader.swift`
  - bounded payload read, LZ4 expansion, exact validation, software RGBA fallback
- `Sources/MacWallSceneTextures/SceneTextureImageDecoder.swift`
  - encoded image signature와 straight RGBA8 ImageIO normalization
- `Sources/MacWallSceneTextures/SceneTextureMemoryBudget.swift`
  - staging/decoded/resident reservation과 peak accounting
- `Sources/MacWallSceneTextures/SceneTextureAllocator.swift`
  - prepared payload, staging layout, allocator contract, allocated artifact
- `Sources/MacWallSceneTextures/SceneTextureUploadExecutor.swift`
  - single-resume command completion/timeout gate
- `Sources/MacWallSceneTextures/DirectSceneTextureAllocator.swift`
  - shared staging buffer, private texture, blit, optional sRGB view
- `Sources/MacWallSceneTextures/SceneTextureCache.swift`
  - storage key, ready entry, generation owners, deterministic LRU
- `Sources/MacWallSceneTextures/SceneTextureStore.swift`
  - public actor, in-flight waiter dedupe, cancellation, cache publication
- `Sources/MacWallSceneTextures/SceneTexturePipelineLoader.swift`
  - resolver/descriptor/planner/payload/allocator production orchestration

새 tests:

- `Tests/MacWallSceneTexturesTests/SceneTextureModelsAndCapabilitiesTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTextureLoadPlannerTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTexturePayloadLoaderTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTextureImageDecoderTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTextureMemoryBudgetTests.swift`
- `Tests/MacWallSceneTexturesTests/DirectSceneTextureAllocatorTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTextureCacheTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTextureStoreTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneTexturePipelineIntegrationTests.swift`
- `Tests/MacWallSceneTexturesTests/SceneLocalFixtureTextureTests.swift`
- `Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json`

수정:

- `Package.swift`
  - `MacWallSceneTextures` production/test target
- `docs/README.md`
- `docs/development-log.md`
- `docs/development-roadmap.md`
- `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- `docs/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`

완료 단계에서 이동:

- `docs/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`
  -> `docs/archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`
- `docs/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md`
  -> `docs/archive/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md`

완료 기록:

- `docs/implemented/2026-08-06-scene-gpu-texture-pipeline.md`

`README.md`, `README.ko.md`, `Sources/MacWallCore`, `Sources/MacWallApp`,
`MacWallNativeWallpaperSpike`, `MacWall.xcodeproj`는 사용자 동작이 바뀌지
않으므로 수정하지 않습니다.

---

## Preflight

- [ ] **Step 1: Create an isolated S3 worktree**

Use `superpowers:using-git-worktrees` from the current
`experiment/fullscreen-auxiliary-window` HEAD and create branch
`feature/scene-s3-gpu-texture-pipeline`.

Expected: the new worktree starts at the commit containing this plan and has
no unrelated dirty files.

- [ ] **Step 2: Confirm the S2 baseline**

Run:

```bash
git status --short --branch
swift test --filter MacWallSceneFormatsTests
swift test --filter MacWallSceneAssetsTests
swift test --filter MacWallSceneGraphTests
```

Expected:

- intended feature branch is active
- Formats, Assets, Graph focused suites pass
- no S3 source file exists before Task 1

If unrelated user changes exist, preserve them and stage only files listed by
the current task.

---

### Task 1: Texture Target, Public Models, and Device Capabilities

**Files:**

- Modify: `Package.swift`
- Create: `Sources/MacWallSceneTextures/SceneTextureModels.swift`
- Create: `Sources/MacWallSceneTextures/SceneTextureCapabilities.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureModelsAndCapabilitiesTests.swift`

**Interfaces:**

- Consumes: `SceneResourceID`, `MTLDevice`
- Produces: `SceneTexturePackageID`, `SceneTextureGenerationID`
- Produces: `SceneTextureRequest`, `SceneTextureLease`
- Produces: `SceneTextureGPUFormat`, `SceneTextureDeviceCapabilities`
- Produces: `SceneTexturePipelineError`, `SceneTextureLimits`, `SceneTextureStoreSnapshot`
- Consumed by: Tasks 2-10

- [ ] **Step 1: Add the target declarations and failing model tests**

Add to `Package.swift`:

```swift
.target(
    name: "MacWallSceneTextures",
    dependencies: [
        "MacWallSceneGraph",
        "MacWallSceneAssets",
        "MacWallSceneFormats"
    ]
),
.testTarget(
    name: "MacWallSceneTexturesTests",
    dependencies: [
        "MacWallSceneTextures",
        "MacWallSceneGraph",
        "MacWallSceneAssets",
        "MacWallSceneFormats",
        "MacWallSceneTestSupport"
    ]
),
```

Create tests that assert exact defaults and value semantics:

```swift
import Metal
import XCTest
@testable import MacWallSceneTextures

final class SceneTextureModelsAndCapabilitiesTests: XCTestCase {
    func testDefaultLimitsMatchS3Contract() {
        let limits = SceneTextureLimits()
        XCTAssertEqual(limits.residentSoftBytes, 384 * 1_024 * 1_024)
        XCTAssertEqual(limits.residentHardBytes, 512 * 1_024 * 1_024)
        XCTAssertEqual(limits.stagingBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(limits.decodedCPUBytes, 160 * 1_024 * 1_024)
        XCTAssertEqual(limits.singlePayloadBytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(limits.maximumTextureDimension, 16_384)
        XCTAssertEqual(limits.maximumDecodedPixels, 18_000_000)
        XCTAssertEqual(limits.maximumConcurrentDecodes, 2)
        XCTAssertEqual(limits.maximumConcurrentUploads, 2)
        XCTAssertEqual(limits.uploadTimeout, .seconds(10))
    }

    func testCapabilityValueDoesNotInferFromArchitecture() {
        let value = SceneTextureDeviceCapabilities(
            supportsBCTextureCompression: false,
            linearTextureAlignment: [.rgba8Unorm: 64]
        )
        XCTAssertFalse(value.supportsBCTextureCompression)
        XCTAssertEqual(value.linearTextureAlignment[.rgba8Unorm], 64)
    }

    func testPackageAndGenerationIDsAreIndependent() {
        let raw = UUID()
        XCTAssertNotEqual(
            SceneTexturePackageID(rawValue: raw),
            SceneTexturePackageID(rawValue: UUID())
        )
        XCTAssertEqual(
            SceneTextureGenerationID(rawValue: raw).rawValue,
            raw
        )
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureModelsAndCapabilitiesTests
```

Expected: compile failure because the S3 models do not exist.

- [ ] **Step 3: Implement the public value contract**

Define these declarations in `SceneTextureModels.swift`:

```swift
import Foundation
import Metal
import MacWallSceneGraph
import MacWallSceneFormats

public struct SceneTexturePackageID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct SceneTextureGenerationID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum SceneTextureColorIntent: String, Hashable, Sendable {
    case colorSRGB
    case dataLinear
}

public struct SceneTextureRequest: Hashable, Sendable {
    public let packageID: SceneTexturePackageID
    public let resourceID: SceneResourceID
    public let imageIndex: Int
    public let colorIntent: SceneTextureColorIntent

    public init(
        packageID: SceneTexturePackageID,
        resourceID: SceneResourceID,
        imageIndex: Int,
        colorIntent: SceneTextureColorIntent
    ) {
        self.packageID = packageID
        self.resourceID = resourceID
        self.imageIndex = imageIndex
        self.colorIntent = colorIntent
    }
}

public struct SceneTextureExtent: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct SceneTextureContentRect: Equatable, Sendable {
    public let u: Float
    public let v: Float
    public let width: Float
    public let height: Float
    public init(u: Float, v: Float, width: Float, height: Float) {
        self.u = u
        self.v = v
        self.width = width
        self.height = height
    }
}

public enum SceneTextureOrigin: String, Sendable { case topLeft }

public enum SceneTextureGPUFormat: String, CaseIterable, Hashable, Sendable {
    case rgba8Unorm
    case rg8Unorm
    case r8Unorm
    case bc1RGBA
    case bc2RGBA
    case bc3RGBA
}

public enum SceneTextureUploadPath: String, Codable, Hashable, Sendable {
    case directUncompressed
    case directBlockCompressed
    case softwareRGBA
    case encodedImageRGBA
}

public enum SceneTextureLimit: String, Equatable, Sendable {
    case residentBytes
    case stagingBytes
    case decodedCPUBytes
    case payloadBytes
    case textureDimension
    case decodedPixels
}

public enum SceneTexturePipelineError: Error, Equatable, Sendable {
    case invalidRequest
    case unsupportedDescriptor(SceneTextureUnsupportedKind)
    case unsupportedAnimation
    case unsupportedVideo
    case unsupportedMultiImage
    case unsupportedPixelFormat(Int)
    case malformedDescriptor
    case malformedPayload
    case resourceLimit(SceneTextureLimit)
    case decodeFailed
    case allocationFailed
    case uploadFailed
    case uploadTimedOut
    case cancelled
}

public struct SceneTextureLimits: Equatable, Sendable {
    public var residentSoftBytes: Int
    public var residentHardBytes: Int
    public var stagingBytes: Int
    public var decodedCPUBytes: Int
    public var singlePayloadBytes: Int
    public var maximumTextureDimension: Int
    public var maximumDecodedPixels: Int
    public var maximumConcurrentDecodes: Int
    public var maximumConcurrentUploads: Int
    public var uploadTimeout: Duration

    public init(
        residentSoftBytes: Int = 384 * 1_024 * 1_024,
        residentHardBytes: Int = 512 * 1_024 * 1_024,
        stagingBytes: Int = 128 * 1_024 * 1_024,
        decodedCPUBytes: Int = 160 * 1_024 * 1_024,
        singlePayloadBytes: Int = 64 * 1_024 * 1_024,
        maximumTextureDimension: Int = 16_384,
        maximumDecodedPixels: Int = 18_000_000,
        maximumConcurrentDecodes: Int = 2,
        maximumConcurrentUploads: Int = 2,
        uploadTimeout: Duration = .seconds(10)
    ) {
        self.residentSoftBytes = residentSoftBytes
        self.residentHardBytes = residentHardBytes
        self.stagingBytes = stagingBytes
        self.decodedCPUBytes = decodedCPUBytes
        self.singlePayloadBytes = singlePayloadBytes
        self.maximumTextureDimension = maximumTextureDimension
        self.maximumDecodedPixels = maximumDecodedPixels
        self.maximumConcurrentDecodes = maximumConcurrentDecodes
        self.maximumConcurrentUploads = maximumConcurrentUploads
        self.uploadTimeout = uploadTimeout
    }
}

public struct SceneTextureLease: @unchecked Sendable {
    public let texture: any MTLTexture
    public let storageExtent: SceneTextureExtent
    public let contentExtent: SceneTextureExtent
    public let contentRect: SceneTextureContentRect
    public let origin: SceneTextureOrigin
    public let mipmapLevelCount: Int
    public let residentBytes: Int
}
```

`SceneTextureStoreSnapshot`은 schema version 1과 다음 aggregate current/peak/count만
`Equatable`, `Sendable`로 노출합니다.

```swift
public struct SceneTextureStoreSnapshot: Equatable, Sendable {
    public let schemaVersion: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let inFlightDedupeHits: Int
    public let readyEntries: Int
    public let loadingEntries: Int
    public let unownedEntries: Int
    public let residentBytes: Int
    public let peakResidentBytes: Int
    public let stagingBytes: Int
    public let peakStagingBytes: Int
    public let decodedCPUBytes: Int
    public let peakDecodedCPUBytes: Int
    public let evictions: Int
    public let resourceLimitFailures: Int
    public let uploadPathCounts: [SceneTextureUploadPath: Int]
    public let unsupportedCounts: [String: Int]
}
```

In `SceneTextureCapabilities.swift`, define a pure value and Metal mapping:

```swift
public struct SceneTextureDeviceCapabilities: Equatable, Sendable {
    public let supportsBCTextureCompression: Bool
    public let linearTextureAlignment: [SceneTextureGPUFormat: Int]

    public init(
        supportsBCTextureCompression: Bool,
        linearTextureAlignment: [SceneTextureGPUFormat: Int]
    ) {
        self.supportsBCTextureCompression = supportsBCTextureCompression
        self.linearTextureAlignment = linearTextureAlignment
    }
}

extension SceneTextureDeviceCapabilities {
    init(device: any MTLDevice) {
        let formats = SceneTextureGPUFormat.allCases
        self.init(
            supportsBCTextureCompression:
                device.supportsBCTextureCompression,
            linearTextureAlignment: Dictionary(
                uniqueKeysWithValues: formats.map {
                    ($0, device.minimumLinearTextureAlignment(
                        for: $0.linearMetalPixelFormat
                    ))
                }
            )
        )
    }
}
```

Make `SceneTextureGPUFormat` conform to `CaseIterable` and map linear/sRGB
formats exactly:

```text
rgba8Unorm -> rgba8Unorm / rgba8Unorm_srgb
rg8Unorm   -> rg8Unorm / no sRGB view
r8Unorm    -> r8Unorm / no sRGB view
bc1RGBA    -> bc1_rgba / bc1_rgba_srgb
bc2RGBA    -> bc2_rgba / bc2_rgba_srgb
bc3RGBA    -> bc3_rgba / bc3_rgba_srgb
```

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureModelsAndCapabilitiesTests
```

Expected: all model/capability tests pass.

Commit:

```bash
git add Package.swift Sources/MacWallSceneTextures/SceneTextureModels.swift Sources/MacWallSceneTextures/SceneTextureCapabilities.swift Tests/MacWallSceneTexturesTests/SceneTextureModelsAndCapabilitiesTests.swift
git commit -m "feat(scene): add texture pipeline contracts"
```

---

### Task 2: Pure Static Texture Load Planner

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureLoadPlanner.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureLoadPlannerTests.swift`

**Interfaces:**

- Consumes: `SceneTextureDescriptor`, `SceneTextureColorIntent`, `SceneTextureDeviceCapabilities`, `SceneTextureLimits`
- Produces: `SceneTextureLoadPlan`, `SceneTextureMipPlan`, `SceneTexturePayloadStrategy`
- Consumed by: Tasks 3, 5, 9, 10

- [ ] **Step 1: Write failing planner tests**

Use `SceneTextureFixtureBuilder` plus `SceneTextureFormatReader` to create real
descriptors. Cover the exact matrix:

```swift
func testMapsKnownFormatsAndBCFallback() throws {
    let cases: [(Int32, Bool, SceneTextureGPUFormat, SceneTextureUploadPath)] = [
        (0, true, .rgba8Unorm, .directUncompressed),
        (8, true, .rg8Unorm, .directUncompressed),
        (9, true, .r8Unorm, .directUncompressed),
        (7, true, .bc1RGBA, .directBlockCompressed),
        (6, true, .bc2RGBA, .directBlockCompressed),
        (4, true, .bc3RGBA, .directBlockCompressed),
        (7, false, .rgba8Unorm, .softwareRGBA),
        (6, false, .rgba8Unorm, .softwareRGBA),
        (4, false, .rgba8Unorm, .softwareRGBA)
    ]

    for (raw, supportsBC, format, path) in cases {
        let plan = try planner(supportsBC: supportsBC).makePlan(
            descriptor: try descriptor(formatRawValue: raw),
            imageIndex: 0,
            colorIntent: .dataLinear
        )
        XCTAssertEqual(plan.storageFormat, format)
        XCTAssertEqual(plan.preferredUploadPath, path)
    }
}

func testCalculatesExactBlockBytesAndPaddedContentRect() throws {
    let plan = try planner(supportsBC: true).makePlan(
        descriptor: try descriptor(
            formatRawValue: 4,
            textureSize: (8, 8),
            imageSize: (6, 5),
            mipSizes: [(8, 8), (4, 4)]
        ),
        imageIndex: 0,
        colorIntent: .colorSRGB
    )
    XCTAssertEqual(plan.mips.map(\.expectedPayloadBytes), [64, 16])
    XCTAssertEqual(plan.storageExtent, .init(width: 8, height: 8))
    XCTAssertEqual(plan.contentExtent, .init(width: 6, height: 5))
    XCTAssertEqual(plan.contentRect.width, 0.75, accuracy: 0.0001)
    XCTAssertEqual(plan.contentRect.height, 0.625, accuracy: 0.0001)
    XCTAssertEqual(plan.mips[1].contentExtent, .init(width: 3, height: 3))
}
```

Add tests for:

- RGBA/RG/R exact byte counts and overflow
- `colorSRGB` rejection for R8/RG8
- `imageIndex != 0` rejection
- animation flag/descriptor -> `.unsupportedAnimation`
- video flag/metadata -> `.unsupportedVideo`
- multiple images -> `.unsupportedMultiImage`
- zero/negative/over-16,384 dimensions
- all supplied mips preserved in source order
- mip dimensions must equal Metal's `max(1, mip0Dimension >> level)` chain;
  incompatible dimensions or excessive levels -> `.malformedDescriptor`
- unknown format produces an internal encoded-image probe plan rather than an
  allocation; Task 3 must reject it unless every mip has an accepted signature

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureLoadPlannerTests
```

Expected: compile failure because planner types do not exist.

- [ ] **Step 3: Implement immutable planning types**

Define internal contracts:

```swift
enum SceneTexturePayloadStrategy: Equatable, Sendable {
    case exactUncompressed(bytesPerPixel: Int)
    case exactBlockCompressed(blockBytes: Int)
    case softwareBC(formatRawValue: Int)
    case encodedImageProbe(unknownFormatRawValue: Int)
}

struct SceneTextureMipPlan: Equatable, Sendable {
    let level: Int
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let payloadRange: Range<UInt64>
    let isLZ4Compressed: Bool
    let declaredDecompressedBytes: UInt64?
    let expectedPayloadBytes: Int?
    let unalignedBytesPerRow: Int?
}

struct SceneTextureLoadPlan: Equatable, Sendable {
    let storageFormat: SceneTextureGPUFormat
    let preferredUploadPath: SceneTextureUploadPath
    let payloadStrategy: SceneTexturePayloadStrategy
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
    let mips: [SceneTextureMipPlan]
    let supportsSRGBView: Bool
}

struct SceneTextureLoadPlanner: Sendable {
    let capabilities: SceneTextureDeviceCapabilities
    let limits: SceneTextureLimits

    func makePlan(
        descriptor: SceneTextureDescriptor,
        imageIndex: Int,
        colorIntent: SceneTextureColorIntent
    ) throws -> SceneTextureLoadPlan
}
```

Implementation order:

1. Reject animation when `descriptor.animation != nil` or flag bit `4` is set.
2. Reject video when `descriptor.isVideoMP4`, flag bit `32`, or any selected mip
   has non-nil video metadata.
3. Require exactly one image and `imageIndex == 0`.
4. Validate descriptor and every mip dimension in `1...16_384`.
5. Calculate raw/BC expected bytes with reporting-overflow operations.
6. Require every supplied level to match Metal's implicit 2D mip dimensions
   from level 0; a private `MTLTexture` cannot represent arbitrary per-level
   dimensions.
7. For mip level `n`, derive logical content extent by preserving the mip-0
   storage/content ratio with checked ceil division, then clamp to storage:

```text
contentWidth  = ceil(imageWidth  * mip.width  / textureWidth)
contentHeight = ceil(imageHeight * mip.height / textureHeight)
```

8. Select BC direct only from the injected capability value.
9. Mark unknown formats as `encodedImageProbe`; do not allocate or claim
   `encodedImageRGBA` until Task 3 verifies all payload signatures.
10. Permit `.colorSRGB` only when the final storage can expose a compatible
   sRGB view. R8/RG8 return `.invalidRequest`.
11. Preserve the complete supplied mip array; do not synthesize or discard a
    level.

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureLoadPlannerTests
```

Expected: all planner matrix, padding, overflow, and unsupported tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureLoadPlanner.swift Tests/MacWallSceneTexturesTests/SceneTextureLoadPlannerTests.swift
git commit -m "feat(scene): plan texture upload paths"
```

---

### Task 3: Bounded Payload Loading and Software BC Fallback

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTexturePayloadLoader.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTexturePayloadLoaderTests.swift`

**Interfaces:**

- Consumes: `SceneTextureLoadPlan`, `SceneTextureDescriptor`, `SceneByteSource`
- Consumes: `SceneLZ4BlockDecoder`, `SceneTextureSoftwareDecoder`
- Produces: `SceneTexturePreparedSource`, `SceneTexturePreparedMip`
- Consumed by: Tasks 4, 5, 6, 9

- [ ] **Step 1: Write failing bounded-read and exact-payload tests**

Create tests with `RecordingSceneByteSource` that assert:

```swift
func testDirectPayloadReadsEachMipOnceAndRequiresExactBytes() throws {
    let fixture = try parsedFixture(
        formatRawValue: 0,
        mipPayloads: [
            Data(repeating: 1, count: 16),
            Data(repeating: 2, count: 4)
        ],
        mipSizes: [(2, 2), (1, 1)]
    )
    fixture.recording.resetReadRanges()

    let result = try SceneTexturePayloadLoader().prepare(
        plan: fixture.plan,
        descriptor: fixture.descriptor,
        source: fixture.recording,
        limits: .init()
    )

    XCTAssertEqual(
        fixture.recording.readRanges,
        fixture.descriptor.images[0].mipmaps.map(\.payloadRange)
    )
    XCTAssertEqual(result.uploadPath, .directUncompressed)
    XCTAssertEqual(result.mips.map(\.bytes.count), [16, 4])
}
```

Also test:

- one byte short and one byte extra -> `.malformedPayload`
- LZ4 expands before exact validation and compressed/decompressed size limit
- BC direct keeps block bytes unchanged
- BC-disabled path calls software decode, then zero-pads cropped straight
  RGBA8 back to each physical mip extent while preserving logical content
- an unknown-format encoded-image probe with an accepted signature on every
  mip returns `.encodedImages`
- mixed encoded/raw mip representation -> `.malformedPayload`
- unknown format without accepted signature -> `.unsupportedPixelFormat(raw)`
- no read exceeds 64 MiB and no whole package source is requested
- cancellation before the next mip -> `.cancelled`

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTexturePayloadLoaderTests
```

Expected: compile failure because payload preparation types do not exist.

- [ ] **Step 3: Implement prepared source models and strict loading**

Define:

```swift
struct SceneTexturePreparedMip: Equatable, Sendable {
    let level: Int
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let unalignedBytesPerRow: Int
    let bytes: Data
}

enum SceneTexturePreparedSource: Equatable, Sendable {
    case upload(
        format: SceneTextureGPUFormat,
        uploadPath: SceneTextureUploadPath,
        mips: [SceneTexturePreparedMip]
    )
    case encodedImages([Data])

    var uploadPath: SceneTextureUploadPath { get }
}

struct SceneTexturePayloadLoader: Sendable {
    func prepare(
        plan: SceneTextureLoadPlan,
        descriptor: SceneTextureDescriptor,
        source: any SceneByteSource,
        limits: SceneTextureLimits
    ) throws -> SceneTexturePreparedSource
}
```

For every mip:

1. Check cancellation.
2. Reject a payload range larger than 64 MiB before reading.
3. Read exactly `payloadRange` from the bounded entry source.
4. If LZ4 is set, require a declared decompressed size within 64 MiB and call
   `SceneLZ4BlockDecoder`.
5. For `encodedImageProbe`, detect PNG, JPEG, GIF87a/GIF89a, RIFF/WEBP, and
   ISO-BMFF HEIC/HEIF/AVIF brands. Known raw/BC strategies remain strict and
   do not reinterpret arbitrary bytes as an encoded image.
6. Require every probed mip to have an accepted encoded signature.
7. For direct raw/BC, require `expanded.count == expectedPayloadBytes`.
8. For software BC, create a one-mip `SceneTextureDescriptor` and
   `SceneDataByteSource` from the already expanded bytes, set its logical
   dimensions to the planner's mip content extent, and invoke
   `SceneTextureSoftwareDecoder`. This avoids a second package read and crops
   padded storage deterministically. Copy the cropped rows into a zero-filled
   RGBA buffer sized to the planner's physical mip extent so all paths retain
   the same Metal-compatible mip chain and content rect.
9. Convert S1 format/resource errors into the bounded public S3 error
   categories without including paths or payloads.

Do not expose the internal encoded-image probe as a public upload path. It
becomes `.encodedImageRGBA` only after Task 4 successfully decodes every mip.

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTexturePayloadLoaderTests
```

Expected: all read-range, exact-size, LZ4, signature, and software fallback
tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTexturePayloadLoader.swift Tests/MacWallSceneTexturesTests/SceneTexturePayloadLoaderTests.swift
git commit -m "feat(scene): prepare bounded texture payloads"
```

---

### Task 4: ImageIO Straight-RGBA Normalization

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureImageDecoder.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureImageDecoderTests.swift`

**Interfaces:**

- Consumes: `.encodedImages`, `SceneTextureLoadPlan`
- Produces: `.upload(format: .rgba8Unorm, uploadPath: .encodedImageRGBA, ...)`
- Consumed by: Tasks 6 and 9

- [ ] **Step 1: Write failing decode tests**

Use a deterministic 2x1 PNG fixture containing one opaque and one
semi-transparent pixel. Assert:

```swift
func testDecodesEncodedMipToStraightSRGBA() throws {
    let decoded = try SceneTextureImageDecoder().decode(
        encodedMips: [encodedTwoPixelPNG],
        expectedContentExtents: [.init(width: 2, height: 1)],
        storageExtents: [.init(width: 2, height: 1)],
        limits: .init()
    )
    XCTAssertEqual(decoded.uploadPath, .encodedImageRGBA)
    XCTAssertEqual(decoded.mips[0].storageExtent, .init(width: 2, height: 1))
    XCTAssertEqual(decoded.mips[0].unalignedBytesPerRow, 8)
    XCTAssertEqual(Array(decoded.mips[0].bytes[0..<4]), [255, 0, 0, 255])
    XCTAssertEqual(Array(decoded.mips[0].bytes[4..<8]), [0, 255, 0, 128])
}
```

Add tests for:

- decoded dimensions must equal the planner's logical content extent
- invalid/truncated encoded data -> `.decodeFailed`
- decoded pixel and decoded CPU byte limits
- full encoded mip chain is preserved
- logical encoded pixels are zero-padded to larger physical storage extents
  without changing content extent
- a 1x2 top-red/bottom-blue source remains in that top-to-bottom byte order
- alpha-zero RGB is normalized to zero and semi-transparent RGB is
  unpremultiplied to straight alpha

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureImageDecoderTests
```

Expected: compile failure because the ImageIO decoder does not exist.

- [ ] **Step 3: Implement ImageIO/CoreGraphics normalization**

Define:

```swift
struct SceneTextureImageDecoder: Sendable {
    func decode(
        encodedMips: [Data],
        expectedContentExtents: [SceneTextureExtent],
        storageExtents: [SceneTextureExtent],
        limits: SceneTextureLimits
    ) throws -> SceneTexturePreparedSource
}
```

For each mip:

1. Create `CGImageSource` from bounded `Data` and decode image index 0 only.
2. Require exactly the expected logical width and height.
3. Draw into an sRGB, 8-bit, RGBA, premultiplied-last bitmap with row bytes
   `width * 4` using checked arithmetic. Apply the fixed CoreGraphics CTM
   needed to make the first output row the source image's top row; verify this
   with the 1x2 orientation test rather than applying a later S4 flip.
4. Convert premultiplied bytes to straight alpha. For alpha 0 set RGB to 0;
   for alpha 255 retain RGB; otherwise compute
   `min(255, (channel * 255 + alpha / 2) / alpha)`.
5. Copy normalized logical rows into a zero-filled RGBA buffer for the paired
   physical storage extent. Return one `.rgba8Unorm` prepared mip with distinct
   storage/content extents and upload path `.encodedImageRGBA`.
6. Never use `NSImage`, AppKit drawing, thumbnail data, or a detached AppKit
   object.

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureImageDecoderTests
```

Expected: all straight-alpha, dimensions, limits, and mip tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureImageDecoder.swift Tests/MacWallSceneTexturesTests/SceneTextureImageDecoderTests.swift
git commit -m "feat(scene): normalize encoded texture images"
```

---

### Task 5: Staging Layout and Memory Budget Reservations

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureMemoryBudget.swift`
- Create: `Sources/MacWallSceneTextures/SceneTextureAllocator.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureMemoryBudgetTests.swift`

**Interfaces:**

- Consumes: prepared mips, per-format device alignment, `SceneTextureLimits`
- Produces: `SceneTextureStagingLayout`, `SceneTextureAllocationPlan`
- Produces: `SceneTextureMemoryBudget`, `SceneTextureMemoryReservation`
- Produces: `SceneTextureAllocator`, `SceneAllocatedTexture`
- Consumed by: Tasks 6-10

- [ ] **Step 1: Write failing alignment and budget tests**

Cover uncompressed and block-compressed row counts without a Metal device:

```swift
func testStagingLayoutUsesInjectedDeviceAlignment() throws {
    let layout = try SceneTextureStagingLayout.make(
        format: .rgba8Unorm,
        mips: [
            preparedMip(width: 3, height: 2, rowBytes: 12),
            preparedMip(width: 1, height: 1, rowBytes: 4)
        ],
        minimumAlignment: 16
    )
    XCTAssertEqual(layout.mips[0].alignedBytesPerRow, 16)
    XCTAssertEqual(layout.mips[0].bytesPerImage, 32)
    XCTAssertEqual(layout.mips[1].offset, 32)
    XCTAssertEqual(layout.mips[1].alignedBytesPerRow, 16)
    XCTAssertEqual(layout.totalBytes, 48)
}

func testBCLayoutCountsBlockRowsInsteadOfPixelRows() throws {
    let layout = try SceneTextureStagingLayout.make(
        format: .bc3RGBA,
        mips: [preparedMip(width: 8, height: 5, rowBytes: 32)],
        minimumAlignment: 64
    )
    XCTAssertEqual(layout.mips[0].blockOrPixelRowCount, 2)
    XCTAssertEqual(layout.mips[0].bytesPerImage, 128)
}
```

Add budget tests for:

- staging reservation at exactly 128 MiB succeeds; one byte over fails
- decoded reservation at exactly 160 MiB succeeds; one byte over fails
- resident reservations enforce 512 MiB hard limit
- `resize` replaces any estimate with actual held bytes and rechecks its cap
- current and peak counts update independently
- failure/cancellation release every reservation
- unknown token and double release return internal invariant errors
- checked additions never wrap

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureMemoryBudgetTests
```

Expected: compile failure because staging and budget types do not exist.

- [ ] **Step 3: Implement allocator boundary and pure staging layout**

Define in `SceneTextureAllocator.swift`:

```swift
struct SceneTextureStagingMip: Equatable, Sendable {
    let level: Int
    let offset: Int
    let alignedBytesPerRow: Int
    let blockOrPixelRowCount: Int
    let bytesPerImage: Int
    let copySize: SceneTextureExtent
}

struct SceneTextureStagingLayout: Equatable, Sendable {
    let mips: [SceneTextureStagingMip]
    let totalBytes: Int

    static func make(
        format: SceneTextureGPUFormat,
        mips: [SceneTexturePreparedMip],
        minimumAlignment: Int
    ) throws -> SceneTextureStagingLayout
}

struct SceneTextureAllocationPlan: Sendable {
    let format: SceneTextureGPUFormat
    let uploadPath: SceneTextureUploadPath
    let mips: [SceneTexturePreparedMip]
    let stagingLayout: SceneTextureStagingLayout
    let supportsSRGBView: Bool
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
}

struct SceneAllocatedTexture: @unchecked Sendable {
    let linearTexture: any MTLTexture
    let srgbTexture: (any MTLTexture)?
    let uploadPath: SceneTextureUploadPath
    let storageExtent: SceneTextureExtent
    let contentExtent: SceneTextureExtent
    let contentRect: SceneTextureContentRect
    let origin: SceneTextureOrigin
    let mipmapLevelCount: Int
    let residentBytes: Int
}

struct SceneTexturePreparedLoad: Sendable {
    let allocationPlan: SceneTextureAllocationPlan
    let estimatedResidentBytes: Int
    let decodedReservation: SceneTextureMemoryReservation?
}

protocol SceneTextureAllocator: Sendable {
    func allocate(
        _ plan: SceneTextureAllocationPlan,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture
}

final class SceneTextureSubmissionState: @unchecked Sendable {
    private let lock = NSLock()
    private var submitted = false

    var wasSubmitted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return submitted
    }

    func markSubmitted() {
        lock.lock()
        submitted = true
        lock.unlock()
    }
}
```

Layout rules:

1. `minimumAlignment` must be positive and a power of two; otherwise return
   `.allocationFailed`.
2. Align every row stride with checked arithmetic.
3. RGBA/RG/R row count is pixel height.
4. BC row count is `ceil(height / 4)` and unaligned row bytes already reflect
   `ceil(width / 4) * blockBytes`.
5. Align each mip offset to the same device-provided alignment.
6. Copy only logical payload bytes row-by-row; zero-fill alignment padding.
7. Do not hardcode 64, 128, or 256-byte Metal alignment.

- [ ] **Step 4: Implement reservation accounting**

Define a lock-protected synchronous ledger. This lets the synchronous
actor-isolated `snapshot()` and `releaseGeneration()` methods update/read
accounting without awaiting a second actor while detached decode/upload work
can reserve concurrently:

```swift
enum SceneTextureMemoryKind: Hashable, Sendable {
    case resident
    case staging
    case decodedCPU
}

struct SceneTextureMemoryReservation: Hashable, Sendable {
    let rawValue: UUID
    let kind: SceneTextureMemoryKind
}

struct SceneTextureMemorySnapshot: Equatable, Sendable {
    let residentBytes: Int
    let peakResidentBytes: Int
    let stagingBytes: Int
    let peakStagingBytes: Int
    let decodedCPUBytes: Int
    let peakDecodedCPUBytes: Int
}

enum SceneTextureMemoryInvariantError: Error, Equatable, Sendable {
    case unknownReservation
    case reservationKindMismatch
}

final class SceneTextureMemoryBudget: @unchecked Sendable {
    init(limits: SceneTextureLimits)

    func reserve(
        _ bytes: Int,
        kind: SceneTextureMemoryKind
    ) throws -> SceneTextureMemoryReservation

    func resize(
        _ reservation: SceneTextureMemoryReservation,
        actualBytes: Int
    ) throws

    func release(
        _ reservation: SceneTextureMemoryReservation
    ) throws

    func snapshot() -> SceneTextureMemorySnapshot
}
```

Use reservation UUIDs to make rollback idempotence mistakes observable. Public
limit failures map to `.resourceLimit(.residentBytes/.stagingBytes/
.decodedCPUBytes)`; unknown or mismatched tokens use an internal Equatable
`SceneTextureMemoryInvariantError` and are never converted into a successful
release. Protect the complete check-and-mutate operation with one `NSLock`;
never call user code or Metal while holding that lock. Add a concurrent test
that races reservations below the configured aggregate cap and proves current
bytes never exceed the cap.

- [ ] **Step 5: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureMemoryBudgetTests
```

Expected: all alignment, exact boundary, peak, reconciliation, and invariant
tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureAllocator.swift Sources/MacWallSceneTextures/SceneTextureMemoryBudget.swift Tests/MacWallSceneTexturesTests/SceneTextureMemoryBudgetTests.swift
git commit -m "feat(scene): bound texture staging memory"
```

---

### Task 6: Direct Private Metal Texture Allocator

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureUploadExecutor.swift`
- Create: `Sources/MacWallSceneTextures/DirectSceneTextureAllocator.swift`
- Create: `Tests/MacWallSceneTexturesTests/DirectSceneTextureAllocatorTests.swift`

**Interfaces:**

- Consumes: `MTLDevice`, `MTLCommandQueue`, `SceneTextureAllocationPlan`
- Produces: `DirectSceneTextureAllocator`, `SceneAllocatedTexture`
- Consumed by: Tasks 9 and 10

- [ ] **Step 1: Write failing upload-executor tests**

Inject completion registration and sleep instead of waiting on a real
command buffer in unit tests:

```swift
func testUploadExecutorAcceptsExactlyOneSuccessfulCompletion() async throws {
    let executor = SceneTextureUploadExecutor()
    try await executor.execute(timeout: .seconds(10)) { finish in
        finish(.success(()))
        finish(.failure(SceneTexturePipelineError.uploadFailed))
    }
}

func testUploadExecutorTimesOutWhenCommandNeverCompletes() async {
    let executor = SceneTextureUploadExecutor(
        sleeper: ImmediateSleeper()
    )
    await XCTAssertThrowsErrorAsync(
        try await executor.execute(timeout: .seconds(10)) { _ in }
    ) { error in
        XCTAssertEqual(error as? SceneTexturePipelineError, .uploadTimedOut)
    }
}
```

Add a failure-completion test and a cancellation test. The completion gate
must ignore late callbacks after timeout without resuming a continuation twice.
Define `ImmediateSleeper` in this test file so `sleep(for:)` returns
immediately. Define a private `XCTAssertThrowsErrorAsync` helper in this test
file with this exact shape:

```swift
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}
```

- [ ] **Step 2: Write failing headless Metal allocation tests**

Use `MTLCreateSystemDefaultDevice()` without a window. The approved Apple
Silicon environment must execute, not skip, these assertions:

```swift
func testUploadsRGBA8ToPrivateTextureAndReadsItBack() async throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let allocator = try DirectSceneTextureAllocator(
        device: device,
        limits: .init()
    )
    let bytes = Data([255, 0, 0, 255, 0, 255, 0, 255])
    let artifact = try await allocator.allocate(
        allocationPlan(
            format: .rgba8Unorm,
            width: 2,
            height: 1,
            mipBytes: [bytes],
            colorView: true
        ),
        submission: SceneTextureSubmissionState()
    )

    XCTAssertEqual(artifact.linearTexture.storageMode, .private)
    XCTAssertEqual(artifact.linearTexture.mipmapLevelCount, 1)
    XCTAssertNotNil(artifact.srgbTexture)
    XCTAssertEqual(try readBack(artifact.linearTexture), bytes)
}
```

Add actual GPU tests for:

- R8 and RG8 direct upload/readback with no sRGB view
- RGBA8 two-mip upload/readback
- BC1/BC2/BC3 compressed-byte upload/readback when
  `supportsBCTextureCompression` is true
- compatible RGBA/BC sRGB texture views share the same allocation
- missing command queue/buffer/encoder/texture/buffer -> `.allocationFailed`
- command buffer `.error` -> `.uploadFailed`
- artifact is returned only after completion callback

If no Metal device exists, throw `XCTSkip` only for this synthetic GPU test
class. The approved completion machine requires zero skips.

- [ ] **Step 3: Run RED**

Run:

```bash
swift test --filter DirectSceneTextureAllocatorTests
```

Expected: compile failure because executor and allocator do not exist.

- [ ] **Step 4: Implement the single-resume upload executor**

Define:

```swift
protocol SceneTextureSleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SceneTextureUploadExecutor: Sendable {
    init(sleeper: any SceneTextureSleeper = ContinuousSceneTextureSleeper())

    func execute(
        timeout: Duration,
        submit: @escaping @Sendable (
            @escaping @Sendable (Result<Void, Error>) -> Void
        ) -> Void
    ) async throws
}
```

Use a lock-protected `SceneTextureUploadCompletionGate` to resolve exactly
once from command completion, timeout, or task cancellation. The timeout path
returns `.uploadTimedOut`; a late Metal callback performs no state mutation.

- [ ] **Step 5: Implement direct allocation and blit**

`DirectSceneTextureAllocator` must:

1. Create its command queue during initialization and fail explicitly if nil.
2. Query `minimumLinearTextureAlignment(for:)` for the actual linear Metal
   format, recompute the expected `SceneTextureStagingLayout`, and require it
   to equal the plan built during production prepare. This prevents budget and
   allocator alignment from diverging.
3. Reserve a `.storageModeShared` staging buffer and copy each payload row into
   its aligned offset, leaving padding zeroed.
4. Create one `.type2D`, `.private`, `.shaderRead` texture with the full mip
   count. Add `.pixelFormatView` only for RGBA/BC compatible views.
5. Encode every mip with the buffer-to-texture blit API using its own offset,
   bytes-per-row, bytes-per-image, and storage extent.
6. End encoding, add the completion handler, call
   `submission.markSubmitted()` immediately before `commandBuffer.commit()`,
   commit, and await the executor.
7. Create the sRGB view after successful completion only.
8. Set `residentBytes` from `linearTexture.allocatedSize`; do not serialize this
   hardware-dependent value into fixture catalogs.
9. Return no artifact on failure or timeout. Let the command buffer retain its
   submitted resources until its eventual completion handler runs.

- [ ] **Step 6: Run GREEN and commit**

Run:

```bash
swift test --filter DirectSceneTextureAllocatorTests
```

Expected: executor unit tests and actual private texture readback tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureUploadExecutor.swift Sources/MacWallSceneTextures/DirectSceneTextureAllocator.swift Tests/MacWallSceneTexturesTests/DirectSceneTextureAllocatorTests.swift
git commit -m "feat(scene): upload private Metal textures"
```

---

### Task 7: Generation-Owned Texture Cache and Deterministic LRU

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureCache.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureCacheTests.swift`

**Interfaces:**

- Consumes: package/resource/entry/device identities and allocated artifacts
- Produces: `SceneTextureStorageKey`, `SceneTextureCache<Value>`
- Consumed by: Tasks 8-10

- [ ] **Step 1: Write failing key and ownership tests**

Use a small `FakeTextureValue` so pure cache tests do not require Metal:

```swift
func testCacheKeyIncludesEveryStorageIdentityFieldButNotColorIntent() {
    let base = key(
        package: packageA,
        path: "materials/a.tex",
        offset: 10,
        bytes: 20,
        imageIndex: 0,
        policyVersion: 1,
        deviceRegistryID: 99
    )
    XCTAssertEqual(
        base,
        key(
            package: packageA,
            path: "materials/a.tex",
            offset: 10,
            bytes: 20,
            imageIndex: 0,
            policyVersion: 1,
            deviceRegistryID: 99
        )
    )
    XCTAssertNotEqual(
        base,
        key(
            package: packageB,
            path: "materials/a.tex",
            offset: 10,
            bytes: 20,
            imageIndex: 0,
            policyVersion: 1,
            deviceRegistryID: 99
        )
    )
    XCTAssertNotEqual(
        base,
        key(
            package: packageA,
            path: "materials/a.tex",
            offset: 11,
            bytes: 20,
            imageIndex: 0,
            policyVersion: 1,
            deviceRegistryID: 100
        )
    )
}

func testOwnedEntryCannotBeEvictedUntilGenerationRelease() throws {
    var cache = SceneTextureCache<FakeTextureValue>()
    cache.install(value(bytes: 100), for: keyA, owner: generationA)
    XCTAssertTrue(cache.trimUnowned(toResidentBytes: 0).isEmpty)

    cache.releaseGeneration(generationA)
    XCTAssertEqual(
        cache.trimUnowned(toResidentBytes: 0).map(\.key),
        [keyA]
    )
}
```

Add tests for:

- same key adds multiple generation owners without duplicate resident bytes
- release removes only the requested generation
- LRU uses monotonic access ordinal, then stable key ordering for ties
- soft trim evicts only unowned entries
- old active generation survives installation failure of a staged generation
- cache hit updates last access and hit counters
- failed values are never installed
- snapshot ready/unowned/resident/eviction values are deterministic

Define the private `key(package:path:offset:bytes:imageIndex:policyVersion:
deviceRegistryID:)` helper in this test file as a direct
`SceneTextureStorageKey` initializer. Construct two `SceneTextureRequest`
values with different color intents and assert that both derive this same
storage key; do not add color to `SceneTextureStorageKey`.

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureCacheTests
```

Expected: compile failure because cache types do not exist.

- [ ] **Step 3: Implement the storage key and generic cache**

Define:

```swift
struct SceneTextureStorageKey: Hashable, Comparable, Sendable {
    let packageID: SceneTexturePackageID
    let canonicalPath: String
    let entryRelativeOffset: UInt64
    let entryByteCount: UInt64
    let imageIndex: Int
    let uploadPolicyVersion: Int
    let deviceRegistryID: UInt64
}

struct SceneTextureCache<Value: Sendable>: Sendable {
    struct ReadyEntry: Sendable {
        let value: Value
        let residentBytes: Int
        var owners: Set<SceneTextureGenerationID>
        var lastAccessOrdinal: UInt64
        let uploadPath: SceneTextureUploadPath
    }

    mutating func value(
        for key: SceneTextureStorageKey,
        owner: SceneTextureGenerationID
    ) -> Value?

    mutating func install(
        _ value: Value,
        residentBytes: Int,
        uploadPath: SceneTextureUploadPath,
        for key: SceneTextureStorageKey,
        owner: SceneTextureGenerationID
    )

    mutating func releaseGeneration(_ generation: SceneTextureGenerationID)

    mutating func trimUnowned(
        toResidentBytes target: Int
    ) -> [(key: SceneTextureStorageKey, value: Value, residentBytes: Int)]
}
```

`Comparable` must compare a stable tuple of UUID string, canonical path,
offset, byte count, image index, policy version, and device ID. It exists only
for deterministic eviction/snapshot ordering; public diagnostics must not
emit the canonical path.

- [ ] **Step 4: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureCacheTests
```

Expected: all key, owner, release, LRU, and snapshot tests pass.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureCache.swift Tests/MacWallSceneTexturesTests/SceneTextureCacheTests.swift
git commit -m "feat(scene): cache textures by generation"
```

---

### Task 8: Async Store Dedupe, Cancellation, and Atomic Publication

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTextureStore.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTextureStoreTests.swift`

**Interfaces:**

- Consumes: `SceneTextureCache`, `SceneTexturePipelineLoading`, `SceneTextureMemoryBudget`
- Produces: public `SceneTextureStore` actor API
- Produces: internal waiter/in-flight state machine
- Consumed by: Tasks 9 and 10, later S4

- [ ] **Step 1: Write a controllable fake pipeline and failing store tests**

Define a test actor whose `prepare` and `allocate` calls can be independently
suspended, completed, failed, and counted. Write tests for:

```swift
func testConcurrentSameStorageKeyLoadsOnce() async throws {
    let fake = ControllableTexturePipeline()
    let store = SceneTextureStore(testPipeline: fake, limits: .init())
    let generationA = await store.makeGeneration()
    let generationB = await store.makeGeneration()

    async let first = store.acquire(
        request(.dataLinear),
        resource: packageTextureResource,
        resolver: resolver,
        for: generationA
    )
    async let second = store.acquire(
        request(.colorSRGB),
        resource: packageTextureResource,
        resolver: resolver,
        for: generationB
    )

    await fake.waitForPrepareCount(1)
    await fake.completePreparation(with: fakePreparedLoad)
    await fake.completeAllocation(with: fakeAllocatedTexture)
    _ = try await (first, second)
    XCTAssertEqual(await fake.prepareCount, 1)
    XCTAssertEqual(await fake.allocateCount, 1)
    XCTAssertEqual((await store.snapshot()).inFlightDedupeHits, 1)
}
```

Add tests for:

- cache hit bypasses pipeline and immediately adds the new generation owner
- different package, entry identity, image, policy, or device creates a new load
- R8/RG8 `.colorSRGB` waiter fails after shared prepare but before allocation
  when no compatible waiter exists; a concurrent `.dataLinear` waiter can
  still use that one preparation/allocation
- one canceled waiter does not cancel another waiter
- all waiters canceled before upload submission cancels the pipeline task
- all waiters canceled after submission waits for cleanup but does not install
- released/stale generation completion is not installed
- load failure is not cached and every waiter receives the same typed failure
- failing generation B leaves generation A's ready texture and owner unchanged
- upload completes before cache install and lease return
- `releaseGeneration` never removes another generation's owner
- `trimToSoftBudget` removes only unowned values
- snapshot contains no path, username, or payload data

- [ ] **Step 2: Run RED**

Run:

```bash
swift test --filter SceneTextureStoreTests
```

Expected: compile failure because store and pipeline protocol do not exist.

- [ ] **Step 3: Implement the injected pipeline boundary**

Define internal inputs and protocol:

```swift
struct SceneTexturePipelineInput: Sendable {
    let request: SceneTextureRequest
    let resource: SceneTextureResource
    let resolver: ScenePackageAssetResolver
    let storageKey: SceneTextureStorageKey
}

struct SceneTextureCachedArtifact: @unchecked Sendable {
    let texture: SceneAllocatedTexture
    let residentReservation: SceneTextureMemoryReservation
}

protocol SceneTexturePipelineLoading: Sendable {
    func prepare(
        _ input: SceneTexturePipelineInput
    ) async throws -> SceneTexturePreparedLoad

    func allocate(
        _ prepared: SceneTexturePreparedLoad,
        submission: SceneTextureSubmissionState
    ) async throws -> SceneAllocatedTexture
}
```

The production loader marks submission immediately before committing its Metal
command buffer. `prepare` performs descriptor/payload/CPU work and returns an
estimated resident size. Store trims unowned cache entries and reserves
resident memory before calling `allocate`. Store cancellation uses submission
state to distinguish a task that may be canceled outright from a submitted
task whose callback must still clean up.

Store's concrete cache type is
`SceneTextureCache<SceneTextureCachedArtifact>`. The reservation is therefore
removed with the exact texture entry and cannot be detached from its lifetime.

- [ ] **Step 4: Implement the public store actor**

Implement the exact public methods from the design:

```swift
public actor SceneTextureStore {
    public func makeGeneration() -> SceneTextureGenerationID

    public func acquire(
        _ request: SceneTextureRequest,
        resource: SceneTextureResource,
        resolver: ScenePackageAssetResolver,
        for generation: SceneTextureGenerationID
    ) async throws -> SceneTextureLease

    public func releaseGeneration(_ generation: SceneTextureGenerationID)
    public func trimToSoftBudget() async
    public func snapshot() -> SceneTextureStoreSnapshot
}
```

State-machine rules:

1. `makeGeneration` inserts a live generation ID. Unknown/released generation
   requests fail `.invalidRequest`.
2. Derive a storage key only from a package resolution whose selected asset
   ID/path/provenance matches `SceneTextureResource`; do not use `asset.id` or
   a host path.
3. Cache hit adds the generation owner and returns the request's linear/sRGB
   view without calling the pipeline.
4. An in-flight entry stores one load task plus waiter IDs, generation IDs, and
   color intents. Color is not part of the storage key. Production storage
   planning uses `.dataLinear` so the first waiter's color cannot poison or
   duplicate the shared allocation.
5. Use `withTaskCancellationHandler` to remove only the canceled waiter.
6. Cancel a non-submitted task only when no waiter remains. A submitted task
   runs through completion cleanup but cannot install without a live waiter.
7. After `prepare`, validate every waiter's requested view against
   `allocationPlan.supportsSRGBView`. Resume incompatible waiters with
   `.invalidRequest`; if none remain, discard preparation before Metal
   submission.
8. Then trim unowned cache to
   `min(softLimit, hardLimit - estimatedResidentBytes)`, release every evicted
   resident reservation, then reserve the estimate. Do not enter `allocate` if
   that reservation fails.
9. After allocation, reconcile the reservation with actual
   `MTLTexture.allocatedSize`. If the delta cannot fit after a final unowned
   trim, discard the artifact and return `.resourceLimit(.residentBytes)`.
10. On success, re-enter the actor and install only if at least one waiter has a
   live generation. Add every such generation as owner before resuming waiters.
11. Cache the resident reservation beside the allocated artifact and release it
    exactly when that cache entry is evicted or discarded.
12. On failure, remove the loading entry and resume all waiters with the same
   error; never cache the error.
13. Create sRGB and linear leases from one `SceneAllocatedTexture`; fail
   `.invalidRequest` if the requested view is absent.
14. `releaseGeneration` removes ownership deterministically. Run cache trim
    before new resident installation and from explicit `trimToSoftBudget()`;
    never evict an entry that still has any generation owner.
15. Update hit/miss/dedupe, final upload path, eviction, resource-limit, and
    stable unsupported-category counters at their single state transition.
    Compose resident/staging/decoded current/peak values from the synchronous
    memory-budget snapshot; never derive diagnostics by enumerating paths.

- [ ] **Step 5: Run GREEN and commit**

Run:

```bash
swift test --filter SceneTextureStoreTests
```

Expected: all dedupe, cancellation, stale completion, atomic publication,
generation, and trim tests pass without real sleep timing.

Commit:

```bash
git add Sources/MacWallSceneTextures/SceneTextureStore.swift Tests/MacWallSceneTexturesTests/SceneTextureStoreTests.swift
git commit -m "feat(scene): coordinate texture generations"
```

---

### Task 9: Production Resolver-to-Metal Pipeline Integration

**Files:**

- Create: `Sources/MacWallSceneTextures/SceneTexturePipelineLoader.swift`
- Modify: `Sources/MacWallSceneTextures/SceneTextureStore.swift`
- Create: `Tests/MacWallSceneTexturesTests/SceneTexturePipelineIntegrationTests.swift`

**Interfaces:**

- Consumes: `SceneTextureResource.resolution`, `ScenePackageAssetResolver.source(for:)`
- Consumes: format reader, planner, payload loader, image decoder, allocator
- Produces: production `SceneTextureStore.init(device:limits:)`
- Consumed by: Task 10 and later S4

- [ ] **Step 1: Write failing resolver identity and error-mapping tests**

Build in-memory packages with `ScenePackageFixtureBuilder` and real
`ScenePackageAssetResolver`. Cover:

```swift
func testRejectsResourceWhoseResolutionDoesNotMatchItsID() async throws {
    let fixture = try makePackageTextureFixture(path: "materials/a.tex")
    let mismatched = SceneTextureResource(
        id: SceneResourceID(
            kind: .texture,
            path: try SceneVirtualPath(canonicalPath: "materials/b.tex")
        ),
        path: try SceneVirtualPath(canonicalPath: "materials/b.tex"),
        resolution: fixture.resolution
    )
    let store = try SceneTextureStore(
        device: XCTUnwrap(MTLCreateSystemDefaultDevice())
    )
    let generation = await store.makeGeneration()

    await XCTAssertThrowsErrorAsync(
        try await store.acquire(
            fixture.request,
            resource: mismatched,
            resolver: fixture.resolver,
            for: generation
        )
    ) { error in
        XCTAssertEqual(error as? SceneTexturePipelineError, .invalidRequest)
    }
}
```

Add tests mapping:

- non-positive limits, soft greater than hard, or zero concurrency ->
  `.invalidRequest` during `SceneTextureStore` construction
- non-package resolution -> `.invalidRequest`
- resolver identity mismatch -> `.invalidRequest`
- unsupported outer/info/container -> `.unsupportedDescriptor(kind)`
- unsupported animation version and parsed animation -> `.unsupportedAnimation`
- video -> `.unsupportedVideo`
- malformed descriptor/range -> `.malformedDescriptor`
- payload size/dimension/decoded pixel limits -> exact `SceneTextureLimit`
- error and snapshot text contains no repository path, `/Users/`, or bytes

Define the same private `XCTAssertThrowsErrorAsync` helper shown in Task 6 in
this integration test file; test targets cannot see file-private helpers from
another test source.

- [ ] **Step 2: Write failing end-to-end synthetic pipeline tests**

Create package-backed resources for:

```swift
func testPackageRGBAReachesPrivateTextureThroughPublicStore() async throws {
    let fixture = try makeRGBAFixture(width: 2, height: 1)
    let store = try SceneTextureStore(
        device: XCTUnwrap(MTLCreateSystemDefaultDevice())
    )
    let generation = await store.makeGeneration()

    let lease = try await store.acquire(
        fixture.request(color: .colorSRGB),
        resource: fixture.resource,
        resolver: fixture.resolver,
        for: generation
    )

    XCTAssertEqual(lease.texture.storageMode, .private)
    XCTAssertEqual(lease.storageExtent, .init(width: 2, height: 1))
    XCTAssertEqual(lease.contentExtent, .init(width: 2, height: 1))
    XCTAssertEqual(try readBack(lease.texture), fixture.expectedRGBA)
    XCTAssertEqual((await store.snapshot()).cacheMisses, 1)
}
```

Add end-to-end tests for:

- R8/RG8 direct path retains channel format
- BC1/BC2/BC3 direct path on the actual capable device
- injected `supportsBCTextureCompression == false` produces RGBA private
  texture through `SceneTextureSoftwareDecoder`
- PNG encoded payload becomes straight RGBA8
- two supplied mips all reach the private texture
- one malformed later mip prevents all cache installation
- second request is a cache hit and does not read/decode/upload again
- allocation/upload failure leaves snapshot ready count at zero
- actual allocated bytes are reconciled and released after generation release
  plus trim

- [ ] **Step 3: Run RED**

Run:

```bash
swift test --filter SceneTexturePipelineIntegrationTests
```

Expected: compile failure because production loader and store initializer do
not exist.

- [ ] **Step 4: Implement bounded decode/upload limiters**

In `SceneTexturePipelineLoader.swift`, add a FIFO actor limiter:

```swift
actor SceneTextureWorkLimiter {
    init(limit: Int)

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T
}
```

Requirements:

- reject non-positive limits during pipeline construction
- preserve FIFO waiter order
- remove canceled waiters without consuming a permit
- release in `defer` on success, failure, and cancellation
- use separate instances with limits 2 for decode and upload
- test maximum observed concurrency with controllable operations, not real
  sleep timing

- [ ] **Step 5: Implement production prepare**

`DefaultSceneTexturePipelineLoader.prepare` performs:

```text
validate resource ID/path/resolution
-> resolver.source(for: selected package asset)
-> SceneTextureFormatReader.inspect
-> SceneTextureLoadPlanner.makePlan(colorIntent: .dataLinear)
-> reserve estimated decoded CPU bytes
-> decode limiter
-> Task.detached bounded payload preparation
-> ImageIO decode when encoded
-> build staging layout from actual device alignment
-> return SceneTexturePreparedLoad
```

Exact rules:

1. Use only `resolution.selected` with `.package(entryIdentity)` provenance.
2. Require selected canonical path to equal both `resource.path` and
   `resource.id.path`, and require resource kind `.texture`.
3. Obtain the source only through `resolver.source(for:)`; this rechecks
   offset/byte-count identity.
4. Convert `SceneTextureInspection.unsupported` outer/info/container kinds to
   `.unsupportedDescriptor(kind)` and animation version to
   `.unsupportedAnimation`.
5. Reserve the maximum simultaneous CPU `Data` footprint before preparation:
   direct paths reserve expanded payload bytes; software BC reserves expanded
   BC input plus physical padded RGBA output; encoded images reserve encoded
   input plus physical padded RGBA output. Include the complete mip chain with
   checked sums.
6. Reserve decoded CPU bytes before materializing `Data`. After preparation,
   call `resize` with the exact bytes retained by final prepared mips, then
   transfer the token in `SceneTexturePreparedLoad` until allocation finishes
   or is abandoned.
7. Run read/LZ4/software/ImageIO work in `Task.detached`; never perform it on
   the Store actor executor.
8. Calculate estimated resident bytes from the final physical prepared mip
   storage,
   never from compressed package byte count when the final format is RGBA.
9. On every thrown error, release reservations and map to a stable S3 error.
10. Preserve `supportsSRGBView` in the prepared allocation plan so Store can
    validate each waiter independently before allocation/publication.
11. Build allocation metadata from the final prepared source. Direct raw/BC,
    software RGBA, and ImageIO RGBA all retain the planner's physical storage
    extent, logical content extent/rect, and Metal-compatible full mip chain.

- [ ] **Step 6: Implement production allocate and store construction**

`DefaultSceneTexturePipelineLoader.allocate` performs:

```text
reserve aligned staging bytes
-> upload limiter
-> DirectSceneTextureAllocator.allocate
-> release staging reservation
-> release decoded reservation
-> return completed SceneAllocatedTexture
```

Add:

```swift
public init(
    device: any MTLDevice,
    limits: SceneTextureLimits = SceneTextureLimits()
) throws
```

The initializer creates:

- runtime capabilities from the exact `MTLDevice`
- device registry ID for cache keys
- one shared `SceneTextureMemoryBudget`
- one `DirectSceneTextureAllocator`
- one default pipeline loader
- upload policy version `1`

Before creating those objects, validate every byte/dimension/pixel/concurrency
limit is positive, `residentSoftBytes <= residentHardBytes`, and timeout is
greater than zero. Invalid configuration throws `.invalidRequest` without
creating a queue or starting work.

Before allocation, Store uses `estimatedResidentBytes` to evict unowned cache
entries down to the hard-safe target, releases their resident reservations,
and reserves resident memory. After allocation it reconciles with actual
`allocatedSize` through `resize`. Any abandoned prepared load releases decoded and resident
reservations; any evicted ready entry releases its resident reservation.

- [ ] **Step 7: Run focused GREEN**

Run:

```bash
swift test --filter SceneTexturePipelineIntegrationTests
swift test --filter MacWallSceneTexturesTests
```

Expected:

- all synthetic resolver-to-private-texture tests pass
- Metal tests execute with zero skips on the approved Apple Silicon machine
- no test depends on GUI, AppKit, or real sleep timing

- [ ] **Step 8: Commit**

```bash
git add Sources/MacWallSceneTextures/SceneTexturePipelineLoader.swift Sources/MacWallSceneTextures/SceneTextureStore.swift Tests/MacWallSceneTexturesTests/SceneTexturePipelineIntegrationTests.swift
git commit -m "feat(scene): connect graph textures to Metal"
```

---

### Task 10: Three-Fixture Texture Catalog and Actual GPU Gate

**Files:**

- Create: `Tests/MacWallSceneTexturesTests/SceneLocalFixtureTextureTests.swift`
- Create: `Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json`

**Interfaces:**

- Consumes: fixed local `scene.pkg` IDs, S2 graph resources, public S3 store
- Produces: deterministic path-redacted aggregate catalog
- Produces: actual local-fixture GPU acceptance gate

- [ ] **Step 1: Write failing fixture availability and catalog validation tests**

Define the fixed set only:

```swift
private enum FixedWorkshopID: String, CaseIterable {
    case fixture2174863503 = "2174863503"
    case fixture2834933421 = "2834933421"
    case fixture3516106265 = "3516106265"

    static let sorted = allCases.sorted { $0.rawValue < $1.rawValue }
}
```

Add pure tests that assert:

- no available fixed ID -> `.absent`
- one/two available -> `.partial` with every missing ID sorted
- all three -> `.complete` sorted
- schema must equal 1
- catalog IDs must exactly equal the fixed set
- duplicate, extra, path-like, or missing ID fails validation
- canonical JSON encoding is byte-identical on repeated encoding
- encoded catalog bytes contain none of `/Users/`, repository root, `.tex`,
  package entry path, or payload bytes

- [ ] **Step 2: Write the local GPU fixture gate**

Implement one local test with this control flow:

```text
if MACWALL_UPDATE_LOCAL_SCENE_TEXTURE_CATALOG == 1:
   require all three fixtures, generate canonical catalog, atomic-write it
load tracked catalog
-> classify fixed fixture availability
-> all absent: XCTSkip
-> partial: XCTFail(sorted missing IDs) and return
-> complete: require default Metal device
-> for each fixture in sorted order:
   open RecordingSceneByteSource read-only
   build ScenePackageAssetResolver and SceneGraphDocument
   collect .texture resources sorted by SceneResourceID
   inspect/plan every dependency using fixed BC-capable catalog profile
   acquire every supported static texture on actual runtime device
   release its generation after validation
   classify typed unsupported animation/video/multi-image/format
   compare aggregate summary to tracked catalog
   repeat planning and compare canonical bytes
   compare scene.pkg SHA-256 before and after
```

Use `.dataLinear` for the fixture upload request because S4 material-slot color
semantics are not implemented. This permits R8/RG8 and does not guess sRGB.

For each acquired texture assert:

- `storageMode == .private`
- mip count equals the full descriptor mip count
- width/height and content rect match the plan
- resident bytes are positive
- no unsupported/failed resource is installed as ready cache state

Read policy:

- maximum individual package read is at most 64 MiB
- no read range covers the entire package
- package source and file bytes remain unchanged
- preview/thumbnail entry ranges are never used as a texture source

- [ ] **Step 3: Run RED against the absent catalog**

Run:

```bash
swift test --filter SceneLocalFixtureTextureTests
```

Expected: failure because the tracked schema-1 catalog does not exist yet.

- [ ] **Step 4: Implement deterministic aggregate models and encoder**

The tracked JSON contains only:

```swift
struct LocalSceneTextureCatalog: Codable, Equatable {
    let schemaVersion: Int
    let capabilityProfile: String
    let fixtures: [LocalSceneTextureFixture]
}

struct LocalSceneTextureFixture: Codable, Equatable {
    let workshopID: String
    let packageVersion: String
    let textureResourceCount: Int
    let formatCounts: [String: Int]
    let containerCounts: [String: Int]
    let uploadPathCounts: [String: Int]
    let unsupportedCounts: [String: Int]
    let logicalPayloadBytes: Int
}
```

Set `capabilityProfile` to
`"bc-compression=true;logical-bytes=unaligned;policy=1"`. Sort fixtures and
dictionary keys, pretty-print with sorted keys and one trailing newline. Never
include `allocatedSize`, alignment, timing, absolute path, entry path, hash,
payload, or screenshot.

- [ ] **Step 5: Generate and inspect the tracked catalog**

Run only when all three local fixtures exist:

```bash
MACWALL_UPDATE_LOCAL_SCENE_TEXTURE_CATALOG=1 swift test --filter SceneLocalFixtureTextureTests/testLocalSceneTexturesMatchTrackedAggregateCatalog
sed -n '1,240p' Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json
```

Expected:

- JSON contains exactly the three fixed IDs
- counts are measured from the current fixtures, not copied from the design
- no path or hardware-dependent allocated size is present
- the update run writes only the tracked catalog, never `test/`

- [ ] **Step 6: Run GREEN twice and verify read-only fixtures**

Run:

```bash
swift test --filter SceneLocalFixtureTextureTests
swift test --filter SceneLocalFixtureTextureTests
git status --short -- test Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json
```

Expected:

- both runs pass with identical aggregate bytes
- approved local environment reports zero skips
- `test/` has no tracked or modified file
- only the new catalog is uncommitted

- [ ] **Step 7: Commit**

```bash
git add Tests/MacWallSceneTexturesTests/SceneLocalFixtureTextureTests.swift Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json
git commit -m "test(scene): gate local texture fixtures"
```

---

### Task 11: Whole-Branch Review, Completion Records, and Full Verification

**Files:**

- Create: `docs/implemented/2026-08-06-scene-gpu-texture-pipeline.md`
- Modify: `docs/README.md`
- Modify: `docs/development-log.md`
- Modify: `docs/development-roadmap.md`
- Modify: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- Move: `docs/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`
  -> `docs/archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md`
- Move: `docs/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md`
  -> `docs/archive/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md`

**Interfaces:**

- Consumes: every S3 implementation/test commit and measured test output
- Produces: implemented S3 record, archived active docs, S4-ready roadmap

- [ ] **Step 1: Run focused S3 verification**

Run:

```bash
swift test --filter SceneTextureModelsAndCapabilitiesTests
swift test --filter SceneTextureLoadPlannerTests
swift test --filter SceneTexturePayloadLoaderTests
swift test --filter SceneTextureImageDecoderTests
swift test --filter SceneTextureMemoryBudgetTests
swift test --filter DirectSceneTextureAllocatorTests
swift test --filter SceneTextureCacheTests
swift test --filter SceneTextureStoreTests
swift test --filter SceneTexturePipelineIntegrationTests
swift test --filter SceneLocalFixtureTextureTests
```

Expected: every focused suite passes; the approved Apple Silicon/local-fixture
environment reports zero skips.

- [ ] **Step 2: Run whole-branch architecture and privacy checks**

Run:

```bash
rg -n "import (Metal|AppKit|AVFoundation)" Sources/MacWallSceneFormats Sources/MacWallSceneAssets Sources/MacWallSceneGraph
rg -n "MacWall(Core|App)|MacWallNative|SceneWallpaperView|desktop-fallback|preview\\.(gif|jpg)|thumbnail\\.jpg|cover\\.png" Sources/MacWallSceneTextures
rg -n "/Users/|scene\\.pkg|materials/.+\\.tex" Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json
git diff --check
git status --short -- test
```

Expected:

- no forbidden import in Formats/Assets/Graph
- no Core/App/Native/fallback/thumbnail integration in S3 production
- tracked catalog has no host or entry path
- no whitespace error
- local fixture directory unchanged/untracked-only under its existing ignore
  policy

- [ ] **Step 3: Review the complete S3 diff against the design**

Run:

```bash
git diff --stat HEAD~10..HEAD
git diff HEAD~10..HEAD -- Package.swift Sources/MacWallSceneTextures Tests/MacWallSceneTexturesTests Tests/Fixtures/SceneTextures
```

Review and fix any mismatch in these exact categories before proceeding:

- dependency direction and file ownership
- exact format mapping and signature override
- full mip atomicity and padding/content metadata
- actor isolation and decode/upload concurrency
- cancellation after Metal submission
- generation owner lifetime and cache publication
- resident/staging/decoded reservation rollback
- deterministic/path-redacted diagnostics and catalog

Each correction gets a focused regression test and a separate
`fix(scene): ...` commit.

- [ ] **Step 4: Run full package verification**

Run:

```bash
swift test
```

Expected: all repository tests pass with zero failures and, on the approved
fixture/GPU environment, zero skips. Record the exact test count and runtime
from this command in the completion document and development log.

- [ ] **Step 5: Write the implemented record**

Create `docs/implemented/2026-08-06-scene-gpu-texture-pipeline.md` with:

- status `implemented / completed`
- target/dependency boundary
- public request/lease/store contract
- direct raw/BC and software/ImageIO paths
- full mip, padding, color/origin policy
- cache key, in-flight dedupe, generation ownership, LRU
- configured and observed memory accounting
- local fixture aggregate results copied from the tracked catalog
- exact focused/full test results from Steps 1 and 4
- explicit nonclaims: no renderer, Desktop Scene, fallback, animation/video,
  heap/streaming, GUI validation
- next phase: S4 Headless 2D Metal Renderer design

Do not report an expected count. Copy the command's actual final summary.

- [ ] **Step 6: Archive completed S3 docs and update indexes**

Use `git mv` for the design and this plan. Update links so:

- `docs/README.md` lists S3 under implemented/archive, not active planning
- `docs/development-roadmap.md` marks S3 implemented with measured tests and
  names S4 Headless 2D Metal Renderer as next design
- `docs/superpowers/specs/2026-07-29-scene-engine-design.md` marks S3
  implemented and links the implemented record
- `docs/development-log.md` adds an Asia/Seoul timestamp, implementation
  summary, exact verification result, and implemented-record link
- `README.md` and `README.ko.md` remain unchanged because no user-visible
  behavior was added

- [ ] **Step 7: Verify active documentation state**

Run:

```bash
rg --files docs | sort
rg --files docs/superpowers/specs docs/superpowers/plans | rg 'scene-gpu-texture-pipeline'
rg -n "S3 planning next|S3.*implementation not started" docs --glob '!docs/archive/**'
rg -n "2026-08-06-scene-gpu-texture-pipeline" docs/README.md docs/development-roadmap.md docs/development-log.md docs/implemented/2026-08-06-scene-gpu-texture-pipeline.md
git diff --check
git diff --name-only -- README.md README.ko.md
```

Expected:

- no completed S3 spec/plan remains under active `docs/superpowers`
- active docs link the implemented record or archived files correctly
- no root README change
- no whitespace error

- [ ] **Step 8: Commit completion documentation**

Stage only S3 documentation and moves, then commit:

```bash
git add docs/README.md docs/development-log.md docs/development-roadmap.md docs/superpowers/specs/2026-07-29-scene-engine-design.md docs/implemented/2026-08-06-scene-gpu-texture-pipeline.md docs/archive/superpowers/specs/2026-08-06-scene-gpu-texture-pipeline-design.md docs/archive/superpowers/plans/2026-08-06-scene-gpu-texture-pipeline.md
git diff --cached --check
git commit -m "docs(scene): record S3 texture pipeline"
```

- [ ] **Step 9: Confirm final clean state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -12
```

Expected: feature branch is clean and the log shows the task-sized S3 commits.

---

## Final Acceptance Checklist

- [ ] `MacWallSceneTextures` exists independently above Formats/Assets/Graph.
- [ ] RGBA8, RG8, R8 use exact direct private texture upload.
- [ ] BC1/BC2/BC3 use capability-gated direct upload and tested software fallback.
- [ ] Encoded image payloads become straight RGBA8 through ImageIO/CoreGraphics.
- [ ] Every supplied static mip is validated and uploaded atomically.
- [ ] Physical storage extent, logical content extent/rect, and top-left origin survive the pipeline.
- [ ] Same storage key is decoded/uploaded once across concurrent generations and color views.
- [ ] Owned textures cannot be evicted; stale/failed generations cannot install.
- [ ] Resident, staging, decoded CPU, payload, dimensions, concurrency, and timeout limits have boundary tests.
- [ ] Three fixed local fixtures pass deterministic/path-redacted catalog and actual GPU gates.
- [ ] Full `swift test` passes with zero failures and zero skips on the approved environment.
- [ ] Core/App/Native/Legacy/Video/Web/CALayer behavior remains unchanged.
- [ ] S3 docs are archived, implementation is recorded, and S4 is the next design phase.
