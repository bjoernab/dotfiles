#!/usr/bin/env bash

set -u

# =========================
# config
# =========================

HYPRLAND_PACKAGES=(
  hyprland
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
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  polkit-gnome
  hyprpaper
  hyprlock
  swayidle
)

HYPRLAND_AUR_PACKAGES=(
  eww
  wvkbd
)

FONT_PACKAGES=(
  ttf-firacode-nerd
  ttf-jetbrains-mono
  ttf-nerd-fonts-symbols
)

FONT_AUR_PACKAGES=(
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
COPY_SHELL_DOTFILES="false"
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

  if ask_yes_no "Copy app configs into ~/.config? [Y/n]: " "y"; then
    COPY_CONFIGS="true"
    print_success "~/.config copy enabled."
  else
    COPY_CONFIGS="false"
    print_info "~/.config copy skipped."
  fi

  if ask_yes_no "Copy shell dotfiles (~/.zshrc and ~/.bashrc)? [y/N]: " "n"; then
    COPY_SHELL_DOTFILES="true"
    print_success "Shell dotfile copy enabled."
  else
    COPY_SHELL_DOTFILES="false"
    print_info "Shell dotfile copy skipped."
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
  local source_file="$REPO_DIR/home/Scripts/Lock/idle.sh"
  local target_file="$HOME/Scripts/Lock/idle.sh"

  print_header "DEPLOYING USER SCRIPTS"

  if ! copy_home_file "$source_file" "$target_file"; then
    rc=1
  elif ! chmod +x "$target_file"; then
    print_error "Failed to make script executable: $target_file"
    rc=1
  fi

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
  backup_home_file "$target_file" || return 1
  cp -a "$source_file" "$target_file" || return 1
  render_placeholders_in_file "$target_file"
}

deploy_configs() {
  local rc=0
  local copied_any=0

  if [[ "$COPY_CONFIGS" != "true" && "$COPY_SHELL_DOTFILES" != "true" ]]; then
    print_info "Dotfile deployment skipped."
    return 0
  fi

  print_header "DEPLOYING DOTFILES"

  if [[ "$COPY_CONFIGS" == "true" ]]; then
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
  else
    print_info "~/.config deployment skipped."
  fi

  if [[ "$COPY_SHELL_DOTFILES" == "true" ]]; then
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

  ensure_yay_installed
  local yay_rc=$?
  report_step_result "Ensured yay is installed" "$yay_rc"
  if [[ "$yay_rc" -ne 0 ]]; then
    print_error "Cannot continue without yay for required AUR packages."
    exit 1
  fi

  install_package_group "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}"
  verify_packages_installed "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}" || record_fail "Verified HYPRLAND PACKAGES"

  install_aur_package_group "HYPRLAND AUR PACKAGES" "${HYPRLAND_AUR_PACKAGES[@]}"
  verify_packages_installed "HYPRLAND AUR PACKAGES" "${HYPRLAND_AUR_PACKAGES[@]}" || record_fail "Verified HYPRLAND AUR PACKAGES"

  install_package_group "FONT PACKAGES" "${FONT_PACKAGES[@]}"
  verify_packages_installed "FONT PACKAGES" "${FONT_PACKAGES[@]}" || record_fail "Verified FONT PACKAGES"

  install_aur_package_group "FONT AUR PACKAGES" "${FONT_AUR_PACKAGES[@]}"
  verify_packages_installed "FONT AUR PACKAGES" "${FONT_AUR_PACKAGES[@]}" || record_fail "Verified FONT AUR PACKAGES"

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

  create_user_directories
  deploy_wallpapers
  deploy_user_scripts

  install_and_set_zsh
  deploy_configs

  print_summary
}

main "$@"
