# Scene S3 GPU Texture Pipeline Design

작성일: 2026-08-06

상태: approved design / implementation plan ready / implementation not started

## 1. 결정 요약

S3는 S2 typed graph가 보존한 package texture resource를 renderer가 소비할
수 있는 immutable Metal texture로 준비하는 독립 pipeline을 만든다.

장기 구조는 heap, streaming, residency를 수용하지만 S3의 첫 allocator는
private `MTLTexture`와 staging buffer를 사용하는 direct allocator다. 실제
renderer usage와 frame lifetime을 측정하기 전에는 `MTLHeap`, sparse texture,
mip streaming, residency set을 구현하지 않는다.

```text
MacWallSceneFormats
        |
        v
MacWallSceneAssets
        |
        v
MacWallSceneGraph
        |
        v
MacWallSceneTextures
        |
        v
S4 Headless 2D Metal Renderer
```

S3는 화면을 그리지 않는다. 첫 offscreen render milestone은 S4이고 첫 실제
Desktop Scene milestone은 S5다.

## 2. 근거

S1은 bounded package/TEX reader와 selected-mip software decoder를 제공한다.
S2는 package identity와 provenance가 있는 `SceneTextureResource`를 typed graph에
보존한다. S3는 이 두 계약을 연결하되 format parsing, graph semantics, GPU
allocation을 다시 섞지 않는다.

세 local fixture의 현재 TEX 분포는 다음과 같다.

| Workshop ID | TEX | Format 분포 | 특이 사항 |
| --- | ---: | --- | --- |
| `2174863503` | 37 | RGBA8888 37 | TEXS0003 animation 4 |
| `2834933421` | 136 | RGBA8888 78, RG88 39, R8 19 | video flag evidence 1 |
| `3516106265` | 27 | RGBA8888 4, DXT5/BC3 18, RG88 1, R8 4 | B0004 non-video 11, TEXS0003 animation 4 |

실제 fixture에서 BC3 direct upload가 의미 있는 최적화이며 RG88/R8을 강제로
RGBA8로 확장하지 않는 것도 resident memory에 중요하다. 반대로 실제 usage가
없는 상태에서 heap 크기와 streaming threshold를 고정할 근거는 없다.

## 3. 목표

- `MacWallSceneTextures` 독립 Swift Package target을 추가한다.
- package texture resource를 bounded read로 inspect하고 upload plan으로 변환한다.
- RGBA8, RG8, R8과 지원되는 BC1/BC2/BC3 payload를 원래 channel/storage 형식으로
  private Metal texture에 올린다.
- BC texture compression 미지원 GPU에서는 기존 software decoder를 사용해
  RGBA8로 fallback한다.
- embedded encoded image는 ImageIO/CoreGraphics로 straight RGBA8로 정규화한다.
- package가 제공한 static mip chain 전체를 atomic하게 준비한다.
- 같은 texture load를 dedupe하고 generation 단위 ownership과 eviction을 제공한다.
- resident, staging, decoded CPU memory를 분리해서 accounting한다.
- allocator 경계를 유지해 후속 `HeapTextureAllocator`를 추가할 수 있게 한다.
- synthetic test와 세 local fixture에서 GUI 없이 실제 Metal upload를 검증한다.

## 4. 비목표

S3에서는 다음을 하지 않는다.

- draw call, render pass, compositor, visual correctness
- `MTLHeap`, placement/sparse texture, residency set
- projected size 기반 mip streaming 또는 mip 생성
- animated texture, video texture, multi-image semantics 실행
- effect, shader, SceneScript 실행
- Core, App, Native Wallpaper extension, 기존 CALayer prototype 연결
- Scene fallback 또는 Workshop thumbnail 사용
- shared external Wallpaper Engine asset integration
- GUI, System Settings, Desktop 출력 검증

## 5. 플랫폼 정책

