#!/usr/bin/env bash
#=============================================================
# utils.sh
#
# Common functions used in each service script
#=============================================================

#--- Ensure AWS CLI and credentials are available -------------
ensure_aws_ready() {
  if ! command -v aws >/dev/null 2>&1; then
    log_error "AWS CLI is not installed. Please install aws-cli v2+."
    exit 1
  fi

  # Use profile only if provided
  if [ -n "${AWS_PROFILE:-}" ]; then
    if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
      log_error "Invalid AWS credentials for profile '${AWS_PROFILE}'."
      exit 1
    fi
  else
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
      log_error "AWS credentials not found (neither profile nor environment variables)."
      exit 1
    fi
  fi

  log_debug "AWS CLI ready (profile=${AWS_PROFILE:-none}, region=${AWS_REGION})"
}

#--- Execute AWS command --------------------------------------
aws_exec() {
  local args=()
  # Add region always
  args+=(--region "${AWS_REGION}")

  # Add profile only if defined
  if [ -n "${AWS_PROFILE:-}" ]; then
    args+=(--profile "${AWS_PROFILE}")
  fi

  # Execute command
  aws "${args[@]}" "$@"
}

# -- Confirm action with user (yes/no) ------------------------
confirm_action() {
  local message="${1:-Are you sure?}"
  local default="${2:-no}"

  # Non-interactive mode (e.g., CI/CD)
  if [ "${AUTO_CONFIRM:-false}" = "true" ]; then
    log_debug "AUTO_CONFIRM enabled, skipping prompt."
    return 0
  fi

  local prompt="[y/N]"
  [[ "$default" == "yes" ]] && prompt="[Y/n]"

  read -r -p "${message} ${prompt} " answer
  case "${answer,,}" in
    y|yes) return 0 ;;
    "") [[ "$default" == "yes" ]] && return 0 || return 1 ;;
    *) return 1 ;;
  esac
}
