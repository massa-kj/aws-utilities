#!/bin/bash
#
# Error Handling Library
# Provides standardized error handling and exit codes
#

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_MISUSE=2
readonly EXIT_CONFIG_ERROR=3
readonly EXIT_AUTH_ERROR=4
readonly EXIT_NETWORK_ERROR=5
readonly EXIT_RESOURCE_NOT_FOUND=6
readonly EXIT_PERMISSION_ERROR=7
readonly EXIT_VALIDATION_ERROR=8

# Error handling flags
ERROR_HANDLER_ENABLED=true
STRICT_MODE=false
DEBUG_MODE=false

#
# Enable strict error handling
#
enable_strict_mode() {
    set -euo pipefail
    STRICT_MODE=true
    log_debug "Strict mode enabled"
}

#
# Disable strict error handling
#
disable_strict_mode() {
    set +euo pipefail
    STRICT_MODE=false
    log_debug "Strict mode disabled"
}

#
# Set error trap for cleanup
#
set_error_trap() {
    local cleanup_function="$1"
    
    if [[ -n "$cleanup_function" ]] && [[ "$(type -t "$cleanup_function" 2>/dev/null)" == "function" ]]; then
        trap "$cleanup_function" ERR EXIT
        log_debug "Error trap set to function: $cleanup_function"
    else
        log_error "Invalid cleanup function: $cleanup_function"
        return 1
    fi
}

#
# Handle errors with context
#
handle_error() {
    local exit_code="${1:-$EXIT_GENERAL_ERROR}"
    local message="${2:-"An error occurred"}"
    local line_number="${3:-${LINENO}}"
    local function_name="${4:-${FUNCNAME[1]}}"
    local script_name="${5:-${BASH_SOURCE[1]}}"
    
    log_error "Error in $script_name:$function_name():$line_number - $message (exit code: $exit_code)"
    
    if [[ "$ERROR_HANDLER_ENABLED" == "true" ]]; then
        exit "$exit_code"
    fi
    
    return "$exit_code"
}

#
# Validate required parameters
#
validate_required_params() {
    local params=("$@")
    local missing_params=()
    
    for param in "${params[@]}"; do
        if [[ -z "${!param:-}" ]]; then
            missing_params+=("$param")
        fi
    done
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        local missing_list=$(IFS=', '; echo "${missing_params[*]}")
        handle_error "$EXIT_VALIDATION_ERROR" "Missing required parameters: $missing_list"
        return 1
    fi
    
    return 0
}

#
# Validate file existence
#
validate_file_exists() {
    local file_path="$1"
    local error_message="${2:-"File not found: $file_path"}"
    
    if [[ ! -f "$file_path" ]]; then
        handle_error "$EXIT_RESOURCE_NOT_FOUND" "$error_message"
        return 1
    fi
    
    return 0
}

#
# Validate directory existence
#
validate_directory_exists() {
    local dir_path="$1"
    local error_message="${2:-"Directory not found: $dir_path"}"
    
    if [[ ! -d "$dir_path" ]]; then
        handle_error "$EXIT_RESOURCE_NOT_FOUND" "$error_message"
        return 1
    fi
    
    return 0
}

#
# Validate command availability
#
validate_command_exists() {
    local command_name="$1"
    local error_message="${2:-"Command not found: $command_name"}"
    
    if ! command -v "$command_name" >/dev/null 2>&1; then
        handle_error "$EXIT_CONFIG_ERROR" "$error_message"
        return 1
    fi
    
    return 0
}

#
# Retry mechanism for commands
#
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt of $max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        fi
        
        local exit_code=$?
        log_warn "Command failed on attempt $attempt (exit code: $exit_code)"
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_info "Retrying in $delay seconds..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    handle_error "$EXIT_GENERAL_ERROR" "Command failed after $max_attempts attempts: ${command[*]}"
    return 1
}

#
# Safe cleanup function template
#
cleanup_on_exit() {
    local exit_code=$?
    
    log_debug "Cleanup function called with exit code: $exit_code"
    
    # Add cleanup logic here
    # Example: remove temporary files, close connections, etc.
    
    return "$exit_code"
}

# Export functions and variables
export ERROR_HANDLER_ENABLED STRICT_MODE DEBUG_MODE
export EXIT_SUCCESS EXIT_GENERAL_ERROR EXIT_MISUSE EXIT_CONFIG_ERROR
export EXIT_AUTH_ERROR EXIT_NETWORK_ERROR EXIT_RESOURCE_NOT_FOUND
export EXIT_PERMISSION_ERROR EXIT_VALIDATION_ERROR

export -f enable_strict_mode disable_strict_mode set_error_trap
export -f handle_error validate_required_params validate_file_exists
export -f validate_directory_exists validate_command_exists retry_command
export -f cleanup_on_exit
