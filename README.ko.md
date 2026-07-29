<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/primary-logo/macwall-primary-on-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="logo/primary-logo/macwall-primary-on-light.svg">
    <img src="logo/primary-logo/macwall-primary-on-light.svg" alt="MacWall" width="640">
  </picture>
</p>

내가 가진 Wallpaper Engine Workshop 프로젝트를 macOS에서 배경화면처럼 사용합니다.

MacWall은 Windows에서 Wallpaper Engine을 구매해 사용하던 사람이, 본인의 로컬 Workshop 폴더를 Mac으로 복사한 뒤 쓰기 위한 앱입니다. 복사한 폴더를 스캔하고, 지원 가능한 월페이퍼를 Mac 전용 로컬 라이브러리에 가져오고, video/web/image/scene 월페이퍼를 데스크톱 레이어에서 재생합니다.

[English README](README.md)

## 빠른 시작

1. Windows에서 Wallpaper Engine Workshop 폴더를 찾습니다.

   ```text
   C:\Program Files (x86)\Steam\steamapps\workshop\content\431960
   ```

2. `431960` 폴더를 Mac으로 복사합니다.
3. GitHub 최신 release에서 `MacWall-macOS-arm64.dmg`를 받습니다.
4. DMG를 열고 **MacWall.app**을 **Applications**로 드래그한 뒤 앱을 엽니다.
5. 메뉴바 아이콘을 누르고 **Open Settings**를 선택합니다.
6. Wallpaper Engine 프로젝트는 **Browse**를 누르고 복사한 `431960` 폴더를 선택한 뒤 **Scan**을 누릅니다.
7. 지원 가능한 프로젝트를 선택하고 **Import Selected**를 누릅니다.
8. 직접 가진 영상을 쓰려면 대신 **Add Video File**을 누릅니다.
9. 가져온 프로젝트나 영상을 선택하고 **Play on Desktop**을 누릅니다.
10. **Display**를 선택합니다.
    - **Fit**: 전체 월페이퍼를 다 보여줍니다. 화면 비율이 다르면 검은 여백이 생길 수 있습니다.
    - **Fill**: Wallpaper Engine의 cover 방식처럼 화면을 꽉 채웁니다. 가장자리가 잘릴 수 있습니다.
    - **Stretch**: 화면에 정확히 맞게 늘립니다. 이미지가 왜곡될 수 있습니다.
    - 재생 중 모드를 바꾸면 현재 영상에 즉시 반영되며 재생 위치는 유지됩니다.
11. 더 이상 필요 없는 항목은 **Remove**로 Mac 로컬 라이브러리에서 지울 수 있습니다. 원본 복사 폴더나 원본 영상은 건드리지 않습니다.

앱은 메뉴바 유틸리티로 실행됩니다. Dock이나 앱 전환기에 계속 뜨지 않고, 설정창을 닫아도 데스크톱 레이어의 움직이는 배경화면은 계속 재생됩니다.

잠금화면에서도 움직이게 하려면 **Animate Lock Screen**을 켜고 **Screen Saver Settings**를 누른 뒤 macOS 화면 보호기에서 **MacWall**을 선택합니다. macOS의 잠금화면 애니메이션은 screen saver 경로로 동작하므로 MP4, MOV, M4V 월페이퍼는 잠금화면에서도 재생됩니다. 다른 형식은 정적 이미지 fallback을 사용합니다.

## 재생 방식

