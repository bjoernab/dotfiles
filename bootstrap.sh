#!/usr/bin/env bash

set -u

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/bjoernab/dotfiles.git}"
DOTFILES_REPO_REF="${DOTFILES_REPO_REF:-main}"
DOTFILES_REPO_DIR="${DOTFILES_REPO_DIR:-}"
DOTFILES_INSTALL_STATE_FILE="${DOTFILES_INSTALL_STATE_FILE:-/var/lib/dotfiles/install-state}"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"
UI_WIDTH="${UI_WIDTH:-72}"

REPO_DIR=""

print_line() {
  printf '%b\n' "$1"
}

repeat_char() {
  local char="$1"
  local count="$2"
  local output=""

  while (( count > 0 )); do
    output+="$char"
    ((count--))
  done

  printf '%s' "${output}"
}

print_header() {
  local title="$1"
  local width="${2:-$UI_WIDTH}"
  local border content

  border="+$(repeat_char "=" "$((width - 2))")+"
  printf -v content "| %-*s |" "$((width - 4))" "${title}"

  print_line ""
  print_line "${CYAN}${BOLD}${border}${RESET}"
  print_line "${CYAN}${BOLD}${content}${RESET}"
  print_line "${CYAN}${BOLD}${border}${RESET}"
}

print_ascii_bootstrap() {
  cat <<'EOF'
 ____              _       _                 
| __ )  ___   ___ | |_ ___| |_ _ __ __ _ _ __
|  _ \ / _ \ / _ \| __/ __| __| '__/ _` | '_ \
| |_) | (_) | (_) | |_\__ \ |_| | | (_| | |_) |
|____/ \___/ \___/ \__|___/\__|_|  \__,_| .__/
                                        |_|   
EOF
}

print_banner() {
  local border subtitle

  border="+$(repeat_char "=" "$((UI_WIDTH - 2))")+"
  printf -v subtitle "| %-*s |" "$((UI_WIDTH - 4))" "bootstrap.sh decides whether to run install.sh or setup.sh"

  print_line ""
  print_line "${CYAN}${BOLD}${border}${RESET}"
  printf '%b' "${CYAN}${BOLD}"
  print_ascii_bootstrap
  printf '%b' "${RESET}"
  print_line "${BLUE}${subtitle}${RESET}"
  print_line "${CYAN}${BOLD}${border}${RESET}"
}

