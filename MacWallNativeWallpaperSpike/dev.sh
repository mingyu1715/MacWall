#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${MACWALL_NATIVE_BUILD_DIR:-/tmp/macwall-native-wallpaper-spike-xcode}"
DERIVED_DATA_DIR="${MACWALL_NATIVE_DERIVED_DATA_DIR:-/tmp/macwall-native-wallpaper-spike-dd}"
CONFIGURATION="${MACWALL_NATIVE_CONFIGURATION:-Debug}"
PROJECT_PATH="$BUILD_DIR/MacWallNativeWallpaperSpike.xcodeproj"
APP_PATH="$BUILD_DIR/$CONFIGURATION/MacWallNativeWallpaperSpikeApp.app"
EXTENSION_PROCESS="MacWallNativeWallpaperExtension"
WALLPAPER_AGENT_PROCESS="WallpaperAgent"
EXTENSION_SUBSYSTEM="com.mingyu1715.macwall.native-wallpaper-extension"
EXTENSION_BUNDLE_ID="com.mingyu1715.macwall.native-wallpaper-spike.extension"
SNAPSHOT_MODE_DEFAULT="disabled"
SNAPSHOT_MODE_FILE="$SCRIPT_DIR/MacWallNativeWallpaperExtension/MacWallSnapshotProbeMode.generated.swift"
VIDEO_SOURCE_MODE_DEFAULT="asset"
VIDEO_SOURCE_MODE_FILE="$SCRIPT_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperVideoSourceMode.generated.swift"
TIMING_CLOCK_DEFAULT="synchronizer"
TIMING_PROFILE_DEFAULT="normal"
TIMING_MODE_FILE="$SCRIPT_DIR/MacWallNativeWallpaperExtension/MacWallNativeWallpaperTimingMode.generated.swift"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
DRY_RUN="${MACWALL_NATIVE_DRY_RUN:-0}"

usage() {
    cat <<'EOF'
Usage: ./dev.sh <command> [options]

Commands:
  reset [--wallpaper-agent]  Terminate stale MacWall native wallpaper extension processes.
  install [--snapshot-mode MODE] [--video-source MODE] [--video-path PATH] [--timing-clock MODE] [--timing-profile PROFILE] [--allow-unsafe-snapshot-xpc]
                             Generate, build, codesign-verify, and register the spike app.
  status                     Print WallpaperAgent and MacWall extension process status.
  logs [--last DURATION]     Show recent WallpaperAgent and extension logs. Default: 10m.
  logs --stream              Stream WallpaperAgent and extension logs.
  help                       Show this help.

Environment:
  MACWALL_NATIVE_DRY_RUN=1          Print commands without executing them.
  MACWALL_NATIVE_BUILD_DIR=PATH     Override Xcode project output directory.
  MACWALL_NATIVE_DERIVED_DATA_DIR=PATH
  MACWALL_NATIVE_CONFIGURATION=Debug
  MACWALL_NATIVE_FAKE_PS_FILE=PATH  Test-only process list fixture.

Human verification remains manual:
  - Select MacWall Native Spike in System Settings yourself.
  - Verify actual Desktop output yourself.

Snapshot modes:
  disabled
  error
  empty-object
  raw-value-retained-iosurface
  box-retained-iosurface
  png-data
  file-url
  snapshot-xpc-file-url       Unsafe: can interrupt WallpaperAgent XPC and remove the active runtime surface.

Video sources:
  asset                       Default. Use the bundled mp4 through AVAssetReader.
  generated                   Use generated sample buffers only, bypassing mp4/AVAssetReader.
  --video-path PATH           Copy an absolute local video file into the temporary build resource.

Timing clocks:
  synchronizer                Default. Use AVSampleBufferRenderSynchronizer.
  control-timebase            Use a host-clock-backed CMTimebase.

Timing profiles:
  normal                      Default timing thresholds.
  reduced                     Reduced buffering and 30fps maximum cadence.
EOF
}

print_command() {
    printf '+'
    local arg
    for arg in "$@"; do
        printf ' %q' "$arg"
    done
    printf '\n'
}

run_cmd() {
    print_command "$@"
    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi
    "$@"
}

process_lines() {
    if [[ -n "${MACWALL_NATIVE_FAKE_PS_FILE:-}" ]]; then
        cat "$MACWALL_NATIVE_FAKE_PS_FILE"
        return
    fi
    ps -axo pid=,comm=
}

