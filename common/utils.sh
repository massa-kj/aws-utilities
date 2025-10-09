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

  # Determine region with proper priority:
  # 1. AWS_REGION environment variable (if set)
  # 2. Profile's region setting (if profile is used)
  local region="${AWS_REGION:-}"

  # If no explicit region but profile is set, try to get region from profile
  if [ -z "$region" ] && [ -n "${AWS_PROFILE:-}" ]; then
    region=$(aws configure get region --profile "${AWS_PROFILE}" 2>/dev/null || echo "")
  fi

  # Add region to arguments
  args+=(--region "$region")

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
