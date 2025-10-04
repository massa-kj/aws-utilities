#!/bin/bash

# QuickSight Dataset Creation and Update Script
# Creates and updates datasets from backup JSON files or edited JSON files

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common library
if [ -f "$SCRIPT_DIR/quicksight_lib.sh" ]; then
    source "$SCRIPT_DIR/quicksight_lib.sh"
else
    echo "Error: quicksight_lib.sh not found." >&2
    exit 1
fi

# Load configuration file
if ! load_config; then
    print_yellow "Failed to load configuration file."
fi

# =============================================================================
# Dataset Creation and Update Functions
# =============================================================================

# Extract dataset creation parameters from backup JSON
extract_dataset_params() {
    local json_file="$1"
    local temp_dir="$2"
    
    # Extract DataSet and remove unnecessary fields (subtraction approach)
    jq '.DataSet | del(.Arn, .CreatedTime, .LastUpdatedTime, .OutputColumns, .ConsumedSpiceCapacityInBytes)' "$json_file" > "$temp_dir/create_params.json"
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$temp_dir/create_params.json"
}

# Check if dataset exists
check_dataset_exists() {
    local dataset_id="$1"
    
    aws quicksight describe-data-set \
        --aws-account-id "$ACCOUNT_ID" \
        --data-set-id "$dataset_id" \
        --region "$REGION" >/dev/null 2>&1
    
    return $?
}

# Create new dataset
create_dataset() {
    local params_file="$1"
    local dry_run="$2"
    
    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")
    
    print_cyan "Creating dataset: $dataset_name (ID: $dataset_id)"
    
    if [ "$dry_run" = "true" ]; then
        print_yellow "  [DRY RUN] Will not perform actual creation"
        print_blue "  Planned command: aws quicksight create-data-set --aws-account-id $ACCOUNT_ID --data-set-id $dataset_id ..."
        return 0
    fi
    
    # Execute actual creation
    if aws quicksight create-data-set \
        --aws-account-id "$ACCOUNT_ID" \
        --data-set-id "$dataset_id" \
        --region "$REGION" \
		--cli-input-json "file://$params_file" \
        --output json > /tmp/create_result.json 2>&1; then
        
        print_green "  ✓ Dataset creation successful"
        local arn
        arn=$(jq -r '.Arn // "N/A"' /tmp/create_result.json 2>/dev/null)
        print_blue "  ARN: $arn"
        return 0
    else
        print_red "  ✗ Dataset creation failed"
        if [ -f /tmp/create_result.json ]; then
            local error_msg
            error_msg=$(jq -r '.message // .Message // "Unknown error"' /tmp/create_result.json 2>/dev/null)
            print_red "  Error: $error_msg"
        fi
        return 1
    fi
}

# Update existing dataset
update_dataset() {
    local params_file="$1"
    local dry_run="$2"
    
    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")
    
    print_cyan "Updating dataset: $dataset_name (ID: $dataset_id)"
    
    if [ "$dry_run" = "true" ]; then
        print_yellow "  [DRY RUN] Will not perform actual update"
        print_blue "  Planned command: aws quicksight update-data-set --aws-account-id $ACCOUNT_ID --data-set-id $dataset_id ..."
        return 0
    fi
    
    # Execute actual update
    if aws quicksight update-data-set \
        --aws-account-id "$ACCOUNT_ID" \
        --data-set-id "$dataset_id" \
		--cli-input-json "file://$params_file" \
        --region "$REGION" \
        --output json > /tmp/update_result.json 2>&1; then
        
        print_green "  ✓ Dataset update successful"
        local arn
        arn=$(jq -r '.Arn // "N/A"' /tmp/update_result.json 2>/dev/null)
        print_blue "  ARN: $arn"
        return 0
    else
        print_red "  ✗ Dataset update failed"
        if [ -f /tmp/update_result.json ]; then
            local error_msg
            error_msg=$(jq -r '.message // .Message // "Unknown error"' /tmp/update_result.json 2>/dev/null)
            print_red "  Error: $error_msg"
        fi
        return 1
    fi
}

# Set dataset permissions
update_dataset_permissions() {
    local dataset_id="$1"
    local permissions_file="$2"
    local dry_run="$3"
    
    if [ ! -f "$permissions_file" ]; then
        print_yellow "  Permissions file not found, skipping: $permissions_file"
        return 0
    fi
    
    print_cyan "Updating dataset permissions: $dataset_id"
    
    if [ "$dry_run" = "true" ]; then
        print_yellow "  [DRY RUN] Will not perform actual permission update"
        return 0
    fi
    
    # Extract permissions information
    local permissions
    permissions=$(jq -c '.Permissions // []' "$permissions_file" 2>/dev/null)
    
    if [ "$permissions" = "[]" ] || [ "$permissions" = "null" ]; then
        print_yellow "  No permissions configuration found, skipping"
        return 0
    fi
    
    if aws quicksight update-data-set-permissions \
        --aws-account-id "$ACCOUNT_ID" \
        --data-set-id "$dataset_id" \
        --grant-permissions "$permissions" \
        --region "$REGION" >/dev/null 2>&1; then
        
        print_green "  ✓ Permissions update successful"
        return 0
    else
        print_red "  ✗ Permissions update failed"
        return 1
    fi
}