process_pids_matching() {
    local pattern="$1"
    process_lines | awk -v pattern="$pattern" '
        index($0, pattern) > 0 {
            print $1
        }
    '
}

read_pids_matching() {
    local pattern="$1"
    local pids=()
    local pid
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(process_pids_matching "$pattern")
    printf '%s\n' "${pids[@]}"
}

terminate_pids() {
    local label="$1"
    shift
    local pids=("$@")

    if [[ "${#pids[@]}" -eq 0 ]]; then
        printf 'No %s process found.\n' "$label"
        return 0
    fi

    local pid
    for pid in "${pids[@]}"; do
        run_cmd kill -TERM "$pid"
    done

    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi

    local attempt
    for attempt in {1..20}; do
        local alive=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                alive+=("$pid")
            fi
        done

        if [[ "${#alive[@]}" -eq 0 ]]; then
            printf '%s processes terminated.\n' "$label"
            return 0
        fi
        sleep 0.1
    done

    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            run_cmd kill -KILL "$pid"
        fi
    done
}

swift_case_for_snapshot_mode() {
    case "$1" in
        disabled) printf '.disabled\n' ;;
        error) printf '.error\n' ;;
        empty-object) printf '.emptyObject\n' ;;
        raw-value-retained-iosurface) printf '.rawValueRetainedIOSurface\n' ;;
        box-retained-iosurface) printf '.boxRetainedIOSurface\n' ;;
        png-data) printf '.pngData\n' ;;
        file-url) printf '.fileURL\n' ;;
        snapshot-xpc-file-url) printf '.snapshotXPCFileURL\n' ;;
        *)
            printf 'Unknown snapshot mode: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

generate_snapshot_mode_source() {
    local mode="$1"
    local swift_case
    swift_case="$(swift_case_for_snapshot_mode "$mode")"
    print_command "generate-snapshot-mode" "$SNAPSHOT_MODE_FILE" "$mode"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'snapshot mode: %s\n' "$mode"
        return 0
    fi

    {
        printf 'enum MacWallSnapshotProbeMode: String, Sendable {\n'
        printf '    case disabled\n'
        printf '    case error\n'
        printf '    case emptyObject = "empty-object"\n'
        printf '    case rawValueRetainedIOSurface = "raw-value-retained-iosurface"\n'
        printf '    case boxRetainedIOSurface = "box-retained-iosurface"\n'
        printf '    case pngData = "png-data"\n'
        printf '    case fileURL = "file-url"\n'
        printf '    case snapshotXPCFileURL = "snapshot-xpc-file-url"\n'
        printf '}\n\n'
        printf 'enum MacWallSnapshotProbeConfiguration {\n'
        printf '    static let mode: MacWallSnapshotProbeMode = %s\n' "$swift_case"
        printf '}\n'
    } >"$SNAPSHOT_MODE_FILE"
    printf 'snapshot mode: %s\n' "$mode"
}

swift_case_for_video_source_mode() {
    case "$1" in
        asset) printf '.asset\n' ;;
        generated) printf '.generated\n' ;;
        *)
            printf 'Unknown video source: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

generate_video_source_mode_source() {
    local mode="$1"
    local swift_case
    swift_case="$(swift_case_for_video_source_mode "$mode")"
    print_command "generate-video-source-mode" "$VIDEO_SOURCE_MODE_FILE" "$mode"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'video source: %s\n' "$mode"
        return 0
    fi

    {
        printf 'enum MacWallNativeWallpaperVideoSourceMode: String, Sendable {\n'
        printf '    case asset\n'
        printf '    case generated\n'
        printf '}\n\n'
        printf 'enum MacWallNativeWallpaperVideoSourceModeConfiguration {\n'
        printf '    static let mode: MacWallNativeWallpaperVideoSourceMode = %s\n' "$swift_case"
        printf '}\n'
    } >"$VIDEO_SOURCE_MODE_FILE"
    printf 'video source: %s\n' "$mode"
}

swift_case_for_timing_clock() {
    case "$1" in
        synchronizer) printf '.synchronizer\n' ;;
        control-timebase) printf '.controlTimebase\n' ;;
        *)
            printf 'Unknown timing clock: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

swift_case_for_timing_profile() {
    case "$1" in
        normal) printf '.normal\n' ;;
        reduced) printf '.reduced\n' ;;
        *)
            printf 'Unknown timing profile: %s\n' "$1" >&2
            exit 2
            ;;
    esac
}

