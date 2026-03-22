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
load_setup_package_groups "$PACKAGE_DIR" || exit 1

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
INSTALL_FILE_MANAGER="true"
INSTALL_BROWSER="false"
COPY_CONFIGS="true"
COPY_SHELL_DOTFILES="false"
INSTALL_EXTRA_APPS="true"
SET_ZSH_DEFAULT="true"

REPO_DIR="$SCRIPT_DIR"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

# =========================
# prompt helpers
# =========================

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

  if ask_yes_no "Install extra apps (mpv, feh, mousepad, code, fastfetch)? [Y/n]: " "y"; then
    INSTALL_EXTRA_APPS="true"
    print_success "Extra app install enabled."
  else
    INSTALL_EXTRA_APPS="false"
    print_info "Extra app install skipped."
  fi

  if ask_yes_no "Copy app configs into ~/.config and sync wallpapers/helper scripts? [Y/n]: " "y"; then
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

preflight_checks() {
  preflight_arch_user_postboot
}

print_selection_summary() {
  print_key_value_box \
    "SELECTED OPTIONS" \
    "File manager" "${INSTALL_FILE_MANAGER}" \
    "Browser" "${INSTALL_BROWSER}" \
    "Extra apps" "${INSTALL_EXTRA_APPS}" \
    "Copy configs" "${COPY_CONFIGS}" \
    "Copy shell rc" "${COPY_SHELL_DOTFILES}" \
    "Default zsh" "${SET_ZSH_DEFAULT}"
}

# =========================
# package helpers
# =========================

refresh_pacman() {
  refresh_pacman_full_upgrade
}

install_required_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")

  install_package_group "$group_name" "${packages[@]}" || return 1
  verify_packages_installed "$group_name" "${packages[@]}" || {
    record_fail "Verified ${group_name}"
    return 1
  }
}

install_required_aur_package_group() {
  local group_name="$1"
  shift
  local packages=("$@")

  install_aur_package_group "$group_name" "${packages[@]}" || return 1
  verify_packages_installed "$group_name" "${packages[@]}" || {
    record_fail "Verified ${group_name}"
    return 1
  }
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

    if package_is_installed "hyprland"; then
      if copy_config_dir "$REPO_DIR/configs/hypr" "$HOME/.config/hypr"; then
        copied_any=1
      else
        rc=1
      fi
    else
      print_info "Skipping Hypr config because hyprland is not installed."
    fi

    if package_is_installed "eww"; then
      if package_is_installed "networkmanager" && any_packages_installed "${PIPEWIRE_PACKAGES[@]}" && command -v nmcli >/dev/null 2>&1 && command -v pactl >/dev/null 2>&1; then
        if copy_config_dir "$REPO_DIR/configs/eww" "$HOME/.config/eww"; then
          copied_any=1
        else
          rc=1
        fi
      else
        print_warn "Skipping Eww config because it expects NetworkManager and PipeWire to be available."
      fi
    else
      print_info "Skipping Eww config because eww is not installed."
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
  print_standard_summary "Setup completed successfully." "Setup completed with errors." "$STATUS_USE_ASCII"
}

abort_setup() {
  print_error "$1"
  print_summary
  exit 1
}

# =========================
# main
# =========================

main() {
  print_script_banner "setup" "Post-boot Hyprland packages, configs, and shell setup"

  preflight_checks
  prompt_user_choices
  print_selection_summary

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

  install_required_package_group "HYPRLAND PACKAGES" "${HYPRLAND_PACKAGES[@]}" || abort_setup "Cannot continue without the Hyprland package group."
  install_required_aur_package_group "HYPRLAND AUR PACKAGES" "${HYPRLAND_AUR_PACKAGES[@]}" || abort_setup "Cannot continue without the Hyprland AUR package group."
  install_required_package_group "FONT PACKAGES" "${FONT_PACKAGES[@]}" || abort_setup "Cannot continue without the font package group."
  install_required_aur_package_group "FONT AUR PACKAGES" "${FONT_AUR_PACKAGES[@]}" || abort_setup "Cannot continue without the font AUR package group."

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

  if [[ "$COPY_CONFIGS" == "true" ]]; then
    deploy_wallpapers
    deploy_user_scripts
  else
    print_info "Wallpaper deployment skipped."
    print_info "User script deployment skipped."
  fi

  install_and_set_zsh
  deploy_configs

  print_summary
}

main "$@"