print_execution_map() {
  local border title_line row

  border="+$(repeat_char "-" "$((UI_WIDTH - 2))")+"
  printf -v title_line "| %-*s |" "$((UI_WIDTH - 4))" "BOOTSTRAP FLOW"

  print_line ""
  print_line "${CYAN}${BOLD}${border}${RESET}"
  print_line "${CYAN}${BOLD}${title_line}${RESET}"
  print_line "${CYAN}${BOLD}${border}${RESET}"

  printf -v row "| %-24s -> %-40s |" "arch-chroot + root" "install.sh"
  print_line "${BLUE}${row}${RESET}"

  printf -v row "| %-24s -> %-40s |" "post-boot + user" "setup.sh"
  print_line "${BLUE}${row}${RESET}"

  print_line "${CYAN}${BOLD}${border}${RESET}"
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

check_root() {
  [[ "${EUID}" -eq 0 ]]
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

check_archiso_live_environment() {
  [[ -d /run/archiso ]] || [[ -f /etc/archiso-release ]]
}

ensure_git_installed() {
  if command -v git >/dev/null 2>&1; then
    print_success "git is already installed."
    return 0
  fi

  print_warn "git is not installed. Installing it now..."

  if check_root; then
    pacman -S --needed --noconfirm git || return 1
  else
    if ! command -v sudo >/dev/null 2>&1; then
      print_error "sudo is required to install git."
      return 1
    fi
    sudo pacman -S --needed --noconfirm git || return 1
  fi

  command -v git >/dev/null 2>&1
}

detect_local_repo_dir() {
  local candidate=""

  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
  fi

  if [[ -n "${candidate}" && -f "${candidate}/install.sh" && -f "${candidate}/setup.sh" && -d "${candidate}/packages" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  return 1
}

default_repo_dir() {
  if check_root; then
    printf '/root/dotfiles\n'
  else
    printf '%s/dotfiles\n' "$HOME"
  fi
}

ensure_repo_checkout() {
  local candidate_dir=""
  local local_repo_dir=""

  if [[ -n "${DOTFILES_REPO_DIR}" ]]; then
    candidate_dir="${DOTFILES_REPO_DIR}"
  elif local_repo_dir="$(detect_local_repo_dir)"; then
    candidate_dir="${local_repo_dir}"
  else
    candidate_dir="$(default_repo_dir)"
  fi

  if [[ -f "${candidate_dir}/install.sh" && -f "${candidate_dir}/setup.sh" && -d "${candidate_dir}/packages" ]]; then
    REPO_DIR="${candidate_dir}"
    print_info "Using existing dotfiles checkout: ${REPO_DIR}"
    return 0
  fi

  if [[ -e "${candidate_dir}" && ! -d "${candidate_dir}" ]]; then
    print_error "Bootstrap target exists but is not a directory: ${candidate_dir}"
    return 1
  fi

  if [[ -d "${candidate_dir}" && ! -d "${candidate_dir}/.git" ]]; then
    if [[ -n "$(ls -A "${candidate_dir}" 2>/dev/null)" ]]; then
      print_error "Bootstrap target already exists but is not a usable dotfiles checkout: ${candidate_dir}"
      print_warn "Set DOTFILES_REPO_DIR to a different path or remove the existing directory."
      return 1
    fi
  fi

  if [[ -d "${candidate_dir}/.git" ]]; then
    REPO_DIR="${candidate_dir}"
    print_info "Using existing git checkout: ${REPO_DIR}"
    return 0
  fi

  print_info "Cloning dotfiles into ${candidate_dir}..."
  git clone --depth 1 --branch "${DOTFILES_REPO_REF}" "${DOTFILES_REPO_URL}" "${candidate_dir}" || return 1

  REPO_DIR="${candidate_dir}"
  print_success "Cloned dotfiles into ${REPO_DIR}"
}

read_install_state_value() {
  local key="$1"

  [[ -f "${DOTFILES_INSTALL_STATE_FILE}" ]] || return 1
  sed -n "s/^${key}=//p" "${DOTFILES_INSTALL_STATE_FILE}" | head -n 1
}

require_install_phase_complete() {
  local install_status=""

  if [[ ! -f "${DOTFILES_INSTALL_STATE_FILE}" ]]; then
    print_error "Install state was not found at ${DOTFILES_INSTALL_STATE_FILE}"
    print_warn "Run bootstrap.sh or install.sh as root inside arch-chroot first."
    return 1
  fi

  install_status="$(read_install_state_value "status" || true)"

  case "${install_status}" in
    success)
      print_success "Detected a successful install.sh run."
      return 0
      ;;
    errors)
      print_error "install.sh previously completed with errors."
      print_warn "Fix the issue and rerun bootstrap.sh or install.sh inside arch-chroot before running setup."
      return 1
      ;;
    *)
      print_warn "Install state exists but does not include a recognized status. Proceeding anyway."
      return 0
      ;;
  esac
}

run_install_phase() {
  if ! check_root; then
    print_error "Inside arch-chroot, bootstrap.sh must be run as root."
    exit 1
  fi

  ensure_git_installed || {
    print_error "Unable to install git."
    exit 1
  }

  ensure_repo_checkout || {
    print_error "Unable to prepare the dotfiles checkout."
    exit 1
  }

  print_info "Running install.sh from ${REPO_DIR}"
  exec bash "${REPO_DIR}/install.sh"
}

run_setup_phase() {
  if check_root; then
    print_error "Outside arch-chroot, bootstrap.sh must be run as your normal user."
    print_warn "install.sh is the root phase; setup.sh is the user phase."
    exit 1
  fi

  if check_archiso_live_environment; then
    print_error "You are on the Arch live ISO outside arch-chroot."
    print_warn "Enter arch-chroot to run install.sh, or boot the installed system to run setup.sh."
    exit 1
  fi

  require_install_phase_complete || exit 1

  ensure_git_installed || {
    print_error "Unable to install git."
    exit 1
  }

  ensure_repo_checkout || {
    print_error "Unable to prepare the dotfiles checkout."
    exit 1
  }

  print_info "Running setup.sh from ${REPO_DIR}"
  exec bash "${REPO_DIR}/setup.sh"
}

main() {
  print_banner
  print_execution_map

  if ! check_arch; then
    print_error "This bootstrap script is intended for Arch Linux only."
    exit 1
  fi

  if detect_chroot; then
    print_info "Detected arch-chroot environment."
    run_install_phase
  else
    print_info "Detected post-boot environment."
    run_setup_phase
  fi
}

main "$@"
