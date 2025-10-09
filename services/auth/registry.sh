#!/usr/bin/env bash
#=============================================================
# registry.sh - Authentication Handler Registry System
#=============================================================

set -euo pipefail

# Load dependencies (avoid circular dependency with lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load only essential dependencies
if [[ -z "${AWS_TOOLS_LOGGER_LOADED:-}" ]]; then
  source "$BASE_DIR/common/logger.sh"
  export AWS_TOOLS_LOGGER_LOADED=1
fi

#--- Registry Configuration ---------------------------------

# Handler registry
declare -A AUTH_HANDLERS=()
declare -A HANDLER_METADATA=()
declare -A HANDLER_CONFIG=()

# Hook registry
declare -A AUTH_HOOKS=()

# Registry state
REGISTRY_INITIALIZED=false
HANDLERS_DIR="${SCRIPT_DIR}/handlers"
HOOKS_DIR="${SCRIPT_DIR}/hooks"
CONFIG_DIR="${SCRIPT_DIR}/config"

#--- Registry Initialization --------------------------------

#
# Initialize the authentication registry
#
init_auth_registry() {
  if [[ "$REGISTRY_INITIALIZED" == "true" ]]; then
    return 0
  fi
  
  log_debug "Initializing authentication registry"
  
  # Load built-in handlers
  load_builtin_handlers
  
  # Load custom handlers
  load_custom_handlers
  
  # Load hooks
  load_auth_hooks
  
  REGISTRY_INITIALIZED=true
  log_debug "Authentication registry initialized with ${#AUTH_HANDLERS[@]} handlers"
}

#--- Handler Management ------------------------------------

#
# Register an authentication handler
#
register_auth_handler() {
  local name="$1"
  local handler_function="$2"
  local description="${3:-}"
  local version="${4:-1.0.0}"
  local dependencies="${5:-}"
  
  if [[ -z "$name" || -z "$handler_function" ]]; then
    log_error "Handler name and function are required"
    return 1
  fi
  
  AUTH_HANDLERS["$name"]="$handler_function"
  HANDLER_METADATA["$name"]="$description|$version|$dependencies"
  
  log_debug "Registered authentication handler: $name -> $handler_function"
}

#
# Get authentication handler function
#
get_auth_handler() {
  local name="$1"
  
  if [[ -z "$name" ]]; then
    log_error "Handler name is required"
    return 1
  fi
  
  if [[ -n "${AUTH_HANDLERS[$name]:-}" ]]; then
    echo "${AUTH_HANDLERS[$name]}"
    return 0
  else
    return 1
  fi
}

#
# Check if handler exists
#
handler_exists() {
  local name="$1"
  [[ -n "${AUTH_HANDLERS[$name]:-}" ]]
}

#
# List available handlers
#
list_auth_handlers() {
  local format="${1:-table}"
  
  if [[ ${#AUTH_HANDLERS[@]} -eq 0 ]]; then
    echo "No authentication handlers registered"
    return 0
  fi
  
  case "$format" in
    table)
      echo "Available Authentication Handlers:"
      echo "=================================="
      printf "%-20s %-15s %-50s\n" "NAME" "VERSION" "DESCRIPTION"
      printf "%-20s %-15s %-50s\n" "----" "-------" "-----------"
      
      for handler in "${!AUTH_HANDLERS[@]}"; do
        local metadata="${HANDLER_METADATA[$handler]:-||}"
        IFS='|' read -r description version dependencies <<< "$metadata"
        printf "%-20s %-15s %-50s\n" "$handler" "${version:-1.0.0}" "${description:-No description}"
      done
      ;;
    
    json)
      echo "{"
      local first=true
      for handler in "${!AUTH_HANDLERS[@]}"; do
        local metadata="${HANDLER_METADATA[$handler]:-||}"
        IFS='|' read -r description version dependencies <<< "$metadata"
        
        if [[ "$first" == "true" ]]; then
          first=false
        else
          echo ","
        fi
        
        echo -n "  \"$handler\": {"
        echo -n "\"function\": \"${AUTH_HANDLERS[$handler]}\", "
        echo -n "\"description\": \"${description:-}\", "
        echo -n "\"version\": \"${version:-1.0.0}\", "
        echo -n "\"dependencies\": \"${dependencies:-}\""
        echo -n "}"
      done
      echo ""
      echo "}"
      ;;
    
    names)
      for handler in "${!AUTH_HANDLERS[@]}"; do
        echo "$handler"
      done
      ;;
    
    *)
      log_error "Unknown format: $format. Supported: table, json, names"
      return 1
      ;;
  esac
}

