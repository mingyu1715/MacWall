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
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
DRY_RUN="${MACWALL_NATIVE_DRY_RUN:-0}"

usage() {
    cat <<'EOF'
Usage: ./dev.sh <command> [options]

Commands:
  reset [--wallpaper-agent]  Terminate stale MacWall native wallpaper extension processes.
  install                    Generate, build, codesign-verify, and register the spike app.
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
    run_cmd cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" -G Xcode
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
