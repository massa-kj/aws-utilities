#!/usr/bin/env bash
#=============================================================
# sso.sh - SSO Authentication Handler
#=============================================================

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

#--- SSO Handler Implementation -----------------------------

#
# Handle SSO authentication
#
handle_sso_auth() {
  local profile_name="${1:-}"
  local session_name="${2:-}"
  local options="${3:-}"
  
  log_debug "SSO Authentication Handler called with profile: $profile_name"
  
  if [[ -z "$profile_name" ]]; then
    log_error "SSO handler requires profile name"
    return 1
  fi
  
  # Validate profile exists and is SSO-configured
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  if ! is_sso_profile "$profile_name"; then
    log_error "Profile '$profile_name' is not configured for SSO"
    return 1
  fi
  
  # Get configuration
  local sso_session_name="${session_name:-$(get_handler_config "sso" "DEFAULT_SESSION_NAME" "aws-utilities-sso")}"
  local login_timeout=$(get_handler_config "sso" "LOGIN_TIMEOUT" "300")
  local auto_refresh=$(get_handler_config "sso" "AUTO_REFRESH" "true")
  
  log_info "Initiating SSO login for profile: $profile_name"
  log_debug "Session name: $sso_session_name, Timeout: ${login_timeout}s"
  
  # Check if already authenticated
  if [[ "$auto_refresh" == "true" ]]; then
    if sso_check_session_status "$profile_name"; then
      log_info "SSO session already active for profile: $profile_name"
      return 0
    fi
  fi
  
  # Perform SSO login
  local aws_args=("sso" "login" "--profile" "$profile_name")
  
  if [[ -n "$sso_session_name" ]]; then
    aws_args+=("--sso-session" "$sso_session_name")
  fi
  
  # Execute with timeout
  if timeout "$login_timeout" aws "${aws_args[@]}"; then
    log_info "SSO login successful for profile: $profile_name"
    
    # Set the profile as active
    export AWS_PROFILE="$profile_name"
    
    # Validate the authentication
    if validate_auth true; then
      log_info "SSO authentication validated successfully"
      return 0
    else
      log_error "SSO authentication validation failed"
      return 1
    fi
  else
    log_error "SSO login failed or timed out for profile: $profile_name"
    return 1
  fi
}

#
# Check SSO session status
#
sso_check_session_status() {
  local profile_name="$1"
  
  # Try to get caller identity with the SSO profile
  if aws sts get-caller-identity --profile "$profile_name" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

#
# SSO logout handler
#
handle_sso_logout() {
  local session_name="${1:-}"
  
  log_info "Logging out from SSO session${session_name:+: $session_name}"
  
  local aws_args=("sso" "logout")
  
  if [[ -n "$session_name" ]]; then
    aws_args+=("--sso-session" "$session_name")
  fi
  
  if aws "${aws_args[@]}"; then
    log_info "SSO logout successful"
    return 0
  else
    log_error "SSO logout failed"
    return 1
  fi
}

#
# Get SSO session information
#
get_sso_session_info() {
  local profile_name="$1"
  
  if ! is_sso_profile "$profile_name"; then
    log_error "Profile '$profile_name' is not configured for SSO"
    return 1
  fi
  
  echo "SSO Session Information for profile: $profile_name"
  echo "================================================="
  
  local start_url
  start_url=$(aws configure get sso_start_url --profile "$profile_name" 2>/dev/null || echo "Not configured")
  echo "Start URL: $start_url"
  
  local account_id
  account_id=$(aws configure get sso_account_id --profile "$profile_name" 2>/dev/null || echo "Not configured")
  echo "Account ID: $account_id"
  
  local role_name
  role_name=$(aws configure get sso_role_name --profile "$profile_name" 2>/dev/null || echo "Not configured")
  echo "Role Name: $role_name"
  
  local region
  region=$(aws configure get region --profile "$profile_name" 2>/dev/null || echo "Not configured")
  echo "Region: $region"
  
  local session_status="expired"
  if sso_check_session_status "$profile_name"; then
    session_status="active"
  fi
  echo "Session Status: $session_status"
}

# Register this handler with the registry (if registry is available)
if command -v register_auth_handler >/dev/null 2>&1; then
  register_auth_handler "sso" "handle_sso_auth" \
    "AWS SSO (IAM Identity Center) authentication with session management" \
    "2.1.0" \
    "aws-cli>=2.0"
fi

# Export handler functions
export -f handle_sso_auth
export -f sso_check_session_status
export -f handle_sso_logout
export -f get_sso_session_info
