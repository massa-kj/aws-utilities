#!/bin/bash
#
# QuickSight Dataset Resource Management
# Modern implementation using the new API abstraction layer
# Compatible with existing dataset_manager.sh functionality
#

# Get the directory of this script
DATASET_RESOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DATASET_RESOURCE_DIR/../../../.." && pwd)"

# Load API abstraction layer
source "$DATASET_RESOURCE_DIR/../api/common.sh"
source "$DATASET_RESOURCE_DIR/../api/v1/dataset_api.sh"

# Color output functions (compatibility with existing lib)
print_green() { echo -e "\033[32m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_blue() { echo -e "\033[34m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

# =============================================================================
# High-Level Dataset Processing Functions
# =============================================================================

#
# Process a single dataset JSON file with full compatibility
# Compatible with existing process_dataset_json function
#
process_dataset_json() {
    local json_file="$1"
    local operation="$2"        # "create", "update", "upsert"
    local dry_run="${3:-false}"
    local update_permissions="${4:-false}"
    local skip_confirmation="${5:-false}"
    
    if [[ ! -f "$json_file" ]]; then
        print_red "File not found: $json_file"
        return 1
    fi
    
    log_info "Processing dataset JSON file: $json_file"
    
    # Initialize API if not already done
    if ! qs_api_init true; then
        print_red "Failed to initialize QuickSight API"
        return 1
    fi
    
    # Extract dataset parameters from backup JSON (compatible with existing format)
    local extract_response
    extract_response=$(qs_dataset_extract_params_from_backup "$(cat "$json_file")")
    
    if ! qs_is_success "$extract_response"; then
        print_red "Failed to extract dataset parameters from JSON"
        return 1
    fi
    
    local params_data
    params_data=$(qs_get_response_data "$extract_response")
    
    local dataset_id dataset_name
    dataset_id=$(echo "$params_data" | jq -r '.DataSetId // empty')
    dataset_name=$(echo "$params_data" | jq -r '.Name // empty')
    
    if [[ -z "$dataset_id" ]]; then
        print_red "DataSetId not found in JSON file"
        return 1
    fi
    
    if [[ -z "$dataset_name" ]]; then
        print_red "Dataset name not found in JSON file"
        return 1
    fi
    
    # Display processing target information (compatibility)
    if [[ "$skip_confirmation" != "true" ]]; then
        show_single_dataset_info "$json_file" "$operation" "$dataset_id" "$dataset_name"
        
        if [[ "$dry_run" != "true" ]]; then
            if ! confirm_execution "Will execute $operation operation on the above dataset."; then
                return 1
            fi
        fi
    fi
    
    print_bold "=== Dataset Processing Started: $(basename "$json_file") ==="
    print_blue "Target dataset: $dataset_name (ID: $dataset_id)"
    
    # Extract dataset configuration parameters
    local physical_table_map logical_table_map import_mode
    physical_table_map=$(echo "$params_data" | jq -c '.PhysicalTableMap // {}')
    logical_table_map=$(echo "$params_data" | jq -c '.LogicalTableMap // {}')
    import_mode=$(echo "$params_data" | jq -r '.ImportMode // "SPICE"')
    
    # Extract additional optional parameters
    local column_groups field_folders row_level_permission_data_set column_level_permission_rules
    column_groups=$(echo "$params_data" | jq -c '.ColumnGroups // []')
    field_folders=$(echo "$params_data" | jq -c '.FieldFolders // {}')
    row_level_permission_data_set=$(echo "$params_data" | jq -c '.RowLevelPermissionDataSet // null')
    column_level_permission_rules=$(echo "$params_data" | jq -c '.ColumnLevelPermissionRules // []')
    
    # Execute dry run information display
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "=== DRY RUN MODE - No actual changes will be made ==="
        print_cyan "Would execute operation: $operation"
        print_cyan "Dataset ID: $dataset_id"
        print_cyan "Dataset Name: $dataset_name"
        print_cyan "Import Mode: $import_mode"
        print_cyan "Physical Tables: $(echo "$physical_table_map" | jq 'keys | length')"
        if [[ "$logical_table_map" != "{}" ]]; then
            print_cyan "Logical Tables: $(echo "$logical_table_map" | jq 'keys | length')"
        fi
        print_cyan "Update permissions: $update_permissions"
        return 0
    fi
    
    # Determine actual operation for upsert
    local actual_operation="$operation"
    if [[ "$operation" == "upsert" ]]; then
        if qs_dataset_exists "$dataset_id"; then
            actual_operation="update"
            print_yellow "Existing dataset detected, switching to update mode"
        else
            actual_operation="create"
            print_yellow "New dataset, switching to create mode"
        fi
    fi
    
    # Execute the operation using new API abstraction layer
    local result=0
    case "$actual_operation" in
        "create")
            if qs_dataset_exists "$dataset_id"; then
                print_red "Dataset already exists: $dataset_id"
                print_yellow "Use --operation update to update it"
                return 1
            fi
            
            local create_response
            create_response=$(qs_dataset_create "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode" "$column_groups" "$field_folders" "null" "$column_level_permission_rules" "$row_level_permission_data_set")
            
            if qs_is_success "$create_response"; then
                print_green "✓ Dataset creation successful"
                local response_data
                response_data=$(qs_get_response_data "$create_response")
                local arn
                arn=$(echo "$response_data" | jq -r '.Arn // "N/A"')
                print_blue "  ARN: $arn"
            else
                print_red "✗ Dataset creation failed"
                local error_info
                error_info=$(qs_get_error_info "$create_response")
                print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
                result=1
            fi
            ;;
            
        "update")
            if ! qs_dataset_exists "$dataset_id"; then
                print_red "Dataset does not exist: $dataset_id"
                print_yellow "Use --operation create to create it"
                return 1
            fi
            
            local update_response
            update_response=$(qs_dataset_update "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode" "$column_groups" "$field_folders" "$row_level_permission_data_set" "$column_level_permission_rules")
            
            if qs_is_success "$update_response"; then
                print_green "✓ Dataset update successful"
                local response_data
                response_data=$(qs_get_response_data "$update_response")
                local arn
                arn=$(echo "$response_data" | jq -r '.Arn // "N/A"')
                print_blue "  ARN: $arn"
            else
                print_red "✗ Dataset update failed"
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
        update_dataset_permissions_from_file "$json_file" "$dataset_id" "$dry_run"
        local perm_result=$?
        if [[ $perm_result -ne 0 ]]; then
            result=$perm_result
        fi
    fi
    
    print_bold "=== Dataset Processing Completed: $(basename "$json_file") ==="
    return $result
}

