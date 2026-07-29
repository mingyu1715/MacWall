# MacWall Scene Format Layer Hardening Design

상태: 설계 합의 완료, 문서 검토 대기

작성일: 2026-07-29
대상: Scene Engine S1 Format Layer Hardening

## 1. 목적

S1은 S0에서 확인한 `scene.pkg`와 TEX 구조를 production-oriented format
module로 다시 구현합니다.

현재 Scene parser는 `MacWallCore` 안에서 package 전체를 `Data`로 읽고,
entry를 `subdata`로 복사합니다. TEX metadata reader는 audit model을 직접
반환하고, software decoder는 format parsing과 payload decode를 한 함수에서
수행합니다.

S1의 목표는 이 결합을 제거하는 것입니다.

```text
scene.pkg file
-> bounded random-access byte source
-> versioned package index
-> bounded entry source
-> versioned TEX descriptor
-> audit 또는 선택적 software decode
```

S1 완료 후에는 package/TEX/audit 구현이 `MacWallCore`에 남지 않습니다.

## 2. 범위

### 포함

- `MacWallSceneFormats` target
- `MacWallSceneAudit` target
- file descriptor와 `pread` 기반 random-access source
- versioned PKG index
- bounded entry source
- versioned TEX inspection과 descriptor
- selected mip software decode
- LZ4, DXT1, DXT3, DXT5 software decode 이관
- audit report schema version 2
- 기존 `SceneRenderPlanBuilder`의 새 Formats API 소비
- 기존 `scene-info`, `scene-render-info` command의 새 module 연결
- synthetic malformed corpus와 local fixture regression
- 기존 format/audit 구현 삭제

### 제외

- S2 asset resolver와 typed Scene graph
- Metal upload와 GPU texture pipeline
- Metal renderer와 Native Scene surface
- Scene fallback 생성
- effect, particle, text, media 실행
- SceneScript 실행
- 새로운 `macwallctl` command
- Workshop crawling, download, authentication, DRM
- 실제 Workshop payload의 Git 추적

현재 `CALayer` Scene prototype은 기능을 확장하지 않습니다.

## 3. 검수 근거

현재 local fixture:

| Workshop ID | PKG | Entries | Size | TEX |
| --- | --- | ---: | ---: | ---: |
| `2174863503` | `PKGV0008` | 107 | 약 13 MiB | 37 |
| `2834933421` | `PKGV0018` | 387 | 약 59 MiB | 136 |
| `3516106265` | `PKGV0023` | 125 | 약 14 MiB | 27 |

세 package 모두:

- exact duplicate entry path: 0
- overlapping payload range: 0
- package index: 16 KiB 미만

TEX 재검수:

- `2174863503`: B0003 37개, TEXS0003 animation 4개
- `2834933421`: B0003 136개
- `3516106265`: B0003 16개, B0004 non-video 11개, TEXS0003 animation 4개
- known TEX entry trailing byte: 모두 0
- 실제 fixture의 B0004 `isVideoMP4 == true`: 0개

B0004 video layout은 synthetic fixture로 검증합니다. 실제 fixture 검증 없이
production-supported라고 표시하지 않습니다.

## 4. Module Architecture

### 4.1 Targets

```text
MacWallSceneFormats
├─ SceneByteSource
├─ ScenePackageArchive
├─ SceneTextureDescriptor
├─ SceneTextureSoftwareDecoder
└─ SceneFormatError

MacWallSceneAudit
├─ SceneAuditReport v2
├─ SceneJSONInspector
├─ SceneAuditor
├─ SceneAuditSupportPolicy
└─ SceneAuditReportEncoder

MacWallCore
├─ Scanner
├─ LibraryStore
├─ Conversion
└─ SceneRenderPlan prototype
```

Target dependency:

```text
MacWallSceneAudit -> MacWallSceneFormats
MacWallCore       -> MacWallSceneFormats
MacWallApp        -> MacWallCore
macwallctl        -> MacWallCore + MacWallSceneAudit
```

`MacWallSceneFormats`와 `MacWallSceneAudit` 사이에 역방향 dependency를
만들지 않습니다. Formats는 audit status, diagnostic, JSON schema를 알지
않습니다.

### 4.2 Test Targets

```text
MacWallSceneTestSupport
├─ synthetic PKG/TEX builders
└─ recording byte source

MacWallSceneFormatsTests
MacWallSceneAuditTests
MacWallCoreTests
```

`MacWallSceneTestSupport`는 product에 포함하지 않는 test-only support target입니다.
Core의 scanner/library tests가 필요한 최소 package fixture helper도 이 target을
사용합니다.

