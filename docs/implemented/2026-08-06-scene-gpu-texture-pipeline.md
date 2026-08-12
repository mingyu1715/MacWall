# Scene S3 GPU Texture Pipeline

작성일: 2026-08-13

상태: implemented / completed

## 완료 범위

S3는 `MacWallSceneFormats -> MacWallSceneAssets -> MacWallSceneGraph` 위에
독립적인 `MacWallSceneTextures` target을 추가했다. 이 target은 package가 제공한
static texture resource를 bounded read, decode/normalization, private Metal texture
upload, generation-aware cache까지 준비한다. 화면을 그리거나 Desktop에 출력하지는
않는다.

의존성 방향은 다음으로 고정했다.

```text
MacWallSceneFormats
        |
MacWallSceneAssets
        |
MacWallSceneGraph
        |
MacWallSceneTextures
        |
S4 Headless 2D Metal Renderer
```

`MacWallSceneFormats`, `MacWallSceneAssets`, `MacWallSceneGraph`에는 Metal,
AppKit, AVFoundation 의존성을 추가하지 않았다. S3 production source는
Core/App/Native Wallpaper/fallback/Workshop thumbnail 경로에 의존하지 않는다.

## 계약과 소유권

- `SceneTextureRequest`는 package ID, canonical resource ID, image index,
  color intent를 소유한다. production request는 static single image와
  `imageIndex == 0`만 허용한다.
- `SceneTextureStore` actor는 generation 생성, `acquire`, generation release,
  unowned LRU trim, aggregate snapshot을 제공한다.
- `SceneTextureLease`는 command buffer completion 뒤에만 반환되며 physical
  storage extent, logical content extent/rect, `topLeft` origin, mip count,
  resident byte를 보존한다.
- cache key는 package ID, canonical path, package entry offset/size, image
  selection, upload policy, Metal device registry ID를 포함한다. linear/sRGB는
  같은 storage allocation의 compatible view로 관리한다.
- 동일 storage key의 concurrent request는 한 preparation/upload를 공유한다.
  generation owner가 남아 있는 ready texture는 eviction하지 않는다. 실패하거나
  stale/released generation의 결과는 cache에 설치하지 않는다.

## 준비와 upload 경로

- RGBA8, RG8, R8은 정확한 byte layout으로 private texture에 직접 upload한다.
- BC1, BC2, BC3은 device capability가 있을 때 direct block-compressed upload를
  사용하고, capability가 없으면 기존 software decoder를 통한 RGBA8 fallback을
  사용한다.
- encoded payload는 ImageIO/CoreGraphics로 straight RGBA8로 정규화한다.
  compact format-0 encoded mip chain도 physical padding과 logical content
  metadata를 유지한다.
- raw RGBA가 PNG prefix로 시작하는 경우와 BC payload의 image-signature
  collision은 raw/BC로 유지한다. 기존 Core/CALayer selected-mip decoder도
  compact format-0 encoded payload를 계속 처리한다.
- package가 제공한 static mip chain 전체를 validate하고 upload한다. 한 mip이라도
  malformed, cancel, timeout, upload failure면 texture 전체를 publish하지 않는다.

## 메모리와 동시성

- resident, aligned staging, decoded CPU memory를 분리해 reserve/resize/release한다.
  모든 실패와 cancellation 경로는 reservation rollback을 검증한다.
- 기본 limit은 resident soft/hard `384 MiB`/`512 MiB`, staging `128 MiB`, decoded
  CPU `160 MiB`, payload `64 MiB`, texture dimension `16,384`, decode/upload
  concurrency `2`/`2`, upload timeout `10s`다.
- package read, LZ4, ImageIO, CPU decode와 GPU completion wait는 Store actor
  executor 밖에서 수행한다. 이미 제출된 Metal command buffer는 completion cleanup을
  끝내되 cancellation 결과를 cache에 publish하지 않는다.

## Local Fixture Gate

tracked catalog `Tests/Fixtures/SceneTextures/local-scene-texture-catalog.json`의
fixed fixture 집계는 capability profile `bc-compression=true;logical-bytes=unaligned;policy=1`
기준이다.

| Workshop ID | Texture resources | GPU successes | Typed unsupported |
| --- | ---: | ---: | ---: |
| `2174863503` | 37 | 33 | animation 4 |
| `2834933421` | 135 | 134 | video 1 |
| `3516106265` | 25 | 21 | animation 4 |
| **Total** | **197** | **188** | **9** |

catalog에는 Workshop ID, package version, format/container/upload path count,
logical payload byte와 typed unsupported aggregate만 둔다. host path, package entry
path, payload, screenshot은 기록하지 않는다.

## 검증

현재 HEAD `7d2748f`에서 2026-08-13 Asia/Seoul 기준으로 실행했다.

| Focused suite | Tests | Failures | Skips |
| --- | ---: | ---: | ---: |
| `SceneTextureModelsAndCapabilitiesTests` | 3 | 0 | 0 |
| `SceneTextureLoadPlannerTests` | 16 | 0 | 0 |
| `SceneTexturePayloadLoaderTests` | 13 | 0 | 0 |
| `SceneTextureImageDecoderTests` | 12 | 0 | 0 |
| `SceneTextureMemoryBudgetTests` | 13 | 0 | 0 |
| `DirectSceneTextureAllocatorTests` | 21 | 0 | 0 |
| `SceneTextureCacheTests` | 12 | 0 | 0 |
| `SceneTextureStoreTests` | 25 | 0 | 0 |
| `SceneTexturePipelineIntegrationTests` | 29 | 0 | 0 |
| `SceneLocalFixtureTextureTests` | 15 | 0 | 0 |
| **Focused total** | **159** | **0** | **0** |

- local fixture GPU aggregate check: `15 tests, 0 failures, 0 skips`, XCTest
  duration `102.257s`.
- full `swift test`: `576 tests, 0 failures, 0 skips`; XCTest duration
  `106.275s` (`106.319s` including suite accounting).
- static/privacy checks: Formats/Assets/Graph forbidden framework import 없음,
  S3 production의 Core/App/Native/fallback/thumbnail reference 없음, tracked
  catalog의 host/entry path 없음, `git diff --check` 통과, fixture directory 변경 없음.
- 전체 S3 diff를 design과 대조했다. dependency/ownership, format/signature,
  full-mip atomicity/padding, actor/cancellation, cache generation, memory rollback,
  deterministic catalog 경계에서 추가 코드 문제를 발견하지 못했다.

## 명시적 비범위

다음은 S3에 구현하지 않았다.

- Scene renderer, Desktop Scene output, Scene fallback
- animation/video texture 실행
- heap allocator, sparse/placement texture, mip streaming, residency set
- GUI, System Settings 또는 visual Desktop validation

기존 Core/CALayer prototype과 Video/Web/Legacy runtime은 S3에 연결하지 않았다.

## 다음 단계

다음 설계 단계는 **S4 Headless 2D Metal Renderer**다. S4는
`SceneGraphDocument + SceneTextureLease`를 소비해 deterministic offscreen 2D
Metal frame을 만드는 범위로 시작한다. Desktop Native adapter, snapshot, effects,
animation/video, heap/streaming은 S4 이후 별도 phase다.
