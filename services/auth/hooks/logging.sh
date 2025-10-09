#!/usr/bin/env bash
#=============================================================
# logging.sh - Authentication Logging Hooks
#=============================================================

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

#--- Authentication Logging Hooks --------------------------

#
# Pre-authentication logging hook
#
pre_auth_logging_hook() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  log_info "[$timestamp] Starting authentication with handler: $handler_name"
  log_debug "[$timestamp] Handler arguments: ${handler_args[*]}"
  
  # Log to auth log file if configured
  local auth_log_file
  auth_log_file=$(get_handler_config "auth" "LOG_FILE" "")
  
  if [[ -n "$auth_log_file" ]]; then
    mkdir -p "$(dirname "$auth_log_file")"
    echo "[$timestamp] PRE-AUTH: handler=$handler_name args=${handler_args[*]}" >> "$auth_log_file"
  fi
}

#
# Post-authentication success logging hook
#
post_auth_success_logging_hook() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  log_info "[$timestamp] Authentication successful with handler: $handler_name"
  
  # Log to auth log file if configured
  local auth_log_file
  auth_log_file=$(get_handler_config "auth" "LOG_FILE" "")
  
  if [[ -n "$auth_log_file" ]]; then
    echo "[$timestamp] POST-AUTH-SUCCESS: handler=$handler_name" >> "$auth_log_file"
  fi
  
  # Log authentication details
  if validate_auth true 2>/dev/null; then
    local account_id region method
    account_id=$(get_account_id 2>/dev/null || echo "unknown")
    region=$(get_region 2>/dev/null || echo "unknown")
    method=$(get_auth_method 2>/dev/null || echo "unknown")
    
    log_debug "[$timestamp] Auth details: account=$account_id region=$region method=$method"
    
    if [[ -n "$auth_log_file" ]]; then
      echo "[$timestamp] AUTH-DETAILS: account=$account_id region=$region method=$method" >> "$auth_log_file"
    fi
  fi
}

#
# Post-authentication failure logging hook
#
post_auth_failure_logging_hook() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  log_warn "[$timestamp] Authentication failed with handler: $handler_name"
  
  # Log to auth log file if configured
  local auth_log_file
  auth_log_file=$(get_handler_config "auth" "LOG_FILE" "")
  
  if [[ -n "$auth_log_file" ]]; then
    echo "[$timestamp] POST-AUTH-FAILURE: handler=$handler_name args=${handler_args[*]}" >> "$auth_log_file"
  fi
}

# Register hooks with the registry (if registry is available)
if command -v register_auth_hook >/dev/null 2>&1; then
  register_auth_hook "pre-auth" "pre_auth_logging_hook" 10
  register_auth_hook "post-auth-success" "post_auth_success_logging_hook" 10
  register_auth_hook "post-auth-failure" "post_auth_failure_logging_hook" 10
fi

# Export hook functions
export -f pre_auth_logging_hook
export -f post_auth_success_logging_hook
export -f post_auth_failure_logging_hook
