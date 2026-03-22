#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_UPDATE_SKIP_REMOTE_SYNC="${DOTFILES_UPDATE_SKIP_REMOTE_SYNC:-false}"
DOTFILES_UPDATE_REEXECED="${DOTFILES_UPDATE_REEXECED:-false}"

for arg in "$@"; do
  if [[ "$arg" == "--no-pull" || "$arg" == "--help" || "$arg" == "-h" ]]; then
    DOTFILES_UPDATE_SKIP_REMOTE_SYNC="true"
    break
  fi
done

if [[ "${DOTFILES_UPDATE_SKIP_REMOTE_SYNC}" != "true" && "${DOTFILES_UPDATE_REEXECED}" != "true" ]] && command -v git >/dev/null 2>&1 && [[ -d "${SCRIPT_DIR}/.git" ]]; then
  if git -C "${SCRIPT_DIR}" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    if git -C "${SCRIPT_DIR}" diff --quiet --ignore-submodules -- && git -C "${SCRIPT_DIR}" diff --cached --quiet --ignore-submodules --; then
      current_head="$(git -C "${SCRIPT_DIR}" rev-parse HEAD 2>/dev/null || true)"

      if git -C "${SCRIPT_DIR}" pull --ff-only --quiet; then
        new_head="$(git -C "${SCRIPT_DIR}" rev-parse HEAD 2>/dev/null || true)"

        if [[ -n "${current_head}" && -n "${new_head}" && "${current_head}" != "${new_head}" ]]; then
          export DOTFILES_UPDATE_REEXECED="true"
          exec bash "${SCRIPT_DIR}/update.sh" "$@"
        fi
      else
        printf '%s\n' "warning: unable to fast-forward the dotfiles repo; continuing with the current checkout." >&2
      fi
    else
      printf '%s\n' "warning: dotfiles repo has local changes; skipping automatic git pull." >&2
    fi
  fi
fi

# shellcheck source=scripts/helpers.sh
source "$SCRIPT_DIR/scripts/helpers.sh"
# shellcheck source=scripts/print_status.sh
source "$SCRIPT_DIR/scripts/print_status.sh"

# =========================
# config
# =========================

PACKAGE_DIR="$SCRIPT_DIR/packages"
load_update_package_groups "$PACKAGE_DIR" || exit 1

SYSTEMD_NETWORKD_SERVICES=(
  systemd-networkd
  systemd-resolved
)

USER_DIRECTORIES=(
  Downloads
  Videos
  Scripts
  Images
  Images/wallpapers
  Documents
  Desktop
)

# =========================
# state
# =========================

STATUS_USE_ASCII="true"
UPDATE_MODE="live"
GPU_CHOICE="skip"
AUDIO_CHOICE="skip"
NETWORK_CHOICE="skip"
UPDATE_LAPTOP="false"
UPDATE_BLUETOOTH="false"
MANAGE_HYPRLAND="true"
MANAGE_FONTS="true"
UPDATE_FILE_MANAGER="false"
UPDATE_BROWSER="false"
UPDATE_EXTRA_APPS="false"
ENSURE_ZSH_PACKAGE="false"
SYNC_APP_CONFIGS="true"
SYNC_SHELL_DOTFILES="true"

REPO_DIR="$SCRIPT_DIR"
BACKUP_DIR="$HOME/.dotfiles-update-backup-$(date +%Y%m%d-%H%M%S)"
DOTFILES_INSTALL_STATE_FILE="${DOTFILES_INSTALL_STATE_FILE:-/var/lib/dotfiles/install-state}"
DOTFILES_UPDATE_STATE_DIR="${DOTFILES_UPDATE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
DOTFILES_UPDATE_STATE_FILE="${DOTFILES_UPDATE_STATE_FILE:-${DOTFILES_UPDATE_STATE_DIR}/update-state}"

# =========================
# prompt helpers
# =========================

current_shell_is_zsh() {
  [[ "${SHELL##*/}" == "zsh" ]]
}

print_usage() {
  cat <<'EOF'
Usage: ./update.sh [--interactive] [--no-pull] [--help]

Default mode:
  Runs a one-click live sync for machines that already use these dotfiles.
  It fast-forwards the repo when possible, upgrades packages, and re-syncs
  the managed configs and home files without prompting.

Options:
  --interactive  Choose update components manually before proceeding
  --no-pull      Skip the automatic git pull of this repo before updating
  --help         Show this help text
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --interactive)
        UPDATE_MODE="interactive"
        ;;
      --no-pull)
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        print_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
    esac

    shift
  done
}

