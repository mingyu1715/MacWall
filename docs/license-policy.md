# License Policy

이 문서는 MacWall repository의 확정 라이선스 정책을 기록합니다.

## 현재 결정

MacWall의 project-authored code 전체는 MIT license를 적용합니다.

별도 제한 license로 분리하지 않는 영역:

- Core
- UI와 Settings
- Legacy Backend
- NativeWallpaperBackend
- WallpaperAgent Integration
- Native Pipeline
- Renderer Pipeline
- Scene Engine
- 향후 공용 module과 연결 코드

라이선스 전문과 저작권 notice는 repository root의
[`LICENSE`](../LICENSE)에서 관리합니다.

## MIT가 허용하는 범위

MIT license는 다음 행위를 허용합니다.

- 개인 및 상업적 사용
- 수정과 재구현
- 복사와 배포
- fork와 sublicense
- 판매

따라서 과거 검토했던 "사용과 수정은 허용하지만 단순 복사 후 판매는 금지"
조건은 적용하지 않습니다. 해당 제한은 MIT 조건과 함께 둘 수 없습니다.

## Attribution

`LICENSE`에는 다음 내용을 유지합니다.

- 원작 Workshop Wallpaper Bridge 저작권 notice
- 현재 작업자 저작권 notice
- 원작에서 파생된 범위에 대한 짧은 설명
- MIT license 전문

기여나 문서 정리 과정에서 원작 notice와 attribution을 제거하거나 축소하지
않습니다.

## Third-party code와 asset

Repository 전체가 MIT라는 결정은 third-party code의 기존 license를
무시하거나 GPL code를 MIT로 재라이선스한다는 뜻이 아닙니다.

- MIT-compatible dependency는 원래 license와 notice를 보존합니다.
- GPL implementation code를 MacWall source에 복사하지 않습니다.
- GPL project는 동작 비교와 format 연구에만 사용할 수 있습니다.
- Wallpaper Engine built-in asset, shader, texture를 app bundle이나
  repository에 포함하지 않습니다.
- 사용자가 합법적으로 보유한 local asset을 선택적으로 읽는 기능은
  MacWall source license와 별개로 취급합니다.

## Source header

Repository root `LICENSE`를 기본 license source로 사용합니다. 법적 또는
배포상 필요가 확인되지 않는 한 모든 source file에 반복적인 MIT header를
추가하지 않습니다.
