#!/usr/bin/env bash
#=============================================================
# ui.sh - User Interface 
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"  # This also loads common libraries
source "$SCRIPT_DIR/api.sh"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
QuickSight Service Commands

Usage:
  awstools quicksight <command> [options...]

Available commands:
  list-datasets           List QuickSight datasets
  list-analyses           List QuickSight analyses
  help                    Show this help

Options:
  --profile <name>        Override AWS profile
  --region <region>       Override AWS region

Examples:
  awstools quicksight list-analyses
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        export AWS_PROFILE="${2:-$AWS_PROFILE}"
        log_debug "Profile overridden to: ${AWS_PROFILE}"
        shift 2
        ;;
      --region)
        export AWS_REGION="${2:-$AWS_REGION}"
        log_debug "Region overridden to: ${AWS_REGION}"
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        # Keep remaining arguments
        REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

#--- Command Implementation -----------------------------------
list_datasets() {
  log_info "Listing QuickSight datasets in region ${AWS_REGION:-default}"
  get_all_datasets
}

list_analyses() {
  log_info "Listing QuickSight datasets in region ${AWS_REGION:-default}"
  get_all_analyses
}

#--- Main Processing -----------------------------------------

# Parse options
REMAINING_ARGS=()
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

# Get command
COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  show_help
  exit 1
fi
shift || true

# Execute command
case "$COMMAND" in
  list-datasets)
    list_datasets "$@"
    ;;
  list-analyses)
    list_analyses "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: $COMMAND"
    log_info "Run 'awstools quicksight help' for available commands"
    exit 1
    ;;
esac
