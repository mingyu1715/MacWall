#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_RUNNER="$SPIKE_DIR/dev.sh"
CMAKE_SOURCE="$SPIKE_DIR/CMakeLists.txt"
REMOTE_CONTEXT_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallRemoteContextProbe.swift"
VIDEO_BRIDGE_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/NativeVideoFrameBridge.swift"
RENDERER_ADAPTER_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/NativeVideoRendererAdapter.swift"
PLAYBACK_CLOCK_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/NativeVideoPlaybackClock.swift"
SAMPLE_RETIMER_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/NativeVideoSampleRetimer.swift"
TIMING_MODE_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift"
XPC_CONFIGURATION_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallWallpaperExtensionConfiguration.swift"
EXTENSION_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperExtension.swift"
XPC_HANDLER_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallWallpaperXPCHandler.swift"
XPC_INTROSPECTION_SOURCE="$SPIKE_DIR/MacWallNativeWallpaperExtension/MacWallWallpaperXPCIntrospection.swift"
APP_INFO_PLIST="$SPIKE_DIR/MacWallNativeWallpaperSpikeApp/Info.plist"
EXTENSION_INFO_PLIST="$SPIKE_DIR/MacWallNativeWallpaperExtension/Info.plist"

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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail "expected output not to contain: $needle"
    fi
}

[[ -x "$DEV_RUNNER" ]] || fail "dev runner is not executable: $DEV_RUNNER"

help_output="$("$DEV_RUNNER" help)"
assert_contains "$help_output" "reset"
assert_contains "$help_output" "install"
assert_contains "$help_output" "status"
assert_contains "$help_output" "logs"
assert_contains "$help_output" "--allow-unsafe-snapshot-xpc"
assert_contains "$help_output" "--video-source MODE"
assert_contains "$help_output" "--video-path PATH"
assert_contains "$help_output" "--timing-clock MODE"
assert_contains "$help_output" "--timing-profile PROFILE"

install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install)"
assert_contains "$install_output" "cmake -S"
assert_contains "$install_output" "-U MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE"
assert_contains "$install_output" "xcodebuild -project"
assert_contains "$install_output" "codesign --verify --deep --strict"
assert_contains "$install_output" "lsregister -f -R -trusted"
assert_contains "$install_output" "snapshot mode: disabled"
assert_contains "$install_output" "video source: asset"
assert_contains "$install_output" "timing clock: synchronizer"
assert_contains "$install_output" "timing profile: normal"

synchronizer_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-clock synchronizer --timing-profile normal)"
assert_contains "$synchronizer_install_output" "timing clock: synchronizer"
assert_contains "$synchronizer_install_output" "timing profile: normal"

timing_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-clock control-timebase)"
assert_contains "$timing_install_output" "MacWallNativeWallpaperTimingMode.generated.swift"
assert_contains "$timing_install_output" "timing clock: control-timebase"

reduced_timing_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-profile reduced)"
assert_contains "$reduced_timing_output" "timing profile: reduced"

set +e
invalid_timing_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-clock invalid 2>&1)"
invalid_timing_status=$?
set -e
[[ "$invalid_timing_status" -eq 2 ]] || fail "invalid timing clock should exit 2, got $invalid_timing_status"
assert_contains "$invalid_timing_output" "Unknown timing clock: invalid"

set +e
invalid_profile_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --timing-profile invalid 2>&1)"
invalid_profile_status=$?
set -e
[[ "$invalid_profile_status" -eq 2 ]] || fail "invalid timing profile should exit 2, got $invalid_profile_status"
assert_contains "$invalid_profile_output" "Unknown timing profile: invalid"

snapshot_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode error)"
assert_contains "$snapshot_install_output" "MacWallSnapshotProbeMode.generated.swift"
assert_contains "$snapshot_install_output" "snapshot mode: error"

generated_video_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-source generated)"
assert_contains "$generated_video_install_output" "MacWallNativeWallpaperVideoSourceMode.generated.swift"
assert_contains "$generated_video_install_output" "video source: generated"