## 5. Replacement Strategy

호환 facade 없이 staged replacement를 사용합니다.

### Stage 1: New package foundation

- 새 targets를 추가합니다.
- random-access source와 PKG index를 구현합니다.
- 기존 `MacWallCore` Scene parser는 비교 기준으로 유지합니다.

### Stage 2: New texture format and decoder

- TEX inspection과 descriptor를 구현합니다.
- software decoder를 새 descriptor 위로 구현합니다.
- 기존 decoder와 synthetic/local 결과를 비교합니다.

### Stage 3: Audit v2

- 새 Audit target을 구현합니다.
- S0 aggregate catalog와 같은 feature/count 결과를 요구합니다.
- schema 2 canonical report를 별도로 검증합니다.

### Stage 4: Consumer migration and deletion

- `SceneRenderPlanBuilder`를 새 Formats API로 전환합니다.
- CLI를 새 Audit/Formats API로 전환합니다.
- README의 `scene-info` 설명을 갱신합니다.
- 모든 focused/full test가 통과한 뒤 기존 format/audit 파일을 삭제합니다.

기존 타입을 re-export하거나 `typealias`로 유지하지 않습니다.

## 6. Random-access Source Contract

### 6.1 Public interface

```swift
public protocol SceneByteSource: Sendable {
    var byteCount: UInt64 { get }

    func read(
        range: Range<UInt64>
    ) throws -> Data
}
```

모든 range는 source-relative입니다. Empty range는 empty `Data`를 반환합니다.
범위 밖, overflow, short read는 typed error입니다.

### 6.2 File source

`SceneFileByteSource`는:

- initializer에서 file을 read-only로 엽니다.
- `fstat`으로 byte count를 고정합니다.
- open file descriptor를 source lifetime 동안 유지합니다.
- shared seek cursor 대신 `pread`를 사용합니다.
- `EINTR`를 재시도합니다.
- expected byte count를 모두 읽지 못하면 truncated read로 처리합니다.
- local absolute path를 error description에 넣지 않습니다.

열린 descriptor는 path가 다른 file로 교체되어도 같은 inode를 계속 가리킵니다.
File이 열린 뒤 truncate되면 short read로 실패합니다.

`pread`는 shared offset을 변경하지 않으므로 concurrent read가 가능합니다.
Source object가 살아 있는 동안 descriptor가 close되지 않도록 강한 ownership을
유지합니다.

### 6.3 Data and bounded source

- `SceneDataByteSource`: Formats target의 작은 in-memory source
- `SceneBoundedByteSource`: parent source의 한 range만 노출
- Bounded source는 child range를 parent range로 overflow 없이 translate

Package entry는 `SceneBoundedByteSource`로 제공하며 entry 전체를 복사하지
않습니다. Test support의 recording source는 production
`SceneDataByteSource`를 감싸고 read range만 기록합니다.

## 7. PKG Contract

### 7.1 Types

```text
ScenePackageArchiveReader
ScenePackageArchive
ScenePackageVersion
ScenePackageEntry
ScenePackageIndexIssue
```

`ScenePackageVersion`은 raw magic과 numeric version을 보존합니다.
`PKGV` 뒤 정확히 네 개의 ASCII decimal digit가 있어야 합니다.

관찰된 `0008`, `0018`, `0023` 외 numeric version도 같은 index envelope로
parse하되 `unverifiedVersion` index issue를 기록합니다. 알 수 없는 version을
지원된다고 표시하지 않으며 raw magic을 보존합니다.

`ScenePackageEntry`는:

- package-relative path
- original offset
- byte count
- payload source range

를 가집니다.

`ScenePackageArchive`는:

- immutable source
- version
- deterministic entry array
- exact path lookup index
- package index issues

를 가집니다.

Entry access:

```swift
public func source(
    for entry: ScenePackageEntry
) -> SceneBoundedByteSource

public func read(
    entry: ScenePackageEntry,
    maximumBytes: UInt64
) throws -> Data
```

Unbounded entry read convenience는 제공하지 않습니다.

### 7.2 Index parsing

- magic과 entry table만 incremental read합니다.
- entry offset은 payload section start 기준으로 계산합니다.
- 모든 signed Int32를 검증한 뒤 UInt64 range로 변환합니다.
- payload start, offset, length addition의 overflow를 검사합니다.
- entry range는 open file size 안에 있어야 합니다.
- package 전체 `Data`를 생성하지 않습니다.

### 7.3 Path policy

다음을 invalid input으로 거부합니다.