auto_detect_selections() {
  print_header "AUTO-DETECTING INSTALLED COMPONENTS"

  if package_is_installed "nvidia-open"; then
    GPU_CHOICE="nvidia-open"
  elif package_is_installed "nvidia"; then
    GPU_CHOICE="nvidia-proprietary"
  elif any_packages_installed libva-mesa-driver vulkan-radeon xf86-video-amdgpu; then
    GPU_CHOICE="amd"
  elif any_packages_installed vulkan-intel intel-media-driver libva-intel-driver; then
    GPU_CHOICE="intel"
  else
    GPU_CHOICE="skip"
  fi
  print_info "GPU update: ${GPU_CHOICE}"

  if any_packages_installed "${PIPEWIRE_PACKAGES[@]}"; then
    AUDIO_CHOICE="pipewire"
  else
    AUDIO_CHOICE="skip"
  fi
  print_info "Audio update: ${AUDIO_CHOICE}"

  if package_is_installed "networkmanager" || systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    NETWORK_CHOICE="networkmanager"
  elif systemctl is-enabled systemd-networkd >/dev/null 2>&1 || systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
    NETWORK_CHOICE="systemd-networkd"
  else
    NETWORK_CHOICE="skip"
  fi
  print_info "Network update: ${NETWORK_CHOICE}"

  if any_packages_installed "${LAPTOP_PACKAGES[@]}" || systemctl is-enabled tlp >/dev/null 2>&1; then
    UPDATE_LAPTOP="true"
  else
    UPDATE_LAPTOP="false"
  fi
  print_info "Laptop update: ${UPDATE_LAPTOP}"

  if any_packages_installed "${BLUETOOTH_PACKAGES[@]}" || systemctl is-enabled bluetooth >/dev/null 2>&1; then
    UPDATE_BLUETOOTH="true"
  else
    UPDATE_BLUETOOTH="false"
  fi
  print_info "Bluetooth update: ${UPDATE_BLUETOOTH}"

  MANAGE_HYPRLAND="true"
  MANAGE_FONTS="true"
  print_info "Hyprland package update: ${MANAGE_HYPRLAND}"
  print_info "Font package update: ${MANAGE_FONTS}"

  if any_packages_installed "${FILE_MANAGER_PACKAGES[@]}"; then
    UPDATE_FILE_MANAGER="true"
  else
    UPDATE_FILE_MANAGER="false"
  fi
  print_info "File manager update: ${UPDATE_FILE_MANAGER}"

  if any_packages_installed "${BROWSER_PACKAGES[@]}"; then
    UPDATE_BROWSER="true"
  else
    UPDATE_BROWSER="false"
  fi
  print_info "Browser update: ${UPDATE_BROWSER}"

  if any_packages_installed "${APP_PACKAGES[@]}"; then
    UPDATE_EXTRA_APPS="true"
  else
    UPDATE_EXTRA_APPS="false"
  fi
  print_info "Extra app update: ${UPDATE_EXTRA_APPS}"

  if any_packages_installed "${SHELL_PACKAGES[@]}" || current_shell_is_zsh || [[ -f "$HOME/.zshrc" ]]; then
    ENSURE_ZSH_PACKAGE="true"
  else
    ENSURE_ZSH_PACKAGE="false"
  fi
  print_info "Ensure zsh package: ${ENSURE_ZSH_PACKAGE}"

  SYNC_APP_CONFIGS="true"
  SYNC_SHELL_DOTFILES="true"
  print_info "Sync app configs: ${SYNC_APP_CONFIGS}"
  print_info "Sync shell dotfiles: ${SYNC_SHELL_DOTFILES}"
}

read_state_value() {
  local file_path="$1"
  local key="$2"

  [[ -f "${file_path}" ]] || return 1
  sed -n "s/^${key}=//p" "${file_path}" | head -n 1
}

set_choice_if_allowed() {
  local variable_name="$1"
  local value="$2"
  shift 2
  local allowed

  for allowed in "$@"; do
    if [[ "${value}" == "${allowed}" ]]; then
      printf -v "${variable_name}" '%s' "${value}"
      return 0
    fi
  done

  return 1
}

set_bool_if_allowed() {
  local variable_name="$1"
  local value="$2"

  case "${value}" in
    true|false)
      printf -v "${variable_name}" '%s' "${value}"
      return 0
      ;;
  esac

  return 1
}

load_install_state_selections() {
  local install_status
  local loaded_any="false"
  local value

  [[ -f "${DOTFILES_INSTALL_STATE_FILE}" ]] || return 1

  install_status="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "status" || true)"
  if [[ -z "${install_status}" ]]; then
    return 1
  fi

  value="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "gpu" || true)"
  if set_choice_if_allowed GPU_CHOICE "${value}" "skip" "nvidia-proprietary" "nvidia-open" "amd" "intel"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "audio" || true)"
  if set_choice_if_allowed AUDIO_CHOICE "${value}" "skip" "pipewire"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "network" || true)"
  if set_choice_if_allowed NETWORK_CHOICE "${value}" "skip" "networkmanager" "systemd-networkd"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "laptop" || true)"
  if set_bool_if_allowed UPDATE_LAPTOP "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_INSTALL_STATE_FILE}" "bluetooth" || true)"
  if set_bool_if_allowed UPDATE_BLUETOOTH "${value}"; then
    loaded_any="true"
  fi

  if [[ "${loaded_any}" == "true" ]]; then
    print_info "Loaded base selections from ${DOTFILES_INSTALL_STATE_FILE} (${install_status})."
    return 0
  fi

  return 1
}

