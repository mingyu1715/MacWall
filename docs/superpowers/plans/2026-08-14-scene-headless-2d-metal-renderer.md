# Scene S4 Headless 2D Metal Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** S2 typed graph와 S3 GPU texture를 입력으로 받아, AppKit이나
WallpaperAgent 없이 fixed time의 실제 2D Scene frame을 Metal texture와 PNG로
생성하는 독립 `MacWallSceneRenderer` target을 구현한다.

**Architecture:** raw JSON 해석은 `MacWallSceneGraph`에서 끝낸다. S4는
`SceneGraphBuildResult`를 immutable `SceneRenderProgram`으로 compile하고,
`SceneTextureStore` generation을 소유하는 `SceneRenderSession`을 준비한 뒤,
timeline/transform을 `SceneFramePlan`으로 평가하고 offscreen Metal render pass에
stable draw order로 합성한다.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Metal, Metal Shading Language,
CoreGraphics, ImageIO, CryptoKit, simd. 최소 배포 대상은 기존 package와 같은
macOS 14다.

작성일: 2026-08-14

상태: executable plan ready / implementation not started

**승인 설계:**
[Scene S4 Headless 2D Metal Renderer Design](../specs/2026-08-14-scene-headless-2d-metal-renderer-design.md)

## Global Constraints

- 구현은 격리된 `feature/scene-s4-headless-metal-renderer` branch와
  `/tmp/macwall-scene-s4` worktree에서 한다.
- PR은 만들지 않는다. 최종 검증 후 `main`에 merge하고 `origin/main`으로 push한 뒤
  임시 branch/worktree를 정리한다.
- `test/2174863503/scene.pkg`, `test/2834933421/scene.pkg`,
  `test/3516106265/scene.pkg`는 읽기 전용 local fixture다. 수정하거나 Git에
  추가하지 않는다.
- GUI app, System Settings, `swift build`, `xcodebuild build`, package/DMG,
  notarization, `dist` 작업을 실행하지 않는다.
- 검증은 focused `swift test`, 전체 `swift test`, 정적 검사, `/tmp` snapshot으로
  제한한다.
- `macwallctl`을 S4 구현이나 검증 경로에 추가하지 않는다.
- Main App, 기존 `CALayer` prototype, Native Wallpaper backend, fallback 정책을
  수정하지 않는다.
- effect/custom shader/text/particle/media/SceneScript/3D는 구현하지 않는다.

---

## 1. 최종 파일 지도

### Package와 Graph 계약

- 수정: `Package.swift`
- 생성: `Sources/MacWallSceneGraph/SceneGraphRenderSemantics.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphAnimation.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphHierarchy.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphHierarchyResolver.swift`
- 수정: `Sources/MacWallSceneTextures/SceneTextureModels.swift`
- 수정: `Sources/MacWallSceneTextures/SceneTextureStore.swift`
- 생성: `Tests/MacWallSceneGraphTests/SceneGraphRenderSemanticsTests.swift`
- 수정: `Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift`
- 수정: `Tests/MacWallSceneGraphTests/SceneGraphHierarchyTests.swift`

### Renderer 제품 target

- 생성: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderLimits.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderCompiler.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderOrdering.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneTimelineEvaluator.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneTransformEvaluator.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderSession.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneMetalPipelines.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderTargetPool.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneMetalRenderer.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneSnapshotReader.swift`
- 생성: `Sources/MacWallSceneRenderer/Shaders/SceneImage.metal`

### Renderer 테스트와 fixture

- 생성: `Tests/MacWallSceneRendererTests/SceneRenderModelTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneRenderCompilerTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneTimelineEvaluatorTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneTransformEvaluatorTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneRenderSessionTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneMetalPipelineTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneMetalPixelTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneSnapshotReaderTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneLocalFixtureRendererTests.swift`
- 생성: `Tests/Fixtures/SceneRenderer/synthetic-scene-golden.json`
- 생성: `Tests/Fixtures/SceneRenderer/local-scene-renderer-catalog.json`

### 완료 문서

- 수정: `docs/README.md`
- 수정: `docs/development-roadmap.md`
- 수정: `docs/development-log.md`
- 수정: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- 생성: `docs/implemented/2026-08-14-scene-headless-2d-metal-renderer.md`
- 이동: 현재 S4 spec/evidence/plan을 `docs/archive/superpowers/`로 이동

## 2. 고정할 공개 계약

구현 중 이름을 임의로 바꾸지 않는다. Swift compiler가 요구하는 사소한 label 변경은
가능하지만, 책임과 소유권은 다음 계약을 유지한다.

```swift
public enum SceneRenderStatus: String, Codable, Sendable {
    case exact, degraded, unsupported, invalid
}

public enum SceneOutputScalingMode: String, Codable, Sendable {
    case fit, fill, stretch
}

public struct SceneRenderColor: Equatable, Sendable {
    public let red: Float
    public let green: Float
    public let blue: Float
    public let alpha: Float
}

public struct SceneRenderCanvas: Equatable, Sendable {
    public let width: Double
    public let height: Double
}

public enum SceneRenderDiagnosticSeverity: String, Codable, Sendable {
    case information, warning, error
}

public struct SceneRenderDiagnostic: Equatable, Sendable {
    public let severity: SceneRenderDiagnosticSeverity
    public let code: String
    public let nodeID: SceneNodeID?
    public let resourceID: SceneResourceID?
    public let arguments: [String]
}

public enum SceneRenderLimit: String, Equatable, Sendable {
    case outputDimension, outputPixels, drawItems, inFlightFrames
    case renderTargetBytes, snapshotReadbackBytes
}

public enum SceneRenderError: Error, Equatable, Sendable {
    case invalidProgram
    case unsupported
    case resourceLimit(SceneRenderLimit)
    case incompatibleDevice
    case invalidTarget
    case sessionInvalidated
    case cancelled
    case commandFailed
}

public final class SceneExternalRenderTargetLease: @unchecked Sendable {
    public let texture: any MTLTexture

    public init(texture: any MTLTexture) {
        self.texture = texture
    }
}

public enum SceneRenderOutputDestination: Sendable {
    case owned
    case external(SceneExternalRenderTargetLease)
}

public struct SceneRenderCompileResult: Sendable {
    public let program: SceneRenderProgram?
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]
}

