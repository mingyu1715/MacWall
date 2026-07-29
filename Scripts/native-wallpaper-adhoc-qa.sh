#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT/tmp/macwall-native-adhoc-qa-dd"
APP="$DERIVED_DATA/Build/Products/AdHocQA/MacWall.app"
EXTENSION="$APP/Contents/Extensions/MacWallNativeWallpaperExtension.appex"
LEGACY_APP="/tmp/macwall-native-adhoc-qa-dd/Build/Products/AdHocQA/MacWall.app"
LEGACY_APP_CANONICAL="/private$LEGACY_APP"
QA_ROOT="$HOME/Library/Application Support/MacWall/NativeRuntimeAdHocQA"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION_EXECUTABLE="MacWallNativeWallpaperExtension"
EXTENSION_BUNDLE_ID="io.github.mingyu1715.MacWall.NativeWallpaper"

usage() {
  cat <<'EOF'
Usage: native-wallpaper-adhoc-qa.sh <command>
  reset             Stop stale production QA extension, unregister app, clear QA runtime
  install           Build/sign/verify/register AdHocQA app without launching GUI
  status            Show matching processes and latest QA command/status
  logs [duration]   Show WallpaperAgent and production extension logs (default: 3m)
  help              Show this message
EOF
}

matching_extension_pids() {
  local pid
  local command

  while read -r pid; do
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command" in
      *"$APP/Contents/Extensions/"*|\
      *"$LEGACY_APP/Contents/Extensions/"*|\
      *"$LEGACY_APP_CANONICAL/Contents/Extensions/"*) printf '%s\n' "$pid" ;;
    esac
  done < <(pgrep -x "$EXTENSION_EXECUTABLE" 2>/dev/null || true)
}

reset_qa() {
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid"
  done < <(matching_extension_pids)

  if [[ -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  fi
  if [[ -d "$LEGACY_APP" ]]; then
    "$LSREGISTER" -u "$LEGACY_APP" >/dev/null 2>&1 || true
  fi

  local expected
  expected="$HOME/Library/Application Support/MacWall/NativeRuntimeAdHocQA"
  [[ "$QA_ROOT" == "$expected" ]] || {
    echo "Refusing to clear unexpected QA root: $QA_ROOT" >&2
    exit 1
  }
  rm -rf -- "$QA_ROOT"
}

install_qa() {
  if [[ -n "$(matching_extension_pids)" ]]; then
    echo "Stale production QA extension is running; run reset first." >&2
    exit 1
  fi

  xcodebuild \
    -project "$ROOT/MacWall.xcodeproj" \
    -scheme MacWallAdHocQA \
    -configuration AdHocQA \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    build

  test -d "$APP"
  test -d "$EXTENSION"
  codesign --verify --deep --strict "$APP"
  "$LSREGISTER" -f "$APP"
  printf 'Installed AdHocQA app: %s\n' "$APP"
  printf 'Extension bundle: %s\n' "$EXTENSION_BUNDLE_ID"
  printf 'Next: select MacWall in System Settings manually.\n'
}

status_qa() {
  local pid
  local name
  local file

  printf '%s\n' "WallpaperAgent:"
  pgrep -fl WallpaperAgent || true
  printf '%s\n' "Production AdHocQA extension:"
  while read -r pid; do
    [[ -n "$pid" ]] && ps -p "$pid" -o pid=,command=
  done < <(matching_extension_pids)
  printf 'extensionBundleID=%s\n' "$EXTENSION_BUNDLE_ID"
  printf 'transportMode=development-home root=%s\n' "$QA_ROOT"
  for name in command status; do
    file="$QA_ROOT/$name.json"
    if [[ -f "$file" ]]; then
      printf '%s.json:\n' "$name"
      plutil -p "$file"
    fi
  done
}

logs_qa() {
  local duration="$1"
  local pid
  local predicate
  predicate='process == "WallpaperAgent" OR subsystem == "io.github.mingyu1715.MacWall"'

  while read -r pid; do
    if [[ -n "$pid" ]]; then
      predicate="$predicate OR processIdentifier == $pid"
    fi
  done < <(matching_extension_pids)

  /usr/bin/log show \
    --last "$duration" \
    --style compact \
    --predicate "$predicate"
}

case "${1:-help}" in
  reset) reset_qa ;;
  install) install_qa ;;
  status) status_qa ;;
  logs) logs_qa "${2:-3m}" ;;
  help|-h|--help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
