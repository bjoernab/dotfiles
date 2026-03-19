#!/usr/bin/env bash
set -euo pipefail

eww open --toggle dashboard

if eww active-windows | grep -q '^dashboard:'; then
  hyprctl dispatch submap eww-dashboard >/dev/null 2>&1 || true
else
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
fi