public struct SceneRenderLimits: Equatable, Sendable {
    public var maximumDimension: Int = 16_384
    public var maximumPixelCount: Int = 33_177_600
    public var maximumDrawItemCount: Int = 100_000
    public var maximumInFlightFrameCount: Int = 3
    public var renderTargetBudgetBytes: Int = 512 * 1_024 * 1_024
    public var snapshotReadbackBudgetBytes: Int = 256 * 1_024 * 1_024

    public init() {}
}

public struct SceneRenderFrameRequest: Sendable {
    public let mediaTimeSeconds: Double
    public let outputWidth: Int
    public let outputHeight: Int
    public let scalingMode: SceneOutputScalingMode
    public let clearColor: SceneRenderColor
    public let output: SceneRenderOutputDestination
    public let requestsSnapshot: Bool
}

public struct SceneTexturePackageContext: Sendable {
    public let packageID: SceneTexturePackageID
    let resolver: ScenePackageAssetResolver

    public init(
        packageID: SceneTexturePackageID,
        resolver: ScenePackageAssetResolver
    ) {
        self.packageID = packageID
        self.resolver = resolver
    }
}

public actor SceneRenderSession {
    public static func prepare(
        program: SceneRenderProgram,
        device: any MTLDevice,
        textureStore: SceneTextureStore,
        textureContext: SceneTexturePackageContext,
        limits: SceneRenderLimits = .init()
    ) async throws -> SceneRenderSession

    public func render(
        _ request: SceneRenderFrameRequest
    ) async throws -> SceneRenderCompletedFrame

    public func invalidate() async
}
```

Graph의 additive typed contract는 raw 보존 계약을 없애지 않는다.

```swift
public enum SceneRenderableProperty: String, Codable, Sendable {
    case origin, position, scale, rotationZ, opacity, visibility, enabled, zOrder
}

public enum SceneTimelinePlaybackMode: String, Codable, Sendable {
    case loop, mirror, single
}

public enum SceneTimelineInterpolation: Equatable, Sendable {
    case linear
    case step
    case cubicBezier(SceneCubicBezierControlPoints)
}

public struct SceneCubicBezierControlPoints: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

public struct SceneTypedAnimationTrack: Equatable, Sendable {
    public let property: SceneRenderableProperty
    public let playbackMode: SceneTimelinePlaybackMode
    public let durationSeconds: Double
    public let isRelative: Bool
    public let startsPaused: Bool
    public let keyframes: [SceneTypedAnimationKeyframe]
}

public struct SceneTypedPropertyOverride: Equatable, Sendable {
    public let property: SceneRenderableProperty
    public let value: SceneTypedPropertyValue
}
```

## 3. 공식 근거

구현자는 Gate 0과 GPU task에서 아래 primary source를 다시 확인한다.

- [Apple TN3133: Packaging a Metal renderer](https://developer.apple.com/documentation/technotes/tn3133-packaging-a-renderer): target source의 `.metal` 파일을 SwiftPM이 자동으로 metallib로 compile하고 `Bundle.module`에서 읽는 구성
- [Apple Shader library and archive creation](https://developer.apple.com/documentation/metal/shader-library-and-archive-creation): `makeDefaultLibrary(bundle:)`와 runtime source compilation 차이
- [Apple MTLTexture.getBytes](https://developer.apple.com/documentation/metal/mtltexture/getbytes%28_%3Abytesperrow%3Afrom%3Amipmaplevel%3A%29): private texture 직접 readback 금지와 GPU completion/synchronization 요구
- [Apple MTLDevice](https://developer.apple.com/documentation/metal/mtldevice): encoder와 resource의 same-device 제약
- [Apple Metal Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html): 최대 3개 in-flight dynamic resource ring
- [Apple Metal Feature Set Tables](https://developer.apple.com/metal/feature-sets/): texture dimension과 device capability 상한
- [Wallpaper Engine Timeline Animation Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html): Loop/Mirror/Single, duration, default Bezier, linear 동작

## 4. Task 0: Scene 의미 증거 Gate 고정

**Files:**

- 수정: `docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-design.md`
- 생성: `docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md`

**목적:** 잘못된 좌표계나 timeline 의미를 구현으로 굳히지 않는다. 이 task가
commit되기 전 renderer source를 생성하지 않는다.

**Interfaces:**

- Consumes: 승인 S4 spec, 현재 Graph parser, S3 lease metadata, 세 read-only fixture
- Produces: 항목별 evidence 판정과 Task 1~11이 따라야 할 좌표/timeline/texture 결정

- [ ] official docs의 timeline mode/duration/interpolation 의미를 evidence 문서에
  URL과 확인일로 기록한다.
- [ ] 기존 parser가 읽는 `origin`, `pivot`, `position`, `angles`, `zorder/zindex`,
  `options.fps`, `options.length`, `options.relative`, `options.mode` raw shape를
  synthetic package와 세 local fixture에서 read-only로 표본화한다.
- [ ] local fixture path, payload, title을 기록하지 않고 Workshop ID와 집계값만
  남긴다.
- [ ] 다음 항목을 각각 `confirmed`, `unsupported-for-S4`, `requires-contract-change`
  중 하나로 판정한다: pivot anchor, Z 방향, origin/position 관계, parent matrix 순서,
  instance override 우선순위, texture orientation, padded mip sampling, straight alpha,
  tint color space, `length/fps/time/frame`, Loop/Mirror/Single endpoint, start-paused.
- [ ] local evidence와 official semantics가 충돌하면 추측하지 않는다. 해당 의미를
  `unsupported-for-S4`로 고정하고 compiler diagnostic code를 문서에 적는다.
- [ ] S3의 단일 `contentRect`로 padded mip sampling이 정확하지 않으면
  `SceneTextureLease`에 per-mip rect를 추가해야 한다고 명시한다. 그렇지 않으면
  Texture target은 수정하지 않는다.
- [ ] 승인 설계의 `Gate 0` 표를 evidence 결과로 갱신하고 다음 task 진입 가능 여부를
  기록한다.

**RED:**

```bash
test -f docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md
```

예상: 아직 파일이 없으므로 실패한다.

**GREEN:**

```bash
rg -n "pivot anchor|Z direction|instance override|padded mip|alpha|timeline" \
  docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md
rg -n "confirmed|unsupported-for-S4|requires-contract-change" \
  docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md
git diff --check
```

**Commit:**

```bash
git add docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-design.md \
  docs/superpowers/specs/2026-08-14-scene-headless-2d-metal-renderer-evidence.md
