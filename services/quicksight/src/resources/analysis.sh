#!/bin/bash
#
# QuickSight Analysis Resource Management
# Modern implementation using the new API abstraction layer
# Compatible with existing analysis_manager.sh functionality
#

# Get the directory of this script
ANALYSIS_RESOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ANALYSIS_RESOURCE_DIR/../../../.." && pwd)"

# Load API abstraction layer
source "$ANALYSIS_RESOURCE_DIR/../api/common.sh"
source "$ANALYSIS_RESOURCE_DIR/../api/v1/analysis_api.sh"

# Color output functions (compatibility with existing lib)
print_green() { echo -e "\033[32m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_blue() { echo -e "\033[34m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

# =============================================================================
# High-Level Analysis Processing Functions
# =============================================================================

#
# Process a single analysis JSON file with full compatibility
# Compatible with existing process_analysis_json function
#
process_analysis_json() {
    local json_file="$1"
    local operation="$2"        # "create", "update", "upsert"
    local dry_run="${3:-false}"
    local update_permissions="${4:-false}"
    local skip_confirmation="${5:-false}"
    
    if [[ ! -f "$json_file" ]]; then
        print_red "File not found: $json_file"
        return 1
    fi
    
    log_info "Processing analysis JSON file: $json_file"
    
    # Initialize API if not already done
    if ! qs_api_init true; then
        print_red "Failed to initialize QuickSight API"
        return 1
    fi
    
    # Extract analysis parameters from backup JSON (compatible with existing format)
    local extract_response
    extract_response=$(qs_analysis_extract_params_from_backup "$(cat "$json_file")")
    
    if ! qs_is_success "$extract_response"; then
        print_red "Failed to extract analysis parameters from JSON"
        return 1
    fi
    
    local params_data
    params_data=$(qs_get_response_data "$extract_response")
    
    local analysis_id analysis_name
    analysis_id=$(echo "$params_data" | jq -r '.AnalysisId // empty')
    analysis_name=$(echo "$params_data" | jq -r '.Name // empty')
    
    if [[ -z "$analysis_id" ]]; then
        print_red "AnalysisId not found in JSON file"
        return 1
    fi
    
    if [[ -z "$analysis_name" ]]; then
        print_red "Analysis name not found in JSON file"
        return 1
    fi
    
    # Display processing target information (compatibility)
    if [[ "$skip_confirmation" != "true" ]]; then
        show_single_analysis_info "$json_file" "$operation" "$analysis_id" "$analysis_name"
        
        if [[ "$dry_run" != "true" ]]; then
            if ! confirm_execution "Will execute $operation operation on the above analysis."; then
                return 1
            fi
        fi
    fi
    
    print_bold "=== Analysis Processing Started: $(basename "$json_file") ==="
    print_blue "Target analysis: $analysis_name (ID: $analysis_id)"
    
    # Search for definition file (compatible with existing structure)
    local definition_json="null"
    local base_dir base_name
    base_dir=$(dirname "$json_file")
    base_name=$(basename "$json_file" .json)
    
    # Check for definition file in ../definitions/ directory
    local potential_def_file="$base_dir/../definitions/${base_name}-definition.json"
    if [[ -f "$potential_def_file" ]]; then
        definition_json=$(cat "$potential_def_file")
        print_blue "Definition file detected: $potential_def_file"
    else
        # Check if definition is included in the main JSON
        local definition_check
        definition_check=$(cat "$json_file" | jq '.Definition // empty')
        if [[ -n "$definition_check" && "$definition_check" != "null" ]]; then
            definition_json="$definition_check"
            print_blue "Using definition from main JSON file"
        fi
    fi
    
    # Execute dry run information display
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "=== DRY RUN MODE - No actual changes will be made ==="
        print_cyan "Would execute operation: $operation"
        print_cyan "Analysis ID: $analysis_id"
        print_cyan "Analysis Name: $analysis_name"
        print_cyan "Has definition: $(if [[ "$definition_json" != "null" ]]; then echo "Yes"; else echo "No"; fi)"
        print_cyan "Update permissions: $update_permissions"
        return 0
    fi
    
    # Determine actual operation for upsert
    local actual_operation="$operation"
    if [[ "$operation" == "upsert" ]]; then
        if qs_analysis_exists "$analysis_id"; then
            actual_operation="update"
            print_yellow "Existing analysis detected, switching to update mode"
        else
            actual_operation="create"
            print_yellow "New analysis, switching to create mode"
        fi
    fi
    
    # Execute the operation using new API abstraction layer
    local result=0
    case "$actual_operation" in
        "create")
            if qs_analysis_exists "$analysis_id"; then
                print_red "Analysis already exists: $analysis_id"
                print_yellow "Use --operation update to update it"
                return 1
            fi
            
            local create_response
            create_response=$(qs_analysis_create "$analysis_id" "$analysis_name" "$definition_json")
            
            if qs_is_success "$create_response"; then
                print_green "✓ Analysis creation successful"
                local response_data
                response_data=$(qs_get_response_data "$create_response")
                local arn
                arn=$(echo "$response_data" | jq -r '.Arn // "N/A"')
                print_blue "  ARN: $arn"
            else
                print_red "✗ Analysis creation failed"
                local error_info
                error_info=$(qs_get_error_info "$create_response")
                print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
                result=1
            fi
            ;;
            
        "update")
            if ! qs_analysis_exists "$analysis_id"; then
                print_red "Analysis does not exist: $analysis_id"
                print_yellow "Use --operation create to create it"
                return 1
            fi
            
            local update_response
            update_response=$(qs_analysis_update "$analysis_id" "$analysis_name" "$definition_json")
            
            if qs_is_success "$update_response"; then
                print_green "✓ Analysis update successful"
                local response_data
                response_data=$(qs_get_response_data "$update_response")
                local arn
                arn=$(echo "$response_data" | jq -r '.Arn // "N/A"')
                print_blue "  ARN: $arn"
            else
                print_red "✗ Analysis update failed"
                local error_info
                error_info=$(qs_get_error_info "$update_response")
                print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
                result=1
            fi
            ;;
            
        *)
            print_red "Unknown operation: $actual_operation"
            return 1
            ;;
    esac
    
    # Update permissions if requested and main operation succeeded
    if [[ "$update_permissions" == "true" && $result -eq 0 ]]; then
        update_analysis_permissions_from_file "$json_file" "$analysis_id" "$dry_run"
        local perm_result=$?
        if [[ $perm_result -ne 0 ]]; then
            result=$perm_result
        fi
    fi
    
    print_bold "=== Analysis Processing Completed: $(basename "$json_file") ==="
    return $result
}

