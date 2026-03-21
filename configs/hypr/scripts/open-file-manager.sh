#!/usr/bin/env bash

set -u

target_dir="${HOME:-/tmp}"

for file_manager in dolphin thunar nautilus nemo pcmanfm pcmanfm-qt caja; do
    if command -v "$file_manager" >/dev/null 2>&1; then
        exec "$file_manager" "$target_dir"
    fi
done

if command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$target_dir"
fi

printf 'No supported file manager was found.\n' >&2
exit 1