git commit -m "docs(scene): lock S4 renderer evidence gate"
```

## 5. Task 1: Graph typed render semantics 추가

**Files:**

- 생성: `Sources/MacWallSceneGraph/SceneGraphRenderSemantics.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphAnimation.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphAnimationParser.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphHierarchy.swift`
- 수정: `Sources/MacWallSceneGraph/SceneGraphHierarchyResolver.swift`
- 생성: `Tests/MacWallSceneGraphTests/SceneGraphRenderSemanticsTests.swift`
- 수정: `Tests/MacWallSceneGraphTests/SceneGraphAnimationTests.swift`
- 수정: `Tests/MacWallSceneGraphTests/SceneGraphHierarchyTests.swift`

**Interfaces:**

- Consumes: Task 0에서 confirmed로 판정된 raw property/timeline/override shape
- Produces: renderer가 raw JSON 없이 소비할 typed track과 typed override

```swift
public enum SceneTypedPropertyValue: Equatable, Sendable {
    case scalar(Double)
    case vector3(SceneGraphVector3)
    case boolean(Bool)
}

public struct SceneTypedAnimationKeyframe: Equatable, Sendable {
    public let timeSeconds: Double
    public let value: SceneTypedPropertyValue
    public let interpolation: SceneTimelineInterpolation
}

extension SceneAnimationTrack {
    public var typedTrack: SceneTypedAnimationTrack? { get }
}

extension ScenePropertyOverride {
    public var typedOverride: SceneTypedPropertyOverride? { get }
}
```

- [ ] supported property별 valid value, invalid component count, non-finite value,
  unsupported path, unsorted/duplicate keyframe, invalid duration tests를 먼저 작성한다.
- [ ] Loop은 `[0, duration)`, Mirror는 왕복 period `2 * duration`, Single은 마지막
  keyframe clamp라는 Gate 0 결과를 test로 고정한다.
- [ ] interpolation raw shape를 typed linear/step/cubicBezier로 변환한다. control point가
  유효하지 않으면 typed track을 만들지 않고 기존 raw track과 degraded diagnostic을
  유지한다.
- [ ] `options.length`와 `fps/frame/time` 변환은 Gate 0에서 확정한 단위만 허용한다.
  확정되지 않은 조합은 typed track을 `nil`로 두고 raw data를 보존한다.
- [ ] instance override는 exact supported path/value만 typed로 변환한다. source node의
  raw override 목록은 그대로 유지한다.
- [ ] `visible`, `enabled`, Z override와 start-paused evidence를 typed/raw contract에
  보존한다. SceneScript 없는 S4의 start-paused 동작은 Gate 0 판정과 다르면 exact로
  추측하지 않는다.
- [ ] parser 결과가 입력 key 순서와 무관하게 동일한 typed track/override 순서를
  반환하는 test를 추가한다.
- [ ] 기존 Graph test를 모두 통과시켜 additive 변경임을 확인한다.

**RED:** `swift test --filter SceneGraphRenderSemanticsTests`

예상: 새 타입/API가 없어 compile 또는 assertion failure가 발생한다.

**GREEN:**

```bash
swift test --filter SceneGraphRenderSemanticsTests
swift test --filter SceneGraphAnimationTests
swift test --filter SceneGraphHierarchyTests
```

**Commit:**

```bash
git add Sources/MacWallSceneGraph Tests/MacWallSceneGraphTests
git commit -m "feat(scene): type render animation and instance overrides"
```

## 6. Task 2: Renderer target, limits, shader packaging 생성

**Files:**

- 수정: `Package.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderLimits.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneMetalPipelines.swift`
- 생성: `Sources/MacWallSceneRenderer/Shaders/SceneImage.metal`
- 생성: `Tests/MacWallSceneRendererTests/SceneRenderModelTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneMetalPipelineTests.swift`

**Package 계약:**

**Interfaces:**

- Consumes: `MacWallSceneGraph`, `MacWallSceneTextures` public modules
- Produces: `MacWallSceneRenderer` target, limits/models, precompiled shader entry points

```swift
.target(
    name: "MacWallSceneRenderer",
    dependencies: ["MacWallSceneGraph", "MacWallSceneTextures"]
),
.testTarget(
    name: "MacWallSceneRendererTests",
    dependencies: [
        "MacWallSceneRenderer", "MacWallSceneGraph", "MacWallSceneTextures",
        "MacWallSceneAssets", "MacWallSceneFormats", "MacWallSceneTestSupport"
    ]
)
```

**Limits:** maximum dimension `16_384`, maximum pixels `33_177_600`, maximum draw
items `100_000`, maximum in-flight `3`, target budget `512 MiB`, snapshot budget
`256 MiB`를 default로 둔다.

- [ ] invalid/non-finite size, pixel multiplication overflow, draw count, in-flight count,
  target budget, readback budget tests를 먼저 작성한다.
- [ ] status, diagnostic, color, output scaling, request/result value를 정의한다. public
  value에는 URL, `MTLDevice`, random UUID가 섞이지 않게 한다.
- [ ] shader에 full quad vertex function, textured fragment function, linear composition용
  tint/opacity uniform만 추가한다.
- [ ] Xcode 26.6 toolchain 검증 결과에 따라 `.metal`은 `.process` resource로 선언한다.
  native SwiftPM engine은 이를 source resource로 복사해 CPU test를 유지하고,
  `swiftbuild` engine은 같은 파일을 `default.metallib`로 compile한다.
- [ ] production은 runtime `makeLibrary(source:)`를 사용하지 않고
  `device.makeDefaultLibrary(bundle: Bundle.module)`로 `sceneImageVertex`와
  `sceneImageFragment`를 찾는다.
- [ ] default Metal device가 없으면 Metal test만 `XCTSkip`하고 CPU model test는
  계속 실행한다.
- [ ] `swift test --build-system swiftbuild` focused test로 shader function을 실제로
  찾는다. Xcode의 별도 Metal Toolchain component가 필요하며, 실패하면 renderer 구현
  전에 Package resource layout을 바로잡는다. native SwiftPM engine에서는 shader
  test만 명시적으로 skip하고 CPU test는 계속 실행한다.

**RED:**

```bash
swift test --filter SceneRenderModelTests
swift test --build-system swiftbuild \
  --filter SceneMetalPipelineTests/testDefaultShaderLibraryContainsSceneFunctions
