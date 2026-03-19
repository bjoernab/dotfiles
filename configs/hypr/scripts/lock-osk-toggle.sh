#!/usr/bin/env bash
set -u

if command -v flock >/dev/null 2>&1; then
    lockfile="${XDG_RUNTIME_DIR:-/tmp}/lock-osk-toggle.lock"
    exec 9>"$lockfile"
    flock -n 9 || exit 0
fi

pidfile="${XDG_RUNTIME_DIR:-/tmp}/lock-osk-toggle.pid"

osk_procs=(wvkbd-mobintl wvkbd maliit-keyboard squeekboard onboard)
osk_cmds=(wvkbd-mobintl wvkbd maliit-keyboard squeekboard onboard)
wvkbd_theme=(
    --bg 100f1ee0
    --fg 1e1a35ec
    --fg-sp 2b2450f0
    --press 6253f2ff
    --press-sp 7a68ffff
    --swipe 1e1a35ec
    --swipe-sp 2b2450f0
    --text ede9ffff
    --text-sp f7f3ffff
    -R 12
    -H 220
    -L 150
    --fn "JetBrains Mono 14"
)

remove_pidfile() {
    rm -f "$pidfile"
}

kill_osk() {
    for p in "${osk_procs[@]}"; do
        pkill -x "$p" >/dev/null 2>&1 || true
    done
    remove_pidfile
}

# If we know the spawned PID, toggle off directly.
if [[ -r "$pidfile" ]]; then
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" >/dev/null 2>&1 || true
        sleep 0.05
        kill -9 "$pid" >/dev/null 2>&1 || true
        remove_pidfile
        exit 0
    fi
    remove_pidfile
fi

# Fallback: toggle off any known running OSK process.
for p in "${osk_procs[@]}"; do
    if pgrep -x "$p" >/dev/null 2>&1; then
        kill_osk
        exit 0
    fi
done

# Otherwise launch the first installed OSK.
for cmd in "${osk_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        proc="$(basename "$cmd")"
        if [[ "$proc" == "wvkbd-mobintl" || "$proc" == "wvkbd" ]]; then
            nohup "$cmd" "${wvkbd_theme[@]}" >/dev/null 2>&1 &
        else
            nohup "$cmd" >/dev/null 2>&1 &
        fi
        osk_pid=$!
        if [[ "$osk_pid" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$osk_pid" > "$pidfile"
        fi
        disown
        exit 0
    fi
done

# Helpful fallback if no OSK backend is installed.
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 3 5000 "rgb(ff6b6b)" "No on-screen keyboard installed (onboard/squeekboard/wvkbd)" >/dev/null 2>&1 || true
fi

exit 1
