#!/usr/bin/env bash

if [[ -n "${DOTFILES_HELPERS_SH_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_HELPERS_SH_LOADED=1

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

print_line() {
  printf '%b\n' "${1}"
}

print_header() {
  print_line ""
  print_line "${CYAN}${BOLD}========================================${RESET}"
  print_line "${CYAN}${BOLD}$1${RESET}"
  print_line "${CYAN}${BOLD}========================================${RESET}"
}

print_info() {
  print_line "${BLUE}[*]${RESET} $1"
}

print_warn() {
  print_line "${YELLOW}[!]${RESET} $1"
}

print_error() {
  print_line "${RED}[x]${RESET} $1"
}

print_success() {
  print_line "${GREEN}[+]${RESET} $1"
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local reply

  while true; do
    read -r -p "$prompt" reply
    reply="${reply:-$default}"

    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) print_warn "Please answer y or n." ;;
    esac
  done
}

check_root() {
  [[ "${EUID}" -eq 0 ]]
}

check_not_root() {
  [[ "${EUID}" -ne 0 ]]
}

check_arch() {
  [[ -f /etc/arch-release ]] && command -v pacman >/dev/null 2>&1
}

detect_chroot() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt --chroot >/dev/null 2>&1
    return $?
  fi

  [[ -f /etc/arch-release ]] &&
    [[ -d /proc/1/root ]] &&
    [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]]
}

check_chroot() {
  detect_chroot
}

check_not_chroot() {
  ! detect_chroot
}

check_archiso_live_environment() {
  [[ -d /run/archiso ]] || [[ -f /etc/archiso-release ]]
}

preflight_arch_root_chroot() {
  print_header "PRE-FLIGHT CHECKS"

  if ! check_root; then
    print_error "This script must be run as root."
    exit 1
  fi

  if ! check_arch; then
    print_error "This script is intended for Arch Linux only."
    exit 1
  fi

  if ! check_chroot; then
    print_error "This script must be run from inside arch-chroot after archinstall."
    exit 1
  fi

  print_success "Environment check passed: Arch + root + chroot detected."
}

preflight_arch_root_any() {
  print_header "PRE-FLIGHT CHECKS"

  if ! check_root; then
    print_error "This script must be run as root."
    exit 1
  fi

  if ! check_arch; then
    print_error "This script is intended for Arch Linux only."
    exit 1
  fi

  if check_chroot; then
    print_success "Environment check passed: Arch + root + chroot detected."
  elif check_archiso_live_environment; then
    print_error "Run this script inside arch-chroot or from the installed Arch system, not directly from the live ISO."
    exit 1
  else
    print_success "Environment check passed: Arch + root detected."
  fi
}

preflight_arch_user_postboot() {
  print_header "PRE-FLIGHT CHECKS"

  if ! check_not_root; then
    print_error "This script must be run as a normal user, not root."
    exit 1
  fi

  if ! check_arch; then
    print_error "This script is intended for Arch Linux only."
    exit 1
  fi

  if ! check_not_chroot; then
    print_error "This script must be run after reboot, not inside arch-chroot."
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    print_error "sudo is required but not installed."
    exit 1
  fi

  print_success "Environment check passed: user session + Arch detected."
}

package_is_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

any_packages_installed() {
  local pkg

  for pkg in "$@"; do
    if package_is_installed "$pkg"; then
      return 0
    fi
  done

  return 1
}

all_packages_installed() {
  local pkg

  for pkg in "$@"; do
    if ! package_is_installed "$pkg"; then
      return 1
    fi
  done

  return 0
}

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

load_list_file() {
  local array_name="$1"
  local file_path="$2"
  local label="${3:-$1}"
  local line
  local -n array_ref="$array_name"

  array_ref=()

  if [[ ! -f "$file_path" ]]; then
    print_error "Required list file not found for ${label}: ${file_path}"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim_whitespace "$line")"

    if [[ -n "$line" ]]; then
      array_ref+=("$line")
    fi
  done < "$file_path"

  if [[ "${#array_ref[@]}" -eq 0 ]]; then
    print_warn "List file is empty for ${label}: ${file_path}"
  fi
}

load_install_package_groups() {
  local package_dir="$1"

  load_list_file CORE_PACKAGES "${package_dir}/core.txt" "CORE PACKAGES" || return 1
  load_list_file PIPEWIRE_PACKAGES "${package_dir}/audio.txt" "AUDIO PACKAGES" || return 1
  load_list_file NETWORKMANAGER_PACKAGES "${package_dir}/network.txt" "NETWORK PACKAGES" || return 1
  load_list_file SYSTEMD_NETWORKD_PACKAGES "${package_dir}/network-systemd.txt" "SYSTEMD NETWORK PACKAGES" || return 1
  load_list_file NVIDIA_PROPRIETARY_PACKAGES "${package_dir}/nvidia.txt" "NVIDIA PROPRIETARY PACKAGES" || return 1
  load_list_file NVIDIA_OPEN_PACKAGES "${package_dir}/nvidia-open.txt" "NVIDIA OPEN PACKAGES" || return 1
  load_list_file AMD_PACKAGES "${package_dir}/amd.txt" "AMD GPU PACKAGES" || return 1
  load_list_file INTEL_PACKAGES "${package_dir}/intel.txt" "INTEL GPU PACKAGES" || return 1
  load_list_file LAPTOP_PACKAGES "${package_dir}/laptop.txt" "LAPTOP PACKAGES" || return 1
  load_list_file BLUETOOTH_PACKAGES "${package_dir}/bluetooth.txt" "BLUETOOTH PACKAGES" || return 1
}