load_update_state_selections() {
  local update_status
  local loaded_any="false"
  local value

  [[ -f "${DOTFILES_UPDATE_STATE_FILE}" ]] || return 1

  update_status="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "status" || true)"

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "gpu" || true)"
  if set_choice_if_allowed GPU_CHOICE "${value}" "skip" "nvidia-proprietary" "nvidia-open" "amd" "intel"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "audio" || true)"
  if set_choice_if_allowed AUDIO_CHOICE "${value}" "skip" "pipewire"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "network" || true)"
  if set_choice_if_allowed NETWORK_CHOICE "${value}" "skip" "networkmanager" "systemd-networkd"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "laptop" || true)"
  if set_bool_if_allowed UPDATE_LAPTOP "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "bluetooth" || true)"
  if set_bool_if_allowed UPDATE_BLUETOOTH "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "hyprland" || true)"
  if set_bool_if_allowed MANAGE_HYPRLAND "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "fonts" || true)"
  if set_bool_if_allowed MANAGE_FONTS "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "file_manager" || true)"
  if set_bool_if_allowed UPDATE_FILE_MANAGER "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "browser" || true)"
  if set_bool_if_allowed UPDATE_BROWSER "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "extra_apps" || true)"
  if set_bool_if_allowed UPDATE_EXTRA_APPS "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "ensure_zsh_package" || true)"
  if set_bool_if_allowed ENSURE_ZSH_PACKAGE "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "sync_app_configs" || true)"
  if set_bool_if_allowed SYNC_APP_CONFIGS "${value}"; then
    loaded_any="true"
  fi

  value="$(read_state_value "${DOTFILES_UPDATE_STATE_FILE}" "sync_shell_dotfiles" || true)"
  if set_bool_if_allowed SYNC_SHELL_DOTFILES "${value}"; then
    loaded_any="true"
  fi

  if [[ "${loaded_any}" == "true" ]]; then
    if [[ -n "${update_status}" ]]; then
      print_info "Loaded saved live selections from ${DOTFILES_UPDATE_STATE_FILE} (${update_status})."
    else
      print_info "Loaded saved live selections from ${DOTFILES_UPDATE_STATE_FILE}."
    fi
    return 0
  fi

  return 1
}

prepare_live_selections() {
  auto_detect_selections
  load_install_state_selections || true
  load_update_state_selections || true
}

gpu_choice_default_number() {
  case "$GPU_CHOICE" in
    skip) print_line "1" ;;
    nvidia-proprietary) print_line "2" ;;
    nvidia-open) print_line "3" ;;
    amd) print_line "4" ;;
    intel) print_line "5" ;;
    *) print_line "1" ;;
  esac
}

audio_choice_default_number() {
  case "$AUDIO_CHOICE" in
    skip) print_line "1" ;;
    pipewire) print_line "2" ;;
    *) print_line "1" ;;
  esac
}

network_choice_default_number() {
  case "$NETWORK_CHOICE" in
    skip) print_line "1" ;;
    networkmanager) print_line "2" ;;
    systemd-networkd) print_line "3" ;;
    *) print_line "1" ;;
  esac
}

bool_default_letter() {
  if [[ "$1" == "true" ]]; then
    print_line "y"
  else
    print_line "n"
  fi
}

select_gpu_choice() {
  local choice
  local default_choice

  default_choice="$(gpu_choice_default_number)"

  print_header "GPU UPDATE"
  print_line "1) Skip GPU package updates"
  print_line "2) NVIDIA proprietary"
  print_line "3) NVIDIA open kernel modules"
  print_line "4) AMD"
  print_line "5) Intel"
  print_line ""

  while true; do
    read -r -p "Choose GPU option [1-5] (default: ${default_choice}): " choice
    choice="${choice:-$default_choice}"

    case "$choice" in
      1) GPU_CHOICE="skip"; break ;;
      2) GPU_CHOICE="nvidia-proprietary"; break ;;
      3) GPU_CHOICE="nvidia-open"; break ;;
      4) GPU_CHOICE="amd"; break ;;
      5) GPU_CHOICE="intel"; break ;;
      *) print_warn "Invalid choice. Enter a number from 1 to 5." ;;
    esac
  done

  print_success "Selected GPU update: ${GPU_CHOICE}"
}

select_audio_choice() {
  local choice
  local default_choice

  default_choice="$(audio_choice_default_number)"

  print_header "AUDIO UPDATE"
  print_line "1) Skip audio package updates"
  print_line "2) PipeWire"
  print_line ""

  while true; do
    read -r -p "Choose audio option [1-2] (default: ${default_choice}): " choice
    choice="${choice:-$default_choice}"

    case "$choice" in
      1) AUDIO_CHOICE="skip"; break ;;
      2) AUDIO_CHOICE="pipewire"; break ;;
      *) print_warn "Invalid choice. Enter 1 or 2." ;;
    esac
  done

  print_success "Selected audio update: ${AUDIO_CHOICE}"
}

select_network_choice() {
  local choice
  local default_choice

  default_choice="$(network_choice_default_number)"

  print_header "NETWORK UPDATE"
  print_line "1) Skip network package/service updates"
  print_line "2) NetworkManager"
  print_line "3) systemd-networkd"
  print_line ""

  while true; do
    read -r -p "Choose network option [1-3] (default: ${default_choice}): " choice
    choice="${choice:-$default_choice}"

    case "$choice" in
      1) NETWORK_CHOICE="skip"; break ;;
      2) NETWORK_CHOICE="networkmanager"; break ;;
      3) NETWORK_CHOICE="systemd-networkd"; break ;;
      *) print_warn "Invalid choice. Enter a number from 1 to 3." ;;
    esac
  done

  print_success "Selected network update: ${NETWORK_CHOICE}"
}