- empty path
- absolute path
- backslash
- NUL
- empty component
- `.` component
- `..` component
- exact duplicate path

Case folding, Unicode normalization, package-local canonical resolution은 S2의
책임입니다. S1은 원본 case와 Unicode를 보존합니다.

### 7.4 Overlap policy

Payload range overlap은 즉시 invalid 처리하지 않습니다.

- archive index issue로 기록
- Audit에서 `package.overlapping-entry-range` warning 생성
- range가 package bounds 안이면 entry read 허용

Overlap은 memory safety 위반이 아니며 미래 package의 shared payload
deduplication 가능성을 차단하면 안 됩니다. Exact duplicate path는 lookup을
모호하게 하므로 계속 invalid입니다.

### 7.5 Limits

| Limit | Value |
| --- | ---: |
| Package bytes | 512 MiB |
| Entry count | 100,000 |
| Entry path | 4,096 bytes |
| Cumulative index bytes | 64 MiB |

Index limit은 path와 table metadata를 합친 cursor 위치 기준입니다.

## 8. TEX Contract

### 8.1 Inspection result

```swift
public enum SceneTextureInspection: Equatable, Sendable {
    case parsed(SceneTextureDescriptor)
    case unsupported(SceneTextureUnsupportedMetadata)
}
```

Unsupported layout과 corrupt/truncated input을 구분합니다.

- unknown version/info/container: `.unsupported`
- invalid count/range/string/truncation: throw `SceneFormatError`
- unknown format/flag: parsed descriptor에 raw value 보존

### 8.2 Known version

S1의 complete descriptor parser:

- outer version: `TEXV0005`
- info version: `TEXI0001`
- container: `TEXB0001`...`TEXB0004`
- animation: `TEXS0001`...`TEXS0003`

Unknown outer version은 version string 이후 구조를 추측하지 않습니다.
Unknown info version은 version/info string까지만 보존합니다.
Unknown container는 확인된 V5/I1 header와 raw container까지만 보존합니다.

### 8.3 Descriptor model

```text
SceneTextureDescriptor
├─ path
├─ version/info
├─ raw format/flags
├─ texture/image dimensions
├─ declared container
├─ mip layout
├─ images
│  └─ mipmaps
│     ├─ dimensions
│     ├─ compression metadata
│     ├─ optional video parameters
│     └─ payload range
├─ optional animation descriptor
└─ trailing byte range
```

`path`는 package-relative path이며 local file path가 아닙니다.

Mipmap layout:

- B0001: dimensions, byte count, payload
- B0002/B0003: dimensions, LZ4 flag, decompressed size, byte count, payload
- B0004 non-video: declared B0004, B0003-compatible mip layout
- B0004 video: video parameters와 condition string 후 B0003-compatible mip

`effectiveContainer`라는 이름 대신 `mipmapLayout`을 사용합니다. Declared
container identity를 다른 container로 바꾸지 않습니다.

### 8.4 Video metadata

B0004 video mip에서:

- first parameter integer
- second parameter integer
- null-terminated condition string
- trailing parameter integer

를 raw value로 보존합니다. Condition은 실행하거나 임의 code로 해석하지
않습니다.

실제 fixture에 video branch가 없으므로 synthetic fixture만 S1 acceptance로
사용합니다.

### 8.5 Animation metadata

- animation version
- frame count
- TEXS0003 GIF width/height
- frame record range
- record size 32 bytes

를 보존합니다. S1은 frame record 의미를 실행하지 않습니다.

### 8.6 Trailing bytes

Known layout parser는 descriptor 종료 위치를 계산합니다.

- trailing byte 0: clean parse
- trailing byte > 0: range를 descriptor에 보존
- Audit warning: `texture.trailing-bytes`

미래 extension data를 조용히 버리거나 corrupt input으로 단정하지 않습니다.

### 8.7 Structural limits

| Limit | Value |
| --- | ---: |
| Images | 4,096 |
| Mipmaps per image | 32 |
| Animation frames | 100,000 |
| Video condition string | 1 MiB |
| Cumulative texture metadata | 16 MiB |

Cumulative metadata budget charge는 image당 64 bytes, mipmap당 96 bytes,
container/animation/condition UTF-8 byte count의 합으로 계산합니다. Payload
range byte count는 metadata budget에 포함하지 않습니다.

Texture dimension과 payload 크기는 structural parser가 거부하지 않습니다.
Descriptor와 audit에 raw value를 보존합니다.

## 9. Software Decode Contract

### 9.1 Separation