#--- Built-in Handler Loading ------------------------------

#
# Load built-in authentication handlers
#
load_builtin_handlers() {
  log_debug "Loading built-in authentication handlers"
  
  # SSO Handler
  register_auth_handler "sso" "handle_sso_auth" \
    "AWS SSO (IAM Identity Center) authentication" \
    "2.0.0" \
    "aws-cli>=2.0"
  
  # Access Key Handler
  register_auth_handler "accesskey" "handle_accesskey_auth" \
    "Static AWS access key authentication" \
    "2.0.0" \
    "aws-cli>=2.0"
  
  # Assume Role Handler
  register_auth_handler "assume" "handle_assume_role_auth" \
    "AWS role assumption authentication" \
    "2.0.0" \
    "aws-cli>=2.0"
  
  # Instance Profile Handler
  register_auth_handler "instance-profile" "handle_instance_profile_auth" \
    "EC2 instance profile authentication" \
    "2.0.0" \
    "aws-cli>=2.0"
  
  # Web Identity Handler
  register_auth_handler "web-identity" "handle_web_identity_auth" \
    "Web identity token authentication (EKS, etc.)" \
    "2.0.0" \
    "aws-cli>=2.0"
  
  # Environment Variables Handler
  register_auth_handler "env-vars" "handle_env_vars_auth" \
    "Environment variable authentication" \
    "2.0.0" \
    "aws-cli>=2.0"
}

#--- Custom Handler Loading --------------------------------

