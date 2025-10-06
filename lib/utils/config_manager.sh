#!/bin/bash
#
# Configuration Management Library
# Handles loading and validation of configuration files
#

# Configuration paths
readonly CONFIG_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
readonly GLOBAL_CONFIG="$CONFIG_BASE_DIR/global.env"
readonly SERVICES_CONFIG_DIR="$CONFIG_BASE_DIR/services"
readonly ENVIRONMENTS_CONFIG_DIR="$CONFIG_BASE_DIR/environments"

# Configuration state
CONFIG_LOADED=false
CURRENT_ENVIRONMENT=""
LOADED_SERVICES=()

#
# Load global configuration
#
load_global_config() {
    if [[ ! -f "$GLOBAL_CONFIG" ]]; then
        log_error "Global configuration file not found: $GLOBAL_CONFIG"
        return 1
    fi
    
    log_debug "Loading global configuration from: $GLOBAL_CONFIG"
    
    # Source global configuration
    # shellcheck source=/dev/null
    source "$GLOBAL_CONFIG" || {
        log_error "Failed to load global configuration"
        return 1
    }
    
    return 0
}

#
# Load service configuration
#
load_service_config() {
    local service="$1"
    
    if [[ -z "$service" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    local service_config="$SERVICES_CONFIG_DIR/${service}.env"
    
    if [[ ! -f "$service_config" ]]; then
        log_error "Service configuration file not found: $service_config"
        return 1
    fi
    
    log_debug "Loading $service configuration from: $service_config"
    
    # Source service configuration
    # shellcheck source=/dev/null
    source "$service_config" || {
        log_error "Failed to load $service configuration"
        return 1
    }
    
    # Track loaded services
    if [[ ! " ${LOADED_SERVICES[*]} " =~ $service ]]; then
        LOADED_SERVICES+=("$service")
    fi
    
    return 0
}

#
# Load environment configuration
#
load_environment_config() {
    local environment="$1"
    
    if [[ -z "$environment" ]]; then
        log_debug "No environment specified, skipping environment config"
        return 0
    fi
    
    local env_config="$ENVIRONMENTS_CONFIG_DIR/${environment}.conf"
    
    if [[ ! -f "$env_config" ]]; then
        log_warn "Environment configuration file not found: $env_config"
        return 1
    fi
    
    log_debug "Loading $environment environment configuration from: $env_config"
    
    # Source environment configuration
    # shellcheck source=/dev/null
    source "$env_config" || {
        log_error "Failed to load $environment environment configuration"
        return 1
    }
    
    CURRENT_ENVIRONMENT="$environment"
    return 0
}

#
# Initialize configuration system
#
init_config() {
    local service="${1:-}"
    local environment="${2:-}"
    
    log_debug "Initializing configuration system..."
    
    # Load in order: global -> service -> environment
    if ! load_global_config; then
        return 1
    fi
    
    if [[ -n "$service" ]]; then
        if ! load_service_config "$service"; then
            return 1
        fi
    fi
    
    if [[ -n "$environment" ]]; then
        if ! load_environment_config "$environment"; then
            return 1
        fi
    fi
    
    CONFIG_LOADED=true
    log_debug "Configuration system initialized successfully"
    
    return 0
}

#
# Validate required configuration variables
#
validate_config() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        local missing_list=$(IFS=', '; echo "${missing_vars[*]}")
        log_error "Missing required configuration variables: $missing_list"
        return 1
    fi
    
    return 0
}

#
# Get configuration value with default
#
get_config() {
    local var_name="$1"
    local default_value="${2:-}"
    
    local value="${!var_name:-$default_value}"
    echo "$value"
}

#
# Set configuration value
#
set_config() {
    local var_name="$1"
    local value="$2"
    
    if [[ -z "$var_name" ]]; then
        log_error "Variable name is required"
        return 1
    fi
    
    # Use declare to set the variable in global scope
    declare -g "$var_name"="$value"
    log_debug "Set configuration: $var_name=$value"
}

#
# Show current configuration
#
show_config() {
    local filter_pattern="${1:-.*}"
    
    echo "=== Current Configuration ==="
    echo "Environment: ${CURRENT_ENVIRONMENT:-"(none)"}"
    echo "Loaded services: ${LOADED_SERVICES[*]:-"(none)"}"
    echo
    
    # Show environment variables matching pattern
    echo "Configuration variables:"
    env | grep -E "^($filter_pattern)" | sort | while IFS='=' read -r key value; do
        echo "  $key = $value"
    done
}

#
# List available environments
#
list_environments() {
    echo "Available environments:"
    
    if [[ -d "$ENVIRONMENTS_CONFIG_DIR" ]]; then
        for config_file in "$ENVIRONMENTS_CONFIG_DIR"/*.conf; do
            if [[ -f "$config_file" ]]; then
                local env_name
                env_name="$(basename "$config_file" .conf)"
                echo "  - $env_name"
            fi
        done
    else
        echo "  (no environments configured)"
    fi
}

#
# List available services
#
list_services() {
    echo "Available services:"
    
    if [[ -d "$SERVICES_CONFIG_DIR" ]]; then
        for config_file in "$SERVICES_CONFIG_DIR"/*.env; do
            if [[ -f "$config_file" ]]; then
                local service_name
                service_name="$(basename "$config_file" .env)"
                echo "  - $service_name"
            fi
        done
    else
        echo "  (no services configured)"
    fi
}

#
# Backup current configuration
#
backup_config() {
    local backup_file="${1:-config-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
    
    log_info "Creating configuration backup: $backup_file"
    
    tar -czf "$backup_file" -C "$(dirname "$CONFIG_BASE_DIR")" "$(basename "$CONFIG_BASE_DIR")" || {
        log_error "Failed to create configuration backup"
        return 1
    }
    
    log_info "Configuration backup created: $backup_file"
    return 0
}

# Export functions
export -f load_global_config load_service_config load_environment_config
export -f init_config validate_config get_config set_config show_config
export -f list_environments list_services backup_config