```

**GREEN:** RED와 같은 두 명령이 모두 통과해야 한다.

**Commit:**

```bash
git add Package.swift Sources/MacWallSceneRenderer Tests/MacWallSceneRendererTests
git commit -m "feat(scene): add headless Metal renderer target"
```

## 7. Task 3: Immutable render compiler 구현

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneRenderCompiler.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderOrdering.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneRenderCompilerTests.swift`

**Interfaces:**

- Consumes: `SceneGraphBuildResult`, typed Graph semantics, `SceneRenderLimits`
- Produces: immutable opaque `SceneRenderProgram`과 deterministic compile result

```swift
public struct SceneRenderCompiler: Sendable {
    public init(limits: SceneRenderLimits = .init())
    public func compile(_ graphResult: SceneGraphBuildResult) -> SceneRenderCompileResult
}

public struct SceneRenderProgram: Sendable {
    public let canvas: SceneRenderCanvas
    public let fingerprint: String
    public let drawCount: Int

    let drawTemplates: [SceneRenderDrawTemplate]
    let evaluationOrder: [SceneRenderNodeIdentity]
    let textureManifest: [SceneRenderTextureManifestEntry]
}

struct SceneRenderNodeIdentity: Hashable, Comparable, Sendable {
    let nodeID: SceneNodeID
    let instancePath: [SceneNodeID]
}

struct SceneRenderDrawTemplate: Sendable {
    let identity: SceneRenderNodeIdentity
    let sourceOrder: Int
    let effectiveZ: Double
    let textureManifestIndex: Int
    let baseProperties: SceneRenderBaseProperties
    let animationBindings: [SceneTypedAnimationTrack]
}

struct SceneRenderBaseProperties: Sendable {
    let origin: SceneGraphVector3
    let pivot: SceneGraphVector3
    let position: SceneGraphVector3
    let scale: SceneGraphVector3
    let rotationZ: Double
    let opacity: Double
    let visible: Bool
    let enabled: Bool
    let color: SceneGraphColor
    let zOrder: Double
}

struct SceneRenderTextureManifestEntry: Sendable {
    let resource: SceneTextureResource
    let imageIndex: Int
    let colorIntent: SceneTextureColorIntent
    let dependentDrawIndices: [Int]
}
```

- [ ] document 부재/invalid graph, empty renderable set, exact image, degraded base image,
  missing mandatory dependency, custom shader independence 증명 실패 test를 작성한다.
- [ ] manifest가 validated `SceneTextureResource`, image index, `.colorSRGB`, dependent
  draw identity를 보존하는지 test한다.
- [ ] effect가 있어도 texture/UV/geometry/transform chain의 독립성이 증명되면 base
  image를 degraded render하고, 증명하지 못하면 해당 layer를 skip한다.
- [ ] stable order를 Gate 0의 Z 방향 → `sourceOrder` → stable node/instance identity로
  고정하고 texture grouping으로 재정렬하지 않는다.
- [ ] upstream diagnostics를 보존하고 status를
  `invalid > unsupported > degraded > exact` 순으로 결합한다.
- [ ] unknown interpolation, ambiguous non-white tint, unsupported start-paused 의미는
  linear/linear-color/auto-play로 추측하지 않고 해당 binding 또는 layer를 stable
  diagnostic과 함께 degraded/skip한다.
- [ ] diagnostic은 stable code/severity/node/resource identity/deterministic arguments만
  가지며 absolute path와 raw payload를 포함하지 않는다.
- [ ] fingerprint는 canonical graph value, policy version, typed render option만 쓰며
  UUID/path/object address/device identity/dictionary order를 배제한다.
- [ ] canonical bytes는 명시적 field order와 little-endian numeric encoding으로 만들고
  `CryptoKit.SHA256` lowercase hex를 fingerprint로 사용한다.
- [ ] program에 resolver, file URL, Metal object가 저장되지 않는 guard test를 둔다.

**RED:** `swift test --filter SceneRenderCompilerTests`

**GREEN:**

```bash
swift test --filter SceneRenderCompilerTests
swift test --filter SceneRenderModelTests
```

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneRenderCompiler.swift \
  Sources/MacWallSceneRenderer/SceneRenderOrdering.swift \
  Sources/MacWallSceneRenderer/SceneRenderModels.swift \
  Tests/MacWallSceneRendererTests/SceneRenderCompilerTests.swift
git commit -m "feat(scene): compile immutable render programs"
```

## 8. Task 4: Deterministic timeline evaluator 구현

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneTimelineEvaluator.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneTimelineEvaluatorTests.swift`

**Interfaces:**

- Consumes: program의 typed animation bindings와 monotonic media time
- Produces: node/instance별 `SceneEvaluatedProperties`

```swift
struct SceneTimelineEvaluator: Sendable {
    func evaluate(
        program: SceneRenderProgram,
        mediaTimeSeconds: Double,
        into scratch: inout SceneEvaluationScratch
    ) throws
}

struct SceneEvaluationScratch: Sendable {
    var nodes: [SceneEvaluatedNodeProperties]
}

struct SceneEvaluatedNodeProperties: Sendable {
    var origin: SceneGraphVector3
    var position: SceneGraphVector3
    var scale: SceneGraphVector3
    var rotationZ: Double
    var opacity: Double
    var visible: Bool
    var enabled: Bool
    var zOrder: Double
}
```

- [ ] exact keyframe, segment midpoint, before-first, after-last, duplicate boundary,
  zero/negative/non-finite time tests를 먼저 작성한다.
- [ ] Loop endpoint jump, Mirror forward/backward, Single final clamp를 fixed decimal
  timestamp test로 고정한다.
- [ ] linear, step, cubic Bezier를 CPU-only로 평가한다. Bezier x-to-progress inversion은
  bounded iteration과 epsilon을 사용한다.
- [ ] Gate 0에서 precedence가 확인되지 않은 relative track과 instance override는
  compiler에서 제외한다. evaluator에 직접 유입되면 추측 적용하지 않고 거부한다.
- [ ] S4 property 우선순위는 `base → supported absolute timeline`으로 고정한다.
- [ ] vector track 일부 channel만 invalid하면 전체 vector를 보간하지 않고 그
  channel의 base/override 값을 유지한다.
- [ ] visibility는 step만 허용하고 연속 interpolation은 compiler에서 unsupported로
  분류한다.
- [ ] evaluator는 session frame slot에 미리 할당된 `SceneEvaluationScratch`에 쓰고,
  dictionary allocation과 raw JSON traversal 없이 immutable binding array를 순회한다.
