# P2 Playback Stability 구현 기록

Status: implemented / completed

Date: 2026-06-04

## Summary

P2 stabilizes live playback transitions for Workshop Wallpaper Bridge without starting Scene S0.

## Implemented

- Transactional hidden/staged replacement window flow.
- A -> failing B state preservation.
- Debounced screen-change, wake, and visibility updates with fake-scheduler-testable timing.
- Simulated unit/integration coverage for monitor and sleep/wake behavior.
- `AppViewModel` playback path now uses an injected player protocol for testable ordering.
- Failed item switching keeps the previous live playback, previous fallback active asset, previous space-refresh active asset, and previous `lastPlayedAssetId`.

## Verification

- `swift test` -> `121 tests, 0 failures`

## Not Implemented

- Scene S0.
- Scene fallback.
- Metal Scene runtime.
- package/DMG/notarization/release artifact work.
- GUI app QA.
