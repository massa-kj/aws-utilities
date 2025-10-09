#!/usr/bin/env bash
#=============================================================
# lib.sh - Authentication utilities and configuration
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${AUTH_LIB_LOADED:-}" ]]; then
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
  
  # Mark Auth lib as loaded to prevent double-loading
  export AUTH_LIB_LOADED=1
  
  log_debug "Auth lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- Authentication Configuration ----------------------------

# Default authentication configuration
AUTH_CONFIG_DIR="${BASE_DIR}/config/auth"
AUTH_TIMEOUT="${AUTH_TIMEOUT:-300}"
AUTH_RETRY_COUNT="${AUTH_RETRY_COUNT:-3}"
AUTH_RETRY_DELAY="${AUTH_RETRY_DELAY:-2}"

# Global authentication state
AUTH_VALIDATED=false
AUTH_METHOD=""
AUTH_PROFILE=""
AUTH_ACCOUNT_ID=""
AUTH_REGION=""
AUTH_USER_ARN=""

#--- Authentication Validation Functions ---------------------

#
# Validate AWS CLI installation and version
#
validate_aws_cli() {
  local quiet=${1:-false}
  
  # Check if AWS CLI is installed
  if ! command -v aws >/dev/null 2>&1; then
    if [[ "$quiet" != "true" ]]; then
      log_error "AWS CLI is not installed. Please install AWS CLI v2+"
    fi
    return 1
  fi
  
  # Check AWS CLI version
  local aws_version
  aws_version=$(aws --version 2>&1 | head -n1 | cut -d/ -f2 | cut -d' ' -f1)
  
  # Validate version is v2+
  local major_version
  major_version=$(echo "$aws_version" | cut -d. -f1)
  if [[ "$major_version" -lt 2 ]]; then
    if [[ "$quiet" != "true" ]]; then
      log_warn "AWS CLI v1 detected ($aws_version). v2+ is recommended."
    fi
  fi
  
  if [[ "$quiet" != "true" ]]; then
    log_info "AWS CLI version: $aws_version"
  fi
  
  return 0
}

#
# Detect current authentication method
#
detect_auth_method() {
  # Check environment variables first
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
      echo "env-vars-session"
    else
      echo "env-vars"
    fi
    return 0
  fi
  
  # Check AWS_PROFILE
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    if aws configure get sso_start_url --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
      echo "profile-sso:${AWS_PROFILE}"
    elif aws configure get role_arn --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
      echo "profile-assume:${AWS_PROFILE}"
    else
      echo "profile-accesskey:${AWS_PROFILE}"
    fi
    return 0
  fi
  
  # Check instance metadata (EC2 instance profile)
  if curl -sf --max-time 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ >/dev/null 2>&1; then
    echo "instance-profile"
    return 0
  fi
  
  # Check for web identity token (EKS, etc.)
  if [[ -n "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" && -n "${AWS_ROLE_ARN:-}" ]]; then
    echo "web-identity"
    return 0
  fi
  
  # Default profile fallback
  if aws configure list-profiles 2>/dev/null | grep -q "^default$"; then
    if aws configure get sso_start_url --profile default >/dev/null 2>&1; then
      echo "profile-sso:default"
    elif aws configure get role_arn --profile default >/dev/null 2>&1; then
      echo "profile-assume:default"
    else
      echo "profile-accesskey:default"
    fi
    return 0
  fi
  
  echo "unknown"
  return 1
}

#
# Validate current AWS authentication
#
validate_auth() {
  local quiet=${1:-false}
  
  # Validate AWS CLI first
  if ! validate_aws_cli "$quiet"; then
    return 1
  fi
  
  # Test AWS credentials
  local caller_identity
  if ! caller_identity=$(aws sts get-caller-identity 2>/dev/null); then
    if [[ "$quiet" != "true" ]]; then
      log_error "AWS authentication failed. Please configure AWS credentials."
    fi
    return 1
  fi
  
  # Extract authentication information
  AUTH_ACCOUNT_ID=$(echo "$caller_identity" | jq -r '.Account // empty')
  AUTH_USER_ARN=$(echo "$caller_identity" | jq -r '.Arn // empty')
  AUTH_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
  AUTH_METHOD=$(detect_auth_method)
  
  # Extract profile if using profile-based auth
  if [[ "$AUTH_METHOD" =~ ^profile- ]]; then
    AUTH_PROFILE="${AUTH_METHOD#*:}"
  else
    AUTH_PROFILE="${AWS_PROFILE:-}"
  fi
  
  if [[ "$quiet" != "true" ]]; then
    log_info "Authentication validated:"
    log_info "  Method: $AUTH_METHOD"
    log_info "  Account: $AUTH_ACCOUNT_ID"
    log_info "  Region: $AUTH_REGION"
    log_info "  User/Role: $AUTH_USER_ARN"
    if [[ -n "$AUTH_PROFILE" ]]; then
      log_info "  Profile: $AUTH_PROFILE"
    fi
  fi
  
  AUTH_VALIDATED=true
  return 0
}

