#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_RUNNER="$SPIKE_DIR/dev.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "expected output to contain: $needle"
    fi
}

[[ -x "$DEV_RUNNER" ]] || fail "dev runner is not executable: $DEV_RUNNER"

help_output="$("$DEV_RUNNER" help)"
assert_contains "$help_output" "reset"
assert_contains "$help_output" "install"
assert_contains "$help_output" "status"
assert_contains "$help_output" "logs"

install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install)"
assert_contains "$install_output" "cmake -S"
assert_contains "$install_output" "xcodebuild -project"
assert_contains "$install_output" "codesign --verify --deep --strict"
assert_contains "$install_output" "lsregister -f -R -trusted"

fake_ps="$(mktemp)"
trap 'rm -f "$fake_ps"' EXIT
cat >"$fake_ps" <<'EOF'
 123 /tmp/MacWallNativeWallpaperSpikeApp.app/Contents/Extensions/MacWallNativeWallpaperExtension.appex/Contents/MacOS/MacWallNativeWallpaperExtension
 456 /System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent
 789 /Applications/Other.app/Contents/MacOS/Other
EOF

reset_output="$(MACWALL_NATIVE_DRY_RUN=1 MACWALL_NATIVE_FAKE_PS_FILE="$fake_ps" "$DEV_RUNNER" reset)"
assert_contains "$reset_output" "kill -TERM 123"
if [[ "$reset_output" == *"kill -TERM 456"* ]]; then
    fail "reset should not kill WallpaperAgent by default"
fi

printf 'dev runner tests passed\n'
