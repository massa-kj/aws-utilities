#!/usr/bin/env bash
#=============================================================
# awstools.sh - Common entry point for tools
#
# Usage:
#   ./awstools.sh <service> <command> [options...]
#
# Example:
#   ./awstools.sh ec2 list
#   ./awstools.sh quicksight export --analysis-id abc123
#=============================================================

set -euo pipefail

#--- Base configuration --------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${BASE_DIR}/common"
SERVICES_DIR="${BASE_DIR}/services"
source "${COMMON_DIR}/logger.sh"

#--- Discover available services dynamically -----------------
discover_services() {
  for dir in "${SERVICES_DIR}"/*/; do
    [[ -d "$dir" ]] || continue
    if [ -f "${dir}/manifest.sh" ]; then
      source "${dir}/manifest.sh"
      printf "  - %-20s %s (v%s)\n" "$SERVICE_NAME" "$SERVICE_DESC" "$SERVICE_VERSION"
    fi
  done
}

#--- Help display --------------------------------------------
show_help() {
  cat <<EOF
AWS Tools - Unified CLI for multiple AWS services

Usage:
  $(basename "$0") <service> <command> [args...]

Available services:
$(discover_services)

Common options:
  --help, -h             Show help
  --debug                Enable debug logging (LOG_LEVEL=debug)
  --no-color             Disable color output (LOG_COLOR=false)
  --log-file <path>      Output logs to specified file

例:
  $(basename "$0") ec2 list
  $(basename "$0") quicksight backup --profile my-profile
EOF
}

#--- Detect authentication source ---------------------------
detect_auth_source() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    echo "profile:${AWS_PROFILE}"
  elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "env-vars"
  else
    echo "iam-role"
  fi
}

#--- Option parsing (pre-processing) -------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help; exit 0 ;;
    --debug)
      export LOG_LEVEL="debug"; shift ;;
    --no-color)
      export LOG_COLOR="false"; shift ;;
    --log-file)
      export LOG_FILE="$2"; shift 2 ;;
    *)
      break ;;
  esac
done

#--- Argument check -----------------------------------------
if [ $# -lt 1 ]; then
  show_help; exit 1
fi

SERVICE="$1"; shift || true
SERVICE_DIR="${SERVICES_DIR}/${SERVICE}"

if [ ! -d "$SERVICE_DIR" ]; then
  log_error "Unknown service: ${SERVICE}"
  log_info  "Available services:"
  discover_services
  exit 1
fi

#--- Delegate to service UI layer ----------------------------
UI_SCRIPT="${SERVICE_DIR}/ui.sh"
if [ ! -f "$UI_SCRIPT" ]; then
  log_error "Service UI not found: ${UI_SCRIPT}"
  exit 1
fi

# Delegate all sub-command processing to the service's ui.sh
log_debug "Delegating to service UI: ${UI_SCRIPT}"
exec "$UI_SCRIPT" "$@"
