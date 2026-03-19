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

SYSTEMD_NETWORKD_PACKAGES=(
  systemd
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

GPU_CHOICE=""
AUDIO_CHOICE=""
NETWORK_CHOICE=""
INSTALL_LAPTOP="false"
INSTALL_BLUETOOTH="false"

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
# prompt helpers
# =========================

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

select_gpu_choice() {
  print_header "GPU DRIVER SELECTION"
  print_line "1) Skip GPU drivers"
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

  print_success "Selected GPU option: ${GPU_CHOICE}"
}

select_audio_choice() {
  print_header "AUDIO STACK SELECTION"
  print_line "1) Skip audio setup"
  print_line "2) PipeWire (recommended)"
  print_line ""

  while true; do
    read -r -p "Choose audio option [1-2] (default: 2): " choice
    choice="${choice:-2}"

    case "$choice" in
      1) AUDIO_CHOICE="skip"; break ;;
      2) AUDIO_CHOICE="pipewire"; break ;;
      *) print_warn "Invalid choice. Enter 1 or 2." ;;
    esac
  done

  print_success "Selected audio option: ${AUDIO_CHOICE}"
}

select_network_choice() {
  print_header "NETWORK SELECTION"
  print_line "1) Skip network setup"
  print_line "2) NetworkManager (recommended)"
  print_line "3) systemd-networkd"
  print_line ""

  while true; do
    read -r -p "Choose network option [1-3] (default: 2): " choice
    choice="${choice:-2}"

    case "$choice" in
      1) NETWORK_CHOICE="skip"; break ;;
      2) NETWORK_CHOICE="networkmanager"; break ;;
      3) NETWORK_CHOICE="systemd-networkd"; break ;;
      *) print_warn "Invalid choice. Enter a number from 1 to 3." ;;
    esac
  done

  print_success "Selected network option: ${NETWORK_CHOICE}"
}

prompt_optional_components() {
  print_header "OPTIONAL COMPONENTS"

  if ask_yes_no "Is this a laptop? [y/N]: " "n"; then
    INSTALL_LAPTOP="true"
    print_success "Laptop support enabled."
  else
    INSTALL_LAPTOP="false"
    print_info "Laptop support skipped."
  fi

  if ask_yes_no "Install Bluetooth support? [y/N]: " "n"; then
    INSTALL_BLUETOOTH="true"
    print_success "Bluetooth support enabled."
  else
    INSTALL_BLUETOOTH="false"
    print_info "Bluetooth support skipped."
  fi
}

prompt_user_choices() {
  print_header "INSTALLER OPTIONS"
  select_gpu_choice
  select_audio_choice
  select_network_choice
  prompt_optional_components
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

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No packages defined for ${group_name}. Skipping."
    return 0
  fi

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

  if [[ "${#packages[@]}" -eq 0 ]]; then
    print_warn "No packages to verify for ${group_name}. Skipping."
    return 0
  fi

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

enable_network_services() {
  print_header "ENABLING NETWORK SERVICES"

  case "$NETWORK_CHOICE" in
    networkmanager)
      print_info "Enabling NetworkManager..."
      systemctl enable NetworkManager
      report_step_result "Enabled NetworkManager" "$?"
      ;;
    systemd-networkd)
      print_info "Enabling systemd-networkd..."
      systemctl enable systemd-networkd
      local rc1=$?

      print_info "Enabling systemd-resolved..."
      systemctl enable systemd-resolved
      local rc2=$?

      if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
        report_step_result "Enabled systemd-networkd and systemd-resolved" 0
      else
        report_step_result "Enabled systemd-networkd and systemd-resolved" 1
      fi
      ;;
    skip)
      print_info "Network service enable skipped."
      ;;
  esac
}

verify_network_services() {
  case "$NETWORK_CHOICE" in
    networkmanager)
      if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
        print_success "Verified NetworkManager is enabled."
        return 0
      fi
      print_error "NetworkManager is not enabled."
      return 1
      ;;
    systemd-networkd)
      local failed=0

      if systemctl is-enabled systemd-networkd >/dev/null 2>&1; then
        print_success "Verified systemd-networkd is enabled."
      else
        print_error "systemd-networkd is not enabled."
        failed=1
      fi

      if systemctl is-enabled systemd-resolved >/dev/null 2>&1; then
        print_success "Verified systemd-resolved is enabled."
      else
        print_error "systemd-resolved is not enabled."
        failed=1
      fi

      return "$failed"
      ;;
    skip)
      print_info "Network verification skipped."
      return 0
      ;;
  esac
}