asset_video_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-source asset)"
assert_contains "$asset_video_install_output" "video source: asset"

video_fixture_dir="$(mktemp -d)"
trap 'rm -rf "$video_fixture_dir"' EXIT
video_fixture="$video_fixture_dir/local-test-video.mp4"
touch "$video_fixture"

video_path_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-source asset --video-path "$video_fixture")"
assert_contains "$video_path_install_output" "video path: $video_fixture"
assert_contains "$video_path_install_output" "-DMACWALL_NATIVE_SAMPLE_VIDEO_SOURCE=$video_fixture"

set +e
relative_video_path_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-path relative-video.mp4 2>&1)"
relative_video_path_status=$?
set -e
[[ "$relative_video_path_status" -eq 2 ]] || fail "relative video path should exit 2, got $relative_video_path_status"
assert_contains "$relative_video_path_output" "install --video-path requires an absolute path"

missing_video_path="$video_fixture_dir/missing-video.mp4"
set +e
missing_video_path_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-path "$missing_video_path" 2>&1)"
missing_video_path_status=$?
set -e
[[ "$missing_video_path_status" -eq 2 ]] || fail "missing video path should exit 2, got $missing_video_path_status"
assert_contains "$missing_video_path_output" "Video path is not an existing regular file: $missing_video_path"

invalid_video_source_output="$(
    MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --video-source invalid-source 2>&1 || true
)"
assert_contains "$invalid_video_source_output" "Unknown video source: invalid-source"

file_url_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode file-url)"
assert_contains "$file_url_install_output" "snapshot mode: file-url"

snapshot_xpc_file_url_blocked_output="$(
    MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode snapshot-xpc-file-url 2>&1 || true
)"
assert_contains "$snapshot_xpc_file_url_blocked_output" "Unsafe snapshot mode: snapshot-xpc-file-url"
assert_contains "$snapshot_xpc_file_url_blocked_output" "--allow-unsafe-snapshot-xpc"

snapshot_xpc_file_url_install_output="$(MACWALL_NATIVE_DRY_RUN=1 "$DEV_RUNNER" install --snapshot-mode snapshot-xpc-file-url --allow-unsafe-snapshot-xpc)"
assert_contains "$snapshot_xpc_file_url_install_output" "UNSAFE snapshot mode enabled: snapshot-xpc-file-url"
assert_contains "$snapshot_xpc_file_url_install_output" "snapshot mode: snapshot-xpc-file-url"

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
assert_contains "$remote_context_source" "case .fileURL"
assert_contains "$remote_context_source" "case .snapshotXPCFileURL"
assert_contains "$remote_context_source" "snapshot probe disabled"
assert_contains "$remote_context_source" "snapshotGate event=snapshot-candidate"
assert_contains "$remote_context_source" "makeSnapshotErrorResponse"
assert_contains "$remote_context_source" "makeEmptySnapshotXPC"
assert_contains "$remote_context_source" "MacWallSnapshotProbeRetainedObjectStore"
assert_contains "$remote_context_source" "makeRawValueRetainedIOSurfaceSnapshot"
assert_contains "$remote_context_source" "makeBoxRetainedIOSurfaceSnapshot"
assert_contains "$remote_context_source" "makePNGDataSnapshot"
assert_contains "$remote_context_source" "makeFileURLSnapshot"
assert_contains "$remote_context_source" "makeSnapshotXPCFileURLSnapshot"
assert_contains "$remote_context_source" "snapshot request home"
assert_contains "$remote_context_source" "snapshot home write preflight failed"
assert_contains "$remote_context_source" "snapshot home write preflight skipped"
assert_contains "$remote_context_source" "snapshot home security scope"
assert_contains "$remote_context_source" "startAccessingSecurityScopedResource"
assert_contains "$remote_context_source" "withSnapshotHomeSecurityScope"
assert_contains "$remote_context_source" "snapshot home coordinated write preflight"
assert_contains "$remote_context_source" "NSFileCoordinator"
assert_contains "$remote_context_source" "MacWallSnapshotHomeWriteAccessCache"
assert_contains "$remote_context_source" "cacheHomeURL"
assert_contains "$remote_context_source" "cacheHomeURL=\\("
assert_contains "$remote_context_source" "normalizedLabel.contains(\"home\")"
assert_contains "$remote_context_source" "normalizedLabel.contains(\"cachedirectory\")"
assert_contains "$remote_context_source" "guard depth < 8"
assert_contains "$remote_context_source" "context?.requestInfo.cacheHomeURL"
assert_contains "$remote_context_source" "snapshot request home source=\\("
assert_contains "$remote_context_source" "logPrivateClassLayoutOnce(snapshotXPCClass, label: \"WallpaperSnapshotXPC\")"
assert_contains "$remote_context_source" "enum MacWallWallpaperContextRole"
assert_contains "$remote_context_source" "role=\\("
assert_contains "$remote_context_source" "previousContextID="

