#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$SCRIPT_DIR/scripts/helpers.sh"
# shellcheck source=scripts/print_status.sh
source "$SCRIPT_DIR/scripts/print_status.sh"

# =========================
# config
# =========================

CORE_PACKAGES=(
  git
  base-devel
  sudo
  curl
  wget
  nano
)

PIPEWIRE_PACKAGES=(
  pipewire
  wireplumber
  pipewire-alsa
  pipewire-pulse
  pipewire-jack
  pavucontrol
)

NETWORKMANAGER_PACKAGES=(
  networkmanager
)

SYSTEMD_NETWORKD_SERVICES=(
  systemd-networkd
  systemd-resolved
)

NVIDIA_PROPRIETARY_PACKAGES=(
  nvidia
  nvidia-utils
  nvidia-settings
  linux-headers
  libva
  libva-nvidia-driver
)

NVIDIA_OPEN_PACKAGES=(
  nvidia-open
  nvidia-utils
  nvidia-settings
  linux-headers
  libva
  libva-nvidia-driver
)

AMD_PACKAGES=(
  mesa
  libva-mesa-driver
  vulkan-radeon
  xf86-video-amdgpu
)

INTEL_PACKAGES=(
  mesa
  vulkan-intel
  intel-media-driver
  libva-intel-driver
)

LAPTOP_PACKAGES=(
  tlp
  brightnessctl
  acpi
)

BLUETOOTH_PACKAGES=(
  bluez
  bluez-utils
)

MANAGED_CONFIG_DIRS=(
  hypr
  eww
  rofi
  kitty
  mako
  fastfetch
  hyprpaper
  hyprlock
)

MANAGED_HOME_FILES=(
  .zshrc
  .bashrc
)

MANAGED_USER_SCRIPT_TARGETS=(
  Scripts/Lock/idle.sh
  Scripts/Lock/lock-now.sh
)

# =========================
# state
# =========================

STATUS_USE_ASCII="true"
UNINSTALL_MODE=""
REMOVE_CORE="false"
GPU_CHOICE=""
AUDIO_CHOICE=""
NETWORK_CHOICE=""
REMOVE_LAPTOP="false"
REMOVE_BLUETOOTH="false"
REMOVE_APP_CONFIGS="false"
REMOVE_SHELL_DOTFILES="false"
REMOVE_WALLPAPERS="false"
REMOVE_USER_SCRIPTS="false"
TARGET_USER=""
TARGET_HOME=""
HOME_UNINSTALL_BACKUP_DIR=""
UNINSTALL_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# =========================
# prompt helpers
# =========================

select_uninstall_mode() {
  print_header "UNINSTALL MODE"
  print_line "A) Uninstall everything the installer installed (auto detect)"
  print_line "B) Interactive uninstall flow"
  print_line "C) Return without doing anything"
  print_line ""

  while true; do
    read -r -p "Choose mode [A/B/C] (default: B): " choice
    choice="${choice:-B}"

    case "${choice^^}" in
      A|1)
        UNINSTALL_MODE="auto"
        print_success "Selected mode: auto-detect uninstall."
        break
        ;;
      B|2)
        UNINSTALL_MODE="interactive"
        print_success "Selected mode: interactive uninstall."
        break
        ;;
      C|3)
        print_info "Returning without making changes."
        exit 0
        ;;
      *)
        print_warn "Invalid choice. Enter A, B, or C."
        ;;
    esac
  done
}