prompt_optional_components() {
  if ask_yes_no "Keep laptop support packages updated? [y/n]: " "$(bool_default_letter "$UPDATE_LAPTOP")"; then
    UPDATE_LAPTOP="true"
    print_success "Laptop package updates enabled."
  else
    UPDATE_LAPTOP="false"
    print_info "Laptop package updates skipped."
  fi

  if ask_yes_no "Keep Bluetooth support packages updated? [y/n]: " "$(bool_default_letter "$UPDATE_BLUETOOTH")"; then
    UPDATE_BLUETOOTH="true"
    print_success "Bluetooth package updates enabled."
  else
    UPDATE_BLUETOOTH="false"
    print_info "Bluetooth package updates skipped."
  fi

  if ask_yes_no "Keep the Hyprland desktop stack updated? [y/n]: " "$(bool_default_letter "$MANAGE_HYPRLAND")"; then
    MANAGE_HYPRLAND="true"
    print_success "Hyprland package updates enabled."
  else
    MANAGE_HYPRLAND="false"
    print_info "Hyprland package updates skipped."
  fi

  if ask_yes_no "Keep font packages updated? [y/n]: " "$(bool_default_letter "$MANAGE_FONTS")"; then
    MANAGE_FONTS="true"
    print_success "Font package updates enabled."
  else
    MANAGE_FONTS="false"
    print_info "Font package updates skipped."
  fi

  if ask_yes_no "Keep Dolphin file manager updated? [y/n]: " "$(bool_default_letter "$UPDATE_FILE_MANAGER")"; then
    UPDATE_FILE_MANAGER="true"
    print_success "File manager updates enabled."
  else
    UPDATE_FILE_MANAGER="false"
    print_info "File manager updates skipped."
  fi

  if ask_yes_no "Keep Firefox updated? [y/n]: " "$(bool_default_letter "$UPDATE_BROWSER")"; then
    UPDATE_BROWSER="true"
    print_success "Browser updates enabled."
  else
    UPDATE_BROWSER="false"
    print_info "Browser updates skipped."
  fi

  if ask_yes_no "Keep extra apps updated? [y/n]: " "$(bool_default_letter "$UPDATE_EXTRA_APPS")"; then
    UPDATE_EXTRA_APPS="true"
    print_success "Extra app updates enabled."
  else
    UPDATE_EXTRA_APPS="false"
    print_info "Extra app updates skipped."
  fi

  if ask_yes_no "Ensure zsh stays installed? [y/n]: " "$(bool_default_letter "$ENSURE_ZSH_PACKAGE")"; then
    ENSURE_ZSH_PACKAGE="true"
    print_success "zsh package update enabled."
  else
    ENSURE_ZSH_PACKAGE="false"
    print_info "zsh package update skipped."
  fi

  if ask_yes_no "Sync app configs from the repo into ~/.config? [y/n]: " "$(bool_default_letter "$SYNC_APP_CONFIGS")"; then
    SYNC_APP_CONFIGS="true"
    print_success "App config sync enabled."
  else
    SYNC_APP_CONFIGS="false"
    print_info "App config sync skipped."
  fi

  if ask_yes_no "Sync shell dotfiles (~/.zshrc and ~/.bashrc)? [y/n]: " "$(bool_default_letter "$SYNC_SHELL_DOTFILES")"; then
    SYNC_SHELL_DOTFILES="true"
    print_success "Shell dotfile sync enabled."
  else
    SYNC_SHELL_DOTFILES="false"
    print_info "Shell dotfile sync skipped."
  fi
}

prompt_user_choices() {
  auto_detect_selections
  select_gpu_choice
  select_audio_choice
  select_network_choice
  print_header "OPTIONAL UPDATE COMPONENTS"
  prompt_optional_components
}

confirm_update() {
  print_line ""
  if ask_yes_no "Proceed with the selected update actions? [Y/n]: " "y"; then
    print_warn "Proceeding with update."
    return 0
  fi

  print_info "Update cancelled."
  exit 0
}

preflight_checks() {
  preflight_arch_user_postboot
}

# =========================
# package helpers
# =========================

refresh_pacman() {
  refresh_pacman_full_upgrade
}

update_installed_aur_packages() {
  if ! command -v yay >/dev/null 2>&1; then
    print_error "yay is required to update installed AUR packages."
    return 1
  fi

  print_header "UPDATING INSTALLED AUR PACKAGES"
  yay -Sua --noconfirm
  local rc=$?

  report_step_result "Updated installed AUR packages" "$rc"
  return "$rc"
}

# =========================
# service helpers
# =========================

service_unit_exists() {
  local service="$1"
  systemctl list-unit-files --type=service --all "${service}.service" 2>/dev/null | awk '{print $1}' | grep -Fxq "${service}.service"
}

enable_service_group() {
  local group_name="$1"
  shift
  local services=("$@")
  local service
  local rc=0

  if [[ "${#services[@]}" -eq 0 ]]; then
    print_warn "No services defined for ${group_name}. Skipping."
    return 0
  fi

  print_header "ENABLING ${group_name}"

  for service in "${services[@]}"; do
    if ! service_unit_exists "$service"; then
      print_error "Service ${service} was not found."
      rc=1
      continue
    fi

    print_info "Enabling ${service}..."
    if ! sudo systemctl enable "$service"; then
      rc=1
    fi
  done

  report_step_result "Enabled ${group_name}" "$rc"
  return "$rc"
}