- [ ] 동일 program/time을 100회 평가한 결과가 동일한지 검증한다.

**RED:** `swift test --filter SceneTimelineEvaluatorTests`

**GREEN:** `swift test --filter SceneTimelineEvaluatorTests`

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneTimelineEvaluator.swift \
  Tests/MacWallSceneRendererTests/SceneTimelineEvaluatorTests.swift
git commit -m "feat(scene): evaluate typed scene timelines"
```

## 9. Task 5: Hierarchy와 output transform 구현, instance 명시적 제외

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneTransformEvaluator.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderCompiler.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneTimelineEvaluator.swift`
- 수정: `Tests/MacWallSceneRendererTests/SceneRenderCompilerTests.swift`
- 수정: `Tests/MacWallSceneRendererTests/SceneTimelineEvaluatorTests.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneTransformEvaluatorTests.swift`

**Interfaces:**

- Consumes: immutable program, evaluated properties, output geometry/scaling mode
- Produces: stable-order `SceneFramePlan`의 matrix, UV, opacity/tint, visibility

```swift
struct SceneTransformEvaluator: Sendable {
    func makeFramePlan(
        program: SceneRenderProgram,
        properties: SceneEvaluationScratch,
        output: SceneRenderOutputGeometry,
        into framePlan: inout SceneFramePlan
    ) throws
}

struct SceneFramePlan: Sendable {
    var drawItems: [SceneFrameDrawItem]
    var skippedDrawCount: Int
}

struct SceneRenderOutputGeometry: Equatable, Sendable {
    let width: Int
    let height: Int
    let scalingMode: SceneOutputScalingMode
}

struct SceneFrameDrawItem: Sendable {
    let identity: SceneRenderNodeIdentity
    let textureManifestIndex: Int
    let clipTransform: simd_float4x4
    let textureCoordinates: SIMD4<Float>
    let linearPremultipliedTint: SIMD4<Float>
}
```

- [ ] identity, origin, scale, Z rotation, parent-child transform tests를 먼저 작성한다.
- [ ] explicit pivot/position/Z와 instance/instance override는 Gate 0 판정대로
  compiler에서 지원하지 않고 deterministic diagnostic과 layer skip으로 고정한다.
- [ ] draw에 base/animation을 중복 저장하지 않는다. evaluation order와 같은 immutable
  node template array에 parent index, base, absolute timeline을 저장하고 draw는 해당
  node index만 참조한다.
- [ ] visibility/enabled false parent가 descendant draw에 미치는 Gate 0 의미를 test로
  고정한다.
- [ ] scene coordinate → clip coordinate matrix와 top-left texture flip을 각각 한
  지점에서만 적용한다.
- [ ] Fit은 letterbox, Fill은 center crop, Stretch는 X/Y 독립 scale로 계산하며 odd
  size와 portrait/landscape를 test한다.
- [ ] Fill crop은 texture UV 변조가 아니라 canvas-to-output transform/scissor로
  수행한다.
- [ ] opacity는 node의 `base → supported absolute timeline` 평가 후 parent opacity를 곱하고,
  각 단계가 아니라 final fragment 입력 직전에만 유효 범위로 정규화한다.
- [ ] tint는 Gate 0이 sRGB 의미를 confirmed한 경우에만 linear shader input으로
  변환한다.
- [ ] NaN/Infinity, singular transform, cycle은 undefined matrix 대신 typed
  error/diagnostic을 반환한다.
- [ ] matrix 평가가 compiler draw order를 바꾸지 않는지 확인한다.

**RED:** `swift test --filter SceneTransformEvaluatorTests`

**GREEN:**

```bash
swift test --filter SceneTransformEvaluatorTests
swift test --filter SceneTimelineEvaluatorTests
```

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneTransformEvaluator.swift \
  Sources/MacWallSceneRenderer/SceneRenderCompiler.swift \
  Sources/MacWallSceneRenderer/SceneRenderModels.swift \
  Sources/MacWallSceneRenderer/SceneTimelineEvaluator.swift \
  Tests/MacWallSceneRendererTests/SceneRenderCompilerTests.swift \
  Tests/MacWallSceneRendererTests/SceneTimelineEvaluatorTests.swift \
  Tests/MacWallSceneRendererTests/SceneTransformEvaluatorTests.swift
git commit -m "feat(scene): evaluate scene transforms and scaling"
```

## 10. Task 6: Metal pipeline, sampler, target pool 구현

**Files:**

- 수정: `Sources/MacWallSceneRenderer/SceneMetalPipelines.swift`
- 생성: `Sources/MacWallSceneRenderer/SceneRenderTargetPool.swift`
- 수정: `Sources/MacWallSceneRenderer/Shaders/SceneImage.metal`
- 수정: `Tests/MacWallSceneRendererTests/SceneMetalPipelineTests.swift`

**Interfaces:**

- Consumes: one `MTLDevice`, render limits, shader library
- Produces: pipeline/sampler states와 lease 기반 internal/final target pool

```swift
final class SceneRenderTargetAllocation: @unchecked Sendable {
    let texture: any MTLTexture
}

actor SceneRenderTargetPool {
    func acquire(width: Int, height: Int) throws -> SceneRenderTargetAllocation
    func invalidate()
}
```

- [ ] `.rgba16Float` internal target, `.bgra8Unorm_srgb` final target, render usage,
  same-device tests를 먼저 작성한다.
- [ ] sampler는 linear min/mag/mip, clamp-to-edge로 만들고 anisotropy는 공식
  `MTLSamplerDescriptor` 허용 범위 `1...16` 안의 `8`로 고정한다. Metal에는
  device별 maximum anisotropy query가 없으므로 존재하지 않는 API를 가정하지 않는다.
- [ ] source sRGB decode → linear tint/opacity → premultiplied source-over blend를 pipeline
  descriptor에 고정한다.
- [ ] straight source RGB에 alpha를 명시적으로 곱한 뒤 blend factor source `one`,
  destination `oneMinusSourceAlpha`를 사용한다. alpha에는 sRGB transfer를 적용하지
  않는다.
- [ ] uniform buffer는 최대 3개 ring으로 미리 할당하고 frame마다 새 buffer를 만들지
  않는다.
- [ ] target pool은 dimension/pixel/aggregate byte budget을 checked arithmetic로
  검증한다.
- [ ] configured max 3을 넘는 lease를 발급하지 않고 512 MiB budget이 더 작으면 실제
  in-flight count를 줄인다.
- [ ] live allocation slot은 재사용하지 않는다. allocation은 exactly-once return closure를
  갖고 마지막 owner가 해제되는 `deinit`에서만 pool slot을 반환한다.
- [ ] caller target validation은 device/size/pixel format/usage를 검사하되 외부 command의
  전역 in-flight 상태를 안다고 주장하지 않는다.
- [ ] Task 6은 clamp sampler 기반만 고정한다. content rect uniform과 exact per-mip
  texel-center/logical-edge clamp는 Task 7의 immutable per-mip rect 계약을 받은 뒤
  Task 8 encode/pixel test에서 완성해 physical padding이 filter footprint에 섞이지
  않게 한다.

**RED:** `swift test --filter SceneMetalPipelineTests`

**GREEN:** `swift test --filter SceneMetalPipelineTests`

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneMetalPipelines.swift \
  Sources/MacWallSceneRenderer/SceneRenderTargetPool.swift \
  Sources/MacWallSceneRenderer/Shaders/SceneImage.metal \
  Tests/MacWallSceneRendererTests/SceneMetalPipelineTests.swift
git commit -m "feat(scene): manage Metal pipelines and frame targets"
```

