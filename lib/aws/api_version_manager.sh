#!/bin/bash
#
# API Version Manager
# Handles different versions of AWS API implementations
#

# API version configuration
readonly DEFAULT_API_VERSION="v1"
readonly SUPPORTED_API_VERSIONS=("v1")
readonly API_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../services/quicksight/src/api" && pwd)"

# Current API version state
CURRENT_API_VERSION="$DEFAULT_API_VERSION"
API_CAPABILITIES=()

#
# Set API version
#
set_api_version() {
    local version="$1"
    
    if [[ -z "$version" ]]; then
        log_error "API version is required"
        return 1
    fi
    
    # Validate version format
    if [[ ! "$version" =~ ^v[0-9]+$ ]]; then
        log_error "Invalid API version format: $version (expected: v1, v2, etc.)"
        return 1
    fi
    
    # Check if version is supported
    local supported=false
    for supported_version in "${SUPPORTED_API_VERSIONS[@]}"; do
        if [[ "$version" == "$supported_version" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" != "true" ]]; then
        log_error "Unsupported API version: $version"
        log_info "Supported versions: ${SUPPORTED_API_VERSIONS[*]}"
        return 1
    fi
    
    CURRENT_API_VERSION="$version"
    log_debug "API version set to: $version"
    
    # Load version-specific capabilities
    load_api_capabilities "$version"
    
    return 0
}

#
# Get current API version
#
get_api_version() {
    echo "$CURRENT_API_VERSION"
}

#
# Load API capabilities for a specific version
#
load_api_capabilities() {
    local version="$1"
    local capabilities_file="$API_BASE_DIR/$version/capabilities.conf"
    
    API_CAPABILITIES=()
    
    if [[ -f "$capabilities_file" ]]; then
        log_debug "Loading API capabilities from: $capabilities_file"
        
        while IFS= read -r capability; do
            # Skip comments and empty lines
            if [[ "$capability" =~ ^[[:space:]]*# ]] || [[ -z "$capability" ]]; then
                continue
            fi
            API_CAPABILITIES+=("$capability")
        done < "$capabilities_file"
        
        log_debug "Loaded ${#API_CAPABILITIES[@]} API capabilities"
    else
        log_warn "API capabilities file not found: $capabilities_file"
    fi
}

#
# Check if API supports a specific capability
#
api_supports() {
    local capability="$1"
    
    if [[ -z "$capability" ]]; then
        log_error "Capability name is required"
        return 1
    fi
    
    for supported_capability in "${API_CAPABILITIES[@]}"; do
        if [[ "$capability" == "$supported_capability" ]]; then
            return 0
        fi
    done
    
    return 1
}

#
# Load API implementation for current version
#
load_api_implementation() {
    local service="$1"
    local resource="${2:-}"
    
    if [[ -z "$service" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    local api_file
    if [[ -n "$resource" ]]; then
        api_file="$API_BASE_DIR/$CURRENT_API_VERSION/${service}_${resource}_api.sh"
    else
        api_file="$API_BASE_DIR/$CURRENT_API_VERSION/${service}_api.sh"
    fi
    
    if [[ ! -f "$api_file" ]]; then
        log_error "API implementation not found: $api_file"
        return 1
    fi
    
    log_debug "Loading API implementation: $api_file"
    
    # Source the API implementation
    # shellcheck source=/dev/null
    source "$api_file" || {
        log_error "Failed to load API implementation: $api_file"
        return 1
    }
    
    return 0
}

#
# Execute API call with version-specific implementation
#
call_api() {
    local operation="$1"
    shift
    local args=("$@")
    
    if [[ -z "$operation" ]]; then
        log_error "API operation is required"
        return 1
    fi
    
    # Check if operation is supported in current API version
    local operation_function="${operation}_${CURRENT_API_VERSION}"
    
    if [[ "$(type -t "$operation_function" 2>/dev/null)" != "function" ]]; then
        # Try generic operation function
        operation_function="$operation"
        
        if [[ "$(type -t "$operation_function" 2>/dev/null)" != "function" ]]; then
            log_error "API operation not supported in version $CURRENT_API_VERSION: $operation"
            return 1
        fi
    fi
    
    log_debug "Calling API operation: $operation_function with ${#args[@]} arguments"
    
    # Execute the operation
    "$operation_function" "${args[@]}"
}

#
# Auto-detect best API version based on AWS CLI capabilities
#
auto_detect_api_version() {
    local service="${1:-quicksight}"
    
    log_info "Auto-detecting best API version for service: $service"
    
    # Try to detect API version by checking AWS CLI version and capabilities
    local aws_version
    aws_version=$(aws --version 2>&1 | head -n1 | cut -d/ -f2 | cut -d' ' -f1)
    
    log_debug "AWS CLI version: $aws_version"
    
    # For now, default to v1
    # In the future, add logic to detect newer API versions
    local detected_version="v1"
    
    log_info "Detected API version: $detected_version"
    set_api_version "$detected_version"
}

#
# List available API versions
#
list_api_versions() {
    echo "Available API versions:"
    
    for version in "${SUPPORTED_API_VERSIONS[@]}"; do
        local status="available"
        local capabilities_count=0
        
        # Load capabilities to get count
        local capabilities_file="$API_BASE_DIR/$version/capabilities.conf"
        if [[ -f "$capabilities_file" ]]; then
            capabilities_count=$(grep -cv "^[[:space:]]*#\|^[[:space:]]*$" "$capabilities_file" 2>/dev/null || echo "0")
        fi
        
        local current_marker=""
        if [[ "$version" == "$CURRENT_API_VERSION" ]]; then
            current_marker=" (current)"
        fi
        
        echo "  - $version: $status ($capabilities_count capabilities)$current_marker"
    done
}

#
# Show API version compatibility information
#
show_api_compatibility() {
    echo "=== API Version Compatibility ==="
    echo "Current version: $CURRENT_API_VERSION"
    echo "Default version: $DEFAULT_API_VERSION"
    echo
    
    list_api_versions
    echo
    
    echo "Current API capabilities:"
    if [[ ${#API_CAPABILITIES[@]} -eq 0 ]]; then
        echo "  (no capabilities loaded)"
    else
        for capability in "${API_CAPABILITIES[@]}"; do
            echo "  - $capability"
        done
    fi
}

#
# Migrate between API versions
#
migrate_api_version() {
    local from_version="$1"
    local to_version="$2"
    
    if [[ -z "$from_version" ]] || [[ -z "$to_version" ]]; then
        log_error "Both from_version and to_version are required"
        return 1
    fi
    
    log_info "Migrating API version from $from_version to $to_version"
    
    # Validate target version
    if ! set_api_version "$to_version"; then
        return 1
    fi
    
    # Check for breaking changes
    local migration_script="$API_BASE_DIR/migrations/${from_version}_to_${to_version}.sh"
    
    if [[ -f "$migration_script" ]]; then
        log_info "Running migration script: $migration_script"
        
        # shellcheck source=/dev/null
        source "$migration_script" || {
            log_error "Migration script failed"
            return 1
        }
    else
        log_info "No migration script needed for $from_version -> $to_version"
    fi
    
    log_info "API version migration completed successfully"
    return 0
}

# Initialize with default API version
set_api_version "$DEFAULT_API_VERSION"

# Export functions
export -f set_api_version get_api_version load_api_capabilities api_supports
export -f load_api_implementation call_api auto_detect_api_version
export -f list_api_versions show_api_compatibility migrate_api_version