- Swift Package compile floor는 macOS 14+와 Swift 6을 유지한다.
- S3의 성능과 실제 GPU acceptance 기준은 Apple Silicon이다.
- S5 Native Scene output은 macOS 26+ Apple Silicon을 기준으로 한다.
- architecture 이름으로 capability를 추측하지 않는다.
- BC direct upload는 `MTLDevice.supportsBCTextureCompression`을 runtime에 확인한다.
- capability가 없으면 software RGBA fallback을 사용한다.
- GPU feature 판단은 테스트에서 주입 가능한 value contract로 분리한다.

Apple은 storage mode가 Apple Silicon과 Intel/discrete GPU에서 다르게 동작하므로
고정된 hardware 가정보다 runtime feature inspection을 사용하도록 안내한다.
S3는 이 원칙을 따른다.

## 6. Target과 의존성

새 target:

```text
MacWallSceneTextures
├─ MacWallSceneGraph
├─ MacWallSceneAssets
├─ MacWallSceneFormats
├─ Foundation
├─ Metal
├─ CoreGraphics
├─ ImageIO
└─ Accelerate (encoded-image alpha normalization에 필요한 경우만)
```

`MacWallSceneGraph`는 Metal을 import하지 않는다. `MacWallSceneTextures`도
Core/App/Native target에 의존하지 않는다. S4 renderer가 이후 이 target에
의존한다.

파일 책임은 다음처럼 분리한다.

```text
Sources/MacWallSceneTextures/
├─ SceneTextureModels.swift
├─ SceneTextureCapabilities.swift
├─ SceneTextureLoadPlanner.swift
├─ SceneTexturePayloadLoader.swift
├─ SceneTextureImageDecoder.swift
├─ SceneTextureAllocator.swift
├─ DirectSceneTextureAllocator.swift
├─ SceneTextureUploadExecutor.swift
├─ SceneTextureMemoryBudget.swift
├─ SceneTextureCache.swift
├─ SceneTextureStore.swift
└─ SceneTexturePipelineLoader.swift
```

한 파일이 format mapping, decode, upload, cache를 동시에 소유하지 않는다.

## 7. Public Contract

### 7.1 Package와 generation identity

```swift
public struct SceneTexturePackageID: Hashable, Sendable {
    public let rawValue: UUID
}

public struct SceneTextureGenerationID: Hashable, Sendable {
    public let rawValue: UUID
}
```

`SceneTexturePackageID`는 absolute path가 아니며 imported asset generation이
바뀔 때 새 값으로 교체한다. 같은 canonical path가 다른 package와 cache에서
충돌하면 안 된다.

### 7.2 Request

```swift
public enum SceneTextureColorIntent: String, Hashable, Sendable {
    case colorSRGB
    case dataLinear
}

public struct SceneTextureRequest: Hashable, Sendable {
    public let packageID: SceneTexturePackageID
    public let resourceID: SceneResourceID
    public let imageIndex: Int
    public let colorIntent: SceneTextureColorIntent
}
```

S3 production request의 `imageIndex`는 `0`만 허용한다. field는 S9 확장 시
public contract를 깨지 않기 위해 유지한다.

### 7.3 Artifact와 lease

```swift
public struct SceneTextureExtent: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
}

public struct SceneTextureContentRect: Equatable, Sendable {
    public let u: Float
    public let v: Float
    public let width: Float
    public let height: Float
}

public enum SceneTextureOrigin: String, Sendable {
    case topLeft
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

lease는 command buffer 완료 후에만 반환된다. lease가 속한 generation을 release한
뒤에는 caller가 texture를 다시 사용하지 않는 것이 계약이다. Store는 generation
ownership을 기준으로 eviction 가능 여부를 판단한다.

### 7.4 Store

```swift
public actor SceneTextureStore {
    public func makeGeneration() -> SceneTextureGenerationID

    public func acquire(
        _ request: SceneTextureRequest,
        resource: SceneTextureResource,
        resolver: ScenePackageAssetResolver,
        for generation: SceneTextureGenerationID
    ) async throws -> SceneTextureLease

    public func releaseGeneration(
        _ generation: SceneTextureGenerationID
    )

    public func trimToSoftBudget() async

    public func snapshot() -> SceneTextureStoreSnapshot
}
```

S4가 package별 resolver/session wrapper를 추가할 수 있지만 S3는 기존 resolver
identity validation을 우회하지 않는다.

## 8. Capability와 Pure Load Plan

Metal object 없이 unit-test 가능한 capability contract를 둔다.

```swift
public struct SceneTextureDeviceCapabilities: Equatable, Sendable {
    public let supportsBCTextureCompression: Bool
    public let linearTextureAlignment: [SceneTextureGPUFormat: Int]
}