## 11. Task 7: Texture acquisition과 session preparation 구현

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneRenderSession.swift`
- 수정: `Sources/MacWallSceneTextures/SceneTextureModels.swift`
- 수정: `Sources/MacWallSceneTextures/SceneTextureStore.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneRenderSessionTests.swift`
- 수정 조건부: `Tests/MacWallSceneTexturesTests/SceneTextureStoreTests.swift`

**Interfaces:**

- Consumes: program texture manifest, `SceneTextureStore`, package context, one Metal device
- Produces: texture leases와 generation을 소유하는 ready/degraded render session

```swift
extension SceneTextureStore {
    public func acquire(
        _ request: SceneTextureRequest,
        resource: SceneTextureResource,
        context: SceneTexturePackageContext,
        for generation: SceneTextureGenerationID
    ) async throws -> SceneTextureLease
}

public actor SceneRenderSession {
    public static func prepare(
        program: SceneRenderProgram,
        device: any MTLDevice,
        textureStore: SceneTextureStore,
        textureContext: SceneTexturePackageContext,
        limits: SceneRenderLimits = .init()
    ) async throws -> SceneRenderSession
}
```

- [ ] `SceneTexturePackageContext`와 context 기반 `SceneTextureStore.acquire` overload를
  S3에 additive로 추가한다. resolver는 Textures 내부에서만 꺼내며 Renderer target은
  `MacWallSceneAssets`를 import하거나 직접 의존하지 않는다.
- [ ] synthetic package/resolver와 real `SceneTextureStore`로 all-success,
  one-resource-failure, all-resource-failure, cancellation, invalid generation,
  cross-device tests를 먼저 작성한다.
- [ ] texture generation을 만들고 manifest entry마다 exact resource/request로 모든
  acquisition을 시도한다.
- [ ] resource-local failure는 dependent draw만 제거하고 surviving draw set/status를
  deterministic하게 다시 계산한다.
- [ ] surviving draw가 0이면 `unsupported`를 반환하고 generation을 release한다.
- [ ] cancellation, invalid generation, device-wide failure는 partial ready session을
  publish하지 않고 모든 lease/generation을 정리한다.
- [ ] package context는 preparation 동안만 쓰고 fingerprint에 넣지 않는다.
- [ ] Gate 0이 per-mip rect를 `requires-contract-change`로 판정한 경우에만 S3 lease에
  immutable per-mip rect를 additive field로 추가하고 S3 tests를 보강한다.
- [ ] `invalidate()`는 idempotent하고 pending frame 완료 후 exactly once로 texture
  generation을 release한다.
- [ ] graph/configuration 변경은 existing session mutation이 아니라 새
  program/session generation 준비로만 처리한다.

**RED:** `swift test --filter SceneRenderSessionTests`

**GREEN:**

```bash
swift test --filter SceneRenderSessionTests
swift test --filter SceneTexture
```

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneRenderSession.swift \
  Tests/MacWallSceneRendererTests/SceneRenderSessionTests.swift
git add Sources/MacWallSceneTextures Tests/MacWallSceneTexturesTests
git commit -m "feat(scene): prepare device-bound render sessions"
```

## 12. Task 8: Headless Metal frame rendering 구현

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneMetalRenderer.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderSession.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 수정: `Sources/MacWallSceneRenderer/Shaders/SceneImage.metal`
- 생성: `Tests/MacWallSceneRendererTests/SceneMetalPixelTests.swift`

**Interfaces:**

- Consumes: prepared session, frame plan, texture leases, target lease/token
- Produces: GPU completion이 확인된 `SceneRenderCompletedFrame`

```swift
public final class SceneRenderCompletedFrame: @unchecked Sendable {
    public let texture: any MTLTexture
    public let mediaTimeSeconds: Double
    public let status: SceneRenderStatus
    public let diagnostics: [SceneRenderDiagnostic]
    public let drawCount: Int
    public let skippedDrawCount: Int
    public let snapshotPNG: Data?
    public func release()

    let targetAllocation: SceneRenderTargetAllocation?
}
```

- [ ] clear-only, one quad, overlapping alpha, stable Z, contentRect crop, top-left
  orientation, opacity/tint tests를 실제 Metal pixel로 먼저 작성한다.
- [ ] internal `.rgba16Float` pass에서 stable order로 합성하고 final
  `.bgra8Unorm_srgb` pass로 변환한다.
- [ ] texture coordinate는 `contentRect`를 사용하고 top-left flip은 한 번만 한다.
- [ ] semaphore blocking 대신 actor의 in-flight permit을 await한다.
- [ ] command buffer `.completed`일 때만 frame을 publish하고 `.error`/`.cancelled`는
  typed error를 반환한다.
- [ ] 첫 frame 실패는 clear/black frame을 성공으로 publish하지 않는다.
- [ ] owned mode의 이후 frame 실패는 session이 보유한 마지막 successful frame lease를
  유지하고, caller target mode는 실패 frame을 publish하지 않는다.
- [ ] completion/throw path가 permit, uniform slot, target slot, retained source를
  exactly once 정리하게 한다.
- [ ] owned output은 frame release/deinit 전 pool slot을 재사용하지 않는다.
- [ ] session의 `lastSuccessfulAllocation`과 returned frame이 같은 allocation을 각각
  strong-retain한다. 다음 성공 frame/invalidate와 caller release/deinit 양쪽이 모두
  끝나야 slot이 pool로 돌아간다.