auto_detect_selections() {
  print_header "AUTO-DETECTING INSTALLED COMPONENTS"

  if all_packages_installed "${CORE_PACKAGES[@]}"; then
    REMOVE_CORE="true"
  else
    REMOVE_CORE="false"
  fi
  print_info "Core package removal: ${REMOVE_CORE}"

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
  print_info "GPU removal: ${GPU_CHOICE}"

  if any_packages_installed "${PIPEWIRE_PACKAGES[@]}"; then
    AUDIO_CHOICE="pipewire"
  else
    AUDIO_CHOICE="skip"
  fi
  print_info "Audio removal: ${AUDIO_CHOICE}"

  if package_is_installed "networkmanager" || systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    NETWORK_CHOICE="networkmanager"
  elif systemctl is-enabled systemd-networkd >/dev/null 2>&1 || systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
    NETWORK_CHOICE="systemd-networkd"
  else
    NETWORK_CHOICE="skip"
  fi
  print_info "Network removal: ${NETWORK_CHOICE}"

  if any_packages_installed "${LAPTOP_PACKAGES[@]}" || systemctl is-enabled tlp >/dev/null 2>&1; then
    REMOVE_LAPTOP="true"
  else
    REMOVE_LAPTOP="false"
  fi
  print_info "Laptop removal: ${REMOVE_LAPTOP}"

  if any_packages_installed "${BLUETOOTH_PACKAGES[@]}" || systemctl is-enabled bluetooth >/dev/null 2>&1; then
    REMOVE_BLUETOOTH="true"
  else
    REMOVE_BLUETOOTH="false"
  fi
  print_info "Bluetooth removal: ${REMOVE_BLUETOOTH}"

  auto_detect_home_cleanup_selections
}

prompt_core_removal() {
  print_header "CORE PACKAGE REMOVAL"
  print_warn "Core packages include git, base-devel, sudo, curl, wget, and nano."

  if ask_yes_no "Remove core packages too? [y/N]: " "n"; then
    REMOVE_CORE="true"
    print_warn "Core package removal enabled."
  else
    REMOVE_CORE="false"
    print_info "Core package removal skipped."
  fi
}

select_gpu_choice() {
  print_header "GPU DRIVER REMOVAL"
  print_line "1) Skip GPU driver removal"
  print_line "2) NVIDIA proprietary"
  print_line "3) NVIDIA open kernel modules"
  print_line "4) AMD"
  print_line "5) Intel"
  print_line ""

  while true; do
    read -r -p "Choose GPU option [1-5] (default: 1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1) GPU_CHOICE="skip"; break ;;
      2) GPU_CHOICE="nvidia-proprietary"; break ;;
      3) GPU_CHOICE="nvidia-open"; break ;;
      4) GPU_CHOICE="amd"; break ;;
      5) GPU_CHOICE="intel"; break ;;
      *) print_warn "Invalid choice. Enter a number from 1 to 5." ;;
    esac
  done

  print_success "Selected GPU removal: ${GPU_CHOICE}"
}

select_audio_choice() {
  print_header "AUDIO STACK REMOVAL"
  print_line "1) Skip audio removal"
  print_line "2) PipeWire"
  print_line ""

  while true; do
    read -r -p "Choose audio option [1-2] (default: 1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1) AUDIO_CHOICE="skip"; break ;;
      2) AUDIO_CHOICE="pipewire"; break ;;
      *) print_warn "Invalid choice. Enter 1 or 2." ;;
    esac
  done

  print_success "Selected audio removal: ${AUDIO_CHOICE}"
}

select_network_choice() {
  print_header "NETWORK REMOVAL"
  print_line "1) Skip network removal"
  print_line "2) NetworkManager"
  print_line "3) systemd-networkd services only"
  print_line ""

  while true; do
    read -r -p "Choose network option [1-3] (default: 1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1) NETWORK_CHOICE="skip"; break ;;
      2) NETWORK_CHOICE="networkmanager"; break ;;
      3) NETWORK_CHOICE="systemd-networkd"; break ;;
      *) print_warn "Invalid choice. Enter a number from 1 to 3." ;;
    esac
  done

  print_success "Selected network removal: ${NETWORK_CHOICE}"
}

