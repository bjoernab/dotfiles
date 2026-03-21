#!/usr/bin/env bash

set -u

lock_file="${XDG_RUNTIME_DIR:-/tmp}/hyprlock-network-killswitch.lock"
network_disabled=0
audio_state_captured=0
audio_sinks=()
audio_sources=()
declare -A sink_mute_state=()
declare -A source_mute_state=()

restore_network() {
  if (( network_disabled )) && command -v nmcli >/dev/null 2>&1; then
    nmcli networking on >/dev/null 2>&1 || true
  fi
}

capture_audio_state() {
  local sink source muted

  if ! command -v pactl >/dev/null 2>&1; then
    return 0
  fi

  if ! pactl info >/dev/null 2>&1; then
    return 0
  fi

  mapfile -t audio_sinks < <(pactl list short sinks 2>/dev/null | awk '{print $2}')
  mapfile -t audio_sources < <(pactl list short sources 2>/dev/null | awk '{print $2}')

  for sink in "${audio_sinks[@]}"; do
    muted="$(pactl get-sink-mute "$sink" 2>/dev/null | awk '{print $2}')"
    if [[ -n "$muted" ]]; then
      sink_mute_state["$sink"]="$muted"
    fi
  done

  for source in "${audio_sources[@]}"; do
    muted="$(pactl get-source-mute "$source" 2>/dev/null | awk '{print $2}')"
    if [[ -n "$muted" ]]; then
      source_mute_state["$source"]="$muted"
    fi
  done

  audio_state_captured=1
}

mute_all_audio() {
  local sink source

  if (( ! audio_state_captured )); then
    return 0
  fi

  for sink in "${audio_sinks[@]}"; do
    pactl set-sink-mute "$sink" 1 >/dev/null 2>&1 || true
  done

  for source in "${audio_sources[@]}"; do
    pactl set-source-mute "$source" 1 >/dev/null 2>&1 || true
  done
}

restore_audio() {
  local sink source muted

  if (( ! audio_state_captured )) || ! command -v pactl >/dev/null 2>&1; then
    return 0
  fi

  for sink in "${audio_sinks[@]}"; do
    muted="${sink_mute_state[$sink]:-yes}"
    if [[ "$muted" == "yes" ]]; then
      pactl set-sink-mute "$sink" 1 >/dev/null 2>&1 || true
    else
      pactl set-sink-mute "$sink" 0 >/dev/null 2>&1 || true
    fi
  done

  for source in "${audio_sources[@]}"; do
    muted="${source_mute_state[$source]:-yes}"
    if [[ "$muted" == "yes" ]]; then
      pactl set-source-mute "$source" 1 >/dev/null 2>&1 || true
    else
      pactl set-source-mute "$source" 0 >/dev/null 2>&1 || true
    fi
  done
}

cleanup() {
  restore_audio
  restore_network
}

trap cleanup EXIT

exec 9>"${lock_file}"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || exit 0
fi

if pgrep -x hyprlock >/dev/null 2>&1; then
  exit 0
fi

if ! command -v hyprlock >/dev/null 2>&1; then
  exec loginctl lock-session
fi

if command -v nmcli >/dev/null 2>&1; then
  if [[ "$(nmcli -t -f NETWORKING general status 2>/dev/null)" == "enabled" ]]; then
    if nmcli networking off >/dev/null 2>&1; then
      network_disabled=1
    fi
  fi
fi

capture_audio_state
mute_all_audio

hyprlock "$@"
exit $?
