#!/usr/bin/env bash
set -u

osk_procs=(wvkbd-mobintl wvkbd maliit-keyboard squeekboard onboard)

cleanup_osk() {
    for p in "${osk_procs[@]}"; do
        pkill -x "$p" >/dev/null 2>&1 || true
    done
}

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
