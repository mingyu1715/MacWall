#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PLIST="$ROOT/MacWallHostApp/Info.plist"
EXTENSION_PLIST="$ROOT/MacWallNativeWallpaperExtension/Info.plist"

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
