# Native Auto-pause 및 Runtime Stability 구현 기록

작성일: 2026-07-29

상태: implemented / completed

실제 Desktop auto-pause, sleep/wake, renderer recovery에 대한 사용자 runtime QA는 별도 gate로 남아 있습니다.

## 목적

production Native Video backend가 Desktop이 가려지거나 시스템이 잠들었을 때 불필요한 decode/read/enqueue를 중단하고, renderer failure가 발생해도 기존 Desktop surface를 가능한 한 보존하도록 안정화했습니다.

이번 구현은 Native Video에만 적용합니다. Legacy fallback, snapshot/export, Web, Scene runtime은 변경하지 않았습니다.

## Playback Control

- Main App과 extension 사이에 generation-scoped `playback-control.json` protocol을 추가했습니다.
- control은 atomic write하며 command ID 중복과 stale generation을 무시합니다.
- coordinator는 최신 desired suspension을 기억하고 active generation에 즉시 전달합니다.
- Native generation 교체가 성공하면 최신 suspension 상태를 새 generation에 다시 적용합니다.
- 실패한 replacement는 기존 active generation과 suspension 상태를 유지합니다.

## Auto-pause

- Desktop covered와 visible 판정은 각각 200ms debounce를 사용합니다.
- sleep은 즉시 suspend합니다.
- wake는 500ms 후 현재 Desktop visibility를 다시 평가합니다.
- 옵션을 끄면 즉시 resume하고 coverage 기반 suspend를 중단합니다.
- Native playback이 active일 때만 visibility와 lifecycle observer를 유지합니다.

Extension의 suspend는 terminal stop이 아닙니다.

- playback clock과 media-data request를 멈춥니다.
- 이전 asynchronous pump callback은 generation token으로 무효화합니다.
- reader, pending sample, layer의 마지막 frame은 유지합니다.
- resume은 현재 media position에서 새 pump generation으로 이어갑니다.

## Transactional Transition

새 candidate를 first-frame 전에 suspend하면 readiness가 완료되지 않을 수 있으므로 다음 순서를 고정했습니다.

```text
candidate renderer 생성
-> 모든 Desktop context에서 first frame 준비
-> candidate commit
-> 최신 suspension 적용
-> old active renderer cleanup
```

전환 중 Desktop이 가려지면 active A는 즉시 suspend하지만 candidate B는 first frame까지 진행합니다. B가 실패하면 A의 playback과 control target을 유지합니다.

## Runtime Recovery

- renderer callback은 generation, runtime instance ID, context identity를 기준으로 검증합니다.
- stale callback과 replacement 진행 중 중복 failure는 무시하거나 coalesce합니다.
- active renderer의 첫 실패는 old surface를 유지한 채 같은 generation replacement를 준비합니다.
- replacement는 모든 context에서 first frame이 준비된 경우에만 commit합니다.
- recovery candidate도 실패하면 최초 active bridge가 이미 terminal 상태이므로 같은 generation의 두 번째 실패로 분류합니다.
- 같은 generation의 두 번째 실패는 재시도하지 않고 active bridge를 마지막 frame으로 freeze한 뒤 failed status를 기록합니다.
- 새 Play generation이 성공하면 retry budget을 초기화합니다.

## Stop Cleanup

Native Stop은 extension의 stopped ACK를 확인한 뒤 host storage를 정리합니다.

- active/candidate generation, instance, suspension state를 clear합니다.
- 모든 generation staging directory를 제거합니다.
- transient display mode 및 playback control update를 제거합니다.
- Stop ACK 대기 중 새 Play가 시작되면 operation revision이 바뀌므로 이전 Stop의 cleanup은 새 generation을 삭제하지 않습니다.
- runtime root와 QA transport 설정은 유지합니다.
- Desktop의 마지막 native frame과 System Settings의 MacWall 선택은 유지합니다.
- Legacy fallback과 original wallpaper restore state는 건드리지 않습니다.

## 검증

- Native runtime model/store/session/control focused tests 통과
- Native auto-pause controller focused tests: 5 tests, 0 failures
- Stop concurrency 및 recovery policy focused tests: 18 tests, 0 failures
- 전체 `swift test`: 254 tests, 0 failures
- `Tests/ProjectStructure/native_wallpaper_project_tests.sh` 통과
- Host + embedded Native extension unsigned AdHocQA compile: `BUILD SUCCEEDED`
- 독립 코드 리뷰와 수정 후 재리뷰에서 Critical/Important 잔여 finding 없음
- `git diff --check` 통과

실행하지 않은 항목:

- 앱 및 GUI 실행
- System Settings 조작
- 실제 Desktop auto-pause, sleep/wake, recovery 확인
- package, DMG, notarization, `dist`

## 관련 문서

- [완료된 설계](../archive/superpowers/specs/2026-07-29-native-auto-pause-runtime-stability-design.md)
- [완료된 실행 계획](../archive/superpowers/plans/2026-07-29-native-auto-pause-runtime-stability.md)