- [ ] caller target은 exclusive token으로 받아 completion까지 retain하며 같은 session의
  token 중복 제출만 거부한다.
- [ ] invalidation 중 완료된 command가 새 generation을 오염시키지 않는 test를 둔다.
- [ ] steady-state render path에서 file I/O, texture decode, shader/pipeline creation,
  per-frame heap allocation이 발생하지 않는 counter/identity test를 둔다.

**RED:** `swift test --filter SceneMetalPixelTests/testOneQuadRendersExpectedPixels`

**GREEN:**

```bash
swift test --filter SceneMetalPixelTests
swift test --filter SceneRenderSessionTests
```

**Commit:**

```bash
git add Sources/MacWallSceneRenderer Tests/MacWallSceneRendererTests
git commit -m "feat(scene): render completed offscreen Metal frames"
```

## 13. Task 9: Snapshot readback와 PNG encode 구현

**Files:**

- 생성: `Sources/MacWallSceneRenderer/SceneSnapshotReader.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderSession.swift`
- 수정: `Sources/MacWallSceneRenderer/SceneRenderModels.swift`
- 생성: `Tests/MacWallSceneRendererTests/SceneSnapshotReaderTests.swift`

**Interfaces:**

- Consumes: completed final Metal texture와 same-device command queue
- Produces: optional path-free PNG `Data` 또는 snapshot-only diagnostic

```swift
struct SceneSnapshotReader: Sendable {
    func pngData(
        from completedTexture: any MTLTexture,
        commandQueue: any MTLCommandQueue,
        limits: SceneRenderLimits
    ) async throws -> Data
}
```

- [ ] 1×1/odd-width/alpha/orientation, row alignment, budget overflow, GPU copy failure
  tests를 먼저 작성한다.
- [ ] private final texture는 shared readback resource로 blit한 뒤 GPU completion 이후
  CPU에서 읽으며 private texture에 `getBytes`를 직접 호출하지 않는다.
- [ ] row/total bytes는 checked arithmetic를 쓰고 256 MiB budget 초과를 GPU allocation
  전에 거부한다.
- [ ] BGRA sRGB의 channel/bitmap info를 명시하고 ImageIO PNG encode는 main actor 밖에서
  실행한다.
- [ ] PNG metadata에 local path/title/Workshop payload를 넣지 않는다.
- [ ] `requestsSnapshot == false`는 readback allocation을 하지 않는다.
- [ ] snapshot failure는 completed Metal frame을 무효화하지 않고 optional diagnostic으로
  분리한다.

**RED:** `swift test --filter SceneSnapshotReaderTests`

**GREEN:**

```bash
swift test --filter SceneSnapshotReaderTests
swift test --filter SceneMetalPixelTests
```

**Commit:**

```bash
git add Sources/MacWallSceneRenderer/SceneSnapshotReader.swift \
  Sources/MacWallSceneRenderer/SceneRenderSession.swift \
  Sources/MacWallSceneRenderer/SceneRenderModels.swift \
  Tests/MacWallSceneRendererTests/SceneSnapshotReaderTests.swift
git commit -m "feat(scene): export renderer snapshots as PNG"
```

## 14. Task 10: Synthetic golden과 GPU correctness matrix 고정

**Files:**

- 수정: `Tests/MacWallSceneRendererTests/SceneMetalPixelTests.swift`
- 수정: `Tests/MacWallSceneRendererTests/SceneSnapshotReaderTests.swift`
- 생성: `Tests/Fixtures/SceneRenderer/synthetic-scene-golden.json`

**Interfaces:**

- Consumes: actual Metal pixel output과 license-safe synthetic scene inputs
- Produces: GPU-independent semantic sample-point golden schema 1

- [ ] license-safe generated 1×1/2×2 texture만 사용하고 Workshop image를 golden으로
  복사하지 않는다.
- [ ] order, alpha, sRGB/linear, contentRect padding, orientation, Fit/Fill/Stretch,
  hierarchy/instance, fixed-time timeline을 matrix에 넣는다.
- [ ] 전체 PNG hash 대신 semantic sample points와 8-bit tolerance 1을 사용한다.
- [ ] clear/edge/center/overlap points를 포함해 뒤집힌 결과가 통과하지 않게 한다.
- [ ] same input 반복 render의 order/status/dimensions/pixels가 동일한지 검증한다.
- [ ] debug PNG는 `/tmp/macwall-scene-renderer-tests/`에만 쓴다.

**RED:** `swift test --filter SceneMetalPixelTests/testSyntheticGoldenMatrix`

**GREEN:**

```bash
swift test --filter SceneMetalPixelTests
swift test --filter SceneSnapshotReaderTests
git status --short -- test Tests/Fixtures/SceneRenderer
```

`test/` 아래에 변경이 있으면 실패다.

**Commit:**

```bash
git add Tests/MacWallSceneRendererTests Tests/Fixtures/SceneRenderer/synthetic-scene-golden.json
git commit -m "test(scene): lock Metal renderer pixel semantics"
```

## 15. Task 11: 세 local fixture headless integration gate 추가

**Files:**

- 생성: `Tests/MacWallSceneRendererTests/SceneLocalFixtureRendererTests.swift`
- 생성: `Tests/Fixtures/SceneRenderer/local-scene-renderer-catalog.json`

**Interfaces:**

- Consumes: fixed local Workshop IDs와 Graph → Texture → Renderer public pipeline
- Produces: path/payload-free aggregate catalog schema 1과 opt-in catalog writer

- [ ] fixed ID를 `2174863503`, `2834933421`, `3516106265`로 hard-code하고 extra,
  duplicate, path-like ID를 거부한다.
- [ ] 모두 없으면 `XCTSkip`, 일부만 있으면 누락 ID 전체를 정렬해 fail, 모두 있으면
  gate를 실행하는 기존 Graph/Textures 정책을 재사용한다.
- [ ] Graph builder → compiler → texture session → fixed-time 320×180 render 순으로
  실행한다.
- [ ] 세 fixture 모두 fixed layer cap 없이 compile되고 surviving draw가 1개 이상이며
  actual Metal output을 생성해야 한다. 하나라도 0 draw/unsupported이면 S4 acceptance
  failure로 남기고 catalog를 그 결과로 승인하지 않는다.