verify_services_enabled() {
  local group_name="$1"
  shift
  local services=("$@")
  local service
  local disabled=()

  if [[ "${#services[@]}" -eq 0 ]]; then
    print_warn "No services to verify for ${group_name}. Skipping."
    return 0
  fi

  for service in "${services[@]}"; do
    if ! systemctl is-enabled "$service" >/dev/null 2>&1; then
      disabled+=("$service")
    fi
  done

  if [[ "${#disabled[@]}" -eq 0 ]]; then
    print_success "Verified ${group_name}: services enabled."
    return 0
  fi

  print_error "Verification failed for ${group_name}. Not enabled: ${disabled[*]}"
  return 1
}

enable_network_services() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      enable_service_group "NETWORK SERVICES" "NetworkManager"
      ;;
    systemd-networkd)
      enable_service_group "SYSTEMD NETWORK SERVICES" "${SYSTEMD_NETWORKD_SERVICES[@]}"
      ;;
    skip)
      print_info "Network service enable skipped."
      ;;
  esac
}

verify_network_services() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      verify_services_enabled "NETWORK SERVICES" "NetworkManager"
      ;;
    systemd-networkd)
      verify_services_enabled "SYSTEMD NETWORK SERVICES" "${SYSTEMD_NETWORKD_SERVICES[@]}"
      ;;
    skip)
      print_info "Network service verification skipped."
      return 0
      ;;
  esac
}

