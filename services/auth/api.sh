#!/usr/bin/env bash
#=============================================================
# api.sh - AWS authentication API wrappers
#=============================================================

set -euo pipefail

# Load dependencies (explicit loading for clarity and testability)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#--- SSO Authentication Methods --------------------------------

#
# Initiate SSO login for a profile
#
auth_sso_login() {
  local profile_name="${1:-}"
  local session_name="${2:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_sso_login <profile-name> [session-name]"
    return 1
  fi
  
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  if ! is_sso_profile "$profile_name"; then
    log_error "Profile '$profile_name' is not configured for SSO"
    return 1
  fi
  
  log_info "Initiating SSO login for profile: $profile_name"
  
  local aws_args=("sso" "login" "--profile" "$profile_name")
  
  if [[ -n "$session_name" ]]; then
    aws_args+=("--sso-session" "$session_name")
  fi
  
  if aws_exec "${aws_args[@]}"; then
    log_info "SSO login successful for profile: $profile_name"
    return 0
  else
    log_error "SSO login failed for profile: $profile_name"
    return 1
  fi
}

#
# Check SSO session status
#
auth_sso_status() {
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_sso_status <profile-name>"
    return 1
  fi
  
  if ! is_sso_profile "$profile_name"; then
    log_error "Profile '$profile_name' is not configured for SSO"
    return 1
  fi
  
  # Try to get caller identity with the SSO profile
  if aws sts get-caller-identity --profile "$profile_name" >/dev/null 2>&1; then
    echo "active"
    return 0
  else
    echo "expired"
    return 1
  fi
}

#
# Logout from SSO session
#
auth_sso_logout() {
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

#--- Role Assumption Methods -----------------------------------

#
# Assume role and set environment variables
#
auth_assume_role() {
  local role_arn="$1"
  local session_name="${2:-aws-utilities-session}"
  local duration="${3:-3600}"
  local external_id="${4:-}"
  local mfa_serial="${5:-}"
  local mfa_token="${6:-}"
  
  if [[ -z "$role_arn" ]]; then
    log_error "Usage: auth_assume_role <role-arn> [session-name] [duration] [external-id] [mfa-serial] [mfa-token]"
    return 1
  fi
  
  log_info "Assuming role: $role_arn"
  log_debug "Session name: $session_name, Duration: ${duration}s"
  
  local aws_args=("sts" "assume-role" 
                   "--role-arn" "$role_arn" 
                   "--role-session-name" "$session_name"
                   "--duration-seconds" "$duration")
  
  if [[ -n "$external_id" ]]; then
    aws_args+=("--external-id" "$external_id")
  fi
  
  if [[ -n "$mfa_serial" && -n "$mfa_token" ]]; then
    aws_args+=("--serial-number" "$mfa_serial" "--token-code" "$mfa_token")
  fi
  
  local credentials
  if ! credentials=$(aws "${aws_args[@]}" 2>/dev/null); then
    log_error "Failed to assume role: $role_arn"
    return 1
  fi
  
  # Extract credentials from JSON response
  local access_key_id secret_access_key session_token
  access_key_id=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
  secret_access_key=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey')
  session_token=$(echo "$credentials" | jq -r '.Credentials.SessionToken')
  
  if [[ "$access_key_id" == "null" || "$secret_access_key" == "null" || "$session_token" == "null" ]]; then
    log_error "Invalid credentials received from assume role operation"
    return 1
  fi
  
  # Set environment variables
  export AWS_ACCESS_KEY_ID="$access_key_id"
  export AWS_SECRET_ACCESS_KEY="$secret_access_key"
  export AWS_SESSION_TOKEN="$session_token"
  
  # Clear profile to prevent conflicts
  unset AWS_PROFILE
  
  log_info "Role assumption successful"
  log_debug "Credentials set in environment variables"
  
  return 0
}

#
# Assume role using profile configuration
#
auth_assume_role_profile() {
  local profile_name="$1"
  local session_name="${2:-aws-utilities-session}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_assume_role_profile <profile-name> [session-name]"
    return 1
  fi
  
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  if ! is_assume_role_profile "$profile_name"; then
    log_error "Profile '$profile_name' is not configured for role assumption"
    return 1
  fi
  
  local role_arn
  role_arn=$(aws configure get role_arn --profile "$profile_name")
  
  if [[ -z "$role_arn" ]]; then
    log_error "No role ARN configured for profile: $profile_name"
    return 1
  fi
  
  # Check for MFA configuration
  local mfa_serial
  mfa_serial=$(aws configure get mfa_serial --profile "$profile_name" 2>/dev/null || echo "")
  
  local mfa_token=""
  if [[ -n "$mfa_serial" ]]; then
    read -p "Enter MFA token for $mfa_serial: " -s mfa_token
    echo  # Add newline after hidden input
  fi
  
  # Get duration if configured
  local duration
  duration=$(aws configure get duration_seconds --profile "$profile_name" 2>/dev/null || echo "3600")
  
  # Get external ID if configured
  local external_id
  external_id=$(aws configure get external_id --profile "$profile_name" 2>/dev/null || echo "")
  
  auth_assume_role "$role_arn" "$session_name" "$duration" "$external_id" "$mfa_serial" "$mfa_token"
}

#--- Profile Management Methods --------------------------------

#
# Set active profile
#
auth_set_profile() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_set_profile <profile-name>"
    return 1
  fi
  
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  export AWS_PROFILE="$profile_name"
  
  # Clear any existing credentials to prevent conflicts
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  
  log_info "Active profile set to: $profile_name"
  
  # Validate the profile works
  if validate_auth true; then
    log_info "Profile validation successful"
    return 0
  else
    log_error "Profile validation failed"
    return 1
  fi
}

