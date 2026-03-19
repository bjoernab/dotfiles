#!/usr/bin/env bash

set -u

# =========================
# config
# =========================

HYPRLAND_PACKAGES=(
  hyprland
  eww
  rofi
  kitty
  mako
  wl-clipboard
  grim
  slurp
  flameshot
  libnotify
  pavucontrol
  python
  perl
  wvkbd
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  polkit-gnome
  hyprpaper
  hyprlock
)

FONT_PACKAGES=(
  ttf-firacode-nerd
  ttf-jetbrains-mono
  ttf-nerd-fonts-symbols
  ttf-twemoji
)

APP_PACKAGES=(
  mpv
  feh
  mousepad
  code
)

FILE_MANAGER_PACKAGES=(
  dolphin
)

SHELL_PACKAGES=(
  zsh
)

BROWSER_PACKAGES=(
  firefox
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

INSTALL_FILE_MANAGER="true"
INSTALL_BROWSER="false"
COPY_CONFIGS="true"
INSTALL_EXTRA_APPS="true"
SET_ZSH_DEFAULT="true"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

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
    print_success "${step_name}"
    record_pass "${step_name}"
  else
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

prompt_user_choices() {
  print_header "SETUP OPTIONS"

  if ask_yes_no "Install Dolphin file manager? [Y/n]: " "y"; then
    INSTALL_FILE_MANAGER="true"
    print_success "Dolphin install enabled."
  else
    INSTALL_FILE_MANAGER="false"
    print_info "Dolphin install skipped."
  fi

  if ask_yes_no "Install Firefox browser? [y/N]: " "n"; then
    INSTALL_BROWSER="true"
    print_success "Browser install enabled."
  else
    INSTALL_BROWSER="false"
    print_info "Browser install skipped."
  fi

  if ask_yes_no "Install extra apps (mpv, feh, mousepad, code)? [Y/n]: " "y"; then
    INSTALL_EXTRA_APPS="true"
    print_success "Extra app install enabled."
  else
    INSTALL_EXTRA_APPS="false"
    print_info "Extra app install skipped."
  fi

  if ask_yes_no "Copy dotfiles into ~/.config? [Y/n]: " "y"; then
    COPY_CONFIGS="true"
    print_success "Config copy enabled."
  else
    COPY_CONFIGS="false"
    print_info "Config copy skipped."
  fi

  if ask_yes_no "Install zsh and make it your default shell? [Y/n]: " "y"; then
    SET_ZSH_DEFAULT="true"
    print_success "zsh default shell setup enabled."
  else
    SET_ZSH_DEFAULT="false"
    print_info "zsh default shell setup skipped."
  fi
}

# =========================
# checks
# =========================

check_not_root() {
  [[ "${EUID}" -ne 0 ]]
}

check_arch() {
  [[ -f /etc/arch-release ]] && command -v pacman >/dev/null 2>&1
}

check_not_chroot() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    ! systemd-detect-virt --chroot >/dev/null 2>&1
    return $?
  fi

  return 0
}