enable_bluetooth_service() {
  if [[ "$UPDATE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth service enable skipped."
    return 0
  fi

  enable_service_group "BLUETOOTH SERVICE" "bluetooth"
}

verify_bluetooth_service() {
  if [[ "$UPDATE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth service verification skipped."
    return 0
  fi

  verify_services_enabled "BLUETOOTH SERVICE" "bluetooth"
}

enable_laptop_services() {
  if [[ "$UPDATE_LAPTOP" != "true" ]]; then
    print_info "Laptop service enable skipped."
    return 0
  fi

  enable_service_group "LAPTOP SERVICES" "tlp"
}

verify_laptop_services() {
  if [[ "$UPDATE_LAPTOP" != "true" ]]; then
    print_info "Laptop service verification skipped."
    return 0
  fi

  verify_services_enabled "LAPTOP SERVICES" "tlp"
}

# =========================
# config deployment
# =========================

create_user_directories() {
  local directory
  local rc=0

  print_header "CREATING USER DIRECTORIES"

  for directory in "${USER_DIRECTORIES[@]}"; do
    if mkdir -p "$HOME/$directory"; then
      print_info "Ensured directory exists: $HOME/$directory"
    else
      print_error "Failed to create directory: $HOME/$directory"
      rc=1
    fi
  done

  report_step_result "Created user directories" "$rc"
  return "$rc"
}

deploy_wallpapers() {
  local source_dir="$REPO_DIR/images"
  local target_dir="$HOME/Images/wallpapers"
  local rc=0

  print_header "DEPLOYING WALLPAPERS"

  if [[ ! -d "$source_dir" ]]; then
    print_error "Wallpaper source directory not found: $source_dir"
    report_step_result "Deployed wallpapers" 1
    return 1
  fi

  if ! find "$source_dir" -maxdepth 1 -type f | grep -q .; then
    print_error "No wallpaper files found in: $source_dir"
    report_step_result "Deployed wallpapers" 1
    return 1
  fi

  if ! mkdir -p "$target_dir"; then
    print_error "Failed to create wallpaper directory: $target_dir"
    report_step_result "Deployed wallpapers" 1
    return 1
  fi

  if ! cp -af "$source_dir/." "$target_dir/"; then
    rc=1
  fi

  report_step_result "Deployed wallpapers" "$rc"
  return "$rc"
}

deploy_user_scripts() {
  local rc=0
  local source_files=(
    "$REPO_DIR/home/Scripts/Lock/idle.sh"
    "$REPO_DIR/home/Scripts/Lock/lock-now.sh"
  )
  local target_files=(
    "$HOME/Scripts/Lock/idle.sh"
    "$HOME/Scripts/Lock/lock-now.sh"
  )
  local i

  print_header "DEPLOYING USER SCRIPTS"

  for i in "${!source_files[@]}"; do
    if ! copy_home_file "${source_files[$i]}" "${target_files[$i]}"; then
      rc=1
      continue
    fi

    if ! chmod +x "${target_files[$i]}"; then
      print_error "Failed to make script executable: ${target_files[$i]}"
      rc=1
    fi
  done

  report_step_result "Deployed user scripts" "$rc"
  return "$rc"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

is_text_file() {
  local target_file="$1"

  if [[ ! -f "$target_file" ]]; then
    return 1
  fi

  if [[ ! -s "$target_file" ]]; then
    return 0
  fi

  LC_ALL=C grep -Iq . "$target_file"
}

render_placeholders_in_file() {
  local target_file="$1"
  local home_replacement user_replacement

  if [[ ! -f "$target_file" ]]; then
    return 0
  fi

  if ! is_text_file "$target_file"; then
    return 0
  fi

  if ! grep -qE '@(HOME|USER)@' "$target_file"; then
    return 0
  fi

  home_replacement="$(escape_sed_replacement "$HOME")"
  user_replacement="$(escape_sed_replacement "$USER")"

  sed -i \
    -e "s|@HOME@|${home_replacement}|g" \
    -e "s|@USER@|${user_replacement}|g" \
    "$target_file"
}

render_placeholders_in_path() {
  local target_path="$1"
  local file

  if [[ -f "$target_path" ]]; then
    render_placeholders_in_file "$target_path"
    return $?
  fi

  if [[ ! -d "$target_path" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    render_placeholders_in_file "$file" || return 1
  done < <(find "$target_path" -type f -print0)
}

backup_path() {
  local target="$1"

  if [[ -e "$target" ]]; then
    mkdir -p "$BACKUP_DIR" || return 1
    mv "$target" "$BACKUP_DIR/" || return 1
    print_warn "Backed up $target to $BACKUP_DIR"
  fi

  return 0
}

copy_config_dir() {
  local source_dir="$1"
  local target_dir="$2"

  if [[ ! -d "$source_dir" ]]; then
    print_error "Source config not found: $source_dir"
    return 1
  fi

  backup_path "$target_dir" || return 1
  mkdir -p "$(dirname "$target_dir")" || return 1
  cp -a "$source_dir" "$target_dir" || return 1
  render_placeholders_in_path "$target_dir"
}

copy_home_file() {
  local source_file="$1"
  local target_file="$2"

  if [[ ! -f "$source_file" ]]; then
    print_error "Source file not found: $source_file"
    return 1
  fi

  mkdir -p "$(dirname "$target_file")" || return 1
  backup_path "$target_file" || return 1
  cp -a "$source_file" "$target_file" || return 1
  render_placeholders_in_file "$target_file"
}

eww_runtime_available() {
  command -v eww >/dev/null 2>&1 || any_packages_installed "eww" "eww-wayland"
}

deploy_eww_config() {
  if ! eww_runtime_available; then
    print_warn "Eww is not installed yet. Copying the config anyway so the bar is ready after a later install."
  fi

  if ! package_is_installed "networkmanager" || ! any_packages_installed "${PIPEWIRE_PACKAGES[@]}" || ! command -v nmcli >/dev/null 2>&1 || ! command -v pactl >/dev/null 2>&1; then
    print_warn "Eww expects NetworkManager and PipeWire tools. Copying the config anyway so the setup stays in sync."
  fi

  copy_config_dir "$REPO_DIR/configs/eww" "$HOME/.config/eww"
}

deploy_configs() {
  local rc=0
  local copied_any=0

  if [[ "$SYNC_APP_CONFIGS" != "true" && "$SYNC_SHELL_DOTFILES" != "true" ]]; then
    print_info "Dotfile deployment skipped."
    return 0
  fi

  print_header "DEPLOYING DOTFILES"

  if [[ "$SYNC_APP_CONFIGS" == "true" ]]; then
    mkdir -p "$HOME/.config" || rc=1

    if package_is_installed "hyprland"; then
      if copy_config_dir "$REPO_DIR/configs/hypr" "$HOME/.config/hypr"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Hypr config because hyprland is not installed."
    fi

    if deploy_eww_config; then
      copied_any=1
    else
      rc=1
    fi

    if package_is_installed "rofi"; then
      if copy_config_dir "$REPO_DIR/configs/rofi" "$HOME/.config/rofi"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Rofi config because rofi is not installed."
    fi

    if package_is_installed "kitty"; then
      if copy_config_dir "$REPO_DIR/configs/kitty" "$HOME/.config/kitty"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Kitty config because kitty is not installed."
    fi

    if package_is_installed "mako"; then
      if copy_config_dir "$REPO_DIR/configs/mako" "$HOME/.config/mako"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Mako config because mako is not installed."
    fi

    if package_is_installed "fastfetch"; then
      if copy_config_dir "$REPO_DIR/configs/fastfetch" "$HOME/.config/fastfetch"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Fastfetch config because fastfetch is not installed."
    fi

    if package_is_installed "hyprpaper"; then
      if copy_config_dir "$REPO_DIR/configs/hyprpaper" "$HOME/.config/hyprpaper"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Hyprpaper config because hyprpaper is not installed."
    fi

    if package_is_installed "hyprlock"; then
      if copy_config_dir "$REPO_DIR/configs/hyprlock" "$HOME/.config/hyprlock"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Hyprlock config because hyprlock is not installed."
    fi
  else
    print_info "~/.config deployment skipped."
  fi

  if [[ "$SYNC_SHELL_DOTFILES" == "true" ]]; then
    if copy_home_file "$REPO_DIR/home/.zshrc" "$HOME/.zshrc"; then
      copied_any=1
    else
      rc=1
    fi

    if copy_home_file "$REPO_DIR/home/.bashrc" "$HOME/.bashrc"; then
      copied_any=1
    else
      rc=1
    fi
  else
    print_info "Shell dotfile deployment skipped."
  fi

  if [[ "$copied_any" -eq 0 ]]; then
    print_error "No selected dotfiles were copied."
    rc=1
  fi

  report_step_result "Deployed configuration files" "$rc"
  return "$rc"
}

# =========================
# update wrappers
# =========================

update_audio_selection() {
  case "$AUDIO_CHOICE" in
    pipewire)
      install_package_group "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}"
      verify_packages_installed "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}" || record_fail "Verified AUDIO PACKAGES"
      ;;
    skip)
      print_info "Audio package update skipped."
      ;;
  esac
}

update_network_selection() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      install_package_group "NETWORK PACKAGES" "${NETWORKMANAGER_PACKAGES[@]}"
      verify_packages_installed "NETWORK PACKAGES" "${NETWORKMANAGER_PACKAGES[@]}" || record_fail "Verified NETWORK PACKAGES"
      ;;
    systemd-networkd)
      install_package_group "NETWORK PACKAGES" "${SYSTEMD_NETWORKD_PACKAGES[@]}"
      verify_packages_installed "NETWORK PACKAGES" "${SYSTEMD_NETWORKD_PACKAGES[@]}" || record_fail "Verified NETWORK PACKAGES"
      ;;
    skip)
      print_info "Network package update skipped."
      ;;
  esac
}

update_gpu_selection() {
  case "$GPU_CHOICE" in
    nvidia-proprietary)
      install_package_group "NVIDIA PROPRIETARY PACKAGES" "${NVIDIA_PROPRIETARY_PACKAGES[@]}"
      verify_packages_installed "NVIDIA PROPRIETARY PACKAGES" "${NVIDIA_PROPRIETARY_PACKAGES[@]}" || record_fail "Verified NVIDIA PROPRIETARY PACKAGES"
      ;;
    nvidia-open)
      install_package_group "NVIDIA OPEN PACKAGES" "${NVIDIA_OPEN_PACKAGES[@]}"
      verify_packages_installed "NVIDIA OPEN PACKAGES" "${NVIDIA_OPEN_PACKAGES[@]}" || record_fail "Verified NVIDIA OPEN PACKAGES"
      ;;
    amd)
      install_package_group "AMD GPU PACKAGES" "${AMD_PACKAGES[@]}"
      verify_packages_installed "AMD GPU PACKAGES" "${AMD_PACKAGES[@]}" || record_fail "Verified AMD GPU PACKAGES"
      ;;
    intel)
      install_package_group "INTEL GPU PACKAGES" "${INTEL_PACKAGES[@]}"
      verify_packages_installed "INTEL GPU PACKAGES" "${INTEL_PACKAGES[@]}" || record_fail "Verified INTEL GPU PACKAGES"
      ;;
    skip)
      print_info "GPU package update skipped."
      ;;
  esac
}

