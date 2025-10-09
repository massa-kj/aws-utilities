#!/usr/bin/env bash
#=============================================================
# example-custom.sh - Example Custom Authentication Handler
#=============================================================
# This is an example of how to create a custom authentication handler
# that integrates with external authentication systems.

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

#--- Custom Handler Implementation --------------------------

#
# Handle custom external authentication
#
handle_custom_external_auth() {
  local external_system="${1:-}"
  local username="${2:-}"
  local options="${3:-}"
  
  log_debug "Custom External Authentication Handler called"
  log_debug "External system: $external_system, Username: $username"
  
  if [[ -z "$external_system" || -z "$username" ]]; then
    log_error "Custom external auth requires external system and username"
    return 1
  fi
  
  # Get configuration for this custom handler
  local api_endpoint
  api_endpoint=$(get_handler_config "custom-external" "API_ENDPOINT" "")
  
  local auth_timeout
  auth_timeout=$(get_handler_config "custom-external" "TIMEOUT" "30")
  
  local verify_ssl
  verify_ssl=$(get_handler_config "custom-external" "VERIFY_SSL" "true")
  
  if [[ -z "$api_endpoint" ]]; then
    log_error "Custom external auth requires API_ENDPOINT configuration"
    return 1
  fi
  
  log_info "Authenticating with external system: $external_system"
  log_debug "API endpoint: $api_endpoint, Timeout: ${auth_timeout}s"
  
  # Simulate external authentication API call
  local curl_args=(
    "--max-time" "$auth_timeout"
    "--silent"
    "--show-error"
    "--fail"
  )
  
  if [[ "$verify_ssl" != "true" ]]; then
    curl_args+=("--insecure")
  fi
  
  # Example: Get temporary credentials from external system
  local auth_response
  if auth_response=$(curl "${curl_args[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"system\":\"$external_system\",\"username\":\"$username\"}" \
    "$api_endpoint/auth" 2>/dev/null); then
    
    log_debug "External authentication API response received"
    
    # Parse the response (example JSON structure)
    local access_key_id secret_access_key session_token
    access_key_id=$(echo "$auth_response" | jq -r '.credentials.access_key_id // empty' 2>/dev/null || echo "")
    secret_access_key=$(echo "$auth_response" | jq -r '.credentials.secret_access_key // empty' 2>/dev/null || echo "")
    session_token=$(echo "$auth_response" | jq -r '.credentials.session_token // empty' 2>/dev/null || echo "")
    
    if [[ -n "$access_key_id" && -n "$secret_access_key" ]]; then
      log_info "External authentication successful"
      
      # Set AWS credentials in environment
      export AWS_ACCESS_KEY_ID="$access_key_id"
      export AWS_SECRET_ACCESS_KEY="$secret_access_key"
      
      if [[ -n "$session_token" ]]; then
        export AWS_SESSION_TOKEN="$session_token"
      fi
      
      # Clear profile to prevent conflicts
      unset AWS_PROFILE
      
      # Validate the credentials
      if validate_auth true; then
        log_info "External authentication validated successfully"
        return 0
      else
        log_error "External authentication validation failed"
        return 1
      fi
    else
      log_error "Invalid credentials received from external system"
      return 1
    fi
  else
    log_error "External authentication API call failed"
    return 1
  fi
}

#
# Get external authentication status
#
get_custom_external_auth_status() {
  local external_system="${1:-}"
  
  if [[ -z "$external_system" ]]; then
    log_error "External system parameter required"
    return 1
  fi
  
  # Check if we have active external credentials
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    if validate_auth true; then
      echo "active"
      return 0
    fi
  fi
  
  echo "inactive"
  return 1
}

#
# Custom authentication cleanup
#
cleanup_custom_external_auth() {
  local external_system="${1:-}"
  
  log_info "Cleaning up external authentication for: $external_system"
  
  # Clear AWS credentials
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  
  # Optional: Notify external system of logout
  local api_endpoint
  api_endpoint=$(get_handler_config "custom-external" "API_ENDPOINT" "")
  
  if [[ -n "$api_endpoint" ]]; then
    curl --max-time 10 --silent --fail \
      -X POST "$api_endpoint/logout" \
      -H "Content-Type: application/json" \
      -d "{\"system\":\"$external_system\"}" >/dev/null 2>&1 || true
  fi
  
  log_info "External authentication cleanup completed"
}

# Register this handler with the registry (if registry is available)
if command -v register_auth_handler >/dev/null 2>&1; then
  register_auth_handler "custom-external" "handle_custom_external_auth" \
    "Custom external authentication system integration" \
    "1.0.0" \
    "curl,jq"
fi

# Export handler functions
export -f handle_custom_external_auth
export -f get_custom_external_auth_status
export -f cleanup_custom_external_auth