#
# List available profiles
#
auth_list_profiles() {
  log_debug "Listing available AWS profiles"
  
  local profiles
  if ! profiles=$(aws configure list-profiles 2>/dev/null); then
    log_error "Failed to list profiles"
    return 1
  fi
  
  if [[ -z "$profiles" ]]; then
    log_warn "No AWS profiles configured"
    return 0
  fi
  
  echo "Available AWS Profiles:"
  echo "======================="
  
  while IFS= read -r profile; do
    local profile_type="accesskey"
    local status_indicator=""
    
    # Determine profile type
    if is_sso_profile "$profile"; then
      profile_type="sso"
      if [[ "$(auth_sso_status "$profile" 2>/dev/null)" == "active" ]]; then
        status_indicator=" ✓"
      else
        status_indicator=" (expired)"
      fi
    elif is_assume_role_profile "$profile"; then
      profile_type="assume-role"
    fi
    
    # Mark current profile
    local current_marker=""
    if [[ "${AWS_PROFILE:-}" == "$profile" ]]; then
      current_marker=" *"
    fi
    
    printf "  %-20s [%-11s]%s%s\n" "$profile" "$profile_type" "$status_indicator" "$current_marker"
  done <<< "$profiles"
  
  echo ""
  echo "Legend: * = current profile, ✓ = active SSO session"
}

#--- Environment Management Methods ----------------------------

#
# Clear authentication environment
#
auth_clear_env() {
  log_info "Clearing authentication environment variables"
  
  unset AWS_PROFILE
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  unset AWS_DEFAULT_REGION
  
  # Reset auth library state
  AUTH_VALIDATED=false
  AUTH_METHOD=""
  AUTH_PROFILE=""
  AUTH_ACCOUNT_ID=""
  AUTH_REGION=""
  AUTH_USER_ARN=""
  
  log_info "Authentication environment cleared"
}

