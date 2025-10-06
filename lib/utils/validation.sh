#!/bin/bash
#
# Validation Library
# Provides input validation and data validation functions
#

#
# Validate email format
#
validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    if [[ ! "$email" =~ $regex ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
    
    return 0
}

#
# Validate AWS Account ID format
#
validate_aws_account_id() {
    local account_id="$1"
    
    if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
        log_error "Invalid AWS Account ID format: $account_id (must be 12 digits)"
        return 1
    fi
    
    return 0
}

#
# Validate AWS Region format
#
validate_aws_region() {
    local region="$1"
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1"
        "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-southeast-1" "ap-southeast-2" "ap-south-1"
        "ca-central-1" "sa-east-1"
        "af-south-1" "ap-east-1" "ap-southeast-3" "eu-south-1" "me-south-1"
    )
    
    for valid_region in "${valid_regions[@]}"; do
        if [[ "$region" == "$valid_region" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid AWS region: $region"
    return 1
}

#
# Validate QuickSight resource ID format
#
validate_quicksight_id() {
    local resource_id="$1"
    local resource_type="${2:-resource}"
    
    # QuickSight IDs typically contain alphanumeric characters, hyphens, and underscores
    # Length is usually between 1-512 characters
    if [[ ! "$resource_id" =~ ^[a-zA-Z0-9_-]{1,512}$ ]]; then
        log_error "Invalid QuickSight $resource_type ID format: $resource_id"
        return 1
    fi
    
    return 0
}

#
# Validate file path and permissions
#
validate_file_path() {
    local file_path="$1"
    local required_permission="${2:-read}"  # read, write, execute
    local must_exist="${3:-true}"
    
    if [[ "$must_exist" == "true" ]]; then
        if [[ ! -f "$file_path" ]]; then
            log_error "File does not exist: $file_path"
            return 1
        fi
    fi
    
    case "$required_permission" in
        "read")
            if [[ ! -r "$file_path" ]]; then
                log_error "File is not readable: $file_path"
                return 1
            fi
            ;;
        "write")
            if [[ -f "$file_path" ]] && [[ ! -w "$file_path" ]]; then
                log_error "File is not writable: $file_path"
                return 1
            elif [[ ! -f "$file_path" ]]; then
                # Check if directory is writable
                local dir_path
                dir_path="$(dirname "$file_path")"
                if [[ ! -w "$dir_path" ]]; then
                    log_error "Directory is not writable: $dir_path"
                    return 1
                fi
            fi
            ;;
        "execute")
            if [[ ! -x "$file_path" ]]; then
                log_error "File is not executable: $file_path"
                return 1
            fi
            ;;
        *)
            log_error "Invalid permission type: $required_permission"
            return 1
            ;;
    esac
    
    return 0
}

#
# Validate directory path and permissions
#
validate_directory_path() {
    local dir_path="$1"
    local required_permission="${2:-read}"  # read, write, execute
    local must_exist="${3:-true}"
    
    if [[ "$must_exist" == "true" ]]; then
        if [[ ! -d "$dir_path" ]]; then
            log_error "Directory does not exist: $dir_path"
            return 1
        fi
    fi
    
    case "$required_permission" in
        "read")
            if [[ ! -r "$dir_path" ]]; then
                log_error "Directory is not readable: $dir_path"
                return 1
            fi
            ;;
        "write")
            if [[ ! -w "$dir_path" ]]; then
                log_error "Directory is not writable: $dir_path"
                return 1
            fi
            ;;
        "execute")
            if [[ ! -x "$dir_path" ]]; then
                log_error "Directory is not accessible: $dir_path"
                return 1
            fi
            ;;
        *)
            log_error "Invalid permission type: $required_permission"
            return 1
            ;;
    esac
    
    return 0
}

#
# Validate URL format
#
validate_url() {
    local url="$1"
    local regex="^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9].*$"
    
    if [[ ! "$url" =~ $regex ]]; then
        log_error "Invalid URL format: $url"
        return 1
    fi
    
    return 0
}

#
# Validate positive integer
#
validate_positive_integer() {
    local value="$1"
    local field_name="${2:-value}"
    
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Invalid $field_name: must be a positive integer (got: $value)"
        return 1
    fi
    
    return 0
}

#
# Validate non-negative integer
#
validate_non_negative_integer() {
    local value="$1"
    local field_name="${2:-value}"
    
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log_error "Invalid $field_name: must be a non-negative integer (got: $value)"
        return 1
    fi
    
    return 0
}

#
# Validate string length
#
validate_string_length() {
    local string="$1"
    local min_length="${2:-0}"
    local max_length="${3:-}"
    local field_name="${4:-string}"
    
    local length=${#string}
    
    if [[ $length -lt $min_length ]]; then
        log_error "$field_name is too short: minimum $min_length characters (got: $length)"
        return 1
    fi
    
    if [[ -n "$max_length" ]] && [[ $length -gt $max_length ]]; then
        log_error "$field_name is too long: maximum $max_length characters (got: $length)"
        return 1
    fi
    
    return 0
}

#
# Validate choice from list
#
validate_choice() {
    local value="$1"
    local field_name="$2"
    shift 2
    local valid_choices=("$@")
    
    for choice in "${valid_choices[@]}"; do
        if [[ "$value" == "$choice" ]]; then
            return 0
        fi
    done
    
    local choices_list=$(IFS=', '; echo "${valid_choices[*]}")
    log_error "Invalid $field_name: '$value'. Valid choices: $choices_list"
    return 1
}

#
# Validate date format (YYYY-MM-DD)
#
validate_date_format() {
    local date_string="$1"
    local field_name="${2:-date}"
    
    if [[ ! "$date_string" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "Invalid $field_name format: '$date_string' (expected: YYYY-MM-DD)"
        return 1
    fi
    
    # Validate actual date using date command
    if ! date -d "$date_string" >/dev/null 2>&1; then
        log_error "Invalid $field_name: '$date_string' is not a valid date"
        return 1
    fi
    
    return 0
}

#
# Validate backup directory naming convention
#
validate_backup_directory_name() {
    local dir_name="$1"
    
    # Expected format: quicksight-{type}-backup-YYYYMMDD-HHMMSS
    local regex="^quicksight-(analysis|dataset|full)-backup-[0-9]{8}-[0-9]{6}$"
    
    if [[ ! "$dir_name" =~ $regex ]]; then
        log_error "Invalid backup directory name format: $dir_name"
        log_info "Expected format: quicksight-{analysis|dataset|full}-backup-YYYYMMDD-HHMMSS"
        return 1
    fi
    
    return 0
}

# Export functions
export -f validate_email validate_aws_account_id validate_aws_region
export -f validate_quicksight_id validate_file_path validate_directory_path
export -f validate_url validate_positive_integer validate_non_negative_integer
export -f validate_string_length validate_choice validate_date_format
export -f validate_backup_directory_name