preflight_checks() {
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

# =========================
# package helpers
# =========================

refresh_pacman() {
  print_info "Refreshing package databases and upgrading installed packages..."
  sudo pacman -Syu --noconfirm
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

  sudo pacman -S --needed --noconfirm "${packages[@]}"
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
# config deployment
# =========================

backup_config_dir() {
  local target="$1"

  if [[ -e "$target" ]]; then
    mkdir -p "$BACKUP_DIR" || return 1
    mv "$target" "$BACKUP_DIR/" || return 1
    print_warn "Backed up $target to $BACKUP_DIR"
  fi

  return 0
}

backup_home_file() {
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

  backup_config_dir "$target_dir" || return 1
  mkdir -p "$(dirname "$target_dir")" || return 1
  cp -a "$source_dir" "$target_dir"
}

copy_home_file() {
  local source_file="$1"
  local target_file="$2"

  if [[ ! -f "$source_file" ]]; then
    print_error "Source file not found: $source_file"
    return 1
  fi

  backup_home_file "$target_file" || return 1
  cp -a "$source_file" "$target_file"
}

deploy_configs() {
  local rc=0
  local copied_any=0

  if [[ "$COPY_CONFIGS" != "true" ]]; then
    print_info "Config deployment skipped."
    return 0
  fi

  print_header "DEPLOYING CONFIGS"

  mkdir -p "$HOME/.config" || rc=1

  if copy_config_dir "$REPO_DIR/configs/hypr" "$HOME/.config/hypr"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/eww" "$HOME/.config/eww"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/rofi" "$HOME/.config/rofi"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/kitty" "$HOME/.config/kitty"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/mako" "$HOME/.config/mako"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/hyprpaper" "$HOME/.config/hyprpaper"; then
    copied_any=1
  else
    rc=1
  fi

  if copy_config_dir "$REPO_DIR/configs/hyprlock" "$HOME/.config/hyprlock"; then
    copied_any=1
  else
    rc=1
  fi

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

  if [[ "$copied_any" -eq 0 ]]; then
    print_error "No configuration sources were copied."
    rc=1
  fi

  report_step_result "Deployed configuration files" "$rc"
  return "$rc"
}

# =========================
# shell setup
# =========================

install_and_set_zsh() {
  if [[ "$SET_ZSH_DEFAULT" != "true" ]]; then
    print_info "zsh default shell setup skipped."
    return 0
  fi

  install_package_group "SHELL PACKAGES" "${SHELL_PACKAGES[@]}"
  verify_packages_installed "SHELL PACKAGES" "${SHELL_PACKAGES[@]}" || record_fail "Verified SHELL PACKAGES"

  print_header "SETTING DEFAULT SHELL"

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ -z "$zsh_path" ]]; then
    report_step_result "Resolved zsh binary" 1
    return 1
  fi

  if chsh -s "$zsh_path"; then
    report_step_result "Changed default shell to zsh" 0
    print_warn "Log out and back in for the shell change to fully apply."
    return 0
  else
    report_step_result "Changed default shell to zsh" 1
    return 1
  fi
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
    print_success "Setup completed successfully."
  else
    print_error "Setup completed with errors."
  fi
}

# =========================
# main
# =========================

main() {
  print_header "POST-BOOT HYPRLAND SETUP"

  preflight_checks
  prompt_user_choices

  refresh_pacman || {
    print_error "Failed to refresh pacman databases."
    exit 1
  }

  install_package_group "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}"
  verify_packages_installed "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}" || record_fail "Verified HYPRLAND PACKAGES"

  install_package_group "FONT PACKAGES" "${FONT_PACKAGES[@]}"
  verify_packages_installed "FONT PACKAGES" "${FONT_PACKAGES[@]}" || record_fail "Verified FONT PACKAGES"

  if [[ "$INSTALL_FILE_MANAGER" == "true" ]]; then
    install_package_group "FILE MANAGER PACKAGES" "${FILE_MANAGER_PACKAGES[@]}"
    verify_packages_installed "FILE MANAGER PACKAGES" "${FILE_MANAGER_PACKAGES[@]}" || record_fail "Verified FILE MANAGER PACKAGES"
  fi

  if [[ "$INSTALL_BROWSER" == "true" ]]; then
    install_package_group "BROWSER PACKAGES" "${BROWSER_PACKAGES[@]}"
    verify_packages_installed "BROWSER PACKAGES" "${BROWSER_PACKAGES[@]}" || record_fail "Verified BROWSER PACKAGES"
  fi

  if [[ "$INSTALL_EXTRA_APPS" == "true" ]]; then
    install_package_group "APP PACKAGES" "${APP_PACKAGES[@]}"
    verify_packages_installed "APP PACKAGES" "${APP_PACKAGES[@]}" || record_fail "Verified APP PACKAGES"
  fi

  install_and_set_zsh
  deploy_configs

  print_summary
}

main "$@"