#
# Process multiple dataset JSON files (batch operation)
# Compatible with existing batch processing functionality
#
process_dataset_directory() {
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
    show_multiple_datasets_info "$target_dir" "$operation" "${json_files[@]}"
    
    # Confirmation for batch operation
    if [[ "$dry_run" != "true" ]]; then
        if ! confirm_execution "Will execute $operation operation on ${#json_files[@]} datasets."; then
            return 1
        fi
    fi
    
    print_bold "=== Batch Dataset Processing Started ==="
    
    local success_count=0
    local error_count=0
    
    for json_file in "${json_files[@]}"; do
        print_cyan "\nProcessing: $(basename "$json_file")"
        
        if process_dataset_json "$json_file" "$operation" "$dry_run" "$update_permissions" "true"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    print_bold "\n=== Batch Dataset Processing Summary ==="
    print_green "Successful: $success_count datasets"
    if [[ $error_count -gt 0 ]]; then
        print_red "Failed: $error_count datasets"
    fi
    
    return $error_count
}

# =============================================================================
# Permission Management Functions
# =============================================================================

#
# Update dataset permissions from backup file
#
update_dataset_permissions_from_file() {
    local json_file="$1"
    local dataset_id="$2"
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
    
    print_cyan "Updating dataset permissions: $dataset_id"
    
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
    perm_response=$(qs_dataset_update_permissions "$dataset_id" "$permissions_data" "null")
    
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

#
# Trigger dataset refresh/ingestion
#
trigger_dataset_refresh() {
    local dataset_id="$1"
    local ingestion_type="${2:-INCREMENTAL_REFRESH}"
    local dry_run="${3:-false}"
    
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "  [DRY RUN] Would trigger dataset refresh: $dataset_id"
        return 0
    fi
    
    print_cyan "Triggering dataset refresh: $dataset_id"
    
    # Generate unique ingestion ID
    local ingestion_id
    ingestion_id="refresh-$(date +%Y%m%d-%H%M%S)-$$"
    
    local refresh_response
    refresh_response=$(qs_dataset_create_ingestion "$dataset_id" "$ingestion_id" "$ingestion_type" "MANUAL")
    
    if qs_is_success "$refresh_response"; then
        print_green "  ✓ Dataset refresh initiated"
        local response_data
        response_data=$(qs_get_response_data "$refresh_response")
        local ingestion_arn
        ingestion_arn=$(echo "$response_data" | jq -r '.Arn // "N/A"')
        print_blue "  Ingestion ARN: $ingestion_arn"
        return 0
    else
        print_red "  ✗ Dataset refresh failed"
        local error_info
        error_info=$(qs_get_error_info "$refresh_response")
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
show_single_dataset_info() {
    local json_file="$1"
    local operation="$2"
    local dataset_id="$3"
    local dataset_name="$4"
    
    print_bold "=== Processing Target Information ==="
    print_cyan "File: $json_file"
    print_blue "Dataset ID: $dataset_id"
    print_blue "Dataset Name: $dataset_name"
    print_blue "Operation to execute: $operation"
}

#
# Display processing target information for multiple files
#
show_multiple_datasets_info() {
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
        local dataset_info
        dataset_info=$(cat "$json_file" | jq -r '.DataSet // {}')
        local dataset_id dataset_name import_mode
        dataset_id=$(echo "$dataset_info" | jq -r '.DataSetId // "N/A"')
        dataset_name=$(echo "$dataset_info" | jq -r '.Name // "N/A"')
        import_mode=$(echo "$dataset_info" | jq -r '.ImportMode // "N/A"')
        
        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        print_blue "    ID: $dataset_id"
        print_blue "    Name: $dataset_name"
        print_blue "    Import Mode: $import_mode"
        echo
        
        ((count++))
    done
}

# =============================================================================
# Legacy Compatibility Functions
# =============================================================================

#
# Legacy function compatibility - extract_dataset_params
# Uses new API abstraction layer but maintains same interface
#
extract_dataset_params() {
    local json_file="$1"
    local temp_dir="$2"
    
    if [[ ! -f "$json_file" ]]; then
        return 1
    fi
    
    # Use new API abstraction layer
    local extract_response
    extract_response=$(qs_dataset_extract_params_from_backup "$(cat "$json_file")")
    
    if ! qs_is_success "$extract_response"; then
        return 1
    fi
    
    # Save to temporary file for compatibility
    local params_file="$temp_dir/create_params.json"
    qs_get_response_data "$extract_response" > "$params_file"
    
    echo "$params_file"
}

#
# Legacy function compatibility - check_dataset_exists
# Now uses new API abstraction layer
#
check_dataset_exists() {
    local dataset_id="$1"
    qs_dataset_exists "$dataset_id"
}

#
# Legacy function compatibility - create_dataset
#
create_dataset() {
    local params_file="$1"
    local dry_run="${2:-false}"
    
    local dataset_data
    dataset_data=$(cat "$params_file")
    
    local dataset_id dataset_name
    dataset_id=$(echo "$dataset_data" | jq -r '.DataSetId')
    dataset_name=$(echo "$dataset_data" | jq -r '.Name')
    
    print_cyan "Creating dataset: $dataset_name (ID: $dataset_id)"
    
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "  [DRY RUN] Will not perform actual creation"
        return 0
    fi
    
    # Extract parameters and call new API
    local physical_table_map logical_table_map import_mode
    physical_table_map=$(echo "$dataset_data" | jq -c '.PhysicalTableMap // {}')
    logical_table_map=$(echo "$dataset_data" | jq -c '.LogicalTableMap // {}')
    import_mode=$(echo "$dataset_data" | jq -r '.ImportMode // "SPICE"')
    
    local create_response
    create_response=$(qs_dataset_create "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode")
    
    if qs_is_success "$create_response"; then
        print_green "  ✓ Dataset creation successful"
        return 0
    else
        print_red "  ✗ Dataset creation failed"
        local error_info
        error_info=$(qs_get_error_info "$create_response")
        print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
        return 1
    fi
}

#
# Legacy function compatibility - update_dataset
#
update_dataset() {
    local params_file="$1"
    local dry_run="${2:-false}"
    
    local dataset_data
    dataset_data=$(cat "$params_file")
    
    local dataset_id dataset_name
    dataset_id=$(echo "$dataset_data" | jq -r '.DataSetId')
    dataset_name=$(echo "$dataset_data" | jq -r '.Name')
    
    print_cyan "Updating dataset: $dataset_name (ID: $dataset_id)"
    
    if [[ "$dry_run" == "true" ]]; then
        print_yellow "  [DRY RUN] Will not perform actual update"
        return 0
    fi
    
    # Extract parameters and call new API
    local physical_table_map logical_table_map import_mode
    physical_table_map=$(echo "$dataset_data" | jq -c '.PhysicalTableMap // {}')
    logical_table_map=$(echo "$dataset_data" | jq -c '.LogicalTableMap // {}')
    import_mode=$(echo "$dataset_data" | jq -r '.ImportMode // "SPICE"')
    
    local update_response
    update_response=$(qs_dataset_update "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode")
    
    if qs_is_success "$update_response"; then
        print_green "  ✓ Dataset update successful"
        return 0
    else
        print_red "  ✗ Dataset update failed"
        local error_info
        error_info=$(qs_get_error_info "$update_response")
        print_red "  Error: $(echo "$error_info" | jq -r '.error_message')"
        return 1
    fi
}

# =============================================================================
# Main CLI Interface (for standalone usage)
# =============================================================================

#
# Show usage information
#
show_usage() {
    cat << 'EOF'
QuickSight Dataset Resource Management

Usage:
    dataset.sh [options]

Options:
    -f, --file FILE         Single JSON file to process
    -d, --dir DIRECTORY     Directory containing JSON files (batch mode)
    -o, --operation OP      Operation: create, update, upsert (default: upsert)
    -n, --dry-run          Show what would be done without making changes
    -p, --permissions      Update permissions after main operation
    -r, --refresh          Trigger dataset refresh after successful operation
    -y, --yes              Skip confirmation prompts
    -h, --help             Show this help message

Examples:
    # Process single dataset file
    ./dataset.sh -f backup/dataset-123.json -o create
    
    # Batch process directory with dry-run
    ./dataset.sh -d backup/datasets/ -o upsert --dry-run
    
    # Update with permissions and refresh
    ./dataset.sh -f dataset.json -o update -p -r -y

Compatible with existing dataset_manager.sh functionality.
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
    local trigger_refresh="false"
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
            -r|--refresh)
                trigger_refresh="true"
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
        local result
        process_dataset_json "$file" "$operation" "$dry_run" "$update_permissions" "$skip_confirmation"
        result=$?
        
        # Trigger refresh if requested and operation succeeded
        if [[ "$trigger_refresh" == "true" && $result -eq 0 && "$dry_run" != "true" ]]; then
            local dataset_id
            dataset_id=$(cat "$file" | jq -r '.DataSet.DataSetId // empty')
            if [[ -n "$dataset_id" ]]; then
                trigger_dataset_refresh "$dataset_id" "INCREMENTAL_REFRESH" "$dry_run"
            fi
        fi
        
        exit $result
        
    elif [[ -n "$directory" ]]; then
        # Directory batch processing
        process_dataset_directory "$directory" "$operation" "$dry_run" "$update_permissions"
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
export -f process_dataset_json process_dataset_directory
export -f update_dataset_permissions_from_file trigger_dataset_refresh
export -f extract_dataset_params check_dataset_exists create_dataset update_dataset
export -f confirm_execution show_single_dataset_info show_multiple_datasets_info

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
