#!/usr/bin/env bash
#=============================================================
# lib.sh - Helper utilities for service
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${EC2_LIB_LOADED:-}" ]]; then
  # Determine script directory and base directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

  # Load common configuration and utilities only once
  if [[ -z "${AWS_TOOLS_CONFIG_LOADED:-}" ]]; then
    source "$BASE_DIR/config.sh"
    export AWS_TOOLS_CONFIG_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_LOGGER_LOADED:-}" ]]; then
    source "$COMMON_DIR/logger.sh"
    export AWS_TOOLS_LOGGER_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_UTILS_LOADED:-}" ]]; then
    source "$COMMON_DIR/utils.sh"
    export AWS_TOOLS_UTILS_LOADED=1
  fi

  # Mark QuickSight lib as loaded to prevent double-loading
  export QuickService_LIB_LOADED=1

  log_debug "QuickSight lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- QuickSight-specific utility functions ----------------------------

