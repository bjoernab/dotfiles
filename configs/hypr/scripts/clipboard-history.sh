#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f "$0")"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
history_file="$state_dir/clipboard-history"
max_entries=200
paste_delay="${CLIPBOARD_HISTORY_PASTE_DELAY:-0.1}"

get_active_window_field() {
    local field="$1"
    hyprctl -j activewindow 2>/dev/null | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

get_paste_shortcut() {
    local window_class="$1"

    case "$window_class" in
        kitty|Alacritty|foot|org.wezfurlong.wezterm|com.mitchellh.ghostty|Ghostty|org.kde.konsole)
            printf '%s' 'CTRL_SHIFT,V'
            ;;
        *)
            printf '%s' 'CTRL,V'
            ;;
    esac
}

ensure_watcher() {
    if pgrep -af -- "wl-paste --type text --watch $script_path store" >/dev/null; then
        return
    fi

    nohup "$script_path" watch >/dev/null 2>&1 &
}

store_entry() {
    local input_file tmp_file encoded

    mkdir -p "$state_dir"
    input_file="$(mktemp)"
    tmp_file="$(mktemp)"

    cat > "$input_file"

    if [ ! -s "$input_file" ]; then
        rm -f "$input_file" "$tmp_file"
        return 0
    fi

    encoded="$(base64 -w 0 < "$input_file")"

    {
        printf '%s\n' "$encoded"
        if [ -f "$history_file" ]; then
            grep -Fvx -- "$encoded" "$history_file" || true
        fi
    } | head -n "$max_entries" > "$tmp_file"

    mv "$tmp_file" "$history_file"
    rm -f "$input_file"
}

show_menu() {
    local -a entries menu_lines
    local encoded decoded preview choice index target_window target_class paste_shortcut

    ensure_watcher

    if [ ! -s "$history_file" ]; then
        return 0
    fi

    target_window="$(get_active_window_field address)"
    target_class="$(get_active_window_field class)"
    paste_shortcut="$(get_paste_shortcut "$target_class")"

    mapfile -t entries < "$history_file"

    for index in "${!entries[@]}"; do
        encoded="${entries[$index]}"
        decoded="$(printf '%s' "$encoded" | base64 -d 2>/dev/null || true)"
        preview="$(printf '%s' "$decoded" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"

        if [ -z "$preview" ]; then
            preview="[blank text]"
        fi

        menu_lines+=("$(printf '%03d %s' "$((index + 1))" "${preview:0:120}")")
    done

    choice="$(printf '%s\n' "${menu_lines[@]}" | rofi -dmenu -i -p clipboard)"

    if [ -z "$choice" ]; then
        return 0
    fi

    index="${choice%% *}"

    if [[ ! "$index" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    encoded="${entries[$((10#$index - 1))]:-}"

    if [ -z "$encoded" ]; then
        return 0
    fi

    printf '%s' "$encoded" | base64 -d | wl-copy

    sleep "$paste_delay"

    if [ -n "$target_window" ]; then
        hyprctl dispatch focuswindow "address:$target_window" >/dev/null 2>&1 || true
        hyprctl dispatch sendshortcut "$paste_shortcut,address:$target_window" >/dev/null 2>&1 || true
        return 0
    fi

    hyprctl dispatch sendshortcut "$paste_shortcut" >/dev/null 2>&1 || true
}

case "${1:-}" in
    watch)
        mkdir -p "$state_dir"
        exec wl-paste --type text --watch "$script_path" store
        ;;
    store)
        store_entry
        ;;
    menu)
        show_menu
        ;;
    *)
        printf 'Usage: %s {watch|store|menu}\n' "$0" >&2
        exit 1
        ;;
esac