# =============================================================================
# Confirmation and Display Functions
# =============================================================================

# Ask user for execution confirmation
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

# Display processing target information for single file
show_single_target_info() {
    local json_file="$1"
    local operation="$2"
    
    print_bold "=== Processing Target Information ==="
    print_cyan "File: $json_file"
    
    # Extract and display dataset information
    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSet.DataSetId // "N/A"' "$json_file" 2>/dev/null)
    dataset_name=$(jq -r '.DataSet.Name // "N/A"' "$json_file" 2>/dev/null)
    
    print_blue "Dataset ID: $dataset_id"
    print_blue "Dataset Name: $dataset_name"
    print_blue "Operation to execute: $operation"
}

# Display processing target information for multiple files
show_multiple_targets_info() {
    local target_dir="$1"
    local operation="$2"
    local json_files=("${@:3}")  # Receive arguments from 3rd onwards as array
    
    print_bold "=== Batch Processing Target Information ==="
    print_cyan "Target Directory: $target_dir"
    print_blue "Operation to execute: $operation"
    print_cyan "Number of files to process: ${#json_files[@]}"
    
    echo
    print_bold "Processing target list:"
    
    local count=1
    for json_file in "${json_files[@]}"; do
        local dataset_id dataset_name
        dataset_id=$(jq -r '.DataSet.DataSetId // "N/A"' "$json_file" 2>/dev/null)
        dataset_name=$(jq -r '.DataSet.Name // "N/A"' "$json_file" 2>/dev/null)
        
        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        print_blue "    ID: $dataset_id"
        print_blue "    Name: $dataset_name"
        echo
        
        ((count++))
    done
}

# =============================================================================
# Main Processing Functions
# =============================================================================

# Process single JSON file
process_dataset_json() {
    local json_file="$1"
    local operation="$2"  # "create", "update", "upsert"
    local dry_run="$3"
    local update_permissions="$4"
    local skip_confirmation="$5"  # Whether to skip confirmation
    
    if [ ! -f "$json_file" ]; then
        print_red "File not found: $json_file"
        return 1
    fi
    
    # Display processing target information and confirmation (when skip flag is false)
    if [ "$skip_confirmation" != "true" ]; then
        show_single_target_info "$json_file" "$operation"
        
        if [ "$dry_run" != "true" ]; then
            if ! confirm_execution "Will execute $operation operation on the above dataset."; then
                return 1
            fi
        fi
    fi
    
    print_bold "=== Dataset Processing Started: $(basename "$json_file") ==="
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    # JSON pre-validation
    # if ! validate_json_syntax "$json_file"; then
    #     print_red "Invalid JSON format"
    #     return 1
    # fi
    
    # Extract parameters
    local params_file
    if ! params_file=$(extract_dataset_params "$json_file" "$temp_dir"); then
        print_red "Failed to extract parameters"
        return 1
    fi
    
    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")
    
    if [ -z "$dataset_id" ] || [ "$dataset_id" = "null" ]; then
        print_red "DataSetId not found"
        return 1
    fi
    
    print_blue "Target dataset: $dataset_name (ID: $dataset_id)"
    
    # Determine operation
    local actual_operation="$operation"
    if [ "$operation" = "upsert" ]; then
        if check_dataset_exists "$dataset_id"; then
            actual_operation="update"
            print_yellow "Existing dataset detected, switching to update mode"
        else
            actual_operation="create"
            print_yellow "New dataset, switching to create mode"
        fi
    fi
    
    # Execute actual processing
    case $actual_operation in
        "create")
            if check_dataset_exists "$dataset_id"; then
                print_red "Dataset already exists: $dataset_id"
                print_yellow "Use --operation update to update it"
                return 1
            fi
            create_dataset "$params_file" "$dry_run"
            ;;
        "update")
            if ! check_dataset_exists "$dataset_id"; then
                print_red "Dataset does not exist: $dataset_id"
                print_yellow "Use --operation create to create it"
                return 1
            fi
            update_dataset "$params_file" "$dry_run"
            ;;
        *)
            print_red "Unknown operation: $actual_operation"
            return 1
            ;;
    esac
    
    local main_result=$?
    
    # Update permissions (only on success)
    if [ $main_result -eq 0 ] && [ "$update_permissions" = "true" ]; then
        local permissions_file
        permissions_file=$(dirname "$json_file")/../permissions/$(basename "$json_file" .json)-permissions.json
        update_dataset_permissions "$dataset_id" "$permissions_file" "$dry_run"
    fi
    
    if [ $main_result -eq 0 ]; then
        print_green "=== Processing Complete: Success ==="
    else
        print_red "=== Processing Complete: Error ==="
    fi
    
    return $main_result
}