- macOS 26 이상 Apple Silicon Mac의 MP4, MOV, M4V 동영상은 Native Video 재생 대상입니다.
- Native Video를 처음 사용할 때는 macOS **배경화면** 설정에서 MacWall을 한 번 선택해야 합니다.
- Native가 활성화되지 않은 상태에서 **Play on Desktop**을 누르면 **배경화면 설정 열기**, **기존 방식으로 재생**, **취소** 중에서 선택할 수 있습니다. 기존 방식 선택은 해당 Play 요청에만 적용됩니다.
- macOS 25 이하, Intel Mac, Native 미지원 형식은 기존 Legacy 데스크톱 레이어로 재생합니다.
- Native 재생에서 **Stop Playback**을 누르면 재생 시계만 멈추고 마지막 프레임과 macOS의 MacWall 배경화면 선택은 유지합니다. Native 모드는 `desktop-fallback.png`를 생성하거나 적용하지 않습니다.
- **Auto-pause behind apps**가 기본으로 켜져 있습니다. Native Video는 다른 앱이 데스크톱을 가린 상태가 200ms 유지되면 재생 시계와 decode/read/enqueue만 멈추고 마지막 프레임은 그대로 유지합니다.
- MacWall 컨트롤 창을 최소화하거나 숨겨도 재생은 멈추지 않습니다.
- 설정창을 닫아도 앱은 종료되지 않습니다. 완전히 끄려면 메뉴바 아이콘에서 **Quit**을 누릅니다.
- 다른 앱이 데스크톱을 가리면 월페이퍼 레이어는 그대로 둡니다. 일반 동영상은 현재 프레임에서 멈추고, 웹 월페이퍼는 CSS 애니메이션만 정지하며 내부 동영상은 재개 지연을 줄이기 위해 계속 재생합니다.
- 다시 바탕화면으로 돌아온 상태가 200ms 유지되면 자동으로 재생을 이어갑니다. 잠자기 직전에는 즉시 멈추고, 깨어난 뒤에는 500ms 후 현재 화면 상태를 다시 확인합니다.
- Native renderer가 실패하면 기존 화면을 유지한 채 같은 재생 generation을 한 번만 자동 복구합니다. 복구가 다시 실패하면 무한 재시작하지 않고 마지막 프레임과 실패 상태를 유지합니다.
- 노트북이 잠자기에서 깨어나거나 모니터 구성이 바뀌면 선택한 월페이퍼의 runtime 상태를 복구합니다.
- 계속 재생하고 싶으면 메뉴바 아이콘이나 설정창에서 **Auto-pause behind apps**를 끄면 됩니다.
- 로그인 후 자동으로 켜지게 하려면 **Open at Login**을 켭니다. **Stop Playback**을 누르지 않았다면 앱 실행 시 마지막으로 재생한 월페이퍼를 다시 복구합니다.
- 가져온 항목이 필요 없어지면 imported library 목록에서 **Remove**를 눌러 Mac 라이브러리 복사본을 삭제합니다.

현재 Native production target은 자동 테스트와 정적 통합 검증까지 완료됐으며, 실제 Desktop 출력과 Fullscreen/Space 동작에 대한 production runtime QA는 후속 검증으로 남아 있습니다.

Legacy 재생에서는 Spaces 전환이나 전체화면 전환 중 기존 macOS 배경화면이 잠깐 보이는 현상을 줄이기 위해 항목별 `Derived/desktop-fallback.png`를 유지합니다. Play/Apply는 먼저 라이브 데스크톱 레이어를 시작하고, 파일이 이미 있으면 이어서 macOS system wallpaper에 적용합니다. 파일이 없으면 Video, Image, Web 항목에 한해 실제 원본이나 렌더링된 Web 출력에서 비동기로 생성합니다. Web snapshot이 실패해도 라이브 재생은 계속됩니다. Workshop 썸네일과 Scene 썸네일은 데스크톱 fallback cache 원본으로 사용하지 않습니다. 라이브러리 항목 메뉴의 **Show in Finder**, **Generate Desktop Fallback**, **Regenerate Desktop Fallback**으로 폴더를 열거나 cache를 수동으로 다시 생성할 수 있습니다. **Restore on Stop**을 켜면 정적 이미지 배경화면에 한해 fallback 적용 전 원본 이미지를 `Application Support/MacWall/DesktopWallpaperRestore/Originals`에 복사하고, **Stop Playback** 시 현재 macOS 배경화면이 앱이 적용한 fallback일 때 그 복사본으로 자동 복원합니다. MacWall의 `desktop-fallback.png`는 원본 배경화면으로 저장하지 않습니다. `Macintosh` 같은 macOS 기본/동적 배경화면은 공개 API로 안정적으로 복원할 수 없어 경고를 표시하고 자동 복원을 건너뜁니다. 다른 항목으로 전환해 새 fallback 적용이 성공하면 이전 항목의 `desktop-fallback.png`는 삭제되며, **Stop Playback**은 현재 항목 cache 파일을 유지합니다.

## 성능 스냅샷

Apple M2 Mac, macOS 26.2, 로컬 MP4 월페이퍼 기준으로 측정했습니다.

- Launch-to-process 평균: 5회 cold open 기준 69.8 ms.
- 재생 샘플: 20초 동안 평균 CPU 2.35%, 평균 RSS 107.1 MB.
- 동영상 still frame 추출: 5회 평균 231.7 ms.
- 현재 로컬 라이브러리 스캔: 466 ms.

## 잠금화면과 정적 배경화면

MacWall은 번들된 macOS screen saver로 잠금화면 애니메이션을 지원합니다. Apple은 커스텀 screen saver를 만들 수 있는 공개 `ScreenSaverView` framework를 제공하고, macOS Lock Screen 설정은 선택한 screen saver를 비활성 상태나 잠금 상태에서 시작할 수 있습니다.

움직이는 잠금화면으로 지원하는 것:

- Mac 라이브러리에서 선택한 MP4, MOV, M4V 동영상 월페이퍼.
- **Add Video File**로 추가한 직접 가진 영상.

정적 이미지 fallback을 쓰는 것:

