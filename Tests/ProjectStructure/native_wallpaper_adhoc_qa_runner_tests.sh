#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/Scripts/native-wallpaper-adhoc-qa.sh"

test -x "$RUNNER"
bash -n "$RUNNER"
"$RUNNER" help | grep -q 'reset'
"$RUNNER" help | grep -q 'install'
"$RUNNER" help | grep -q 'status'
"$RUNNER" help | grep -q 'logs'

grep -q 'MacWallAdHocQA' "$RUNNER"
grep -q 'AdHocQA' "$RUNNER"
grep -q 'NativeRuntimeAdHocQA' "$RUNNER"
grep -q 'codesign --verify --deep --strict' "$RUNNER"
grep -q 'lsregister' "$RUNNER"
grep -q 'WallpaperAgent' "$RUNNER"
grep -q 'io.github.mingyu1715.MacWall.NativeWallpaper' "$RUNNER"

if grep -E -q \
  'package-app\.sh|notarytool|create-dmg|xcodebuild .*archive|/dist|open ' \
  "$RUNNER"; then
  echo "AdHocQA runner contains a forbidden release or GUI operation." >&2
  exit 1
fi