- [ ] catalog에는 ID, status, aggregate draw/skipped/diagnostic counts, dimensions,
  path-redacted semantic sample hash만 기록한다.
- [ ] absolute path, title, file name, raw payload, preview bytes가 catalog/diagnostic에
  들어가지 않는 test를 추가한다.
- [ ] actual PNG는 `/tmp/macwall-scene-renderer-local-fixtures/`에만 생성한다.
- [ ] catalog writer는 `MACWALL_UPDATE_SCENE_RENDERER_CATALOG=1`일 때만 동작하고 일반
  test는 tracked catalog와 비교만 한다.
- [ ] unsupported fixture도 crash 없이 deterministic status가 되고 texture generation이
  release되는지 확인한다.

**RED:** `swift test --filter SceneLocalFixtureRendererTests`

**Catalog 생성 1회:**

```bash
MACWALL_UPDATE_SCENE_RENDERER_CATALOG=1 \
  swift test --filter SceneLocalFixtureRendererTests/testLocalSceneRendererMatchesTrackedCatalog
```

**GREEN:**

```bash
swift test --filter SceneLocalFixtureRendererTests
rg -n "/Users/|scene\.pkg|preview\.(gif|jpg)|thumbnail\.jpg|cover\.png" \
  Tests/Fixtures/SceneRenderer/local-scene-renderer-catalog.json
```

두 번째 명령은 일치 항목이 없어 exit 1이어야 정상이다.

**Commit:**

```bash
git add Tests/MacWallSceneRendererTests/SceneLocalFixtureRendererTests.swift \
  Tests/Fixtures/SceneRenderer/local-scene-renderer-catalog.json
git commit -m "test(scene): validate S4 against local scene fixtures"
```

## 16. Task 12: 전체 검증, review, 완료 문서와 직접 통합

**Files:**

- 생성: `docs/implemented/2026-08-14-scene-headless-2d-metal-renderer.md`
- 수정: `docs/README.md`
- 수정: `docs/development-roadmap.md`
- 수정: `docs/development-log.md`
- 수정: `docs/superpowers/specs/2026-07-29-scene-engine-design.md`
- 이동: S4 spec/evidence/plan을 `docs/archive/superpowers/`로 이동

**Interfaces:**

- Consumes: Task 0~11 commits, complete diff, focused/full test evidence
- Produces: implemented record, archived active docs, reviewed `main` commit

- [ ] `superpowers:requesting-code-review`로 spec과 diff 전체를 독립 검토한다.
- [ ] Critical/Important finding을 수정하고 focused test를 다시 실행한다.
- [ ] focused Graph/compiler/evaluator/Metal/snapshot/local fixture suite를 실행한다.
- [ ] 전체 `swift test`를 실행하고 total/failure/skip count를 기록한다.
- [ ] AppKit/Core/App/Native Runtime/WallpaperExtensionKit/fallback 참조가 Renderer
  target에 없는지 확인한다.
- [ ] raw JSON parsing, preview source, `makeLibrary(source:)`, blocking
  `waitUntilCompleted()`가 Renderer source에 없는지 확인한다.
- [ ] 구현 기록에 범위, degraded 규칙, limits, Metal test, local fixture aggregate,
  남은 S5 경계를 기록한다.
- [ ] roadmap은 S4 implemented, S5를 다음 phase로 바꾼다.
- [ ] active S4 spec/evidence/plan을 archive로 옮기고 docs index를 갱신한다.
- [ ] 사용자 동작은 바뀌지 않아 root README를 수정하지 않았다고 log에 기록한다.

**RED:**

```bash
test -f docs/implemented/2026-08-14-scene-headless-2d-metal-renderer.md
```

예상: 완료 기록을 아직 만들지 않았으므로 실패한다.

**GREEN:**

Focused verification:

```bash
swift test --filter SceneGraphRenderSemanticsTests
swift test --filter SceneRenderCompilerTests
swift test --filter SceneTimelineEvaluatorTests
swift test --filter SceneTransformEvaluatorTests
swift test --filter SceneRenderSessionTests
swift test --filter SceneMetalPixelTests
swift test --filter SceneSnapshotReaderTests
swift test --filter SceneLocalFixtureRendererTests
```

**Full verification:**

```bash
swift test
git diff --check
rg -n "import AppKit|MacWallCore|MacWallApp|MacWallNativeRuntimeSupport|WallpaperExtensionKit|DesktopFallback" \
  Sources/MacWallSceneRenderer
rg -n "preview\.gif|preview\.jpg|thumbnail\.jpg|cover\.png|makeLibrary\(source:|waitUntilCompleted" \
  Sources/MacWallSceneRenderer
git status --short
```

두 `rg` source guard는 일치 항목이 없어 exit 1이어야 정상이다.

**Commit:**

```bash
git add docs
git commit -m "docs(scene): record S4 headless renderer implementation"
```

**직접 통합:**

```bash
git checkout main
git merge --no-ff feature/scene-s4-headless-metal-renderer
swift test
git push origin main
git branch -d feature/scene-s4-headless-metal-renderer
```

worktree를 사용했다면 branch 삭제 전에 `git worktree list`로 실제 경로를 확인하고
`git worktree remove /tmp/macwall-scene-s4`로 계획에서 정한 격리 worktree를 제거한다.
최종 `swift test`가 실패하면 push와 branch 정리를 진행하지 않는다.

## 17. 완료 판정

1. renderer가 raw JSON, AppKit, WallpaperAgent 없이 독립 target으로 test된다.
2. supported image layer가 stable order, hierarchy/instance, transform/opacity/visibility,
   fixed-time timeline으로 평가된다.
3. S3 texture의 content rect/origin/mip 계약으로 실제 Metal pixel을 출력한다.
4. linear RGBA16Float premultiplied composition 후 BGRA8 sRGB를 출력한다.
5. target lifetime, max 3 in-flight, memory budget, cancellation이 검증된다.
6. private texture snapshot이 GPU completion 이후 PNG로 encode된다.
7. synthetic golden과 세 local fixture gate가 path/payload leakage 없이 통과한다.
8. 전체 `swift test`가 통과하고 Critical/Important review finding이 없다.
9. Main App, Native Wallpaper, Scene fallback은 변경되지 않는다.

S4 완료 후 다음 구현은 S5 Native Scene Frame Adapter다. S5 전에는 renderer output을
Desktop surface나 `desktop-fallback.png`에 연결하지 않는다.