- MP4로 변환하기 전의 WebM, MKV, AVI.
- 웹 월페이퍼.
- scene 월페이퍼는 기본적으로 데스크톱에서 정적 Workshop preview를 사용합니다. 실험적인 2D image-layer 렌더링은 별도로 켤 수 있습니다. 잠금화면 screen saver도 scene 프로젝트에 대해 정적 fallback 이미지를 사용합니다.

켜는 방법:

1. **MacWall Settings**를 엽니다.
2. **Animate Lock Screen**을 켭니다.
3. **Screen Saver Settings**를 누릅니다.
4. macOS 화면 보호기에서 **MacWall**을 선택합니다.
5. macOS Lock Screen 설정에서 화면 보호기 시작 시간과 암호 요구 시간을 정합니다.

이 앱은 Apple Aerial wallpaper database를 패치하거나 비공개 Lock Screen wallpaper database를 수정하지 않습니다.

대신 안전하게 할 수 있는 것:

- 정적 이미지를 macOS 데스크톱 배경화면으로 설정합니다.
- MP4, MOV, M4V 동영상 월페이퍼는 작은 Workshop preview GIF 대신 동영상 파일에서 still frame을 뽑아 사용합니다.
- 현재 사용자용 macOS Lock Screen cache가 사용 가능한 경우, 같은 정적 이미지를 그 cache에도 기록합니다.

가져온 프로젝트에서 **Set Still Wallpaper**를 누르면 됩니다. 바로 재생 가능한 동영상 프로젝트는 동영상 파일에서 생성한 frame을 사용하고, WebM/MKV/AVI 프로젝트는 먼저 변환해야 합니다. 이미지/scene 프로젝트는 사용 가능한 still preview를 사용합니다. macOS가 이미 잠금화면 이미지를 캐시한 상태라면 실제 화면 반영은 잠금, 로그아웃, 다음 wallpaper refresh 이후에 보일 수 있습니다.

## 지원 범위

| 프로젝트 유형 | 지원 |
| --- | --- |
| `.mp4`, `.mov`, `.m4v` 동영상 | 바로 재생 |
| `.webm`, `.mkv`, `.avi` 동영상 | 로컬 `ffmpeg`로 변환 후 재생 |
| `index.html` 웹 월페이퍼 | 제한된 WebView에서 로컬 재생, 선택적으로 Web Mouse Interaction 사용 |
| `.jpg`, `.png`, `.gif`, `.heic` 이미지 | 정적 데스크톱 레이어로 표시 |
| `scene.pkg` 씬 월페이퍼 | 기본적으로 정적 preview 표시, 선택적으로 실험적 2D renderer 사용 |

직접 가진 로컬 영상도 **Add Video File**로 추가할 수 있습니다. MP4, MOV, M4V는 바로 재생하고, WebM, MKV, AVI는 먼저 가져온 뒤 로컬 `ffmpeg`로 변환해서 재생합니다. 변환된 월페이퍼 영상은 데스크톱 재생이 음소거이므로 오디오 트랙을 제거한 H.264 MP4로 저장합니다.

`preview.jpg`, `thumbnail.jpg`, `cover.png` 같은 Workshop 미리보기 파일은 일반적으로 썸네일로 취급합니다. scene 프로젝트는 지원하지 않는 런타임 기능 때문에 화면 구성이 깨지는 것을 막기 위해 기본적으로 preview를 정적 데스크톱 레이어 placeholder로 사용합니다. 이런 preview 파일은 `Derived/desktop-fallback.png` 시스템 배경화면 cache 원본으로 사용하지 않습니다.

웹 월페이퍼는 일반적인 데스크톱 클릭을 유지하기 위해 기본적으로 마우스 입력을 무시합니다. 클릭 가능한 컨트롤을 사용할 때만 **Web Mouse Interaction**을 켜고, 데스크톱 조작이 필요하면 다시 끄면 됩니다.

실험적인 scene 렌더링은 보수적으로 동작합니다. 일부 packed `.tex` texture, LZ4 block, 주요 DXT texture 형식, 기본 position/scale/rotation/opacity keyframe을 처리할 수 있습니다. 하지만 particle, audio-reactive script, custom shader, text layer, media integration, video/GIF texture animation 같은 Wallpaper Engine 런타임 기능은 생략되거나 원본과 다르게 보일 수 있습니다.

## 하지 않는 것

MacWall은 local-only 앱입니다.

- Steam Workshop 자료를 다운로드하지 않습니다.
- Steam 인증을 우회하지 않습니다.
- DRM을 우회하지 않습니다.
- Steam protocol을 흉내 내지 않습니다.
- 완전한 `scene.pkg` 런타임 호환을 지원한다고 주장하지 않습니다.
- 제작자 asset을 업로드, 공유, 재배포하지 않습니다.
- 원본으로 복사해 온 Workshop 폴더를 수정하지 않습니다.