generate_timing_mode_source() {
    local clock="$1"
    local profile="$2"
    local clock_case
    local profile_case
    clock_case="$(swift_case_for_timing_clock "$clock")"
    profile_case="$(swift_case_for_timing_profile "$profile")"
    print_command "generate-timing-mode" "$TIMING_MODE_FILE" "$clock" "$profile"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'timing clock: %s\n' "$clock"
        printf 'timing profile: %s\n' "$profile"
        return 0
    fi

    {
        printf 'enum MacWallNativeWallpaperTimingClockMode: String, Sendable {\n'
        printf '    case controlTimebase = "control-timebase"\n'
        printf '    case synchronizer\n'
        printf '}\n\n'
        printf 'enum MacWallNativeWallpaperTimingProfile: String, Sendable {\n'
        printf '    case normal\n'
        printf '    case reduced\n'
        printf '}\n\n'
        printf 'enum MacWallNativeWallpaperTimingConfiguration {\n'
        printf '    static let clockMode: MacWallNativeWallpaperTimingClockMode = %s\n' "$clock_case"
        printf '    static let profile: MacWallNativeWallpaperTimingProfile = %s\n' "$profile_case"
        printf '}\n'
    } >"$TIMING_MODE_FILE"
    printf 'timing clock: %s\n' "$clock"
    printf 'timing profile: %s\n' "$profile"
}

guard_unsafe_snapshot_mode() {
    local mode="$1"
    local allow_unsafe="$2"

    if [[ "$mode" != "snapshot-xpc-file-url" ]]; then
        return 0
    fi

    if [[ "$allow_unsafe" == "1" ]]; then
        printf 'UNSAFE snapshot mode enabled: %s\n' "$mode"
        printf 'This mode can interrupt WallpaperAgent XPC, invalidate the native runtime, and blank the Desktop surface.\n'
        return 0
    fi

    printf 'Unsafe snapshot mode: %s\n' "$mode" >&2
    printf 'This mode previously triggered NSCocoaErrorDomain(4099), WallpaperAgent XPC invalidation, and runtime removal.\n' >&2
    printf 'Use --allow-unsafe-snapshot-xpc only when intentionally reproducing that failure mode.\n' >&2
    exit 2
}

cmd_reset() {
    local include_wallpaper_agent=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --wallpaper-agent)
                include_wallpaper_agent=1
                ;;
            *)
                printf 'Unknown reset option: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done

    local extension_pids=()
    local pid
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && extension_pids+=("$pid")
    done < <(read_pids_matching "$EXTENSION_PROCESS")
    terminate_pids "$EXTENSION_PROCESS" "${extension_pids[@]}"

    if [[ "$include_wallpaper_agent" == "1" ]]; then
        local wallpaper_agent_pids=()
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && wallpaper_agent_pids+=("$pid")
        done < <(read_pids_matching "$WALLPAPER_AGENT_PROCESS")
        terminate_pids "$WALLPAPER_AGENT_PROCESS" "${wallpaper_agent_pids[@]}"
    fi
}