#
# Show current authentication environment
#
auth_show_env() {
  echo "Current Authentication Environment:"
  echo "=================================="
  
  echo "Environment Variables:"
  echo "  AWS_PROFILE: ${AWS_PROFILE:-<not set>}"
  echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:+<set>}${AWS_ACCESS_KEY_ID:-<not set>}"
  echo "  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:+<set>}${AWS_SECRET_ACCESS_KEY:-<not set>}"
  echo "  AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:+<set>}${AWS_SESSION_TOKEN:-<not set>}"
  echo "  AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-<not set>}"
  
  echo ""
  if validate_auth true; then
    echo "Active Authentication:"
    echo "  Method: $(get_auth_method)"
    echo "  Account ID: $(get_account_id)"
    echo "  Region: $(get_region)"
    echo "  User/Role ARN: $AUTH_USER_ARN"
    if [[ -n "$(get_profile)" ]]; then
      echo "  Profile: $(get_profile)"
    fi
  else
    echo "Authentication Status: ❌ Not authenticated or invalid"
  fi
}

#--- Session Management Methods --------------------------------

#
# Create authentication session with automatic method detection
#
auth_create_session() {
  local profile_name="${1:-}"
  local mode="${2:-auto}"
  
  log_info "Creating authentication session${profile_name:+ for profile: $profile_name}"
  log_debug "Authentication mode: $mode"
  
  case "$mode" in
    sso)
      if [[ -z "$profile_name" ]]; then
        log_error "Profile name required for SSO authentication"
        return 1
      fi
      auth_sso_login "$profile_name"
      ;;
    
    profile|accesskey)
      if [[ -z "$profile_name" ]]; then
        log_error "Profile name required for profile authentication"
        return 1
      fi
      auth_set_profile "$profile_name"
      ;;
    
    assume)
      if [[ -z "$profile_name" ]]; then
        log_error "Profile name required for assume role authentication"
        return 1
      fi
      auth_assume_role_profile "$profile_name"
      ;;
    
    auto)
      if [[ -n "$profile_name" ]]; then
        # Profile specified, auto-detect its type
        if is_sso_profile "$profile_name"; then
          log_info "Detected SSO profile, initiating SSO login"
          auth_sso_login "$profile_name"
        elif is_assume_role_profile "$profile_name"; then
          log_info "Detected assume role profile, assuming role"
          auth_assume_role_profile "$profile_name"
        else
          log_info "Using access key profile"
          auth_set_profile "$profile_name"
        fi
      else
        # No profile specified, use current environment or default
        if validate_auth true; then
          log_info "Using existing authentication"
          return 0
        else
          log_error "No authentication available and no profile specified"
          return 1
        fi
      fi
      ;;
    
    *)
      log_error "Unknown authentication mode: $mode"
      log_error "Supported modes: auto, sso, profile, accesskey, assume"
      return 1
      ;;
  esac
  
  # Validate the created session
  if validate_auth; then
    log_info "Authentication session created successfully"
    return 0
  else
    log_error "Failed to create valid authentication session"
    return 1
  fi
}

#
# Test authentication with AWS service call
#
auth_test() {
  local service="${1:-sts}"
  
  log_info "Testing authentication with $service service"
  
  case "$service" in
    sts)
      if aws sts get-caller-identity >/dev/null 2>&1; then
        log_info "✅ STS authentication test passed"
        return 0
      else
        log_error "❌ STS authentication test failed"
        return 1
      fi
      ;;
    
    s3)
      if aws s3 ls >/dev/null 2>&1; then
        log_info "✅ S3 authentication test passed"
        return 0
      else
        log_error "❌ S3 authentication test failed"
        return 1
      fi
      ;;
    
    ec2)
      if aws ec2 describe-regions --region us-east-1 >/dev/null 2>&1; then
        log_info "✅ EC2 authentication test passed"
        return 0
      else
        log_error "❌ EC2 authentication test failed"
        return 1
      fi
      ;;
    
    *)
      log_error "Unknown service for authentication test: $service"
      log_error "Supported services: sts, s3, ec2"
      return 1
      ;;
  esac
}
