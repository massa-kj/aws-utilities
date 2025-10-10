#!/usr/bin/env bash
#=============================================================
# ui.sh - Authentication User Interface 
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"  # This also loads common libraries
source "$SCRIPT_DIR/api.sh"

load_config "" "auth"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
Authentication Service Commands

Usage:
  awstools auth <command> [options...]

Available commands:
  status                  Show current authentication status
  detect                  Detect authentication method
  login <profile>         Login using profile (auto-detect method)
  sso-login <profile>     Login using AWS SSO
  assume <profile>        Assume role using profile configuration
  set-profile <profile>   Set active profile
  list-profiles           List available profiles
  list-handlers           List available authentication handlers
  test [service]          Test authentication (default: sts)
  clear                   Clear authentication environment
  show-env                Show authentication environment variables
  profile-info <profile>  Show detailed profile configuration
  help                    Show this help

Options:
  --profile <name>        Override AWS profile
  --region <region>       Override AWS region
  --mode <mode>           Authentication mode (auto|sso|profile|assume)
  --session-name <name>   Custom session name for role assumption
  --duration <seconds>    Session duration (default: 3600)

Examples:
  awstools auth status
  awstools auth detect
  awstools auth login my-dev-profile
  awstools auth sso-login my-sso-profile
  awstools auth assume my-role-profile
  awstools auth set-profile production
  awstools auth list-profiles
  awstools auth test s3
  awstools auth profile-info my-profile
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        OVERRIDE_PROFILE="${2:-}"
        if [[ -n "$OVERRIDE_PROFILE" ]]; then
          export AWS_PROFILE="$OVERRIDE_PROFILE"
          log_debug "Profile overridden to: $AWS_PROFILE"
        fi
        shift 2
        ;;
      --region)
        OVERRIDE_REGION="${2:-}"
        if [[ -n "$OVERRIDE_REGION" ]]; then
          export AWS_REGION="$OVERRIDE_REGION"
          log_debug "Region overridden to: $AWS_REGION"
        fi
        shift 2
        ;;
      --mode)
        AUTH_MODE="${2:-auto}"
        log_debug "Authentication mode set to: $AUTH_MODE"
        shift 2
        ;;
      --session-name)
        SESSION_NAME="${2:-aws-utilities-session}"
        log_debug "Session name set to: $SESSION_NAME"
        shift 2
        ;;
      --duration)
        DURATION="${2:-3600}"
        log_debug "Session duration set to: $DURATION seconds"
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

#--- Utility Functions ----------------------------------------

#
# Confirm action with user
#
confirm_action() {
  local message="$1"
  local default="${2:-yes}"
  
  local prompt
  if [[ "$default" == "yes" ]]; then
    prompt="$message [Y/n]: "
  else
    prompt="$message [y/N]: "
  fi
  
  read -p "$prompt" -r response
  
  case "$response" in
    [Yy]|[Yy][Ee][Ss])
      return 0
      ;;
    [Nn]|[Nn][Oo])
      return 1
      ;;
    "")
      if [[ "$default" == "yes" ]]; then
        return 0
      else
        return 1
      fi
      ;;
    *)
      log_warn "Please answer yes or no."
      confirm_action "$message" "$default"
      ;;
  esac
}

#
# Display authentication status with colors
#
display_status() {
  echo "Authentication Status:"
  echo "====================="
  
  if validate_auth true; then
    echo "Status: ✅ Authenticated"
    echo "Method: $(get_auth_method)"
    echo "Account ID: $(get_account_id)"
    echo "Region: $(get_region)"
    echo "User/Role ARN: $AUTH_USER_ARN"
    
    local profile
    profile=$(get_profile)
    if [[ -n "$profile" ]]; then
      echo "Profile: $profile"
    fi
    
    # Additional SSO status for SSO profiles
    if [[ "$(get_auth_method)" =~ sso ]]; then
      local sso_status
      sso_status=$(auth_sso_status "$profile" 2>/dev/null || echo "unknown")
      echo "SSO Session: $sso_status"
    fi
  else
    echo "Status: ❌ Not authenticated"
    echo ""
    echo "Suggestions:"
    echo "  1. Configure AWS credentials: aws configure"
    echo "  2. Use SSO login: awstools auth sso-login <profile>"
    echo "  3. Set profile: awstools auth set-profile <profile>"
    echo "  4. Check available profiles: awstools auth list-profiles"
  fi
}

#--- Command Implementation -----------------------------------

cmd_status() {
  log_debug "Checking authentication status"
  display_status
}

cmd_detect() {
  log_debug "Detecting authentication method"
  
  local method
  method=$(detect_auth_method)
  
  echo "Detected authentication method: $method"
  
  case "$method" in
    env-vars*)
      echo "Using environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
      ;;
    profile-sso:*)
      local profile_name="${method#*:}"
      echo "Using SSO profile: $profile_name"
      local sso_status
      sso_status=$(auth_sso_status "$profile_name" 2>/dev/null || echo "expired")
      echo "SSO session status: $sso_status"
      ;;
    profile-assume:*)
      local profile_name="${method#*:}"
      echo "Using assume role profile: $profile_name"
      ;;
    profile-accesskey:*)
      local profile_name="${method#*:}"
      echo "Using access key profile: $profile_name"
      ;;
    instance-profile)
      echo "Using EC2 instance profile"
      ;;
    web-identity)
      echo "Using web identity token (EKS, etc.)"
      ;;
    unknown)
      echo "No authentication method detected"
      return 1
      ;;
  esac
}