```text
SceneTextureFormatReader.inspect(source)
-> SceneTextureInspection

SceneTextureFormatReader.read(source)
-> SceneTextureDescriptor or SceneFormatError.unsupportedLayout

SceneTextureSoftwareDecoder.decode(
    descriptor,
    source,
    imageIndex,
    mipmapIndex
)
-> SceneDecodedTexture
```

`inspect`는 unknown version/info/container를 `.unsupported` evidence로
보존합니다. `read`는 `.parsed` descriptor를 반환하고 `.unsupported`이면
`unsupportedLayout` error로 변환하는 strict convenience API입니다.

Decoder는 descriptor에 기록된 선택한 mip payload range만 읽습니다.
Format header를 다시 parse하지 않습니다.

### 9.2 Supported decode

- embedded PNG/JPEG/GIF/WebP passthrough
- raw RGBA
- DXT1
- DXT3
- DXT5
- RG88
- R8
- LZ4 block expansion
- padded texture crop

Unknown format과 unsupported animated/video decode는 explicit error입니다.
Raw metadata inspection은 계속 성공해야 합니다.

### 9.3 Decode limits

| Limit | Value |
| --- | ---: |
| Texture dimension | 16,384 |
| Compressed payload | 64 MiB |
| Default software decoded pixels | 18,000,000 |

이 제한은 decode를 요청할 때만 적용합니다.

## 10. Audit v2

### 10.1 Schema

새 `MacWallSceneAudit` report는 `schemaVersion == 2`입니다.
S0의 aggregate fixture catalog schema version 1과는 별개입니다.

Aggregate catalog는 count-only compatibility gate이므로 그대로 유지합니다.

### 10.2 Texture summary

Audit texture summary는 다음을 구분합니다.

- `parsed`
- `unsupportedVersion`
- `unsupportedInfoVersion`
- `unsupportedContainer`
- `invalid`

확인하지 못한 field는 optional입니다. Unknown field를 0이나 empty string으로
위조하지 않습니다.

Raw evidence:

- version/info/container
- format/flags
- dimensions
- image/mipmap counts
- declared layout
- animation metadata
- trailing byte count

Condition source와 payload bytes는 report에 넣지 않습니다.

### 10.3 JSON limits

- packaged JSON entry: 16 MiB
- 한 package audit의 cumulative JSON: 64 MiB

Limit을 넘는 auxiliary JSON은 warning과 함께 건너뜁니다. `scene.json`이 limit을
넘으면 report status는 invalid입니다. `SceneRenderPlanBuilder`도 JSON entry당
16 MiB limit을 사용합니다.

### 10.4 Diagnostics

Stable diagnostic code:

- `package.unverified-version`
- `package.invalid-index`
- `package.duplicate-entry-path`
- `package.overlapping-entry-range`
- `texture.unsupported-version`
- `texture.unsupported-info-version`
- `texture.unsupported-container`
- `texture.invalid-metadata`
- `texture.trailing-bytes`
- `resource.limit-exceeded`

Error/diagnostic message에는 absolute input URL, username, errno 문자열,
payload content를 넣지 않습니다.

### 10.5 Existing evidence

S0에서 구현한:

- object classification
- parent/instance count
- nested animation evidence
- dependency resolution evidence
- effect/shader count
- inline SceneScript handler count
- canonical sorted JSON
- support policy

동작은 schema 2로 옮기되 aggregate 결과를 변경하지 않습니다.

## 11. Consumer Migration

### 11.1 SceneRenderPlan

`SceneRenderPlanBuilder`는 `MacWallCore`에 남습니다.

- `ScenePackageArchiveReader`로 archive open
- JSON entry만 bounded read
- model/material chain은 현재 prototype 동작 유지
- texture descriptor parse 후 selected first mip만 software decode
- decoded layer limit 16 유지

새 parent/instance/effect 지원을 추가하지 않습니다.

### 11.2 CLI

새 command를 추가하지 않습니다.

- `scene-info`: Audit v2 canonical JSON 출력
- `scene-render-info`: 기존 prototype render-plan summary 유지

CLI target은 `MacWallCore`와 `MacWallSceneAudit`에 의존합니다.
README와 README.ko의 `scene-info` 설명은 schema 2 기준으로 갱신합니다.

### 11.3 Existing implementation removal

Consumer 전환 후 삭제 대상:

- old package reader/analyzer
- old texture parser/decoder
- old LZ4/DXT files
- S0 audit models/auditor/JSON inspector/metadata reader
- 새 test targets로 이전이 끝난 old Scene package/texture/audit test files

`SceneRenderPlan.swift`와 app의 prototype view는 삭제하지 않습니다.

## 12. Error Model