cmd_install() {
    local snapshot_mode="$SNAPSHOT_MODE_DEFAULT"
    local video_source_mode="$VIDEO_SOURCE_MODE_DEFAULT"
    local video_path=""
    local timing_clock="$TIMING_CLOCK_DEFAULT"
    local timing_profile="$TIMING_PROFILE_DEFAULT"
    local allow_unsafe_snapshot_xpc=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --snapshot-mode)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'install --snapshot-mode requires a mode\n' >&2
                    exit 2
                }
                snapshot_mode="$1"
                ;;
            --video-source)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'install --video-source requires a mode\n' >&2
                    exit 2
                }
                video_source_mode="$1"
                ;;
            --video-path)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'install --video-path requires a path\n' >&2
                    exit 2
                }
                video_path="$1"
                ;;
            --timing-clock)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'install --timing-clock requires a mode\n' >&2
                    exit 2
                }
                timing_clock="$1"
                ;;
            --timing-profile)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'install --timing-profile requires a profile\n' >&2
                    exit 2
                }
                timing_profile="$1"
                ;;
            --allow-unsafe-snapshot-xpc)
                allow_unsafe_snapshot_xpc=1
                ;;
            *)
                printf 'Unknown install option: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done

    if [[ -n "$video_path" ]]; then
        if [[ "$video_path" != /* ]]; then
            printf 'install --video-path requires an absolute path: %s\n' "$video_path" >&2
            exit 2
        fi
        if [[ ! -f "$video_path" ]]; then
            printf 'Video path is not an existing regular file: %s\n' "$video_path" >&2
            exit 2
        fi
        printf 'video path: %s\n' "$video_path"
    fi

    guard_unsafe_snapshot_mode "$snapshot_mode" "$allow_unsafe_snapshot_xpc"
    generate_snapshot_mode_source "$snapshot_mode"
    generate_video_source_mode_source "$video_source_mode"
    generate_timing_mode_source "$timing_clock" "$timing_profile"
    local cmake_arguments=(-S "$SCRIPT_DIR" -B "$BUILD_DIR" -G Xcode)
    if [[ -n "$video_path" ]]; then
        cmake_arguments+=("-DMACWALL_NATIVE_SAMPLE_VIDEO_SOURCE=$video_path")
    else
        cmake_arguments+=(-U MACWALL_NATIVE_SAMPLE_VIDEO_SOURCE)
    fi
    run_cmd cmake "${cmake_arguments[@]}"
    run_cmd xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme MacWallNativeWallpaperSpikeApp \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        build
    run_cmd codesign --verify --deep --strict "$APP_PATH"
    run_cmd "$LSREGISTER" -f -R -trusted "$APP_PATH"
    printf 'Install complete: %s\n' "$APP_PATH"
    printf 'Next: select MacWall Native Spike in System Settings.\n'
}

cmd_status() {
    printf 'Build dir: %s\n' "$BUILD_DIR"
    printf 'App path: %s\n' "$APP_PATH"
    printf 'Snapshot mode source: %s\n' "$SNAPSHOT_MODE_FILE"
    if [[ -f "$SNAPSHOT_MODE_FILE" ]]; then
        awk '/static let mode:/ { print "Snapshot mode: " $0 }' "$SNAPSHOT_MODE_FILE"
    else
        printf 'Snapshot mode: missing generated source, run ./dev.sh install\n'
    fi
    printf 'Video source mode source: %s\n' "$VIDEO_SOURCE_MODE_FILE"
    if [[ -f "$VIDEO_SOURCE_MODE_FILE" ]]; then
        awk '/static let mode:/ { print "Video source: " $0 }' "$VIDEO_SOURCE_MODE_FILE"
    else
        printf 'Video source: missing generated source, run ./dev.sh install\n'
    fi
    printf 'Timing mode source: %s\n' "$TIMING_MODE_FILE"
    if [[ -f "$TIMING_MODE_FILE" ]]; then
        awk '/static let clockMode:/ { print "Timing clock: " $0 }' "$TIMING_MODE_FILE"
        awk '/static let profile:/ { print "Timing profile: " $0 }' "$TIMING_MODE_FILE"
    else
        printf 'Timing mode: missing generated source, run ./dev.sh install\n'
    fi
    printf '\nProcesses:\n'
    process_lines | awk -v extension="$EXTENSION_PROCESS" -v agent="$WALLPAPER_AGENT_PROCESS" '
        index($0, extension) > 0 || index($0, agent) > 0 {
            print $0
        }
    '
    printf '\nRecent extension session logs:\n'
    /usr/bin/log show --last 20m --info --style compact \
        --predicate "subsystem == '$EXTENSION_SUBSYSTEM' AND eventMessage CONTAINS 'session='" \
        2>/dev/null | tail -n 20 || true
}

cmd_logs() {
    local mode="show"
    local last="10m"
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --stream)
                mode="stream"
                ;;
            --last)
                shift
                [[ "$#" -gt 0 ]] || {
                    printf 'logs --last requires a duration, for example 10m\n' >&2
                    exit 2
                }
                last="$1"
                ;;
            *)
                printf 'Unknown logs option: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done

    local wallpaper_agent_predicate="process == 'WallpaperAgent' AND eventMessage CONTAINS '$EXTENSION_BUNDLE_ID'"
    local predicate="subsystem == '$EXTENSION_SUBSYSTEM' OR ($wallpaper_agent_predicate)"
    if [[ "$mode" == "stream" ]]; then
        run_cmd /usr/bin/log stream --info --style compact --predicate "$predicate"
    else
        run_cmd /usr/bin/log show --last "$last" --info --style compact --predicate "$predicate"
    fi
}

main() {
    local command="${1:-help}"
    if [[ "$#" -gt 0 ]]; then
        shift
    fi

    case "$command" in
        reset)
            cmd_reset "$@"
            ;;
        install)
            cmd_install "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            printf 'Unknown command: %s\n\n' "$command" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