#--- Authentication Helper Functions ------------------------

#
# Get AWS account ID (validates auth if needed)
#
get_account_id() {
  if [[ "$AUTH_VALIDATED" != "true" ]]; then
    validate_auth true || return 1
  fi
  echo "$AUTH_ACCOUNT_ID"
}

#
# Get AWS region (validates auth if needed)
#
get_region() {
  if [[ "$AUTH_VALIDATED" != "true" ]]; then
    validate_auth true || return 1
  fi
  echo "$AUTH_REGION"
}

#
# Get authentication method (validates auth if needed)
#
get_auth_method() {
  if [[ "$AUTH_VALIDATED" != "true" ]]; then
    validate_auth true || return 1
  fi
  echo "$AUTH_METHOD"
}

#
# Get current profile (validates auth if needed)
#
get_profile() {
  if [[ "$AUTH_VALIDATED" != "true" ]]; then
    validate_auth true || return 1
  fi
  echo "$AUTH_PROFILE"
}

#
# Check if profile exists
#
profile_exists() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  aws configure list-profiles 2>/dev/null | grep -q "^${profile_name}$"
}

#
# Check if profile is SSO-based
#
is_sso_profile() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  aws configure get sso_start_url --profile "$profile_name" >/dev/null 2>&1
}

#
# Check if profile uses role assumption
#
is_assume_role_profile() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  aws configure get role_arn --profile "$profile_name" >/dev/null 2>&1
}

#
# Get profile configuration
#
get_profile_config() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  local config_output
  config_output=$(aws configure list --profile "$profile_name" 2>/dev/null)
  
  echo "Profile Configuration: $profile_name"
  echo "$config_output"
  
  # Additional SSO/Role information
  if is_sso_profile "$profile_name"; then
    echo ""
    echo "SSO Configuration:"
    echo "  Start URL: $(aws configure get sso_start_url --profile "$profile_name" 2>/dev/null || echo "Not configured")"
    echo "  Account ID: $(aws configure get sso_account_id --profile "$profile_name" 2>/dev/null || echo "Not configured")"
    echo "  Role Name: $(aws configure get sso_role_name --profile "$profile_name" 2>/dev/null || echo "Not configured")"
  fi
  
  if is_assume_role_profile "$profile_name"; then
    echo ""
    echo "Role Configuration:"
    echo "  Role ARN: $(aws configure get role_arn --profile "$profile_name" 2>/dev/null || echo "Not configured")"
    echo "  Source Profile: $(aws configure get source_profile --profile "$profile_name" 2>/dev/null || echo "Not configured")"
  fi
}

#--- Configuration Management Functions ---------------------

#
# Load authentication configuration
#
load_auth_config() {
  local config_file="${AUTH_CONFIG_DIR}/auth.conf"
  
  if [[ -f "$config_file" ]]; then
    log_debug "Loading auth configuration from: $config_file"
    source "$config_file"
  else
    log_debug "No auth configuration file found, using defaults"
  fi
}

#
# Set region override
#
set_region() {
  local region="$1"
  
  if [[ -z "$region" ]]; then
    log_error "Region parameter is required"
    return 1
  fi
  
  AUTH_REGION="$region"
  export AWS_DEFAULT_REGION="$region"
  log_info "AWS Region set to: $region"
}

# Initialize authentication library
load_auth_config

# Registry system is available but loaded on-demand to avoid circular dependencies
AUTH_REGISTRY_AVAILABLE=true

# Export functions for use in other scripts
export -f validate_aws_cli
export -f detect_auth_method
export -f validate_auth
export -f get_account_id
export -f get_region
export -f get_auth_method
export -f get_profile
export -f profile_exists
export -f is_sso_profile
export -f is_assume_role_profile
export -f get_profile_config
export -f set_region
