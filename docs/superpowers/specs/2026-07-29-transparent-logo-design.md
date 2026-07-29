# MacWall 투명 배경 로고 설계

작성일: 2026-07-29

상태: 설계 승인 / 구현 대기

## 목적

`logo/macwall-dark-app-icon.svg`를 기존 `1024 x 1024` 캔버스 크기로 유지하면서, 검은 배경과 둥근 앱 타일을 제거한 투명 배경 로고로 변경합니다.

## 변경

- `width`, `height`, `viewBox`는 `1024 x 1024`로 유지합니다.
- 전체 검은 캔버스, 둥근 타일, 타일 glow, rim을 제거합니다.
- 타일 전용 gradient, shadow, clip path 정의를 제거합니다.
- M형 화면 심볼과 노트북 받침의 좌표 및 크기는 변경하지 않습니다.
- 청록색에서 파랑, 보라, 자홍색으로 이어지는 brand gradient를 유지합니다.
- 심볼 highlight와 shadow를 유지합니다.
- SVG 접근성 title/description은 투명 배경 로고에 맞게 수정합니다.

## 검증

- SVG/XML 문법 확인
- `1024 x 1024` canvas와 viewBox 확인
- PNG preview 렌더링
- 모서리와 심볼 주변 alpha가 투명한지 확인

## 제외

- 심볼 확대 또는 위치 변경
- 색상 변경
- 앱 Asset Catalog 연결
- PNG 및 ICNS 배포 asset 생성