#
# Process multiple analysis JSON files (batch operation)
# Compatible with existing batch processing functionality
#
process_analysis_directory() {
    local target_dir="$1"
    local operation="$2"
    local dry_run="${3:-false}"
    local update_permissions="${4:-false}"
    
    if [[ ! -d "$target_dir" ]]; then
        print_red "Directory not found: $target_dir"
        return 1
    fi
    
    # Find all JSON files in the directory
    local json_files=()
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find "$target_dir" -name "*.json" -type f -print0)
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        print_yellow "No JSON files found in directory: $target_dir"
        return 1
    fi
    
    # Display batch processing information
    show_multiple_analyses_info "$target_dir" "$operation" "${json_files[@]}"
    
    # Confirmation for batch operation
    if [[ "$dry_run" != "true" ]]; then
        if ! confirm_execution "Will execute $operation operation on ${#json_files[@]} analyses."; then
            return 1
        fi
    fi
    
    print_bold "=== Batch Analysis Processing Started ==="
    
    local success_count=0
    local error_count=0
    
    for json_file in "${json_files[@]}"; do
        print_cyan "\nProcessing: $(basename "$json_file")"
        
        if process_analysis_json "$json_file" "$operation" "$dry_run" "$update_permissions" "true"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    print_bold "\n=== Batch Analysis Processing Summary ==="
    print_green "Successful: $success_count analyses"
    if [[ $error_count -gt 0 ]]; then
        print_red "Failed: $error_count analyses"
    fi
    
    return $error_count
}