update_laptop_selection() {
  if [[ "$UPDATE_LAPTOP" != "true" ]]; then
    print_info "Laptop package update skipped."
    return 0
  fi

  install_package_group "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}"
  verify_packages_installed "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}" || record_fail "Verified LAPTOP PACKAGES"
}

update_bluetooth_selection() {
  if [[ "$UPDATE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth package update skipped."
    return 0
  fi

  install_package_group "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}"
  verify_packages_installed "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}" || record_fail "Verified BLUETOOTH PACKAGES"
}

update_hyprland_selection() {
  if [[ "$MANAGE_HYPRLAND" != "true" ]]; then
    print_info "Hyprland package update skipped."
    return 0
  fi

  install_package_group "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}"
  verify_packages_installed "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}" || record_fail "Verified HYPRLAND PACKAGES"

  install_aur_package_group "HYPRLAND AUR PACKAGES" "${HYPRLAND_AUR_PACKAGES[@]}"
  verify_packages_installed "HYPRLAND AUR PACKAGES" "${HYPRLAND_AUR_PACKAGES[@]}" || record_fail "Verified HYPRLAND AUR PACKAGES"
}

update_font_selection() {
  if [[ "$MANAGE_FONTS" != "true" ]]; then
    print_info "Font package update skipped."
    return 0
  fi

  install_package_group "FONT PACKAGES" "${FONT_PACKAGES[@]}"
  verify_packages_installed "FONT PACKAGES" "${FONT_PACKAGES[@]}" || record_fail "Verified FONT PACKAGES"

  install_aur_package_group "FONT AUR PACKAGES" "${FONT_AUR_PACKAGES[@]}"
  verify_packages_installed "FONT AUR PACKAGES" "${FONT_AUR_PACKAGES[@]}" || record_fail "Verified FONT AUR PACKAGES"
}

update_file_manager_selection() {
  if [[ "$UPDATE_FILE_MANAGER" != "true" ]]; then
    print_info "File manager package update skipped."
    return 0
  fi

  install_package_group "FILE MANAGER PACKAGES" "${FILE_MANAGER_PACKAGES[@]}"
  verify_packages_installed "FILE MANAGER PACKAGES" "${FILE_MANAGER_PACKAGES[@]}" || record_fail "Verified FILE MANAGER PACKAGES"
}

update_browser_selection() {
  if [[ "$UPDATE_BROWSER" != "true" ]]; then
    print_info "Browser package update skipped."
    return 0
  fi

  install_package_group "BROWSER PACKAGES" "${BROWSER_PACKAGES[@]}"
  verify_packages_installed "BROWSER PACKAGES" "${BROWSER_PACKAGES[@]}" || record_fail "Verified BROWSER PACKAGES"
}

update_extra_apps_selection() {
  if [[ "$UPDATE_EXTRA_APPS" != "true" ]]; then
    print_info "Extra app update skipped."
    return 0
  fi

  install_package_group "APP PACKAGES" "${APP_PACKAGES[@]}"
  verify_packages_installed "APP PACKAGES" "${APP_PACKAGES[@]}" || record_fail "Verified APP PACKAGES"
}

update_zsh_selection() {
  if [[ "$ENSURE_ZSH_PACKAGE" != "true" ]]; then
    print_info "zsh package update skipped."
    return 0
  fi

  install_package_group "SHELL PACKAGES" "${SHELL_PACKAGES[@]}"
  verify_packages_installed "SHELL PACKAGES" "${SHELL_PACKAGES[@]}" || record_fail "Verified SHELL PACKAGES"

  if current_shell_is_zsh; then
    print_success "Current shell is already zsh."
    record_pass "Verified current shell is zsh"
  else
    print_warn "zsh is installed, but your current shell is ${SHELL##*/}. Run 'chsh -s $(command -v zsh)' if you want to switch."
  fi
}

# =========================
# summary
# =========================

print_selection_summary() {
  print_key_value_box \
    "SELECTED OPTIONS" \
    "Mode" "${UPDATE_MODE}" \
    "GPU" "${GPU_CHOICE}" \
    "Audio" "${AUDIO_CHOICE}" \
    "Network" "${NETWORK_CHOICE}" \
    "Laptop" "${UPDATE_LAPTOP}" \
    "Bluetooth" "${UPDATE_BLUETOOTH}" \
    "Hyprland" "${MANAGE_HYPRLAND}" \
    "Fonts" "${MANAGE_FONTS}" \
    "File manager" "${UPDATE_FILE_MANAGER}" \
    "Browser" "${UPDATE_BROWSER}" \
    "Extra apps" "${UPDATE_EXTRA_APPS}" \
    "Ensure zsh" "${ENSURE_ZSH_PACKAGE}" \
    "Sync app cfgs" "${SYNC_APP_CONFIGS}" \
    "Sync shell rc" "${SYNC_SHELL_DOTFILES}"
}

print_summary() {
  print_standard_summary "Update completed successfully." "Update completed with errors." "$STATUS_USE_ASCII"
}

write_update_state() {
  local status="success"

  if [[ "${#FAILED_STEPS[@]}" -ne 0 ]]; then
    status="errors"
  fi

  mkdir -p "${DOTFILES_UPDATE_STATE_DIR}" || return 1

  cat > "${DOTFILES_UPDATE_STATE_FILE}" <<EOF
status=${status}
timestamp=$(date -Iseconds)
gpu=${GPU_CHOICE}
audio=${AUDIO_CHOICE}
network=${NETWORK_CHOICE}
laptop=${UPDATE_LAPTOP}
bluetooth=${UPDATE_BLUETOOTH}
hyprland=${MANAGE_HYPRLAND}
fonts=${MANAGE_FONTS}
file_manager=${UPDATE_FILE_MANAGER}
browser=${UPDATE_BROWSER}
extra_apps=${UPDATE_EXTRA_APPS}
ensure_zsh_package=${ENSURE_ZSH_PACKAGE}
sync_app_configs=${SYNC_APP_CONFIGS}
sync_shell_dotfiles=${SYNC_SHELL_DOTFILES}
failed_steps=${#FAILED_STEPS[@]}
EOF
}

# =========================
# main
# =========================

main() {
  parse_args "$@"

  print_header "DOTFILES UPDATE"
  print_info "Sync source: ${REPO_DIR}"

  preflight_checks

  if [[ "$UPDATE_MODE" == "interactive" ]]; then
    prompt_user_choices
  else
    prepare_live_selections
    print_info "Running live sync mode with saved selections and auto-detected fallbacks."
  fi

  print_selection_summary

  if [[ "$UPDATE_MODE" == "interactive" ]]; then
    confirm_update
  fi

  refresh_pacman || {
    print_error "Failed to refresh pacman databases."
    exit 1
  }

  install_package_group "CORE PACKAGES" "${CORE_PACKAGES[@]}"
  verify_packages_installed "CORE PACKAGES" "${CORE_PACKAGES[@]}" || record_fail "Verified CORE PACKAGES"

  ensure_yay_installed
  local yay_rc=$?
  report_step_result "Ensured yay is installed" "$yay_rc"
  if [[ "$yay_rc" -ne 0 ]]; then
    print_error "Cannot continue without yay for required AUR packages."
    exit 1
  fi

  update_installed_aur_packages

  update_network_selection
  update_audio_selection
  update_gpu_selection
  update_laptop_selection
  update_bluetooth_selection
  update_hyprland_selection
  update_font_selection
  update_file_manager_selection
  update_browser_selection
  update_extra_apps_selection
  update_zsh_selection

  enable_network_services
  verify_network_services || record_fail "Verified network services"

  enable_laptop_services
  verify_laptop_services || record_fail "Verified laptop services"

  enable_bluetooth_service
  verify_bluetooth_service || record_fail "Verified bluetooth service"

  create_user_directories
  deploy_wallpapers
  deploy_user_scripts
  deploy_configs

  write_update_state
  report_step_result "Wrote update state" "$?"

  print_summary
}

main "$@"