prompt_optional_components() {
  print_header "OPTIONAL COMPONENT REMOVAL"

  if ask_yes_no "Remove laptop support packages and TLP? [y/N]: " "n"; then
    REMOVE_LAPTOP="true"
    print_success "Laptop removal enabled."
  else
    REMOVE_LAPTOP="false"
    print_info "Laptop removal skipped."
  fi

  if ask_yes_no "Remove Bluetooth support packages and service? [y/N]: " "n"; then
    REMOVE_BLUETOOTH="true"
    print_success "Bluetooth removal enabled."
  else
    REMOVE_BLUETOOTH="false"
    print_info "Bluetooth removal skipped."
  fi
}

prompt_home_cleanup_options() {
  print_header "HOME FILE REMOVAL"

  if ! resolve_target_home_context; then
    print_warn "Could not auto-detect a single user home inside the installed system."
    print_warn "Set DOTFILES_TARGET_USER before running if you want to remove deployed dotfiles/assets too."
    REMOVE_APP_CONFIGS="false"
    REMOVE_SHELL_DOTFILES="false"
    REMOVE_WALLPAPERS="false"
    REMOVE_USER_SCRIPTS="false"
    return 0
  fi

  print_info "Targeting user ${TARGET_USER} at ${TARGET_HOME}"

  if ask_yes_no "Remove deployed app configs from ${TARGET_HOME}/.config? [y/N]: " "n"; then
    REMOVE_APP_CONFIGS="true"
    print_success "App config removal enabled."
  else
    REMOVE_APP_CONFIGS="false"
    print_info "App config removal skipped."
  fi

  if ask_yes_no "Remove deployed shell dotfiles (${TARGET_HOME}/.zshrc and ${TARGET_HOME}/.bashrc)? [y/N]: " "n"; then
    REMOVE_SHELL_DOTFILES="true"
    print_success "Shell dotfile removal enabled."
  else
    REMOVE_SHELL_DOTFILES="false"
    print_info "Shell dotfile removal skipped."
  fi

  if ask_yes_no "Remove repo wallpapers from ${TARGET_HOME}/Images/wallpapers? [y/N]: " "n"; then
    REMOVE_WALLPAPERS="true"
    print_success "Wallpaper removal enabled."
  else
    REMOVE_WALLPAPERS="false"
    print_info "Wallpaper removal skipped."
  fi

  if ask_yes_no "Remove deployed user scripts from ${TARGET_HOME}/Scripts/Lock? [y/N]: " "n"; then
    REMOVE_USER_SCRIPTS="true"
    print_success "User script removal enabled."
  else
    REMOVE_USER_SCRIPTS="false"
    print_info "User script removal skipped."
  fi
}

prompt_user_choices() {
  print_header "UNINSTALLER OPTIONS"
  prompt_core_removal
  select_gpu_choice
  select_audio_choice
  select_network_choice
  prompt_optional_components
  prompt_home_cleanup_options
}

confirm_uninstall() {
  print_line ""
  if ask_yes_no "Proceed with the selected uninstall actions? [y/N]: " "n"; then
    print_warn "Proceeding with uninstall."
    return 0
  fi

  print_info "Uninstall cancelled."
  exit 0
}

preflight_checks() {
  preflight_arch_root_any
}

# =========================
# package helpers
# =========================

resolve_target_home_context() {
  local user_entry
  local candidate_count

  if [[ -n "${TARGET_USER}" && -n "${TARGET_HOME}" ]]; then
    return 0
  fi

  if [[ -n "${DOTFILES_TARGET_USER:-}" ]]; then
    user_entry="$(getent passwd "${DOTFILES_TARGET_USER}")" || {
      print_warn "DOTFILES_TARGET_USER was set to '${DOTFILES_TARGET_USER}', but that user was not found."
      return 1
    }
  else
    candidate_count="$(awk -F: '$3 >= 1000 && $1 != "nobody" && $6 ~ /^\/home\// && $7 !~ /(nologin|false)$/ {count++} END {print count+0}' /etc/passwd)"

    if [[ "${candidate_count}" -ne 1 ]]; then
      if [[ "${candidate_count}" -eq 0 ]]; then
        print_warn "No eligible non-root user under /home was detected."
      else
        print_warn "Multiple eligible users were detected. Set DOTFILES_TARGET_USER to choose one."
      fi
      return 1
    fi

    user_entry="$(awk -F: '$3 >= 1000 && $1 != "nobody" && $6 ~ /^\/home\// && $7 !~ /(nologin|false)$/ {print; exit}' /etc/passwd)"
  fi

  TARGET_USER="$(printf '%s\n' "$user_entry" | cut -d: -f1)"
  TARGET_HOME="$(printf '%s\n' "$user_entry" | cut -d: -f6)"

  [[ -n "${TARGET_USER}" && -n "${TARGET_HOME}" ]]
}

