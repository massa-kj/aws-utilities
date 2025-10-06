#!/bin/bash
#
# Logging Library
# Provides standardized logging functionality
#

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Default configuration
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}
LOG_TIMESTAMP=${LOG_TIMESTAMP:-true}
LOG_COLOR=${LOG_COLOR:-true}
LOG_FILE=${LOG_FILE:-}

# Color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_PURPLE='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GRAY='\033[0;37m'

#
# Get timestamp string
#
get_timestamp() {
    if [[ "$LOG_TIMESTAMP" == "true" ]]; then
        date '+%Y-%m-%d %H:%M:%S'
    fi
}

#
# Get log level name
#
get_level_name() {
    local level="$1"
    case "$level" in
        "$LOG_LEVEL_DEBUG") echo "DEBUG" ;;
        "$LOG_LEVEL_INFO")  echo "INFO"  ;;
        "$LOG_LEVEL_WARN")  echo "WARN"  ;;
        "$LOG_LEVEL_ERROR") echo "ERROR" ;;
        "$LOG_LEVEL_FATAL") echo "FATAL" ;;
        *) echo "UNKNOWN" ;;
    esac
}

#
# Get color for log level
#
get_level_color() {
    local level="$1"
    if [[ "$LOG_COLOR" != "true" ]]; then
        echo ""
        return
    fi
    
    case "$level" in
        "$LOG_LEVEL_DEBUG") echo -e "$COLOR_GRAY"   ;;
        "$LOG_LEVEL_INFO")  echo -e "$COLOR_BLUE"   ;;
        "$LOG_LEVEL_WARN")  echo -e "$COLOR_YELLOW" ;;
        "$LOG_LEVEL_ERROR") echo -e "$COLOR_RED"    ;;
        "$LOG_LEVEL_FATAL") echo -e "$COLOR_PURPLE" ;;
        *) echo "" ;;
    esac
}

#
# Core logging function
#
log_message() {
    local level="$1"
    local message="$2"
    local caller="${3:-${FUNCNAME[2]}}"
    
    # Check if message should be logged based on current log level
    if [[ "$level" -lt "$LOG_LEVEL" ]]; then
        return 0
    fi
    
    local timestamp=""
    if [[ "$LOG_TIMESTAMP" == "true" ]]; then
        timestamp="$(get_timestamp) "
    fi
    
    local level_name
    level_name="$(get_level_name "$level")"
    
    local color
    color="$(get_level_color "$level")"
    
    local reset=""
    if [[ -n "$color" ]]; then
        reset="$COLOR_RESET"
    fi
    
    local log_entry="${timestamp}${color}[${level_name}]${reset} ${message}"
    
    # Output to stderr for errors and warnings, stdout for others
    if [[ "$level" -ge "$LOG_LEVEL_WARN" ]]; then
        echo -e "$log_entry" >&2
    else
        echo -e "$log_entry"
    fi
    
    # Also log to file if specified
    if [[ -n "$LOG_FILE" ]]; then
        # Remove color codes for file output
        local file_entry="${timestamp}[${level_name}] ${message}"
        echo "$file_entry" >> "$LOG_FILE"
    fi
}

#
# Logging functions for different levels
#
log_debug() {
    log_message "$LOG_LEVEL_DEBUG" "$1" "${FUNCNAME[1]}"
}

log_info() {
    log_message "$LOG_LEVEL_INFO" "$1" "${FUNCNAME[1]}"
}

log_warn() {
    log_message "$LOG_LEVEL_WARN" "$1" "${FUNCNAME[1]}"
}

log_error() {
    log_message "$LOG_LEVEL_ERROR" "$1" "${FUNCNAME[1]}"
}

log_fatal() {
    log_message "$LOG_LEVEL_FATAL" "$1" "${FUNCNAME[1]}"
}

#
# Set log level
#
set_log_level() {
    local level="$1"
    
    case "$level" in
        "debug"|"DEBUG") LOG_LEVEL="$LOG_LEVEL_DEBUG" ;;
        "info"|"INFO")   LOG_LEVEL="$LOG_LEVEL_INFO"  ;;
        "warn"|"WARN")   LOG_LEVEL="$LOG_LEVEL_WARN"  ;;
        "error"|"ERROR") LOG_LEVEL="$LOG_LEVEL_ERROR" ;;
        "fatal"|"FATAL") LOG_LEVEL="$LOG_LEVEL_FATAL" ;;
        [0-4]) LOG_LEVEL="$level" ;;
        *)
            log_error "Invalid log level: $level"
            return 1
            ;;
    esac
    
    log_debug "Log level set to: $(get_level_name "$LOG_LEVEL")"
}

#
# Set log file
#
set_log_file() {
    local file_path="$1"
    
    # Create directory if it doesn't exist
    local dir_path
    dir_path="$(dirname "$file_path")"
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path" || {
            log_error "Failed to create log directory: $dir_path"
            return 1
        }
    fi
    
    # Test if file is writable
    if ! touch "$file_path" 2>/dev/null; then
        log_error "Cannot write to log file: $file_path"
        return 1
    fi
    
    LOG_FILE="$file_path"
    log_info "Log file set to: $file_path"
}

#
# Enable/disable colored output
#
set_log_color() {
    local enabled="$1"
    if [[ "$enabled" == "true" || "$enabled" == "1" ]]; then
        LOG_COLOR=true
    else
        LOG_COLOR=false
    fi
}

#
# Enable/disable timestamp
#
set_log_timestamp() {
    local enabled="$1"
    if [[ "$enabled" == "true" || "$enabled" == "1" ]]; then
        LOG_TIMESTAMP=true
    else
        LOG_TIMESTAMP=false
    fi
}

#
# Progress indicator for long-running operations
#
show_progress() {
    local message="$1"
    local pid="$2"
    
    local chars="/-\|"
    local i=0
    
    log_info "$message"
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${message} %c" "${chars:$((i % 4)):1}"
        sleep 0.2
        ((i++))
    done
    
    printf "\r%s ✓\n" "$message"
}

# Export functions and variables
export LOG_LEVEL LOG_TIMESTAMP LOG_COLOR LOG_FILE
export LOG_LEVEL_DEBUG LOG_LEVEL_INFO LOG_LEVEL_WARN LOG_LEVEL_ERROR LOG_LEVEL_FATAL

export -f log_debug log_info log_warn log_error log_fatal
export -f set_log_level set_log_file set_log_color set_log_timestamp
export -f show_progress
