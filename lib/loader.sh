#!/bin/bash
#
# Library Loader
# Central loader for all common libraries
#

# Get the directory where this script is located
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load order is important due to dependencies
LIBRARIES=(
    "utils/logger.sh"
    "aws/error_handler.sh"
    "utils/validation.sh"
    "utils/json_parser.sh"
    "utils/config_manager.sh"
    "aws/auth.sh"
    "aws/api_version_manager.sh"
)

#
# Load a single library
#
load_library() {
    local lib_path="$1"
    local full_path="$LIB_DIR/$lib_path"
    
    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Library not found: $full_path" >&2
        return 1
    fi
    
    # Source the library
    # shellcheck source=/dev/null
    source "$full_path" || {
        echo "ERROR: Failed to load library: $lib_path" >&2
        return 1
    }
    
    return 0
}

#
# Load all libraries
#
load_all_libraries() {
    local failed_libraries=()
    
    for lib in "${LIBRARIES[@]}"; do
        if ! load_library "$lib"; then
            failed_libraries+=("$lib")
        fi
    done
    
    if [[ ${#failed_libraries[@]} -gt 0 ]]; then
        echo "ERROR: Failed to load the following libraries:" >&2
        printf "  - %s\n" "${failed_libraries[@]}" >&2
        return 1
    fi
    
    return 0
}

#
# Initialize libraries with default settings
#
initialize_libraries() {
    # Set default log level if not already set
    if [[ -z "${LOG_LEVEL:-}" ]]; then
        set_log_level "info"
    fi
    
    # Enable error handling by default
    if [[ "${ERROR_HANDLER_ENABLED:-}" != "false" ]]; then
        ERROR_HANDLER_ENABLED=true
    fi
    
    # Set up basic error trap
    set_error_trap cleanup_on_exit
    
    log_debug "Libraries initialized successfully"
}

# Auto-load libraries when this file is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # This file is being sourced, not executed
    if load_all_libraries; then
        initialize_libraries
        log_debug "AWS Utilities libraries loaded successfully"
    else
        echo "ERROR: Failed to load AWS Utilities libraries" >&2
        return 1 2>/dev/null || exit 1
    fi
fi

# Export the loader functions
export -f load_library load_all_libraries initialize_libraries
