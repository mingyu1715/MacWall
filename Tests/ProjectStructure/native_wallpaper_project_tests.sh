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

grep -q 'io.github.mingyu1715.MacWall' "$PROJECT"
grep -q 'io.github.mingyu1715.MacWall.NativeWallpaper' "$PROJECT"
grep -q 'MacWallNativeWallpaperExtension.appex' "$PROJECT"
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

if grep -q 'com.apple.security.app-sandbox' "$HOST_ENTITLEMENTS"; then
  echo "Host app must remain unsandboxed during native backend promotion." >&2
  exit 1
fi