video_bridge_source="$(cat "$VIDEO_BRIDGE_SOURCE")"
assert_contains "$video_bridge_source" "MacWallNativeWallpaperVideoSourceModeConfiguration.mode"
assert_contains "$video_bridge_source" "case .generated"
assert_contains "$video_bridge_source" "case .asset"
assert_contains "$video_bridge_source" "videoSourceMode="
assert_contains "$video_bridge_source" "pendingAssetSampleBuffer"
assert_contains "$video_bridge_source" "scheduleAssetPump"
assert_contains "$video_bridge_source" "assetPumpGeneration"
assert_contains "$video_bridge_source" "NativeVideoAssetPumpTransition"
assert_contains "$video_bridge_source" "min(max(delay, 0.005), 0.500)"
assert_contains "$video_bridge_source" "playbackClock.start(at: .zero)"
assert_contains "$video_bridge_source" "playbackClock?.stop()"
assert_contains "$video_bridge_source" "playbackClock.stop(completion: finishFallback)"
assert_contains "$video_bridge_source" "rendererAdapter.stopRequestingMediaData()"
assert_contains "$video_bridge_source" "NativeVideoPlaybackTimingPolicy"
assert_contains "$video_bridge_source" "NativeVideoRendererAdapter"
assert_contains "$video_bridge_source" "NativeVideoPlaybackClock"
assert_contains "$video_bridge_source" "nativeVideoTiming"
assert_contains "$video_bridge_source" "samplePTS="
assert_contains "$video_bridge_source" "mediaNow="
assert_contains "$video_bridge_source" "lead="
assert_contains "$video_bridge_source" "lag="
assert_contains "$video_bridge_source" "bufferBand="
assert_contains "$video_bridge_source" "rendererReady="
assert_contains "$video_bridge_source" "loopIndex="
assert_contains "$video_bridge_source" "droppedFrameCount="
assert_contains "$video_bridge_source" "queuedFrameCount="
assert_contains "$video_bridge_source" "decision="
assert_contains "$video_bridge_source" "clockMode="
assert_contains "$video_bridge_source" "profile="
assert_contains "$video_bridge_source" "NativeVideoSampleRetimer.loopOffset"
assert_contains "$video_bridge_source" "NativeVideoSampleRetimer.retime"
assert_contains "$video_bridge_source" "asset-repeated-hard-reset"
assert_contains "$video_bridge_source" "asset-sample-retiming-failed"
assert_contains "$video_bridge_source" "rendererAdapter.flush(removeDisplayedImage: false) {"
assert_contains "$video_bridge_source" "assetPumpGeneration.accepts(generation)"
assert_contains "$video_bridge_source" "osStatus="
assert_not_contains "$video_bridge_source" "scheduleAssetLoopRestart"
assert_not_contains "$video_bridge_source" "playbackClock.seek(to: .zero)"
assert_not_contains "$video_bridge_source" "while isRunning, !didStop, displayLayer.isReadyForMoreMediaData"
assert_not_contains "$video_bridge_source" "displayLayer.enqueue("