cmd_login() {
  local profile_name="${1:-}"
  local mode="${AUTH_MODE:-auto}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth login <profile-name>"
    return 1
  fi
  
  log_info "Logging in with profile: $profile_name (mode: $mode)"
  
  if auth_create_session "$profile_name" "$mode"; then
    log_info "✅ Login successful"
    display_status
  else
    log_error "❌ Login failed"
    return 1
  fi
}

cmd_sso_login() {
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth sso-login <profile-name>"
    return 1
  fi
  
  log_info "Initiating SSO login for profile: $profile_name"
  
  if auth_sso_login "$profile_name"; then
    log_info "✅ SSO login successful"
    export AWS_PROFILE="$profile_name"
    display_status
  else
    log_error "❌ SSO login failed"
    return 1
  fi
}

cmd_assume() {
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth assume <profile-name>"
    return 1
  fi
  
  log_info "Assuming role using profile: $profile_name"
  
  if auth_assume_role_profile "$profile_name" "${SESSION_NAME:-}"; then
    log_info "✅ Role assumption successful"
    display_status
  else
    log_error "❌ Role assumption failed"
    return 1
  fi
}

cmd_set_profile() {
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth set-profile <profile-name>"
    return 1
  fi
  
  log_info "Setting active profile to: $profile_name"
  
  if auth_set_profile "$profile_name"; then
    log_info "✅ Profile set successfully"
    display_status
  else
    log_error "❌ Failed to set profile"
    return 1
  fi
}

cmd_list_profiles() {
  log_debug "Listing available profiles"
  auth_list_profiles
}

cmd_list_handlers() {
  log_debug "Listing available authentication handlers"
  
  echo "Available Authentication Handlers:"
  echo "=================================="
  printf "%-20s %-15s %-50s\n" "NAME" "VERSION" "DESCRIPTION"
  printf "%-20s %-15s %-50s\n" "----" "-------" "-----------"
  
  # Built-in handlers
  printf "%-20s %-15s %-50s\n" "sso" "2.0.0" "AWS SSO (IAM Identity Center) authentication"
  printf "%-20s %-15s %-50s\n" "accesskey" "2.0.0" "Static AWS access key authentication"
  printf "%-20s %-15s %-50s\n" "assume" "2.0.0" "AWS role assumption authentication"
  printf "%-20s %-15s %-50s\n" "instance-profile" "2.0.0" "EC2 instance profile authentication"
  printf "%-20s %-15s %-50s\n" "web-identity" "2.0.0" "Web identity token authentication"
  printf "%-20s %-15s %-50s\n" "env-vars" "2.0.0" "Environment variable authentication"
  
  # Check for custom handlers
  local handlers_dir="$SCRIPT_DIR/handlers"
  if [[ -d "$handlers_dir" ]]; then
    echo ""
    echo "Custom Handlers:"
    echo "================"
    
    for handler_file in "$handlers_dir"/*.sh; do
      if [[ -f "$handler_file" ]]; then
        local handler_name
        handler_name=$(basename "$handler_file" .sh)
        if [[ "$handler_name" != "example-custom" ]]; then
          printf "%-20s %-15s %-50s\n" "$handler_name" "custom" "Custom authentication handler"
        fi
      fi
    done
  fi
  
  echo ""
  echo "Handler files location: $SCRIPT_DIR/handlers/"
  echo "Configuration files location: $SCRIPT_DIR/config/"
}

cmd_test() {
  local service="${1:-sts}"
  
  log_info "Testing authentication with $service service"
  
  if auth_test "$service"; then
    log_info "✅ Authentication test passed"
  else
    log_error "❌ Authentication test failed"
    return 1
  fi
}

cmd_clear() {
  if confirm_action "Are you sure you want to clear the authentication environment?" "no"; then
    auth_clear_env
    log_info "✅ Authentication environment cleared"
  else
    log_info "Operation cancelled"
  fi
}

cmd_show_env() {
  log_debug "Showing authentication environment"
  auth_show_env
}

cmd_profile_info() {
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth profile-info <profile-name>"
    return 1
  fi
  
  log_debug "Getting profile information for: $profile_name"
  get_profile_config "$profile_name"
}

cmd_sso_logout() {
  local session_name="${1:-}"
  
  if confirm_action "Are you sure you want to logout from SSO?" "yes"; then
    if auth_sso_logout "$session_name"; then
      log_info "✅ SSO logout successful"
    else
      log_error "❌ SSO logout failed"
      return 1
    fi
  else
    log_info "Operation cancelled"
  fi
}

#--- Main Processing -----------------------------------------

# Initialize variables
REMAINING_ARGS=()
AUTH_MODE="auto"
SESSION_NAME="aws-utilities-session"
DURATION="3600"
OVERRIDE_PROFILE=""
OVERRIDE_REGION=""

# Parse options
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
  status)
    cmd_status "$@"
    ;;
  detect)
    cmd_detect "$@"
    ;;
  login)
    cmd_login "$@"
    ;;
  sso-login)
    cmd_sso_login "$@"
    ;;
  sso-logout)
    cmd_sso_logout "$@"
    ;;
  assume)
    cmd_assume "$@"
    ;;
  set-profile)
    cmd_set_profile "$@"
    ;;
  list-profiles)
    cmd_list_profiles "$@"
    ;;
  list-handlers)
    cmd_list_handlers "$@"
    ;;
  test)
    cmd_test "$@"
    ;;
  clear)
    cmd_clear "$@"
    ;;
  show-env)
    cmd_show_env "$@"
    ;;
  profile-info)
    cmd_profile_info "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: $COMMAND"
    log_info "Run 'awstools auth help' for available commands"
    exit 1
    ;;
esac