enable_bluetooth_service() {
  if [[ "$INSTALL_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth service enable skipped."
    return 0
  fi

  print_header "ENABLING BLUETOOTH SERVICE"
  print_info "Enabling bluetooth..."
  systemctl enable bluetooth
  report_step_result "Enabled bluetooth service" "$?"
}

verify_bluetooth_service() {
  if [[ "$INSTALL_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth verification skipped."
    return 0
  fi

  if systemctl is-enabled bluetooth >/dev/null 2>&1; then
    print_success "Verified bluetooth service is enabled."
    return 0
  fi

  print_error "Bluetooth service is not enabled."
  return 1
}

enable_laptop_services() {
  if [[ "$INSTALL_LAPTOP" != "true" ]]; then
    print_info "Laptop service enable skipped."
    return 0
  fi

  print_header "ENABLING LAPTOP SERVICES"
  print_info "Enabling TLP..."
  systemctl enable tlp
  report_step_result "Enabled TLP" "$?"
}

verify_laptop_services() {
  if [[ "$INSTALL_LAPTOP" != "true" ]]; then
    print_info "Laptop verification skipped."
    return 0
  fi

  if systemctl is-enabled tlp >/dev/null 2>&1; then
    print_success "Verified TLP is enabled."
    return 0
  fi

  print_error "TLP is not enabled."
  return 1
}

# =========================
# install selection wrappers
# =========================

install_audio_selection() {
  case "$AUDIO_CHOICE" in
    pipewire)
      install_package_group "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}"
      verify_packages_installed "AUDIO PACKAGES" "${PIPEWIRE_PACKAGES[@]}" || record_fail "Verified AUDIO PACKAGES"
      ;;
    skip)
      print_info "Audio package installation skipped."
      ;;
  esac
}

install_network_selection() {
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
      print_info "Network package installation skipped."
      ;;
  esac
}

install_gpu_selection() {
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
      print_info "GPU package installation skipped."
      ;;
  esac
}

install_laptop_selection() {
  if [[ "$INSTALL_LAPTOP" != "true" ]]; then
    print_info "Laptop package installation skipped."
    return 0
  fi

  install_package_group "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}"
  verify_packages_installed "LAPTOP PACKAGES" "${LAPTOP_PACKAGES[@]}" || record_fail "Verified LAPTOP PACKAGES"
}

install_bluetooth_selection() {
  if [[ "$INSTALL_BLUETOOTH" != "true" ]]; then
    print_info "Bluetooth package installation skipped."
    return 0
  fi

  install_package_group "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}"
  verify_packages_installed "BLUETOOTH PACKAGES" "${BLUETOOTH_PACKAGES[@]}" || record_fail "Verified BLUETOOTH PACKAGES"
}

# =========================
# summary
# =========================

print_selection_summary() {
  print_header "SELECTED OPTIONS"
  print_line "GPU:        ${GPU_CHOICE}"
  print_line "Audio:      ${AUDIO_CHOICE}"
  print_line "Network:    ${NETWORK_CHOICE}"
  print_line "Laptop:     ${INSTALL_LAPTOP}"
  print_line "Bluetooth:  ${INSTALL_BLUETOOTH}"
}

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
  prompt_user_choices
  print_selection_summary

  refresh_pacman || {
    print_error "Failed to refresh pacman databases."
    exit 1
  }

  install_package_group "CORE PACKAGES" "${CORE_PACKAGES[@]}"
  verify_packages_installed "CORE PACKAGES" "${CORE_PACKAGES[@]}" || record_fail "Verified CORE PACKAGES"

  install_network_selection
  install_audio_selection
  install_gpu_selection
  install_laptop_selection
  install_bluetooth_selection

  enable_network_services
  verify_network_services || record_fail "Verified network services"

  enable_laptop_services
  verify_laptop_services || record_fail "Verified laptop services"

  enable_bluetooth_service
  verify_bluetooth_service || record_fail "Verified bluetooth service"

  print_summary
  prompt_reboot
}

main "$@"