renderer_adapter_source="$(cat "$RENDERER_ADAPTER_SOURCE")"
assert_contains "$renderer_adapter_source" "sampleBufferRenderer"
assert_contains "$renderer_adapter_source" "requestMediaDataWhenReady"

playback_clock_source="$(cat "$PLAYBACK_CLOCK_SOURCE")"
assert_contains "$playback_clock_source" "AVSampleBufferRenderSynchronizer"
assert_contains "$playback_clock_source" "CMTimebaseCreateWithSourceClock"
assert_contains "$playback_clock_source" "delaysRateChangeUntilHasSufficientMediaData = false"
assert_contains "$playback_clock_source" "case .synchronizer"
assert_contains "$playback_clock_source" "case .controlTimebase"

sample_retimer_source="$(cat "$SAMPLE_RETIMER_SOURCE")"
assert_contains "$sample_retimer_source" "CMSampleBufferCreateCopyWithNewTiming"
assert_contains "$sample_retimer_source" "loopOffset(assetDuration:"
assert_contains "$sample_retimer_source" "CMTimeMultiplyByFloat64"
assert_contains "$sample_retimer_source" "nonnumericPresentationTime"
assert_contains "$sample_retimer_source" "timing.duration.isValid, !timing.duration.isNumeric"

timing_mode_source="$(cat "$TIMING_MODE_SOURCE")"
assert_contains "$timing_mode_source" "clockMode"
assert_contains "$timing_mode_source" "case controlTimebase"
assert_contains "$timing_mode_source" "case synchronizer"

cmake_source="$(cat "$CMAKE_SOURCE")"
assert_contains "$cmake_source" "CACHE FILEPATH"
assert_contains "$cmake_source" "configure_file"

extension_source="$(cat "$EXTENSION_SOURCE")"
assert_contains "$extension_source" "requiresSnapshotEncodeSwizzle"
assert_contains "$extension_source" "WallpaperSnapshotXPC encode swizzle disabled"

xpc_handler_source="$(cat "$XPC_HANDLER_SOURCE")"
assert_contains "$xpc_handler_source" "snapshotGate event=snapshot-request"
assert_contains "$xpc_handler_source" "snapshotGate event=snapshot-reply"
assert_contains "$xpc_handler_source" "logXPCShapeProbe(\"acquire.request\", request)"
assert_contains "$xpc_handler_source" "logXPCShapeProbe(\"update.request\", request)"
assert_contains "$xpc_handler_source" "logXPCShapeProbe(\"snapshot.id\", id)"

xpc_introspection_source="$(cat "$XPC_INTROSPECTION_SOURCE")"
assert_contains "$xpc_introspection_source" "shapeProbe label="
assert_contains "$xpc_introspection_source" "interestingLabels="
assert_contains "$xpc_introspection_source" "urlCandidates="
assert_contains "$xpc_introspection_source" "fileCandidates="
assert_contains "$xpc_introspection_source" "tokenCandidates="
assert_contains "$xpc_introspection_source" "descriptorCandidates="
assert_contains "$xpc_introspection_source" "bookmarkCandidates="
assert_contains "$xpc_introspection_source" "shapeProbe classLayout"
assert_contains "$xpc_introspection_source" "interestingFieldKeywords"

xpc_configuration_source="$(cat "$XPC_CONFIGURATION_SOURCE")"
assert_contains "$xpc_configuration_source" "import IOSurface"
assert_contains "$xpc_configuration_source" "classSet.add(IOSurface.self)"

app_info_plist="$(cat "$APP_INFO_PLIST")"
assert_contains "$app_info_plist" "NSAppDataUsageDescription"
assert_contains "$app_info_plist" "WallpaperAgent"

extension_info_plist="$(cat "$EXTENSION_INFO_PLIST")"
assert_contains "$extension_info_plist" "NSAppDataUsageDescription"
assert_contains "$extension_info_plist" "WallpaperAgent"

fake_ps="$(mktemp)"
trap 'rm -rf "$video_fixture_dir"; rm -f "$fake_ps"' EXIT
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