Formats error는 다음 category를 가집니다.

- `io`
- `outOfBounds`
- `truncated`
- `invalidMagic`
- `invalidCount`
- `invalidString`
- `invalidPath`
- `duplicatePath`
- `invalidRange`
- `resourceLimit`
- `unsupportedLayout`
- `unsupportedDecode`
- `decompressionFailed`

Associated raw value는 structured programmatic inspection에 사용할 수 있지만
`LocalizedError` message는 generic하고 local path를 포함하지 않습니다.

Audit는 format error를 stable diagnostic code와 generic message로 변환합니다.

## 13. Test Strategy

### 13.1 Random-access tests

- recording source가 read range와 최대 read size를 기록
- index parsing 중 package 전체 read 금지
- package index parser의 단일 read는 path limit인 4,096 bytes 이하
- texture metadata string scan은 4,096-byte chunk 이하
- entry read 전 payload access 없음
- bounded child source translation
- concurrent `pread` exact result
- short read와 truncate mapping
- audit JSON은 entry당 16 MiB limit 안에서만 read
- decoder는 선택한 mip 하나만, 64 MiB limit 안에서 read

### 13.2 PKG corpus

- PKGV0008/0018/0023 synthetic index
- malformed magic/version
- negative/overflow count
- truncated string/table
- absolute/traversal/backslash/NUL/empty path
- exact duplicate path
- out-of-bounds entry
- overlapping range issue
- 64 MiB index limit

### 13.3 TEX corpus

- B0001/B0002/B0003
- B0004 non-video/video
- multi-image/mipmap
- unknown version/info/container
- unknown format/flag
- truncated payload range
- TEXS0001/0002/0003
- animation record range
- trailing bytes
- per-string/cumulative metadata limit

### 13.4 Decoder tests

- selected mip만 read
- encoded image passthrough
- RGBA/DXT/RG88/R8
- LZ4 valid/invalid
- crop
- dimension/payload/pixel limit
- unsupported format/animated/video error

### 13.5 Audit tests

- schema 2 canonical determinism
- unsupported partial metadata
- overlap/trailing warning
- absolute path exclusion
- package entry ordering independence
- S0 object/dependency/script counts 유지

### 13.6 Local fixture gate

세 local fixture가 있으면:

- aggregate catalog 전체 일치
- package/TEX invalid diagnostic 0
- known TEX trailing byte 0
- package 전체 read 없음
- deterministic report bytes

Fixture가 없으면 explicit `XCTSkip` 한 번으로 끝납니다.

## 14. Verification Policy

허용:

- focused `swift test`
- 전체 `swift test`
- source/static `rg`
- `git diff --check`
- local fixture read-only inspection

금지:

- `swift build`
- `xcodebuild build`
- 앱/GUI/System Settings 실행
- WallpaperAgent runtime 조작
- package, DMG, notarization
- `dist` 생성/삭제/갱신

`swift test` 내부 compile은 테스트 실행의 일부이며 별도 `swift build`를
실행하지 않습니다.

## 15. Acceptance Criteria

S1 완료 조건:

- `MacWallSceneFormats`, `MacWallSceneAudit` target이 독립됨
- Formats가 Audit/Core/AppKit/Metal에 의존하지 않음
- package 전체 `Data(contentsOf:)` load가 Scene format path에서 사라짐
- 59 MiB fixture audit에서 package 전체 read가 없음
- 최대 단일 read range가 recording source assertion을 통과
- 세 local fixture aggregate catalog가 유지됨
- unknown version/container/format/flag raw evidence가 보존됨
- B0004 video synthetic fixture가 통과함
- overlap은 warning, out-of-range는 invalid로 분리됨
- Audit v2 JSON이 deterministic하고 absolute path를 포함하지 않음
- 기존 Scene prototype의 현재 render-plan tests가 통과함
- 기존 `scene-info`, `scene-render-info` command가 동작함
- 기존 Core package/texture/audit 구현이 삭제됨
- compatibility facade/typealias가 없음
- 전체 `swift test`가 실패 없이 통과함
- S2, Metal, Native Scene, Scene fallback 구현이 시작되지 않음

## 16. 후속 단계

S1 완료 후 다음 단계는 S2 Asset Resolver and Typed Scene Graph입니다.

S2 전에는:

- clean-room built-in asset contract를 확정하지 않음
- package-local path를 graph node로 해석하지 않음
- parent/instance/effect를 실행하지 않음
- Metal resource를 생성하지 않음

S1 결과는 S2가 안전하게 사용할 immutable package/texture descriptor
contract가 됩니다.