load_setup_package_groups() {
  local package_dir="$1"

  load_list_file HYPRLAND_PACKAGES "${package_dir}/hyprland.txt" "HYPRLAND PACKAGES" || return 1
  load_list_file HYPRLAND_AUR_PACKAGES "${package_dir}/hyprland-aur.txt" "HYPRLAND AUR PACKAGES" || return 1
  load_list_file FONT_PACKAGES "${package_dir}/fonts.txt" "FONT PACKAGES" || return 1
  load_list_file FONT_AUR_PACKAGES "${package_dir}/fonts-aur.txt" "FONT AUR PACKAGES" || return 1
  load_list_file APP_PACKAGES "${package_dir}/apps.txt" "APP PACKAGES" || return 1
  load_list_file FILE_MANAGER_PACKAGES "${package_dir}/file-manager.txt" "FILE MANAGER PACKAGES" || return 1
  load_list_file SHELL_PACKAGES "${package_dir}/shell.txt" "SHELL PACKAGES" || return 1
  load_list_file BROWSER_PACKAGES "${package_dir}/browser.txt" "BROWSER PACKAGES" || return 1
}

load_update_package_groups() {
  local package_dir="$1"

  load_install_package_groups "$package_dir" || return 1
  load_setup_package_groups "$package_dir" || return 1
}

run_pacman() {
  if check_root; then
    pacman "$@"
  else
    sudo pacman "$@"
  fi
}

refresh_pacman_sync_only() {
  print_info "Refreshing package databases..."
  run_pacman -Sy --noconfirm
}

refresh_pacman_full_upgrade() {
  print_info "Refreshing package databases and upgrading installed packages..."
  run_pacman -Syu --noconfirm
}

install_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No packages defined for ${group_name}. Skipping."
    return 0
  fi

  print_header "INSTALLING ${group_name}"
  print_info "Packages: ${packages[*]}"

  run_pacman -S --needed --noconfirm "${packages[@]}"
  local rc=$?

  report_step_result "Installed ${group_name}" "$rc"
  return "$rc"
}

verify_packages_installed() {
  local group_name="$1"
  shift
  local packages=("$@")
  local missing=()
  local pkg

  for pkg in "${packages[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    print_success "Verified ${group_name}: all packages installed."
    return 0
  fi

  print_error "Verification failed for ${group_name}. Missing: ${missing[*]}"
  return 1
}

install_single_aur_package() {
  local package_name="$1"

  if pacman -Q "$package_name" >/dev/null 2>&1; then
    print_info "AUR package already installed: ${package_name}"
    return 0
  fi

  if ! command -v yay >/dev/null 2>&1; then
    print_error "yay is required to install AUR package ${package_name}."
    return 1
  fi

  yay -S --needed --noconfirm "$package_name"
}

ensure_yay_installed() {
  local build_root repo_dir rc=0

  if command -v yay >/dev/null 2>&1; then
    print_info "yay is already installed."
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    print_error "git is required to install yay."
    return 1
  fi

  if ! command -v makepkg >/dev/null 2>&1; then
    print_error "makepkg is required to install yay."
    return 1
  fi

  print_header "INSTALLING YAY"
  print_info "Bootstrapping yay from the AUR..."

  build_root="$(mktemp -d)" || return 1
  repo_dir="${build_root}/yay"

  if ! git clone --depth 1 "https://aur.archlinux.org/yay.git" "$repo_dir"; then
    rc=1
  elif ! (
    cd "$repo_dir" &&
    makepkg -si --needed --noconfirm
  ); then
    rc=1
  fi

  if [[ "$rc" -eq 0 ]] && ! command -v yay >/dev/null 2>&1; then
    rc=1
  fi

  rm -rf "$build_root"
  return "$rc"
}

install_aur_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")
  local pkg
  local rc=0

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No AUR packages defined for ${group_name}. Skipping."
    return 0
  fi

  print_header "INSTALLING ${group_name}"
  print_info "Packages: ${packages[*]}"

  for pkg in "${packages[@]}"; do
    print_info "Installing AUR package: ${pkg}"
    if ! install_single_aur_package "$pkg"; then
      rc=1
    fi
  done

  report_step_result "Installed ${group_name}" "$rc"
  return "$rc"
}