# =============================================================================
# Permission Management Functions
# =============================================================================

#
# Update analysis permissions from backup file
#
update_analysis_permissions_from_file() {
    local json_file="$1"
    local analysis_id="$2"
    local dry_run="${3:-false}"
    
    # Search for permissions file
    local base_dir base_name
    base_dir=$(dirname "$json_file")
    base_name=$(basename "$json_file" .json)
    
    local permissions_file="$base_dir/../permissions/${base_name}-permissions.json"
    
    if [[ ! -f "$permissions_file" ]]; then
        print_yellow "  Permissions file not found, skipping: $permissions_file"
        return 0
    fi
    
    print_cyan "Updating analysis permissions: $analysis_id"
    
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "  [DRY RUN] Would update permissions from: $permissions_file"
        return 0
    fi
    
    # Extract permissions from file
    local permissions_data
    permissions_data=$(cat "$permissions_file" | jq '.Permissions // []')
    
    if [[ "$permissions_data" == "[]" || "$permissions_data" == "null" ]]; then
        print_yellow "  No permissions configuration found, skipping"
        return 0
    fi
    
    # Update permissions using new API
    local perm_response
    perm_response=$(qs_analysis_update_permissions "$analysis_id" "$permissions_data" "null")
    
    if qs_is_success "$perm_response"; then
        print_green "  ✓ Permissions update successful"
        return 0
    else
        print_red "  ✗ Permissions update failed"
        local error_info
        error_info=$(qs_get_error_info "$perm_response")
        print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
        return 1
    fi
}

# =============================================================================
# Display and Confirmation Functions (Compatibility)
# =============================================================================

#
# Ask user for execution confirmation
#
confirm_execution() {
    local message="$1"
    
    print_yellow "$message"
    print_blue "Do you want to execute this operation? [y/N]: "
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            print_yellow "Operation cancelled"
            return 1
            ;;
    esac
}

#
# Display processing target information for single file
#
show_single_analysis_info() {
    local json_file="$1"
    local operation="$2"
    local analysis_id="$3"
    local analysis_name="$4"
    
    print_bold "=== Processing Target Information ==="
    print_cyan "File: $json_file"
    print_blue "Analysis ID: $analysis_id"
    print_blue "Analysis Name: $analysis_name"
    print_blue "Operation to execute: $operation"
}

#
# Display processing target information for multiple files
#
show_multiple_analyses_info() {
    local target_dir="$1"
    local operation="$2"
    shift 2
    local json_files=("$@")
    
    print_bold "=== Batch Processing Target Information ==="
    print_cyan "Target Directory: $target_dir"
    print_blue "Operation to execute: $operation"
    print_cyan "Number of files to process: ${#json_files[@]}"
    
    echo
    print_bold "Processing target list:"
    
    local count=1
    for json_file in "${json_files[@]}"; do
        # Extract info for display
        local analysis_info
        analysis_info=$(cat "$json_file" | jq -r '.Analysis // {}')
        local analysis_id analysis_name
        analysis_id=$(echo "$analysis_info" | jq -r '.AnalysisId // "N/A"')
        analysis_name=$(echo "$analysis_info" | jq -r '.Name // "N/A"')
        
        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        print_blue "    ID: $analysis_id"
        print_blue "    Name: $analysis_name"
        echo
        
        ((count++))
    done
}

# =============================================================================
# Legacy Compatibility Functions
# =============================================================================

