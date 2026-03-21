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

PACKAGE_DIR="$SCRIPT_DIR/packages"
load_install_package_groups "$PACKAGE_DIR" || exit 1

# =========================
# state
# =========================

STATUS_USE_ASCII="true"
GPU_CHOICE=""
AUDIO_CHOICE=""
NETWORK_CHOICE=""
INSTALL_LAPTOP="false"
INSTALL_BLUETOOTH="false"

# =========================
# prompt helpers
# =========================

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

preflight_checks() {
  preflight_arch_root_chroot
}

# =========================
# package helpers
# =========================

refresh_pacman() {
  refresh_pacman_sync_only
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
  print_standard_summary "Bootstrap completed successfully." "Bootstrap completed with errors." "$STATUS_USE_ASCII"
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