#
# Load custom authentication handlers from handlers directory
#
load_custom_handlers() {
  if [[ ! -d "$HANDLERS_DIR" ]]; then
    log_debug "No custom handlers directory found: $HANDLERS_DIR"
    return 0
  fi
  
  log_debug "Loading custom handlers from: $HANDLERS_DIR"
  
  for handler_file in "$HANDLERS_DIR"/*.sh; do
    if [[ -f "$handler_file" ]]; then
      local handler_name
      handler_name=$(basename "$handler_file" .sh)
      
      log_debug "Loading custom handler: $handler_name"
      
      # Source the handler file safely
      if source "$handler_file" 2>/dev/null; then
        log_debug "Successfully loaded custom handler: $handler_name"
      else
        log_warn "Failed to load custom handler: $handler_file"
      fi
    fi
  done
}

#--- Hook Management ---------------------------------------

#
# Register an authentication hook
#
register_auth_hook() {
  local hook_type="$1"  # pre-auth, post-auth, auth-failed, etc.
  local hook_function="$2"
  local priority="${3:-100}"
  
  if [[ -z "$hook_type" || -z "$hook_function" ]]; then
    log_error "Hook type and function are required"
    return 1
  fi
  
  # Initialize hook array if it doesn't exist
  if [[ -z "${AUTH_HOOKS[$hook_type]:-}" ]]; then
    AUTH_HOOKS["$hook_type"]=""
  fi
  
  # Add hook with priority
  AUTH_HOOKS["$hook_type"]+="${priority}:${hook_function}|"
  
  log_debug "Registered auth hook: $hook_type -> $hook_function (priority: $priority)"
}

#
# Execute authentication hooks
#
execute_auth_hooks() {
  local hook_type="$1"
  shift
  local hook_args=("$@")
  
  if [[ -z "${AUTH_HOOKS[$hook_type]:-}" ]]; then
    log_debug "No hooks registered for: $hook_type"
    return 0
  fi
  
  log_debug "Executing hooks for: $hook_type"
  
  # Sort hooks by priority and execute
  local hooks_string="${AUTH_HOOKS[$hook_type]}"
  local hooks_array
  IFS='|' read -ra hooks_array <<< "$hooks_string"
  
  # Sort by priority (lower number = higher priority)
  local sorted_hooks
  readarray -t sorted_hooks < <(printf '%s\n' "${hooks_array[@]}" | grep -v '^$' | sort -n)
  
  for hook_entry in "${sorted_hooks[@]}"; do
    if [[ -n "$hook_entry" ]]; then
      local priority_and_function="${hook_entry}"
      local hook_function="${priority_and_function#*:}"
      
      log_debug "Executing hook: $hook_function"
      
      # Execute the hook function with provided arguments
      if command -v "$hook_function" >/dev/null 2>&1; then
        "$hook_function" "${hook_args[@]}" || {
          log_warn "Hook function failed: $hook_function"
        }
      else
        log_warn "Hook function not found: $hook_function"
      fi
    fi
  done
}

#
# Load authentication hooks from hooks directory
#
load_auth_hooks() {
  if [[ ! -d "$HOOKS_DIR" ]]; then
    log_debug "No hooks directory found: $HOOKS_DIR"
    return 0
  fi
  
  log_debug "Loading authentication hooks from: $HOOKS_DIR"
  
  for hook_file in "$HOOKS_DIR"/*.sh; do
    if [[ -f "$hook_file" ]]; then
      local hook_name
      hook_name=$(basename "$hook_file" .sh)
      
      log_debug "Loading hook file: $hook_name"
      
      # Source the hook file safely
      if source "$hook_file" 2>/dev/null; then
        log_debug "Successfully loaded hook file: $hook_name"
      else
        log_warn "Failed to load hook file: $hook_file"
      fi
    fi
  done
}

#--- Handler Execution -------------------------------------

#
# Execute authentication handler with hooks
#
execute_auth_handler() {
  local handler_name="$1"
  shift
  local handler_args=("$@")
  
  if ! handler_exists "$handler_name"; then
    log_error "Authentication handler not found: $handler_name"
    return 1
  fi
  
  # Execute pre-auth hooks
  execute_auth_hooks "pre-auth" "$handler_name" "${handler_args[@]}"
  
  # Get and execute the handler function
  local handler_function
  handler_function=$(get_auth_handler "$handler_name")
  
  log_debug "Executing authentication handler: $handler_name -> $handler_function"
  
  local result=0
  if command -v "$handler_function" >/dev/null 2>&1; then
    "$handler_function" "${handler_args[@]}" || result=$?
  else
    log_error "Handler function not found: $handler_function"
    result=1
  fi
  
  # Execute appropriate post-hooks
  if [[ $result -eq 0 ]]; then
    execute_auth_hooks "post-auth-success" "$handler_name" "${handler_args[@]}"
    execute_auth_hooks "post-auth" "$handler_name" "${handler_args[@]}"
  else
    execute_auth_hooks "post-auth-failure" "$handler_name" "${handler_args[@]}"
    execute_auth_hooks "post-auth" "$handler_name" "${handler_args[@]}"
  fi
  
  return $result
}

#--- Configuration Management ------------------------------

#
# Load handler configuration
#
load_handler_config() {
  local handler_name="$1"
  
  local config_file="$CONFIG_DIR/${handler_name}.conf"
  
  if [[ -f "$config_file" ]]; then
    log_debug "Loading configuration for handler: $handler_name"
    source "$config_file"
    HANDLER_CONFIG["$handler_name"]="loaded"
    return 0
  else
    log_debug "No configuration file found for handler: $handler_name"
    return 1
  fi
}

#
# Get handler configuration value
#
get_handler_config() {
  local handler_name="$1"
  local config_key="$2"
  local default_value="${3:-}"
  
  # Load config if not already loaded
  if [[ -z "${HANDLER_CONFIG[$handler_name]:-}" ]]; then
    load_handler_config "$handler_name"
  fi
  
  # Return the configuration value
  local var_name="${handler_name^^}_${config_key^^}"
  var_name="${var_name//-/_}"
  
  echo "${!var_name:-$default_value}"
}

# Export registry functions
export -f init_auth_registry
export -f register_auth_handler
export -f get_auth_handler
export -f handler_exists
export -f list_auth_handlers
export -f register_auth_hook
export -f execute_auth_hooks
export -f execute_auth_handler
export -f load_handler_config
export -f get_handler_config
