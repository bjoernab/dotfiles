#!/usr/bin/env bash

set -u

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

NETWORK_PACKAGES=(
  networkmanager
)

AUDIO_PACKAGES=(
  pipewire
  wireplumber
  pipewire-alsa
  pipewire-pulse
  pipewire-jack
  pavucontrol
)

NVIDIA_PACKAGES=(
  nvidia
  nvidia-utils
  nvidia-settings
  linux-headers
  libva
  libva-nvidia-driver
)

# =========================
# colors
# =========================

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

# =========================
# state
# =========================

FAILED_STEPS=()
PASSED_STEPS=()

# =========================
# ui helpers
# =========================

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

print_ascii_success() {
  print_line "${GREEN}${BOLD}"
  cat <<'EOF'
  _____ _    _  _____  _____ ______  _____ _____
 / ____| |  | |/ ____|/ ____|  ____|/ ____/ ____|
| (___ | |  | | |    | |    | |__  | (___| (___
 \___ \| |  | | |    | |    |  __|  \___ \\___ \
 ____) | |__| | |____| |____| |____ ____) |___) |
|_____/ \____/ \_____|\_____|______|_____/_____/
EOF
  print_line "${RESET}"
}

print_ascii_error() {
  print_line "${RED}${BOLD}"
  cat <<'EOF'
 ______ _____  _____   ____  _____
|  ____|  __ \|  __ \ / __ \|  __ \
| |__  | |__) | |__) | |  | | |__) |
|  __| |  _  /|  _  /| |  | |  _  /
| |____| | \ \| | \ \| |__| | | \ \
|______|_|  \_\_|  \_\\____/|_|  \_\
EOF
  print_line "${RESET}"
}

record_pass() {
  PASSED_STEPS+=("$1")
}

record_fail() {
  FAILED_STEPS+=("$1")
}

report_step_result() {
  local step_name="$1"
  local exit_code="$2"

  if [[ "$exit_code" -eq 0 ]]; then
    print_ascii_success
    print_success "${step_name}"
    record_pass "${step_name}"
  else
    print_ascii_error
    print_error "${step_name}"
    record_fail "${step_name}"
  fi
}

# =========================
# checks
# =========================

check_root() {
  [[ "${EUID}" -eq 0 ]]
}

check_arch() {
  [[ -f /etc/arch-release ]] && command -v pacman >/dev/null 2>&1
}

check_chroot() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt --chroot >/dev/null 2>&1
    return $?
  fi

  # fallback if systemd-detect-virt is unavailable
  [[ -f /etc/arch-release ]] && [[ -d /proc/1/root ]] && [[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]]
}

preflight_checks() {
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

# =========================
# package helpers
# =========================

refresh_pacman() {
  print_info "Refreshing package databases..."
  pacman -Sy --noconfirm
}

install_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")

  print_header "INSTALLING ${group_name}"
  print_info "Packages: ${packages[*]}"

  pacman -S --needed --noconfirm "${packages[@]}"
  local rc=$?

  report_step_result "Installed ${group_name}" "$rc"
  return "$rc"
}

verify_packages_installed() {
  local group_name="$1"
  shift
  local packages=("$@")
  local missing=()

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

# =========================
# services
# =========================

enable_networkmanager() {
  print_header "ENABLING SERVICES"

  print_info "Enabling NetworkManager..."
  systemctl enable NetworkManager
  local rc=$?

  report_step_result "Enabled NetworkManager" "$rc"
  return "$rc"
}

verify_networkmanager() {
  if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    print_success "Verified NetworkManager is enabled."
    return 0
  fi

  print_error "NetworkManager is not enabled."
  return 1
}

# =========================
# summary
# =========================

print_summary() {
  print_header "FINAL SUMMARY"

  if [[ "${#PASSED_STEPS[@]}" -gt 0 ]]; then
    print_line "${GREEN}${BOLD}Passed:${RESET}"
    for step in "${PASSED_STEPS[@]}"; do
      print_line "  ${GREEN}-${RESET} $step"
    done
  fi

  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    print_line ""
    print_line "${RED}${BOLD}Failed:${RESET}"
    for step in "${FAILED_STEPS[@]}"; do
      print_line "  ${RED}-${RESET} $step"
    done
  fi

  print_line ""

  if [[ "${#FAILED_STEPS[@]}" -eq 0 ]]; then
    print_ascii_success
    print_success "Bootstrap completed successfully."
  else
    print_ascii_error
    print_error "Bootstrap completed with errors."
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
  print_header "ARCH CHROOT BOOTSTRAP"

  preflight_checks

  refresh_pacman || {
    print_error "Failed to refresh pacman databases."
    exit 1
  }

  install_package_group "CORE PACKAGES" "${CORE_PACKAGES[@]}"
  verify_packages_installed "CORE PACKAGES" "${CORE_PACKAGES[@]}" || record_fail "Verified CORE PACKAGES"

  install_package_group "NETWORK PACKAGES" "${NETWORK_PACKAGES[@]}"
  verify_packages_installed "NETWORK PACKAGES" "${NETWORK_PACKAGES[@]}" || record_fail "Verified NETWORK PACKAGES"

  install_package_group "AUDIO PACKAGES" "${AUDIO_PACKAGES[@]}"
  verify_packages_installed "AUDIO PACKAGES" "${AUDIO_PACKAGES[@]}" || record_fail "Verified AUDIO PACKAGES"

  install_package_group "NVIDIA PACKAGES" "${NVIDIA_PACKAGES[@]}"
  verify_packages_installed "NVIDIA PACKAGES" "${NVIDIA_PACKAGES[@]}" || record_fail "Verified NVIDIA PACKAGES"

  enable_networkmanager
  verify_networkmanager || record_fail "Verified NetworkManager enabled"

  print_summary
  prompt_reboot
}

main "$@"