#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}

count_lines() {
  awk 'NF { count += 1 } END { print count + 0 }'
}

repo_count() {
  if command -v yay >/dev/null 2>&1; then
    yay -Qu --repo 2>/dev/null | count_lines
    return 0
  fi

  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates 2>/dev/null | count_lines
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    pacman -Qu 2>/dev/null | count_lines
    return 0
  fi

  printf '0\n'
}

aur_count() {
  if command -v yay >/dev/null 2>&1; then
    yay -Qua 2>/dev/null | count_lines
    return 0
  fi

  if command -v paru >/dev/null 2>&1; then
    paru -Qua 2>/dev/null | count_lines
    return 0
  fi

  printf '0\n'
}

case "$mode" in
  repo|pacman)
    repo_count || printf '0\n'
    ;;
  aur|yay)
    aur_count || printf '0\n'
    ;;
  *)
    printf '0\n'
    ;;
esac
