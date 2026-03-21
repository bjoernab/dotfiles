#!/usr/bin/env bash
set -u

osk_procs=(wvkbd-mobintl wvkbd maliit-keyboard squeekboard onboard)

cleanup_osk() {
    for p in "${osk_procs[@]}"; do
        pkill -x "$p" >/dev/null 2>&1 || true
    done
}

lock_script="${HOME}/Scripts/Lock/lock-now.sh"

if [[ -x "$lock_script" ]]; then
    "$lock_script" "$@"
    status=$?
    cleanup_osk
    exit "$status"
fi

if command -v hyprlock >/dev/null 2>&1; then
    hyprlock "$@"
    status=$?
    cleanup_osk
    exit "$status"
fi

loginctl lock-session
status=$?
cleanup_osk
exit "$status"
