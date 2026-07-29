#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/MacWall.xcodeproj/project.pbxproj"
HOST_PLIST="$ROOT/MacWallHostApp/Info.plist"
HOST_ENTITLEMENTS="$ROOT/MacWallHostApp/MacWallHostApp.entitlements"
EXTENSION_PLIST="$ROOT/MacWallNativeWallpaperExtension/Info.plist"
EXTENSION_ENTITLEMENTS="$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"
SAVER_PLIST="$ROOT/MacWallLockScreenSaver/Info.plist"

test -f "$PROJECT"
test -f "$ROOT/MacWallHostApp/main.swift"
test -f "$HOST_PLIST"
test -f "$HOST_ENTITLEMENTS"
test -f "$EXTENSION_PLIST"
test -f "$EXTENSION_ENTITLEMENTS"
test -f "$SAVER_PLIST"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/MacWallRemoteContext.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/NativeRuntimeDarwinObserver.swift"
test -f "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
test -f \
  "$ROOT/Sources/MacWallNativeRuntimeSupport/NativeRuntimeDisplayModeUpdatePolicy.swift"
test -f \
  "$ROOT/Sources/MacWallNativeRuntimeSupport/NativeRuntimePlaybackControlPolicy.swift"
test -f \
  "$ROOT/Sources/MacWallNativeRuntimeSupport/NativeRuntimeRecoveryPolicy.swift"

grep -q 'io.github.mingyu1715.MacWall' "$PROJECT"
grep -q 'io.github.mingyu1715.MacWall.NativeWallpaper' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.appex' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.appex in Embed Foundation Extensions' "$PROJECT"
grep -F -q 'dstPath = "$(EXTENSIONS_FOLDER_PATH)"' "$PROJECT"
grep -q 'dstSubfolderSpec = 16' "$PROJECT"
grep -q 'MacWallLockScreenSaver' "$PROJECT"
grep -q 'MacWallNativeRuntimeSupport' "$PROJECT"
grep -q 'MacWallApp' "$PROJECT"

test "$(plutil -extract EXAppExtensionAttributes.EXExtensionPointIdentifier raw \
  "$EXTENSION_PLIST")" = "com.apple.wallpaper"
test "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.app-sandbox' "$EXTENSION_ENTITLEMENTS")" = "true"
test "$(plutil -extract LSUIElement raw "$HOST_PLIST")" = "true"

grep -q 'group.com.mingyu1715.macwall' "$HOST_ENTITLEMENTS"
grep -q 'group.com.mingyu1715.macwall' "$EXTENSION_ENTITLEMENTS"
HOST_APP_GROUP="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups:0' "$HOST_ENTITLEMENTS")"
EXTENSION_APP_GROUP="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups:0' "$EXTENSION_ENTITLEMENTS")"
test "$HOST_APP_GROUP" = "group.com.mingyu1715.macwall"
test "$HOST_APP_GROUP" = "$EXTENSION_APP_GROUP"
grep -q 'provideSettingsViewModels' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'func acquire' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'snapshotGate.*mode=disabled' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
grep -q 'MacWall' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallWallpaperSettingsViewModel.swift"
grep -q 'ARCHS = arm64' "$PROJECT"
grep -q 'freezeKeepingLastFrame' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
grep -q 'CFNotificationCenterGetDarwinNotifyCenter' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeRuntimeDarwinObserver.swift"
grep -q 'registerDesktopSurface' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'state.beginCandidate' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'candidateInstanceID' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'bridge.layer.opacity = 0' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'readDisplayModeUpdate' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'NativeRuntimeDisplayModeUpdatePolicy.decision' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'bridge.setDisplayMode' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'readPlaybackControlUpdate' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'NativeRuntimePlaybackControlPolicy.decision' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'candidatePlaybackSuspended' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'bridge.setPlaybackSuspended' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'handleBridgeFailureOnQueue' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'activeInstanceID' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'recoveryPolicy.registerFailure' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'replacement-candidate-failed' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'nativeRecovery event=exhausted' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'nativeRecovery event=coalesced' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'state.stop()' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'removeAllGenerationsAndTransientUpdates' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
grep -q 'func setPlaybackSuspended' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
grep -q '!isPlaybackSuspended' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
grep -q 'layer.videoGravity = videoGravity(for: displayMode)' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
grep -q 'MACOSX_DEPLOYMENT_TARGET = 14.0' "$PROJECT"
grep -q 'MACOSX_DEPLOYMENT_TARGET = 26.0' "$PROJECT"
grep -q 'fallbackCoordinator.applyOrGenerate' \
  "$ROOT/Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift"
grep -q 'fallbackCoordinator.abandonManagedWallpaperSession' \
  "$ROOT/Sources/MacWallApp/Playback/LegacyWallpaperBackend.swift"

if grep -E -q \
  'DesktopFallbackCoordinator|DesktopFallbackCoordinating|desktop-fallback' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"; then
  echo "Native wallpaper backend must not depend on desktop fallback." >&2
  exit 1
fi

while IFS= read -r private_source; do
  case "$private_source" in
    "$ROOT/MacWallNativeWallpaperExtension/"*|"$ROOT/MacWallNativeWallpaperSpike/"*)
      ;;
    *)
      echo "Native wallpaper private API escaped its target: $private_source" >&2
      exit 1
      ;;
  esac
done < <(
  grep -R -l -E \
    'WallpaperExtensionKit|WallpaperRemoteContextXPC|CAContext.*remoteContext' \
    "$ROOT" \
    --include='*.swift' \
    --exclude-dir='.build' \
    --exclude-dir='.git' \
    --exclude-dir='.worktrees' || true
)

if grep -R -E -q \
  'MacWallSnapshotProbe|fallbackToGenerated|bundledProbeURL|attachGeneratedProbe' \
  "$ROOT/MacWallNativeWallpaperExtension"/*.swift; then
  echo "Production extension must not contain spike snapshot or generated-frame fallbacks." >&2
  exit 1
fi

if grep -q 'com.apple.security.app-sandbox' "$HOST_ENTITLEMENTS"; then
  echo "Host app must remain unsandboxed during native backend promotion." >&2
  exit 1
fi
