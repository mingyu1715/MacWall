#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/MacWall.xcodeproj/project.pbxproj"
SCHEME="$ROOT/MacWall.xcodeproj/xcshareddata/xcschemes/MacWallAdHocQA.xcscheme"
HOST_PLIST="$ROOT/MacWallHostApp/Info.plist"
HOST_QA_ENTITLEMENTS="$ROOT/MacWallHostApp/MacWallHostApp.AdHocQA.entitlements"
EXTENSION_PLIST="$ROOT/MacWallNativeWallpaperExtension/Info.plist"
EXTENSION_QA_ENTITLEMENTS="$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.AdHocQA.entitlements"

EXPECTED="\$(MACWALL_NATIVE_RUNTIME_TRANSPORT)"
test "$(plutil -extract MacWallNativeRuntimeTransport raw "$HOST_PLIST")" \
  = "$EXPECTED"
test "$(plutil -extract MacWallNativeRuntimeTransport raw "$EXTENSION_PLIST")" \
  = "$EXPECTED"

grep -q 'NativeRuntimeTransportMode.configured' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
grep -q 'transportMode=' \
  "$ROOT/Sources/MacWallApp/Playback/NativeWallpaperBackend.swift"
grep -q 'NativeRuntimeTransportMode.configured' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"
grep -q 'transportMode=' \
  "$ROOT/MacWallNativeWallpaperExtension/NativeWallpaperSessionController.swift"

test -f "$SCHEME"
test -f "$HOST_QA_ENTITLEMENTS"
test -f "$EXTENSION_QA_ENTITLEMENTS"
plutil -lint "$HOST_QA_ENTITLEMENTS"
plutil -lint "$EXTENSION_QA_ENTITLEMENTS"

if /usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups' \
  "$HOST_QA_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "AdHocQA Host must not contain App Group entitlement." >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.application-groups' \
  "$EXTENSION_QA_ENTITLEMENTS" >/dev/null 2>&1; then
  echo "AdHocQA Extension must not contain App Group entitlement." >&2
  exit 1
fi

test "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.app-sandbox' \
  "$EXTENSION_QA_ENTITLEMENTS")" = "true"
test "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
  "$EXTENSION_QA_ENTITLEMENTS")" \
  = "/Library/Application Support/MacWall/NativeRuntimeAdHocQA/"

if grep -q \
  'com.apple.security.temporary-exception.files.home-relative-path.read-write' \
  "$ROOT/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.entitlements"; then
  echo "Debug/Release Extension entitlements must not contain QA exception." >&2
  exit 1
fi

grep -q 'name = AdHocQA' "$PROJECT"
grep -q 'MACWALL_NATIVE_RUNTIME_TRANSPORT = app-group' "$PROJECT"
grep -q 'MACWALL_NATIVE_RUNTIME_TRANSPORT = development-home' "$PROJECT"
grep -q 'MacWallHostApp.AdHocQA.entitlements' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.AdHocQA.entitlements' "$PROJECT"
grep -q 'buildConfiguration="AdHocQA"' "$SCHEME"
