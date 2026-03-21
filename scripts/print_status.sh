#!/usr/bin/env bash

if [[ -n "${DOTFILES_PRINT_STATUS_SH_LOADED:-}" ]]; then
  return 0
fi
DOTFILES_PRINT_STATUS_SH_LOADED=1

: "${STATUS_USE_ASCII:=false}"

if ! declare -p FAILED_STEPS >/dev/null 2>&1; then
  FAILED_STEPS=()
fi

if ! declare -p PASSED_STEPS >/dev/null 2>&1; then
  PASSED_STEPS=()
fi

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
    if [[ "${STATUS_USE_ASCII}" == "true" ]]; then
      print_ascii_success
    fi
    print_success "${step_name}"
    record_pass "${step_name}"
  else
    if [[ "${STATUS_USE_ASCII}" == "true" ]]; then
      print_ascii_error
    fi
    print_error "${step_name}"
    record_fail "${step_name}"
  fi
}

print_standard_summary() {
  local success_message="$1"
  local failure_message="$2"
  local final_ascii="${3:-false}"
  local step

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
    if [[ "$final_ascii" == "true" ]]; then
      print_ascii_success
    fi
    print_success "${success_message}"
  else
    if [[ "$final_ascii" == "true" ]]; then
      print_ascii_error
    fi
    print_error "${failure_message}"
  fi
}