#
# Legacy function compatibility - extract_analysis_params
# Uses new API abstraction layer but maintains same interface
#
extract_analysis_params() {
    local json_file="$1"
    local temp_dir="$2"
    
    if [[ ! -f "$json_file" ]]; then
        return 1
    fi
    
    # Use new API abstraction layer
    local extract_response
    extract_response=$(qs_analysis_extract_params_from_backup "$(cat "$json_file")")
    
    if ! qs_is_success "$extract_response"; then
        return 1
    fi
    
    # Save to temporary file for compatibility
    local params_file="$temp_dir/create_params.json"
    qs_get_response_data "$extract_response" > "$params_file"
    
    echo "$params_file"
}

#
# Legacy function compatibility - extract_analysis_definition
#
extract_analysis_definition() {
    local definition_file="$1"
    local temp_dir="$2"
    
    if [[ ! -f "$definition_file" ]]; then
        echo "null"
        return 0
    fi
    
    # Extract analysis definition (compatible with existing format)
    local output_file="$temp_dir/definition.json"
    jq '.Definition // {}' "$definition_file" > "$output_file"
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$output_file"
}

#
# Legacy function compatibility - check_analysis_exists
# Now uses new API abstraction layer
#
check_analysis_exists() {
    local analysis_id="$1"
    qs_analysis_exists "$analysis_id"
}

# =============================================================================
# Main CLI Interface (for standalone usage)
# =============================================================================

#
# Show usage information
#
show_usage() {
    cat << 'EOF'
QuickSight Analysis Resource Management

Usage:
    analysis.sh [options]

Options:
    -f, --file FILE         Single JSON file to process
    -d, --dir DIRECTORY     Directory containing JSON files (batch mode)
    -o, --operation OP      Operation: create, update, upsert (default: upsert)
    -n, --dry-run          Show what would be done without making changes
    -p, --permissions      Update permissions after main operation
    -y, --yes              Skip confirmation prompts
    -h, --help             Show this help message

Examples:
    # Process single analysis file
    ./analysis.sh -f backup/analysis-123.json -o create
    
    # Batch process directory with dry-run
    ./analysis.sh -d backup/analyses/ -o upsert --dry-run
    
    # Update with permissions
    ./analysis.sh -f analysis.json -o update -p -y

Compatible with existing analysis_manager.sh functionality.
EOF
}

#
# Parse command line arguments and execute
#
main() {
    local file=""
    local directory=""
    local operation="upsert"
    local dry_run="false"
    local update_permissions="false"
    local skip_confirmation="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                file="$2"
                shift 2
                ;;
            -d|--dir|--directory)
                directory="$2"
                shift 2
                ;;
            -o|--operation)
                operation="$2"
                shift 2
                ;;
            -n|--dry-run)
                dry_run="true"
                shift
                ;;
            -p|--permissions)
                update_permissions="true"
                shift
                ;;
            -y|--yes)
                skip_confirmation="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_red "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate operation
    if [[ ! "$operation" =~ ^(create|update|upsert)$ ]]; then
        print_red "Invalid operation: $operation"
        print_yellow "Valid operations: create, update, upsert"
        exit 1
    fi
    
    # Process based on input type
    if [[ -n "$file" ]]; then
        # Single file processing
        process_analysis_json "$file" "$operation" "$dry_run" "$update_permissions" "$skip_confirmation"
        exit $?
        
    elif [[ -n "$directory" ]]; then
        # Directory batch processing
        process_analysis_directory "$directory" "$operation" "$dry_run" "$update_permissions"
        exit $?
        
    else
        print_red "Either --file or --directory must be specified"
        show_usage
        exit 1
    fi
}

# =============================================================================
# Export Functions
# =============================================================================

# Export functions for use by other scripts
export -f process_analysis_json process_analysis_directory
export -f update_analysis_permissions_from_file
export -f extract_analysis_params extract_analysis_definition check_analysis_exists
export -f confirm_execution show_single_analysis_info show_multiple_analyses_info

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
