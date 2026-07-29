# Scene S1 Format Layer Hardening 구현 기록

작성일: 2026-07-29

상태: implemented / completed

## 목적

Scene Engine S0에서 `MacWallCore` 안에 만들었던 PKG/TEX parser와 audit를
독립 모듈로 교체하고, package 전체를 메모리에 올리지 않는 bounded
random-access 경로를 확정했습니다.

이번 작업은 Scene 입력 형식과 audit 계약을 안정화한 S1입니다. Asset
Resolver, typed Scene Graph, Metal renderer, Native Scene output, Scene
fallback, SceneScript/effect 실행은 시작하지 않았습니다.

## 모듈 구조

```text
MacWallSceneFormats
        |
        +--> MacWallSceneAudit
        |
        +--> MacWallCore --> MacWallApp

MacWallCore + MacWallSceneAudit --> macwallctl
```

- `MacWallSceneFormats`는 Foundation만 사용합니다.
- `MacWallSceneAudit`는 Formats에만 의존합니다.
- `MacWallCore`는 Formats를 사용하지만 Audit에는 의존하지 않습니다.
- `MacWallApp`은 Formats/Audit를 직접 참조하지 않고 Core-owned
  `SceneRenderTexture`만 소비합니다.
- `macwallctl`은 Core와 Audit에 의존하며 기존 command 이름을 유지합니다.
- compatibility facade, typealias, re-export는 두지 않았습니다.

## Random-access Source

- file descriptor와 `pread` 기반 `SceneFileByteSource`를 추가했습니다.
- source를 연 뒤 같은 path가 교체돼도 열린 file identity를 유지합니다.
- concurrent range read와 truncation detection을 검증했습니다.
- `SceneDataByteSource`, bounded sub-source, binary cursor를 분리했습니다.
- C string은 bounded chunk로 읽고 payload skip은 allocation 없이 cursor만
  이동합니다.
- Scene format 경로에는 package 전체 `Data(contentsOf:)`가 없습니다.

## PKG Archive

`ScenePackageArchiveReader`는 index와 payload를 분리합니다. Entry payload는
호출자가 `maximumBytes`를 명시한 경우에만 읽을 수 있습니다.

지원 및 보존 계약:

- `PKGV0008`, `PKGV0018`, `PKGV0023`을 verified version으로 처리
- 형식이 유효한 미확인 numeric version은 issue와 raw version을 보존
- duplicate path와 unsafe path는 invalid
- 음수, overflow, out-of-range payload는 invalid
- overlapping payload range는 별도 issue로 기록
- case와 Unicode path identity 보존

기본 제한:

- package: 512 MiB
- entry count: 100,000
- entry path: 4 KiB
- index: 64 MiB

## TEX Inspection 및 Decode

`SceneTextureFormatReader`는 metadata inspection과 payload decode를
분리합니다.

- `TEXV0005`, `TEXI0001`
- `TEXB0001`부터 `TEXB0004`
- multi-image와 image별 mip chain
- B0004 video metadata
- animation version/frame metadata
- trailing byte range
- unknown version/container/format/flag의 partial evidence

기본 metadata 제한:

- image count: 4,096
- mip count: image당 32
- animation frame count: 100,000
- condition string: 1 MiB
- metadata scan: 16 MiB

`SceneTextureSoftwareDecoder`는 선택된 image/mip range만 읽습니다.

- PNG/JPEG/GIF/HEIC encoded payload 보존
- RGBA8888, RG88, R8
- DXT1/BC1, DXT3/BC2, DXT5/BC3
- bounded LZ4 block decode
- padded texture에서 logical image 영역 crop
- animated/video descriptor는 현재 software decode에서 명시적으로 거부

기본 decode 제한:

- texture dimension: 16,384
- compressed/decompressed payload: 64 MiB
- software decoded pixels: 18,000,000

## Audit Schema 2

`MacWallSceneAudit`는 deterministic schema 2 report를 생성합니다.

- package version/entry summary
- TEX support와 partial metadata
- object, animation, parent/instance, dependency evidence
- effect, shader, inline SceneScript evidence
- unresolved/built-in candidate dependency
- stable support status와 diagnostic
- semantic array 정렬, sorted JSON key, trailing newline
- 입력 filesystem path를 diagnostic에 노출하지 않는 path redaction

JSON은 entry당 16 MiB, 전체 64 MiB까지 bounded read합니다. 제한을 넘는
auxiliary JSON은 path 순서대로 skip하고 diagnostic을 남기며,
`scene.json`을 읽을 수 없으면 report를 invalid로 만듭니다.

## Consumer Migration

- `SceneRenderPlanBuilder`를 Formats archive/descriptor/decoder로 전환했습니다.
- scene/model/material JSON read는 각각 최대 16 MiB입니다.
- 기존 16-layer prototype limit과 model/material resolution 동작은
  유지했습니다.
- Formats decode 결과는 Core-owned `SceneRenderTexture`로 명시적으로
  변환합니다.
- `SceneWallpaperView`는 새 Core model을 소비합니다.
- Scanner, LibraryStore, RenderPlan 테스트는 공용
  `MacWallSceneTestSupport` fixture builder를 사용합니다.
- `macwallctl scene-info`는 canonical Audit schema 2 JSON을 출력합니다.
- `scene-render-info`는 제한적인 2D prototype summary로 유지합니다.

## 제거한 기존 구현

`MacWallCore/Scene`의 기존 package, texture, LZ4, DXT, audit model,
auditor, JSON inspector 구현과 중복 Core 테스트를 삭제했습니다.
Core에는 `SceneRenderPlan`과 Core-owned render output model만 남았습니다.

## Local Fixture

사용자가 보유한 실제 Workshop payload는 `test/`에 local-only로 유지하고
Git에는 aggregate catalog만 저장합니다.

- `PKGV0008`, `PKGV0018`, `PKGV0023` fixture 3개 audit 통과
- S0 aggregate catalog와 일치
- fixture skip 0, failure 0
- package 전체 read 없음
- 단일 read range 16 MiB 이하
- invalid/error diagnostic 없음
- TEX trailing byte 0

## 검증

- `MacWallSceneFormatsTests`: 49 tests, 0 failures
- `MacWallSceneAuditTests`: 17 tests, 0 failures
- `SceneRenderPlanTests`: 2 tests, 0 failures
- 전체 `swift test`: 310 tests, 0 failures
- `git diff --check` 통과

실행하지 않은 항목:

- `swift build`, `xcodebuild build`
- 앱/GUI/System Settings 실행
- package, DMG, notarization, `dist`
- S2 Asset Resolver/Typed Scene Graph
- Metal/Native Scene renderer
- Scene fallback
- SceneScript/effect 실행

## 다음 단계

다음 Scene planning phase는 S2 Asset Resolver and Typed Scene Graph입니다.
S2 구현 전 canonical path, layered resolver, provenance, typed node 및
parent/instance 계약을 별도 설계와 실행 계획으로 확정합니다.

## 관련 문서

- [Scene Engine 설계](../superpowers/specs/2026-07-29-scene-engine-design.md)
- [보관된 S0 실행 계획](../archive/superpowers/plans/2026-07-29-scene-format-research-and-fixture-catalog.md)
- [보관된 S1 설계](../archive/superpowers/specs/2026-07-29-scene-format-layer-hardening-design.md)
- [보관된 S1 실행 계획](../archive/superpowers/plans/2026-07-29-scene-format-layer-hardening.md)
