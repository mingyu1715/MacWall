#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_RUNNER="$SPIKE_DIR/dev.sh"
REMOTE_CONTEXT_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallRemoteContextProbe.swift"
XPC_CONFIGURATION_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallWallpaperExtensionConfiguration.swift"
EXTENSION_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift"
XPC_HANDLER_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"

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

snapshot_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode error)"
assert_contains "$snapshot_install_output" "MacWallSnapshotProbeMode.generated.swift"
assert_contains "$snapshot_install_output" "snapshot mode: error"

invalid_mode_output="$(
    MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode invalid-mode 2>&1 || true
)"
assert_contains "$invalid_mode_output" "Unknown snapshot mode: invalid-mode"

logs_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" logs --last 1m)"
assert_contains "$logs_output" "/usr/bin/log show"
assert_contains "$logs_output" "com.mingyu1715.macwall.native-wallpaper-extension"
assert_contains "$logs_output" "process\\ ==\\ \\'WallpaperAgent\\'\\ AND"
assert_contains "$logs_output" "eventMessage\\ CONTAINS\\ \\'com.mingyu1715.macwall.native-wallpaper-spike.extension\\'"
if [[ "$logs_output" == *"subsystem\\ ==\\ \\'com.mingyu1715.macwall.native-wallpaper-extension\\'\\ OR\\ eventMessage"* ]]; then
    fail "logs predicate should not include broad unscoped bundle-id eventMessage matches"
fi
if [[ "$logs_output" == *"WallpaperExtensionError"* || "$logs_output" == *"Wallpaper\\ Timeline"* ]]; then
    fail "logs predicate should not include broad WallpaperAgent error or timeline matches by default"
fi

remote_context_source="$(cat "$REMOTE_CONTEXT_SOURCE")"
assert_contains "$remote_context_source" "class_getInstanceVariable(snapshotXPCClass, \"box\")"
assert_contains "$remote_context_source" "MacWallSnapshotProbeConfiguration.mode"
assert_contains "$remote_context_source" "case .disabled"
assert_contains "$remote_context_source" "case .error"
assert_contains "$remote_context_source" "case .emptyObject"
assert_contains "$remote_context_source" "case .rawValueRetainedIOSurface"
assert_contains "$remote_context_source" "case .boxRetainedIOSurface"
assert_contains "$remote_context_source" "case .pngData"
assert_contains "$remote_context_source" "snapshot probe disabled"
assert_contains "$remote_context_source" "snapshotGate event=snapshot-candidate"
assert_contains "$remote_context_source" "logPrivateClassLayoutOnce(snapshotXPCClass, label: \"WallpaperSnapshotXPC\")"
assert_contains "$remote_context_source" "enum MacWallWallpaperContextRole"
assert_contains "$remote_context_source" "role=\\("
assert_contains "$remote_context_source" "previousContextID="

extension_source="$(cat "$EXTENSION_SOURCE")"
assert_contains "$extension_source" "if MacWallSnapshotProbe.isEnabled"
assert_contains "$extension_source" "WallpaperSnapshotXPC encode swizzle disabled"

xpc_handler_source="$(cat "$XPC_HANDLER_SOURCE")"
assert_contains "$xpc_handler_source" "snapshotGate event=snapshot-request"
assert_contains "$xpc_handler_source" "snapshotGate event=snapshot-reply"

xpc_configuration_source="$(cat "$XPC_CONFIGURATION_SOURCE")"
assert_contains "$xpc_configuration_source" "import IOSurface"
assert_contains "$xpc_configuration_source" "classSet.add(IOSurface.self)"

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