# Batch processing of multiple files
process_multiple_datasets() {
    local target_dir="$1"
    local operation="$2"
    local dry_run="$3"
    local update_permissions="$4"
    
    # Search for JSON files
    local json_files=()
    while IFS= read -r -d '' file; do
        # Exclude permissions files
        if [[ "$file" != *"-permissions.json" ]]; then
            json_files+=("$file")
        fi
    done < <(find "$target_dir" -name "*.json" -print0 2>/dev/null)
    
    if [ ${#json_files[@]} -eq 0 ]; then
        print_red "No JSON files found"
        return 1
    fi
    
    # Display processing targets and confirmation
    show_multiple_targets_info "$target_dir" "$operation" "${json_files[@]}"
    
    if [ "$dry_run" != "true" ]; then
        if ! confirm_execution "Will batch execute $operation operation on the above ${#json_files[@]} datasets."; then
            return 1
        fi
    fi
    
    print_bold "=== Batch Processing of Multiple Datasets Started ==="
    
    local success_count=0
    local error_count=0
    
    # Process each file (skip confirmation)
    for json_file in "${json_files[@]}"; do
        echo
        if process_dataset_json "$json_file" "$operation" "$dry_run" "$update_permissions" "true"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done
    
    echo
    print_bold "=== Batch Processing Complete ==="
    print_green "Successful: $success_count items"
    [ $error_count -gt 0 ] && print_red "Errors: $error_count items"
    
    return $error_count
}

# =============================================================================
# CLI Interface
# =============================================================================

show_help() {
    cat << 'EOF'
QuickSight Dataset Creation and Update Script

Usage:
    ./dataset_manager.sh [options]

Options:
    -f, --file FILE       Process a single JSON file
    -d, --dir DIR         Batch process JSON files in directory
    -o, --operation OP    Specify operation (create|update|upsert)
                         - create: Create new only
                         - update: Update only  
                         - upsert: Update if exists, create if not
    -p, --permissions     Also update permissions (if permission file exists)
    -n, --dry-run         Show execution details without actually executing
    -h, --help            Show this help

Safety Features:
    - Display detailed target information before execution
    - Show all targets in advance during batch processing
    - Show confirmation prompt before actual operations (except in dry-run)

Examples:
    # Create new from single file
    ./dataset_manager.sh -f dataset.json -o create
    
    # Update single file (including permissions)
    ./dataset_manager.sh -f dataset.json -o update -p
    
    # Batch upsert in directory
    ./dataset_manager.sh -d ./datasets/ -o upsert
    
    # Dry run execution
    ./dataset_manager.sh -f dataset.json -o upsert --dry-run

Notes:
    - JSON files support QuickSight backup format (.DataSet) or
      new creation format
    - Permission files are automatically searched in permissions/ directory
    - Pre-validation with validate-changes is recommended before actual AWS operations
EOF
}

# Parse options
TARGET_FILE=""
TARGET_DIR=""
OPERATION="upsert"
UPDATE_PERMISSIONS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            TARGET_FILE="$2"
            shift 2
            ;;
        -d|--dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -o|--operation)
            OPERATION="$2"
            shift 2
            ;;
        -p|--permissions)
            UPDATE_PERMISSIONS=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_red "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Pre-execution checks
if [ -z "$TARGET_FILE" ] && [ -z "$TARGET_DIR" ]; then
    print_red "Error: Please specify file (-f) or directory (-d)"
    show_help
    exit 1
fi

if [ -n "$TARGET_FILE" ] && [ -n "$TARGET_DIR" ]; then
    print_red "Error: Cannot specify both file (-f) and directory (-d) at the same time"
    exit 1
fi

# Operation validation
case $OPERATION in
    create|update|upsert)
        ;;
    *)
        print_red "Error: Invalid operation: $OPERATION"
        print_yellow "Valid operations: create, update, upsert"
        exit 1
        ;;
esac

# Dependency check
check_dependencies || exit 1

# Execute main processing
if [ -n "$TARGET_FILE" ]; then
    process_dataset_json "$TARGET_FILE" "$OPERATION" "$DRY_RUN" "$UPDATE_PERMISSIONS"
else
    process_multiple_datasets "$TARGET_DIR" "$OPERATION" "$DRY_RUN" "$UPDATE_PERMISSIONS"
fi
