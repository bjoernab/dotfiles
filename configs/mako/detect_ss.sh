#!/usr/bin/env bash
set -euo pipefail

MODE_NAME="screenshare"
MASK_APP_NAME="mako-screenshare-mask"
MAIN_BASHPID="$BASHPID"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="$SCRIPT_DIR/detect_ss_helper.py"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mako-detect-ss.lock"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$1" >&2
        exit 1
    fi
}

enable_mode() {
    makoctl mode -a "$MODE_NAME" >/dev/null 2>&1 || true
}

disable_mode() {
    makoctl mode -r "$MODE_NAME" >/dev/null 2>&1 || true
}

sync_mode() {
    if ((${#ACTIVE_SESSIONS[@]} > 0)); then
        enable_mode
    else
        disable_mode
    fi
}

watch_screencast_events() {
    exec 9>&-

    while IFS=$'\t' read -r event session_path; do
        [[ -n "${event:-}" && -n "${session_path:-}" ]] || continue

        case "$event" in
            start)
                ACTIVE_SESSIONS["$session_path"]=1
                ;;
            closed)
                unset "ACTIVE_SESSIONS[$session_path]"
                ;;
        esac

        sync_mode
    done < <(
        while true; do
            busctl --user monitor --json=short org.freedesktop.portal.Desktop |
                python3 -u "$HELPER_SCRIPT" portal
            sleep 1
        done
    )
}

watch_notification_stream() {
    exec 9>&-

    while true; do
        busctl --user monitor --json=short \
            --match="type='method_call',interface='org.freedesktop.Notifications',member='Notify'" |
            python3 -u "$HELPER_SCRIPT" notifications "$MASK_APP_NAME" "$MODE_NAME"
        sleep 1
    done
}

cleanup() {
    if [[ "${BASHPID:-}" != "$MAIN_BASHPID" ]]; then
        return
    fi

    disable_mode

    if [[ -n "${NOTIFY_WATCH_PID:-}" ]]; then
        kill "$NOTIFY_WATCH_PID" >/dev/null 2>&1 || true
        wait "$NOTIFY_WATCH_PID" 2>/dev/null || true
    fi

    if [[ -n "${PORTAL_WATCH_PID:-}" ]]; then
        kill "$PORTAL_WATCH_PID" >/dev/null 2>&1 || true
        wait "$PORTAL_WATCH_PID" 2>/dev/null || true
    fi
}

require_command busctl
require_command flock
require_command makoctl
require_command notify-send
require_command python3

if [[ ! -f "$HELPER_SCRIPT" ]]; then
    printf 'Missing helper script: %s\n' "$HELPER_SCRIPT" >&2
    exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    printf 'detect_ss.sh is already running\n' >&2
    exit 1
fi

declare -A ACTIVE_SESSIONS=()

trap cleanup EXIT INT TERM

makoctl reload >/dev/null 2>&1 || true
disable_mode

watch_notification_stream &
NOTIFY_WATCH_PID=$!

watch_screencast_events &
PORTAL_WATCH_PID=$!

wait "$NOTIFY_WATCH_PID" "$PORTAL_WATCH_PID"
