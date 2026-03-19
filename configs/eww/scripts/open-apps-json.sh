#!/usr/bin/env bash
set -euo pipefail

map_label() {
  case "${1,,}" in
    firefox*|librewolf|zen-browser|zen)
      printf 'Firefox'
      ;;
    code|code-oss|codium|vscodium)
      printf 'Code'
      ;;
    vesktop|discord)
      printf 'Vesktop'
      ;;
    kitty|foot|wezterm|alacritty)
      printf 'Terminal'
      ;;
    thunar|nautilus|dolphin)
      printf 'Files'
      ;;
    steam)
      printf 'Steam'
      ;;
    spotify)
      printf 'Spotify'
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

map_icon() {
  case "${1,,}" in
    firefox*|librewolf|zen-browser|zen)
      printf '󰈹'
      ;;
    code|code-oss|codium|vscodium)
      printf '󰨞'
      ;;
    vesktop|discord)
      printf '󰙯'
      ;;
    kitty|foot|wezterm|alacritty)
      printf ''
      ;;
    thunar|nautilus|dolphin)
      printf ''
      ;;
    steam)
      printf '󰓓'
      ;;
    spotify)
      printf '󰓇'
      ;;
    *)
      printf '󰣆'
      ;;
  esac
}

json_escape() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

declare -A counts=()
declare -A addresses=()
declare -A workspaces=()
classes=()

while IFS=$'\t' read -r cls workspace address; do
  [[ -z "$cls" ]] && continue
  [[ "$cls" == "eww" ]] && continue
  if [[ -v "counts[$cls]" ]]; then
    counts["$cls"]=$((counts["$cls"] + 1))
  else
    counts["$cls"]=1
    addresses["$cls"]=$address
    workspaces["$cls"]=$workspace
    classes+=("$cls")
  fi
done < <(
  hyprctl clients -j 2>/dev/null | awk -F'"' '
    /"address"[[:space:]]*:/ { address=$4; next }
    /"mapped"[[:space:]]*:[[:space:]]*true/ { mapped=1; next }
    /"mapped"[[:space:]]*:[[:space:]]*false/ { mapped=0; next }
    /"workspace"[[:space:]]*:/ { in_workspace=1; next }
    in_workspace && /"id"[[:space:]]*:/ {
      workspace=$0
      gsub(/[^0-9-]/, "", workspace)
      in_workspace=0
      next
    }
    /"class"[[:space:]]*:/ {
      if (mapped && $4 != "" && address != "" && workspace != "") {
        print $4 "\t" workspace "\t" address
        mapped=0
        workspace=""
        address=""
      }
    }
  '
)

printf '['
for ((i = 0; i < ${#classes[@]}; i++)); do
  cls=${classes[i]}
  label=$(map_label "$cls")
  icon=$(map_icon "$cls")
  count=${counts["$cls"]}
  if (( count > 1 )); then
    label="$label ($count)"
  fi

  if (( i % 5 == 0 )); then
    (( i > 0 )) && printf '],'
    printf '['
    first=1
  fi

  (( first )) || printf ','
  printf '{"id":"%s","icon":"%s","label":"%s","workspace":"%s","address":"%s"}' \
    "$(json_escape "$cls")" \
    "$(json_escape "$icon")" \
    "$(json_escape "$label")" \
    "$(json_escape "${workspaces["$cls"]}")" \
    "$(json_escape "${addresses["$cls"]}")"
  first=0
done
(( ${#classes[@]} > 0 )) && printf ']'
printf ']'
