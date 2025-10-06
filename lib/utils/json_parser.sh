#!/bin/bash
#
# JSON Parser Library
# Provides safe JSON parsing and manipulation functions
#

# Dependency check
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed" >&2
    exit 1
fi

#
# Validate JSON format
#
json_validate() {
    local json_input="$1"
    local input_type="${2:-string}"  # string, file
    
    case "$input_type" in
        "string")
            if ! echo "$json_input" | jq . >/dev/null 2>&1; then
                log_error "Invalid JSON format"
                return 1
            fi
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            if ! jq . "$json_input" >/dev/null 2>&1; then
                log_error "Invalid JSON format in file: $json_input"
                return 1
            fi
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    return 0
}

#
# Extract value from JSON
#
json_get() {
    local json_input="$1"
    local path="$2"
    local input_type="${3:-string}"  # string, file
    local default_value="${4:-null}"
    
    local result
    
    case "$input_type" in
        "string")
            result=$(echo "$json_input" | jq -r "$path // \"$default_value\"" 2>/dev/null)
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            result=$(jq -r "$path // \"$default_value\"" "$json_input" 2>/dev/null)
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to extract JSON path: $path"
        return 1
    fi
    
    echo "$result"
}

#
# Set value in JSON
#
json_set() {
    local json_input="$1"
    local path="$2"
    local value="$3"
    local input_type="${4:-string}"  # string, file
    
    local result
    local jq_expression
    
    # Determine if value should be treated as string or raw JSON
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]] || [[ "$value" == "null" ]]; then
        # Numeric, boolean, or null value
        jq_expression="$path = $value"
    else
        # String value
        jq_expression="$path = \"$value\""
    fi
    
    case "$input_type" in
        "string")
            result=$(echo "$json_input" | jq "$jq_expression" 2>/dev/null)
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            result=$(jq "$jq_expression" "$json_input" 2>/dev/null)
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to set JSON path: $path"
        return 1
    fi
    
    echo "$result"
}

#
# Delete key from JSON
#
json_delete() {
    local json_input="$1"
    local path="$2"
    local input_type="${3:-string}"  # string, file
    
    local result
    
    case "$input_type" in
        "string")
            result=$(echo "$json_input" | jq "del($path)" 2>/dev/null)
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            result=$(jq "del($path)" "$json_input" 2>/dev/null)
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to delete JSON path: $path"
        return 1
    fi
    
    echo "$result"
}

#
# Merge JSON objects
#
json_merge() {
    local json1="$1"
    local json2="$2"
    local input_type="${3:-string}"  # string, file
    
    local result
    
    case "$input_type" in
        "string")
            result=$(echo "$json1" | jq -s ".[0] * .[1]" - <(echo "$json2") 2>/dev/null)
            ;;
        "file")
            if [[ ! -f "$json1" ]] || [[ ! -f "$json2" ]]; then
                log_error "One or both JSON files not found: $json1, $json2"
                return 1
            fi
            result=$(jq -s ".[0] * .[1]" "$json1" "$json2" 2>/dev/null)
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to merge JSON objects"
        return 1
    fi
    
    echo "$result"
}

#
# Get array length
#
json_array_length() {
    local json_input="$1"
    local path="${2:-.}"
    local input_type="${3:-string}"  # string, file
    
    local result
    
    case "$input_type" in
        "string")
            result=$(echo "$json_input" | jq -r "($path | length)" 2>/dev/null)
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            result=$(jq -r "($path | length)" "$json_input" 2>/dev/null)
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get array length for path: $path"
        return 1
    fi
    
    echo "$result"
}

#
# Pretty print JSON
#
json_pretty() {
    local json_input="$1"
    local input_type="${2:-string}"  # string, file
    
    case "$input_type" in
        "string")
            echo "$json_input" | jq .
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            jq . "$json_input"
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
}

#
# Compact JSON (remove whitespace)
#
json_compact() {
    local json_input="$1"
    local input_type="${2:-string}"  # string, file
    
    case "$input_type" in
        "string")
            echo "$json_input" | jq -c .
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            jq -c . "$json_input"
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
}

#
# Convert JSON to shell variables (for simple key-value objects)
#
json_to_vars() {
    local json_input="$1"
    local prefix="${2:-}"
    local input_type="${3:-string}"  # string, file
    
    local json_data
    
    case "$input_type" in
        "string")
            json_data="$json_input"
            ;;
        "file")
            if [[ ! -f "$json_input" ]]; then
                log_error "JSON file not found: $json_input"
                return 1
            fi
            json_data=$(cat "$json_input")
            ;;
        *)
            log_error "Invalid input type: $input_type"
            return 1
            ;;
    esac
    
    # Convert JSON keys to shell variables
    echo "$json_data" | jq -r "to_entries | .[] | \"${prefix}\(.key | ascii_upcase)='\(.value)'\""
}

# Export functions
export -f json_validate json_get json_set json_delete json_merge
export -f json_array_length json_pretty json_compact json_to_vars
