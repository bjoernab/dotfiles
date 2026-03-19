#!/usr/bin/env bash
set -euo pipefail

last_application=""

emit_current_application() {
  local window app

  window=$(hyprctl activewindow -j 2>/dev/null || true)
  app=$(printf '%s\n' "$window" | awk -F'"' '/"class"[[:space:]]*:/ { print $4; exit }')

  if [[ -z "$app" ]]; then
    app=$(printf '%s\n' "$window" | awk -F'"' '/"title"[[:space:]]*:/ { print $4; exit }')
  fi

  if [[ -z "$app" ]]; then
    app="Desktop"
  fi

  app=$(printf '%.48s' "$app")

  if [[ "$app" != "$last_application" ]]; then
    printf '%s\n' "$app"
    last_application=$app
  fi
}

stream_hyprland_events() {
  perl -MIO::Socket::UNIX -MSocket -e '
    my $path = shift;
    my $socket = IO::Socket::UNIX->new(Type => SOCK_STREAM, Peer => $path) or exit 1;
    $| = 1;

    while (my $event = <$socket>) {
      print $event;
    }
  ' "$1"
}

socket_path=""
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  socket_path="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
fi

emit_current_application

if [[ -S "$socket_path" ]]; then
  while IFS= read -r event; do
    case "$event" in
      activewindow\>\>*|activewindowv2\>\>*|closewindow\>\>*|openwindow\>\>*|workspace\>\>*|workspacev2\>\>*|focusedmon\>\>*|focusedmonv2\>\>*)
        emit_current_application
        ;;
    esac
  done < <(stream_hyprland_events "$socket_path" 2>/dev/null)
fi

while sleep 0.1; do
  emit_current_application
done