## 개발 문서와 기여

- 개발 문서 index: [docs/README.md](docs/README.md)
- 개발 로드맵: [docs/development-roadmap.md](docs/development-roadmap.md)
- 기여 가이드: [CONTRIBUTING.md](CONTRIBUTING.md)
- 라이선스: [LICENSE](LICENSE)

가져온 파일은 아래 위치에 복사됩니다.

```text
~/Library/Application Support/MacWall
```

## 소스에서 실행

필요한 것:

- macOS 14 이상
- Xcode command line tools
- Swift 6 toolchain
- 선택: WebM/MKV/AVI 변환용 `ffmpeg`

```bash
git clone https://github.com/mingyu1715/MacWall.git
cd MacWall
swift run MacWall
```

`ffmpeg` 설치:

```bash
brew install ffmpeg
```

## 로컬 앱 번들 만들기

```bash
bash Scripts/package-app.sh
open "dist/MacWall.app"
```

생성되는 파일:

```text
dist/MacWall-macOS-arm64.dmg
```

## Developer ID 서명과 공증

로컬 개발 빌드는 unsigned여도 괜찮지만, 공개 GitHub release는 Apple Developer ID 서명과 notarization을 해야 사용자가 확인되지 않은 개발자 경고를 덜 보게 됩니다.

필요한 것:

- Apple Developer Program 가입
- Keychain에 설치된 `Developer ID Application` 인증서
- 저장된 notary profile. 예:

```bash
xcrun notarytool store-credentials "macwall-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

DMG 빌드, 서명, 공증, staple:

```bash
SIGN_IDENTITY="Developer ID Application: NAME (TEAM_ID)" \
NOTARY_PROFILE="macwall-notary" \
REQUIRE_SIGNING=1 \
bash Scripts/package-app.sh
```

스크립트는 번들 내부 실행 파일, 앱 번들, DMG를 서명하고, `notarytool`로 제출한 뒤 통과한 ticket을 staple하고 `spctl`로 최종 DMG를 검증합니다.

## CLI

고급 사용자와 검증을 위해 `macwallctl`도 제공합니다.

```bash
swift run macwallctl scan "/path/to/431960" --out index.json
swift run macwallctl import "/path/to/431960"
swift run macwallctl import-video "/path/to/video.mp4"
swift run macwallctl remove "<asset-id>"
swift run macwallctl convert input.webm --out output.mp4
swift run macwallctl scene-info "/path/to/scene.pkg"
swift run macwallctl scene-render-info "/path/to/scene.pkg"
swift run macwallctl doctor
```

scene이 정적으로 보이면 먼저 `scene-info`를 실행해 보세요. 큰 texture를 디코딩하지 않고 animation, particle, effect, shader 개수를 보여줍니다. `scene-render-info`는 지원 가능한 texture를 실제로 디코딩하므로 고해상도 scene에서는 시간이 더 걸릴 수 있습니다.

## 문제 해결

바탕화면에 아무것도 안 보이면:

- 가져온 프로젝트가 `playable`인지 확인합니다.
- **Stop**을 누른 뒤 **Play on Desktop**을 다시 누릅니다.
- 잠시 **Auto-pause behind apps**를 꺼봅니다.
- 전체화면 앱 Space가 아니라 실제 바탕화면을 보고 있는지 확인합니다.

화질이 흐리거나 화면이 잘려 보이면:

- 전체 이미지/영상을 다 보고 싶으면 **Fit**을 선택합니다.
- 화면을 꽉 채우고 가장자리 잘림을 허용하려면 **Fill**을 선택합니다.
- Experimental Scene Rendering이 켜져 있는지 확인합니다. scene 프로젝트는 기본적으로 정적 preview를 사용하며, particle, script, custom shader, animated texture 기능은 Wallpaper Engine과 다르게 보일 수 있습니다.

WebM/MKV/AVI 변환이 실패하면:

```bash
brew install ffmpeg
```

macOS가 확인되지 않은 개발자 경고를 띄우면 아직 공증되지 않은 배포본이라는 뜻입니다. 원하면 Swift로 직접 빌드해서 실행할 수 있습니다.

## Wallpaper Engine과의 관계

이 프로젝트는 Valve, Steam, Wallpaper Engine과 관련이 없는 비공식 프로젝트입니다. Wallpaper Engine은 해당 소유자의 상표입니다. MacWall은 사용자가 합법적으로 접근할 수 있는 로컬 파일을 개인적으로 활용하기 위한 호환 도구입니다.

## 라이선스

MIT. 원작 project notice와 현재 작업자 notice는 [LICENSE](LICENSE)에 정리되어 있습니다.
