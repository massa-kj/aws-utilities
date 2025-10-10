#!/usr/bin/env bash
#=============================================================
# utils.sh
#
# Common functions used in each service script
#=============================================================

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
  if ( -n "$region" ); then
    args+=(--region "$region")
  fi

  # Add profile only if defined
  if [ -n "${AWS_PROFILE:-}" ]; then
    args+=(--profile "${AWS_PROFILE}")
  fi

  # Execute command
  # aws "${args[@]}" "$@"
  #
  log_debug "Executing: aws ${args[*]} $*"

  local output
  local exit_code

  output=$(aws "${args[@]}" "$@" 2>&1)
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
      echo "$output"
      return 0
  else
      log_error "AWS command failed: aws ${args[*]} $*"
      log_error "Error output: $output"
      return $exit_code
  fi
}

#--- Ensure AWS CLI and credentials are available -------------
ensure_aws_ready() {
  if ! command -v aws >/dev/null 2>&1; then
    log_error "AWS CLI is not installed. Please install aws-cli v2+."
    exit 1
  fi

  # Use profile only if provided
  if [ -n "${AWS_PROFILE:-}" ]; then
    if ! aws_exec sts get-caller-identity >/dev/null 2>&1; then
      log_error "Invalid AWS credentials for profile '${AWS_PROFILE}'."
      exit 1
    fi
  else
    if ! aws_exec sts get-caller-identity >/dev/null 2>&1; then
      log_error "AWS credentials not found (neither profile nor environment variables)."
      exit 1
    fi
  fi

  log_debug "AWS CLI ready (profile=${AWS_PROFILE:-none}, region=${AWS_REGION})"
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
