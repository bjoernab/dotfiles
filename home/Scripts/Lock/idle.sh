#!/usr/bin/env bash

# Idle management for Hyprland using swayidle + hyprlock.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
lock_cmd="${script_dir}/lock-now.sh"

swayidle -w \
  timeout 1800 "${lock_cmd}" \
  before-sleep "${lock_cmd}"