public enum SceneTextureGPUFormat: String, Hashable, Sendable {
    case rgba8Unorm
    case rg8Unorm
    case r8Unorm
    case bc1RGBA
    case bc2RGBA
    case bc3RGBA
}

public enum SceneTextureUploadPath: String, Sendable {
    case directUncompressed
    case directBlockCompressed
    case softwareRGBA
    case encodedImageRGBA
}
```

`SceneTextureLoadPlanner`는 descriptor, color intent, capability만 받아 immutable
plan을 반환한다. package read, allocation, command submission은 하지 않는다.

encoded image signature는 payload read 전에 판단할 수 없으므로 unknown format은
planner 내부의 encoded-image probe로 유예한다. bounded payload loader가
선택된 static mip 전부의 signature를 확인한 후에만 final
`.encodedImageRGBA` path로 승격하고, 하나라도 인식되지 않으면
`unsupportedPixelFormat(rawValue)`를 반환한다.

## 9. Format Mapping

| TEX format | 의미 | GPU format | 기본 path |
| ---: | --- | --- | --- |
| `0` | RGBA8888 | `rgba8Unorm` | direct uncompressed |
| `4` | DXT5/BC3 | `bc3RGBA` | direct BC 또는 software RGBA |
| `6` | DXT3/BC2 | `bc2RGBA` | direct BC 또는 software RGBA |
| `7` | DXT1/BC1 | `bc1RGBA` | direct BC 또는 software RGBA |
| `8` | RG88 | `rg8Unorm` | direct uncompressed |
| `9` | R8 | `r8Unorm` | direct uncompressed |
| signature 기반 encoded image | PNG/JPEG/GIF/WebP/HEIC 등 | `rgba8Unorm` | ImageIO RGBA |

정책:

- LZ4는 GPU texture compression이 아니므로 bounded CPU expansion 후 mapping한다.
- BC direct path는 capability가 true일 때만 선택한다.
- BC capability가 false이면 `SceneTextureSoftwareDecoder`의 RGBA path를 사용한다.
- unknown format은 모든 selected static mip이 accepted encoded-image signature일
  때만 ImageIO path로 승격하고 그 외에는
  `unsupportedPixelFormat(rawValue)`다.
- malformed block/payload는 fallback하지 않고 invalid error다.
- R8/RG8은 linear data texture다. `colorSRGB` request는 invalid request다.
- RGBA/BC는 linear base storage와 compatible sRGB texture view를 제공한다.
- 같은 payload의 linear/sRGB view는 resident allocation을 중복하지 않는다.

## 10. Payload Validation과 Upload

각 mip은 allocation 전에 expected payload byte count를 계산한다.

```text
RGBA8 = width * height * 4
RG8   = width * height * 2
R8    = width * height
BC1   = ceil(width / 4) * ceil(height / 4) * 8
BC2/3 = ceil(width / 4) * ceil(height / 4) * 16
```

모든 곱셈과 합은 overflow checked다. LZ4 expansion 결과와 raw payload는 expected
byte count와 정확히 일치해야 한다. extra/truncated bytes를 조용히 무시하지 않는다.

staging layout은 256-byte 같은 값을 hardcode하지 않는다. 실제 device의
`minimumLinearTextureAlignment(for:)` 결과로 mip별 row stride와 offset을
정렬한다. logical payload bytes와 aligned staging bytes를 따로 accounting한다.

upload 흐름:

```text
bounded entry source
-> descriptor inspect/read
-> selected static image and full mip chain
-> per-mip bounded payload read
-> optional LZ4 expansion
-> direct payload or CPU decode
-> aligned staging buffer
-> private texture allocation
-> blit copy for every mip
-> command buffer completion
-> optional sRGB view
-> cache install and lease publication
```

texture descriptor는 `.private`, `.shaderRead`, 필요한 경우 `.pixelFormatView`를
사용한다. command buffer가 error 또는 timeout 상태면 cache에 설치하지 않는다.

## 11. Mip, Padding, Image 정책

- descriptor의 static `images.count == 1`만 지원한다.
- descriptor가 제공한 mip chain 전체를 upload한다.
- mip 하나만 있으면 GPU/CPU에서 임의 mip을 생성하지 않는다.
- 한 mip이라도 실패하면 texture 전체가 실패한다.
- `descriptor.animation != nil`, animation flag, video flag/metadata는 typed
  unsupported다.
- 의미가 확정되지 않은 multi-image는 typed unsupported다.
- B0004라도 video가 아니고 single static image/mip contract를 만족하면 지원한다.

compressed texture는 padded physical extent를 유지할 수 있다. artifact는 다음을
모두 보존한다.

```text
storageExtent       physical mip-0 storage dimensions
contentExtent       logical image dimensions
contentRect         normalized logical sampling rectangle
origin              topLeft
```

S4는 `contentRect`를 적용해야 하며 padding을 화면에 표시하면 안 된다. CPU crop
fallback도 같은 metadata contract를 반환한다.

## 12. Color, Alpha, Origin

- color intent는 request에 명시한다. S3가 material slot 이름으로 추측하지 않는다.
- RGBA/BC color view는 sRGB sampling conversion을 사용한다.
- normal, mask, lookup/data texture는 linear view를 사용한다.
- R8/RG8은 항상 linear다.
- raw RGBA/BC의 alpha 표현은 straight alpha로 취급한다.
- ImageIO decode는 CoreGraphics/Accelerate를 사용해 straight RGBA8로 정규화한다.
- decoded image dimensions는 descriptor의 logical content extent와 일치해야 한다.
- row orientation은 `topLeft` metadata로 고정하고 S4 shader가 UV convention을
  소비한다. S3는 임의 vertical flip을 하지 않는다.

색 의미가 아직 불명확한 binding은 S4에서 `dataLinear`를 기본으로 선택하고
unsupported/degraded evidence를 유지한다. 시각적으로 그럴듯하다는 이유로 sRGB를
추측하지 않는다.

## 13. Allocator 경계

내부 allocator contract:

```swift
protocol SceneTextureAllocator: Sendable {
    func allocate(
        _ plan: SceneTextureAllocationPlan,
        payload: SceneTexturePreparedPayload
    ) async throws -> SceneAllocatedTexture
}
```

S3 구현:

```text
DirectSceneTextureAllocator
-> aligned staging MTLBuffer
-> private MTLTexture
-> blit command buffer
```

후속 구현:

```text
HeapSceneTextureAllocator
-> MTLHeap suballocation
-> renderer usage 기반 alias/residency
```

Store, cache key, lease, S4 consumer는 allocator 종류를 알지 못한다.

## 14. Cache와 Generation Ownership

cache key:

```text
package ID
+ canonical resource path
+ package entry identity(offset, byte count)
+ image selection
+ upload policy version
+ Metal device registry ID
```

color view는 같은 storage entry 아래 관리한다. 동일 key의 concurrent load는 한
in-flight task로 dedupe한다.

Store의 shared storage preparation은 linear allocation 기준으로 한 번만 실행하고
prepare 결과의 compatible sRGB view 여부를 각 waiter color intent에 따라
개별 검증한다. 첫 waiter의 color intent가 같은 storage의 다른
waiter를 실패시키거나 duplicate allocation을 만들면 안 된다.

entry 상태:

```text
loading(waiters)
ready(texture, generation owners, last access)
failed(not cached)
```

generation 정책:

- `acquire` 성공 시 generation owner를 추가한다.
- staged generation 전체가 실패하면 caller가 그 generation만 release한다.
- 기존 active generation의 owners와 texture는 유지한다.
- owner가 하나라도 있는 ready entry는 eviction하지 않는다.
- `releaseGeneration`은 deterministic하게 모든 owner를 제거한다.
- owner가 없는 entry만 LRU 후보가 된다.

한 waiter가 cancel되어도 다른 waiter가 있으면 load를 유지한다. 모든 waiter가
cancel되면 아직 제출하지 않은 작업은 취소한다. 이미 제출한 Metal command
buffer는 완료 handler까지 cleanup 책임을 유지하고 결과를 cache에 설치하지 않는다.

## 15. Concurrency

- `SceneTextureStore`는 actor다.
- package read와 CPU decode/LZ4/ImageIO는 Store actor executor 밖에서 실행한다.
- bounded decode worker와 upload limiter를 사용한다.
- 기본 concurrent decode 수는 2다.
- 기본 concurrent upload 수는 2다.
- 기본 upload completion timeout은 10초다.
- actor는 mutable cache/accounting만 소유하고 긴 decode 또는 GPU wait를 직접
  수행하지 않는다.
- upload 완료 전 texture를 publication하지 않는다.
- stale package/generation completion은 cache ownership을 획득하지 못한다.

## 16. Memory Budget

기본값:

| Budget | 값 |
| --- | ---: |
| resident soft | 384 MiB |
| resident hard | 512 MiB |
| staging aggregate | 128 MiB |
| decoded CPU aggregate | 160 MiB |
| single compressed/decompressed payload | 64 MiB |
| maximum texture dimension | 16,384 |
| maximum software decoded pixels | 18,000,000 |
| concurrent decode | 2 |
| concurrent upload | 2 |
| upload completion timeout | 10 seconds |

정책:

- 새 allocation 전 soft budget을 넘으면 unowned LRU를 먼저 제거한다.
- hard budget을 넘는데 제거 가능한 entry가 없으면 명시적 resource-limit error다.
- live generation을 강제로 제거하지 않는다.
- resident accounting은 생성된 resource의 실제 `allocatedSize`를 우선한다.
- staging은 aligned allocation size, decoded CPU는 실제 `Data.count`를 사용한다.
- in-flight reservation을 먼저 잡고 작업 실패/cancel 시 반드시 반환한다.
- underflow, double release, reservation leak은 invariant failure로 테스트한다.

thermal, battery, memory pressure에 따른 동적 budget 조절은 usage 측정 후 별도
정책으로 추가한다.

## 17. Error Contract

```swift
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
```

원칙:

- unsupported와 malformed를 구분한다.
- capability 부재는 BC software fallback 가능 여부를 먼저 확인한다.
- malformed payload를 fallback으로 숨기지 않는다.
- 실패 texture와 generation은 cache에 설치하지 않는다.
- absolute filesystem path, payload bytes, local username은 error/summary에 넣지 않는다.
- public error는 stable category와 bounded metadata만 제공한다.

## 18. Snapshot과 Deterministic Summary

`SceneTextureStoreSnapshot`은 다음 aggregate만 제공한다.

- cache hit/miss/in-flight dedupe count
- direct raw/direct BC/software/ImageIO path count
- ready/loading/unowned entry count
- resident/staging/decoded current와 peak bytes
- eviction count와 resource-limit failure count
- unsupported category count

tracked local catalog 경로:

```text
Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json
```

tracked catalog는 `supportsBCTextureCompression == true`인 fixed capability
profile과 unaligned logical byte 계산을 사용한다. 실제
`MTLTexture.allocatedSize`와 device alignment는 hardware마다 다를 수 있으므로
tracked deterministic JSON에 넣지 않는다. runtime 실제 peak는 test output과
development log에 측정값으로 기록할 수 있다.

catalog에는 Workshop ID, package version, format/container count, upload plan count,
unsupported count, logical payload bytes만 기록한다. package path, entry path,
payload, screenshot은 기록하지 않는다.

## 19. Test Strategy

### 19.1 Pure unit tests

- format/capability별 upload plan
- BC block count와 byte 계산
- raw row byte와 overflow
- device alignment 기반 staging layout
- full mip chain과 partial failure
- padded content rect
- linear/sRGB view policy
- animated/video/multi-image unsupported
- cache key와 in-flight dedupe
- generation ownership/release
- LRU와 soft/hard budget
- staging/decoded reservation rollback
- cancellation과 stale completion
- deterministic snapshot ordering

### 19.2 Synthetic headless Metal tests

- GUI 없이 `MTLCreateSystemDefaultDevice()` 사용
- R8/RG8/RGBA8 private upload와 blit readback
- BC1/BC2/BC3 private upload와 compressed byte readback
- injected BC-disabled capability에서 software RGBA fallback
- encoded image ImageIO normalization과 readback
- multiple mip upload
- sRGB-compatible texture view
- command buffer/allocation failure 시 cache 미설치

Metal device가 없는 environment에서는 synthetic GPU integration만 명시적으로
skip할 수 있다. 현재 승인된 macOS 개발 환경의 완료 검증에서는 skip 0을 요구한다.

### 19.3 Local fixture gate

fixed IDs:

```text
2174863503
2834933421
3516106265
```

- 세 fixture가 모두 없을 때만 local test를 skip한다.
- 일부만 있으면 missing fixed ID를 정렬해 실패한다.
- 모든 texture dependency를 resolve/inspect한다.
- 지원 가능한 static single-image texture를 실제 default Metal device에 upload한다.
- unsupported animation/video/multi-image를 category별로 집계한다.
- 같은 fixture를 두 번 planning하여 canonical catalog bytes가 같은지 확인한다.
- fixture source git status와 package SHA-256가 unchanged인지 확인한다.
- 원본 package를 수정하거나 Git에 커밋하지 않는다.

정확한 supported/unsupported 수와 peak memory는 구현 후 command output에서 측정해
완료 기록에 넣는다. 설계 문서에 예측값을 적지 않는다.

## 20. 완료 조건

- `MacWallSceneTextures` target이 독립적으로 존재한다.
- Formats/Assets/Graph target은 Metal을 import하지 않는다.
- 실제 세 fixture의 지원 가능한 static texture가 crash 없이 GPU upload된다.
- BC direct와 injected BC-disabled software fallback이 모두 검증된다.
- 전체 supplied mip chain이 atomic하게 upload된다.
- 같은 key concurrent request가 한 번만 decode/upload된다.
- generation release 전 live texture가 eviction되지 않는다.
- 모든 configured memory limit에 boundary test가 있다.
- local catalog가 deterministic/path-redacted aggregate만 포함한다.
- focused와 full `swift test`가 failure 0, 승인 환경에서 skip 0으로 통과한다.
- Core/App/Native/CALayer prototype과 Video/Web/Legacy behavior가 unchanged다.
- GUI, Desktop output, Scene fallback, S4 rendering을 완료했다고 주장하지 않는다.

## 21. 후속 단계

S3 완료 후 S4는 다음 계약만 소비한다.

```text
SceneGraphDocument
+ SceneTextureLease
-> image transform/opacity/Z/parent/instance evaluation
-> offscreen deterministic Metal frame
```

S4 실제 측정에서 direct allocations의 fragmentation, churn, residency cost가
확인되면 `HeapSceneTextureAllocator`를 추가한다. projected size와 frame usage가
생긴 뒤 mip streaming을 설계한다. 이 순서는 long-term 구조를 막지 않으면서
근거 없는 optimization을 피한다.

## 22. 참고 자료

- [Apple: Setting resource storage modes](https://developer.apple.com/documentation/metal/setting-resource-storage-modes)
- [Apple: Copying data to a private resource](https://developer.apple.com/documentation/metal/copying-data-to-a-private-resource)
- [Apple: MTLDevice.supportsBCTextureCompression](https://developer.apple.com/documentation/metal/mtldevice/supportsbctexturecompression)
- [Apple: Metal pixel formats](https://developer.apple.com/documentation/metal/mtlpixelformat)
- [Apple: Metal Feature Set Tables](https://developer.apple.com/metal/capabilities/)
- [S1 구현 기록](../../implemented/2026-07-29-scene-format-layer-hardening.md)
- [S2 구현 기록](../../implemented/2026-08-04-scene-asset-resolver-typed-graph.md)
- [Scene Engine 상위 설계](2026-07-29-scene-engine-design.md)
