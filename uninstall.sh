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

REMOVE_CORE="false"
GPU_CHOICE=""
AUDIO_CHOICE=""
NETWORK_CHOICE=""
REMOVE_LAPTOP="false"
REMOVE_BLUETOOTH="false"

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

prompt_user_choices() {
  print_header "UNINSTALLER OPTIONS"
  prompt_core_removal
  select_gpu_choice
  select_audio_choice
  select_network_choice
  prompt_optional_components
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
  print_line "Core:       ${REMOVE_CORE}"
  print_line "GPU:        ${GPU_CHOICE}"
  print_line "Audio:      ${AUDIO_CHOICE}"
  print_line "Network:    ${NETWORK_CHOICE}"
  print_line "Laptop:     ${REMOVE_LAPTOP}"
  print_line "Bluetooth:  ${REMOVE_BLUETOOTH}"

  if [[ "$NETWORK_CHOICE" == "systemd-networkd" ]]; then
    print_line ""
    print_warn "systemd-networkd selection disables services only and keeps the systemd package installed."
  fi
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
    print_success "Uninstall completed successfully."
  else
    print_ascii_error
    print_error "Uninstall completed with errors."
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
  print_header "ARCH CHROOT UNINSTALL"

  preflight_checks
  prompt_user_choices
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

  print_summary
  prompt_reboot
}

main "$@"