target_home_path_exists() {
  [[ -n "${TARGET_HOME}" && -e "${TARGET_HOME}/$1" ]]
}

repo_wallpaper_file_exists_in_target_home() {
  local source_file
  local wallpaper_name

  [[ -d "${SCRIPT_DIR}/images" ]] || return 1

  for source_file in "${SCRIPT_DIR}"/images/*; do
    [[ -f "${source_file}" ]] || continue
    wallpaper_name="$(basename "${source_file}")"
    if [[ -e "${TARGET_HOME}/Images/wallpapers/${wallpaper_name}" ]]; then
      return 0
    fi
  done

  return 1
}

auto_detect_home_cleanup_selections() {
  if ! resolve_target_home_context; then
    REMOVE_APP_CONFIGS="false"
    REMOVE_SHELL_DOTFILES="false"
    REMOVE_WALLPAPERS="false"
    REMOVE_USER_SCRIPTS="false"
    return 0
  fi

  if target_home_path_exists ".config/hypr" ||
     target_home_path_exists ".config/eww" ||
     target_home_path_exists ".config/rofi" ||
     target_home_path_exists ".config/kitty" ||
     target_home_path_exists ".config/mako" ||
     target_home_path_exists ".config/fastfetch" ||
     target_home_path_exists ".config/hyprpaper" ||
     target_home_path_exists ".config/hyprlock"; then
    REMOVE_APP_CONFIGS="true"
  else
    REMOVE_APP_CONFIGS="false"
  fi

  if target_home_path_exists ".zshrc" || target_home_path_exists ".bashrc"; then
    REMOVE_SHELL_DOTFILES="true"
  else
    REMOVE_SHELL_DOTFILES="false"
  fi

  if repo_wallpaper_file_exists_in_target_home; then
    REMOVE_WALLPAPERS="true"
  else
    REMOVE_WALLPAPERS="false"
  fi

  if target_home_path_exists "Scripts/Lock/idle.sh" || target_home_path_exists "Scripts/Lock/lock-now.sh"; then
    REMOVE_USER_SCRIPTS="true"
  else
    REMOVE_USER_SCRIPTS="false"
  fi

  print_info "Target user home cleanup: ${TARGET_USER} (${TARGET_HOME})"
  print_info "App config removal: ${REMOVE_APP_CONFIGS}"
  print_info "Shell dotfile removal: ${REMOVE_SHELL_DOTFILES}"
  print_info "Wallpaper removal: ${REMOVE_WALLPAPERS}"
  print_info "User script removal: ${REMOVE_USER_SCRIPTS}"
}

remove_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")
  local installed=()
  local pkg

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No packages defined for ${group_name}. Skipping."
    return 0
  fi

  for pkg in "${packages[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      installed+=("$pkg")
    fi
  done

  if [[ "${#installed[@]}" -eq 0 ]]; then
    print_info "No installed packages found for ${group_name}. Skipping removal."
    return 0
  fi

  print_header "REMOVING ${group_name}"
  print_info "Packages: ${installed[*]}"

  pacman -Rns --noconfirm "${installed[@]}"
  local rc=$?

  report_step_result "Removed ${group_name}" "$rc"
  return "$rc"
}

verify_packages_removed() {
  local group_name="$1"
  shift
  local packages=("$@")
  local remaining=()
  local pkg

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No packages to verify for ${group_name}. Skipping."
    return 0
  fi

  for pkg in "${packages[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      remaining+=("$pkg")
    fi
  done

  if [[ "${#remaining[@]}" -eq 0 ]]; then
    print_success "Verified ${group_name}: packages removed."
    return 0
  fi

  print_error "Verification failed for ${group_name}. Still installed: ${remaining[*]}"
  return 1
}

# =========================
# home cleanup helpers
# =========================

ensure_home_uninstall_backup_dir() {
  local target_group

  if [[ -n "${HOME_UNINSTALL_BACKUP_DIR}" ]]; then
    return 0
  fi

  if ! resolve_target_home_context; then
    return 1
  fi

  HOME_UNINSTALL_BACKUP_DIR="${TARGET_HOME}/.dotfiles-uninstall-backup-${UNINSTALL_TIMESTAMP}"
  target_group="$(id -gn "${TARGET_USER}" 2>/dev/null || printf '%s' "${TARGET_USER}")"

  install -d -m 700 -o "${TARGET_USER}" -g "${target_group}" "${HOME_UNINSTALL_BACKUP_DIR}" 2>/dev/null ||
    mkdir -p "${HOME_UNINSTALL_BACKUP_DIR}" ||
    return 1
}

cleanup_empty_parent_dirs() {
  local removed_path="$1"
  local parent_dir

  parent_dir="$(dirname "${removed_path}")"

  while [[ "${parent_dir}" != "${TARGET_HOME}" && "${parent_dir}" != "/" ]]; do
    rmdir "${parent_dir}" 2>/dev/null || break
    parent_dir="$(dirname "${parent_dir}")"
  done
}

move_target_home_path_to_backup() {
  local target_path="$1"
  local relative_path
  local backup_path

  if [[ ! -e "${target_path}" ]]; then
    print_info "Path not found. Skipping: ${target_path}"
    return 0
  fi

  ensure_home_uninstall_backup_dir || return 1

  relative_path="${target_path#${TARGET_HOME}/}"
  backup_path="${HOME_UNINSTALL_BACKUP_DIR}/${relative_path}"

  mkdir -p "$(dirname "${backup_path}")" || return 1
  mv "${target_path}" "${backup_path}" || return 1
  print_warn "Moved ${target_path} to ${backup_path}"
  cleanup_empty_parent_dirs "${target_path}"
}

remove_app_configs() {
  local config_name
  local target_path
  local rc=0

  if [[ "${REMOVE_APP_CONFIGS}" != "true" ]]; then
    print_info "App config removal skipped."
    return 0
  fi

  if ! resolve_target_home_context; then
    print_error "Cannot remove app configs without a resolved target home."
    report_step_result "Removed deployed app configs" 1
    return 1
  fi

  print_header "REMOVING DEPLOYED APP CONFIGS"

  for config_name in "${MANAGED_CONFIG_DIRS[@]}"; do
    target_path="${TARGET_HOME}/.config/${config_name}"
    if ! move_target_home_path_to_backup "${target_path}"; then
      rc=1
    fi
  done

  report_step_result "Removed deployed app configs" "${rc}"
  return "${rc}"
}

remove_shell_dotfiles() {
  local target_file
  local rc=0

  if [[ "${REMOVE_SHELL_DOTFILES}" != "true" ]]; then
    print_info "Shell dotfile removal skipped."
    return 0
  fi

  if ! resolve_target_home_context; then
    print_error "Cannot remove shell dotfiles without a resolved target home."
    report_step_result "Removed deployed shell dotfiles" 1
    return 1
  fi

  print_header "REMOVING DEPLOYED SHELL DOTFILES"

  for target_file in "${MANAGED_HOME_FILES[@]}"; do
    if ! move_target_home_path_to_backup "${TARGET_HOME}/${target_file}"; then
      rc=1
    fi
  done

  report_step_result "Removed deployed shell dotfiles" "${rc}"
  return "${rc}"
}

remove_repo_wallpapers() {
  local source_file
  local wallpaper_name
  local target_path
  local rc=0

  if [[ "${REMOVE_WALLPAPERS}" != "true" ]]; then
    print_info "Wallpaper removal skipped."
    return 0
  fi

  if ! resolve_target_home_context; then
    print_error "Cannot remove wallpapers without a resolved target home."
    report_step_result "Removed deployed wallpapers" 1
    return 1
  fi

  print_header "REMOVING DEPLOYED WALLPAPERS"

  if [[ ! -d "${SCRIPT_DIR}/images" ]]; then
    print_info "No repo wallpaper directory found. Skipping wallpaper removal."
    report_step_result "Removed deployed wallpapers" 0
    return 0
  fi

  for source_file in "${SCRIPT_DIR}"/images/*; do
    [[ -f "${source_file}" ]] || continue
    wallpaper_name="$(basename "${source_file}")"
    target_path="${TARGET_HOME}/Images/wallpapers/${wallpaper_name}"
    if ! move_target_home_path_to_backup "${target_path}"; then
      rc=1
    fi
  done

  report_step_result "Removed deployed wallpapers" "${rc}"
  return "${rc}"
}

remove_user_scripts() {
  local script_target
  local rc=0

  if [[ "${REMOVE_USER_SCRIPTS}" != "true" ]]; then
    print_info "User script removal skipped."
    return 0
  fi

  if ! resolve_target_home_context; then
    print_error "Cannot remove user scripts without a resolved target home."
    report_step_result "Removed deployed user scripts" 1
    return 1
  fi

  print_header "REMOVING DEPLOYED USER SCRIPTS"

  for script_target in "${MANAGED_USER_SCRIPT_TARGETS[@]}"; do
    if ! move_target_home_path_to_backup "${TARGET_HOME}/${script_target}"; then
      rc=1
    fi
  done

  report_step_result "Removed deployed user scripts" "${rc}"
  return "${rc}"
}

# =========================
# service helpers
# =========================

service_unit_exists() {
  local service="$1"
  systemctl list-unit-files --type=service --all "${service}.service" 2>/dev/null | awk '{print $1}' | grep -Fxq "${service}.service"
}

disable_service_group() {
  local group_name="$1"
  shift
  local services=("$@")
  local service
  local rc=0

  if [[ "${#services[@]}" -eq 0 ]]; then
    print_warn "No services defined for ${group_name}. Skipping."
    return 0
  fi

  print_header "DISABLING ${group_name}"

  for service in "${services[@]}"; do
    if ! service_unit_exists "$service"; then
      print_info "Service ${service} not found. Skipping."
      continue
    fi

    print_info "Disabling ${service}..."
    if ! systemctl disable "$service"; then
      rc=1
    fi
  done

  report_step_result "Disabled ${group_name}" "$rc"
  return "$rc"
}

verify_services_disabled() {
  local group_name="$1"
  shift
  local services=("$@")
  local service
  local still_enabled=()

  if [[ "${#services[@]}" -eq 0 ]]; then
    print_warn "No services to verify for ${group_name}. Skipping."
    return 0
  fi

  for service in "${services[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
      still_enabled+=("$service")
    fi
  done

  if [[ "${#still_enabled[@]}" -eq 0 ]]; then
    print_success "Verified ${group_name}: services disabled or absent."
    return 0
  fi

  print_error "Verification failed for ${group_name}. Still enabled: ${still_enabled[*]}"
  return 1
}

disable_network_services() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      disable_service_group "NETWORK SERVICES" "NetworkManager"
      ;;
    systemd-networkd)
      disable_service_group "SYSTEMD NETWORK SERVICES" "${SYSTEMD_NETWORKD_SERVICES[@]}"
      ;;
    skip)
      print_info "Network service disable skipped."
      ;;
  esac
}

verify_network_services_disabled() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      verify_services_disabled "NETWORK SERVICES" "NetworkManager"
      ;;
    systemd-networkd)
      verify_services_disabled "SYSTEMD NETWORK SERVICES" "${SYSTEMD_NETWORKD_SERVICES[@]}"
      ;;
    skip)
      print_info "Network verification skipped."
      return 0
      ;;
  esac
}

disable_bluetooth_service() {
  if [[ "$REMOVE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth service disable skipped."
    return 0
  fi

  disable_service_group "BLUETOOTH SERVICE" "bluetooth"
}

verify_bluetooth_service_disabled() {
  if [[ "$REMOVE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth verification skipped."
    return 0
  fi

  verify_services_disabled "BLUETOOTH SERVICE" "bluetooth"
}

disable_laptop_services() {
  if [[ "$REMOVE_LAPTOP" != "true" ]]; then
    print_info "Laptop service disable skipped."
    return 0
  fi

  disable_service_group "LAPTOP SERVICES" "tlp"
}

verify_laptop_services_disabled() {
  if [[ "$REMOVE_LAPTOP" != "true" ]]; then
    print_info "Laptop verification skipped."
    return 0
  fi

  verify_services_disabled "LAPTOP SERVICES" "tlp"
}

# =========================
# uninstall selection wrappers
# =========================

remove_core_selection() {
  if [[ "$REMOVE_CORE" != "true" ]]; then
    print_info "Core package removal skipped."
    return 0
  fi

  remove_package_group "CORE PACKAGES" "${CORE_PACKAGES[@]}"
  verify_packages_removed "CORE PACKAGES" "${CORE_PACKAGES[@]}" || record_fail "Verified CORE PACKAGES"
}

remove_audio_selection() {
  case "$AUDIO_CHOICE" in
    pipewire)
      remove_package_group "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}"
      verify_packages_removed "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}" || record_fail "Verified AUDIO PACKAGES"
      ;;
    skip)
      print_info "Audio package removal skipped."
      ;;
  esac
}

remove_network_selection() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      remove_package_group "NETWORK PACKAGES" "${NETWORKMANAGER_PACKAGES[@]}"
      verify_packages_removed "NETWORK PACKAGES" "${NETWORKMANAGER_PACKAGES[@]}" || record_fail "Verified NETWORK PACKAGES"
      ;;
    systemd-networkd)
      print_warn "systemd-networkd removal only disables services. The systemd package will not be removed."
      record_pass "Skipped package removal for systemd-networkd"
      ;;
    skip)
      print_info "Network package removal skipped."
      ;;
  esac
}

remove_gpu_selection() {
  case "$GPU_CHOICE" in
    nvidia-proprietary)
      remove_package_group "NVIDIA PROPRIETARY PACKAGES" "${NVIDIA_PROPRIETARY_PACKAGES[@]}"
      verify_packages_removed "NVIDIA PROPRIETARY PACKAGES" "${NVIDIA_PROPRIETARY_PACKAGES[@]}" || record_fail "Verified NVIDIA PROPRIETARY PACKAGES"
      ;;
    nvidia-open)
      remove_package_group "NVIDIA OPEN PACKAGES" "${NVIDIA_OPEN_PACKAGES[@]}"
      verify_packages_removed "NVIDIA OPEN PACKAGES" "${NVIDIA_OPEN_PACKAGES[@]}" || record_fail "Verified NVIDIA OPEN PACKAGES"
      ;;
    amd)
      remove_package_group "AMD GPU PACKAGES" "${AMD_PACKAGES[@]}"
      verify_packages_removed "AMD GPU PACKAGES" "${AMD_PACKAGES[@]}" || record_fail "Verified AMD GPU PACKAGES"
      ;;
    intel)
      remove_package_group "INTEL GPU PACKAGES" "${INTEL_PACKAGES[@]}"
      verify_packages_removed "INTEL GPU PACKAGES" "${INTEL_PACKAGES[@]}" || record_fail "Verified INTEL GPU PACKAGES"
      ;;
    skip)
      print_info "GPU package removal skipped."
      ;;
  esac
}

remove_laptop_selection() {
  if [[ "$REMOVE_LAPTOP" != "true" ]]; then
    print_info "Laptop package removal skipped."
    return 0
  fi

  remove_package_group "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}"
  verify_packages_removed "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}" || record_fail "Verified LAPTOP PACKAGES"
}

remove_bluetooth_selection() {
  if [[ "$REMOVE_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth package removal skipped."
    return 0
  fi

  remove_package_group "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}"
  verify_packages_removed "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}" || record_fail "Verified BLUETOOTH PACKAGES"
}

# =========================
# summary
# =========================

print_selection_summary() {
  print_header "SELECTED OPTIONS"
  print_line "Mode:       ${UNINSTALL_MODE}"
  print_line "Core:       ${REMOVE_CORE}"
  print_line "GPU:        ${GPU_CHOICE}"
  print_line "Audio:      ${AUDIO_CHOICE}"
  print_line "Network:    ${NETWORK_CHOICE}"
  print_line "Laptop:     ${REMOVE_LAPTOP}"
  print_line "Bluetooth:  ${REMOVE_BLUETOOTH}"
  print_line "App Configs:  ${REMOVE_APP_CONFIGS}"
  print_line "Shell Files:  ${REMOVE_SHELL_DOTFILES}"
  print_line "Wallpapers:   ${REMOVE_WALLPAPERS}"
  print_line "User Scripts: ${REMOVE_USER_SCRIPTS}"

  if [[ -n "${TARGET_USER}" && -n "${TARGET_HOME}" ]]; then
    print_line "Target User: ${TARGET_USER}"
    print_line "Target Home: ${TARGET_HOME}"
  elif [[ "${REMOVE_APP_CONFIGS}" == "true" || "${REMOVE_SHELL_DOTFILES}" == "true" || "${REMOVE_WALLPAPERS}" == "true" || "${REMOVE_USER_SCRIPTS}" == "true" ]]; then
    print_line ""
    print_warn "Home-side cleanup was selected, but no target user home could be resolved."
  fi

  if [[ "$NETWORK_CHOICE" == "systemd-networkd" ]]; then
    print_line ""
    print_warn "systemd-networkd selection disables services only and keeps the systemd package installed."
  fi
}

print_summary() {
  print_standard_summary "Uninstall completed successfully." "Uninstall completed with errors." "$STATUS_USE_ASCII"

  if [[ -n "${HOME_UNINSTALL_BACKUP_DIR}" ]]; then
    print_line ""
    print_info "Removed home-side files were backed up to ${HOME_UNINSTALL_BACKUP_DIR}"
  fi
}

prompt_reboot() {
  print_line ""
  read -r -p "Press Y to reboot now, or any other key to stay in chroot: " reboot_choice

  if [[ "${reboot_choice}" =~ ^[Yy]$ ]]; then
    print_warn "Attempting reboot..."
    systemctl reboot || reboot || shutdown -r now
  else
    print_info "Reboot skipped."
  fi
}

# =========================
# main
# =========================

main() {
  print_header "DOTFILES UNINSTALL"

  preflight_checks
  select_uninstall_mode

  if [[ "$UNINSTALL_MODE" == "auto" ]]; then
    auto_detect_selections
  else
    prompt_user_choices
  fi

  print_selection_summary
  confirm_uninstall

  disable_network_services
  verify_network_services_disabled || record_fail "Verified network services disabled"

  disable_laptop_services
  verify_laptop_services_disabled || record_fail "Verified laptop services disabled"

  disable_bluetooth_service
  verify_bluetooth_service_disabled || record_fail "Verified bluetooth service disabled"

  remove_network_selection
  remove_audio_selection
  remove_gpu_selection
  remove_laptop_selection
  remove_bluetooth_selection
  remove_core_selection
  remove_app_configs
  remove_shell_dotfiles
  remove_repo_wallpapers
  remove_user_scripts

  print_summary
  prompt_reboot
}

main "$@"
