#!/bin/bash

# QuickSight Analysis Creation and Update Script
# Creates and updates analyses from backup JSON files or edited JSON files

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
# Analysis Creation and Update Functions
# =============================================================================

# Extract analysis creation parameters from backup JSON
extract_analysis_params() {
    local json_file="$1"
    local temp_dir="$2"
    
    # Extract Analysis and remove unnecessary fields (subtraction approach)
    jq '.Analysis | del(.Arn, .CreatedTime, .LastUpdatedTime, .Status)' "$json_file" > "$temp_dir/create_params.json"
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$temp_dir/create_params.json"
}

# Extract definition from analysis definition file
extract_analysis_definition() {
    local definition_file="$1"
    local temp_dir="$2"
    
    if [ ! -f "$definition_file" ]; then
        echo "null"
        return 0
    fi
    
    # Extract analysis definition
    jq '.Definition // {}' "$definition_file" > "$temp_dir/definition.json"
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$temp_dir/definition.json"
}

# Check if analysis exists
check_analysis_exists() {
    local analysis_id="$1"
    
    aws quicksight describe-analysis \
        --aws-account-id "$ACCOUNT_ID" \
        --analysis-id "$analysis_id" \
        --region "$REGION" >/dev/null 2>&1
    
    return $?
}

# Create new analysis
create_analysis() {
    local params_file="$1"
    local definition_file="$2"
    local dry_run="$3"
    
    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")
    
    print_cyan "Creating analysis: $analysis_name (ID: $analysis_id)"
    
    if [ "$dry_run" = "true" ]; then
        print_yellow "  [DRY RUN] Will not perform actual creation"
        print_blue "  Planned command: aws quicksight create-analysis --aws-account-id $ACCOUNT_ID --analysis-id $analysis_id ..."
        return 0
    fi
    
    # Build command when definition exists
    local create_cmd="aws quicksight create-analysis \
        --aws-account-id $ACCOUNT_ID \
        --analysis-id $analysis_id \
        --name '$analysis_name' \
        --region $REGION \
        --output json"
    
    if [ -f "$definition_file" ] && [ "$(jq -r '. | length' "$definition_file" 2>/dev/null)" != "0" ]; then
        create_cmd="$create_cmd --definition file://$definition_file"
        print_blue "  Using definition file: $definition_file"
    fi
    
    # If theme ARN exists
    local theme_arn
    theme_arn=$(jq -r '.ThemeArn // empty' "$params_file")
    if [ -n "$theme_arn" ]; then
        create_cmd="$create_cmd --theme-arn $theme_arn"
    fi
    
    # Execute actual creation
    if eval "$create_cmd" > /tmp/create_analysis_result.json 2>&1; then
        print_green "  ✓ Analysis creation successful"
        local arn
        arn=$(jq -r '.Arn // "N/A"' /tmp/create_analysis_result.json 2>/dev/null)
        print_blue "  ARN: $arn"
        return 0
    else
        print_red "  ✗ Analysis creation failed"
        if [ -f /tmp/create_analysis_result.json ]; then
            local error_msg
            error_msg=$(jq -r '.message // .Message // "Unknown error"' /tmp/create_analysis_result.json 2>/dev/null)
            print_red "  Error: $error_msg"
        fi
        return 1
    fi
}

# Update existing analysis
update_analysis() {
    local params_file="$1"
    local definition_file="$2"
    local dry_run="$3"
    
    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")
    
    print_cyan "Updating analysis: $analysis_name (ID: $analysis_id)"
    
    if [ "$dry_run" = "true" ]; then
        print_yellow "  [DRY RUN] Will not perform actual update"
        print_blue "  Planned command: aws quicksight update-analysis --aws-account-id $ACCOUNT_ID --analysis-id $analysis_id ..."
        return 0
    fi
    
    # Build update command
    local update_cmd="aws quicksight update-analysis \
        --aws-account-id $ACCOUNT_ID \
        --analysis-id $analysis_id \
        --name '$analysis_name' \
        --region $REGION \
        --output json"
    
    if [ -f "$definition_file" ] && [ "$(jq -r '. | length' "$definition_file" 2>/dev/null)" != "0" ]; then
        update_cmd="$update_cmd --definition file://$definition_file"
        print_blue "  Using definition file: $definition_file"
    fi
    
    # If theme ARN exists
    local theme_arn
    theme_arn=$(jq -r '.ThemeArn // empty' "$params_file")
    if [ -n "$theme_arn" ]; then
        update_cmd="$update_cmd --theme-arn $theme_arn"
    fi
    
    # Execute actual update
    if eval "$update_cmd" > /tmp/update_analysis_result.json 2>&1; then
        print_green "  ✓ Analysis update successful"
        local arn
        arn=$(jq -r '.Arn // "N/A"' /tmp/update_analysis_result.json 2>/dev/null)
        print_blue "  ARN: $arn"
        return 0
    else
        print_red "  ✗ Analysis update failed"
        if [ -f /tmp/update_analysis_result.json ]; then
            local error_msg
            error_msg=$(jq -r '.message // .Message // "Unknown error"' /tmp/update_analysis_result.json 2>/dev/null)
            print_red "  Error: $error_msg"
        fi
        return 1
    fi
}

# Set analysis permissions
update_analysis_permissions() {
    local analysis_id="$1"
    local permissions_file="$2"
    local dry_run="$3"
    
    if [ ! -f "$permissions_file" ]; then
        print_yellow "  Permissions file not found, skipping: $permissions_file"
        return 0
    fi
    
    print_cyan "Updating analysis permissions: $analysis_id"
    
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
    
    if aws quicksight update-analysis-permissions \
        --aws-account-id "$ACCOUNT_ID" \
        --analysis-id "$analysis_id" \
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
show_single_analysis_info() {
    local json_file="$1"
    local operation="$2"
    
    print_bold "=== Processing Target Information ==="
    print_cyan "File: $json_file"
    
    # Extract and display analysis information
    local analysis_id analysis_name
    analysis_id=$(jq -r '.Analysis.AnalysisId // "N/A"' "$json_file" 2>/dev/null)
    analysis_name=$(jq -r '.Analysis.Name // "N/A"' "$json_file" 2>/dev/null)
    
    print_blue "Analysis ID: $analysis_id"
    print_blue "Analysis Name: $analysis_name"
    print_blue "Operation to execute: $operation"
}

# Display processing target information for multiple files
show_multiple_analyses_info() {
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
        local analysis_id analysis_name
        analysis_id=$(jq -r '.Analysis.AnalysisId // "N/A"' "$json_file" 2>/dev/null)
        analysis_name=$(jq -r '.Analysis.Name // "N/A"' "$json_file" 2>/dev/null)
        
        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        print_blue "    ID: $analysis_id"
        print_blue "    Name: $analysis_name"
        echo
        
        ((count++))
    done
}

# =============================================================================
# Main Processing Functions
# =============================================================================

# Process single JSON file
process_analysis_json() {
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
        show_single_analysis_info "$json_file" "$operation"
        
        if [ "$dry_run" != "true" ]; then
            if ! confirm_execution "Will execute $operation operation on the above analysis."; then
                return 1
            fi
        fi
    fi
    
    print_bold "=== Analysis Processing Started: $(basename "$json_file") ==="
    
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
    if ! params_file=$(extract_analysis_params "$json_file" "$temp_dir"); then
        print_red "Failed to extract parameters"
        return 1
    fi
    
    # Search and extract definition files
    local definition_file=""
    local base_dir
    base_dir=$(dirname "$json_file")
    local base_name
    base_name=$(basename "$json_file" .json)
    
    # Search for corresponding files in definitions directory
    local potential_def_file="$base_dir/../definitions/${base_name}-definition.json"
    if [ -f "$potential_def_file" ]; then
        definition_file=$(extract_analysis_definition "$potential_def_file" "$temp_dir")
        print_blue "Definition file detected: $potential_def_file"
    else
        # When definition is included in JSON
        if jq -e '.Definition' "$json_file" >/dev/null 2>&1; then
            jq '.Definition' "$json_file" > "$temp_dir/definition.json"
            definition_file="$temp_dir/definition.json"
            print_blue "Using definition from JSON"
        fi
    fi
    
    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")
    
    if [ -z "$analysis_id" ] || [ "$analysis_id" = "null" ]; then
        print_red "AnalysisId not found"
        return 1
    fi
    
    print_blue "Target analysis: $analysis_name (ID: $analysis_id)"
    
    # Determine operation
    local actual_operation="$operation"
    if [ "$operation" = "upsert" ]; then
        if check_analysis_exists "$analysis_id"; then
            actual_operation="update"
            print_yellow "Existing analysis detected, switching to update mode"
        else
            actual_operation="create"
            print_yellow "New analysis, switching to create mode"
        fi
    fi
    
    # Execute actual processing
    case $actual_operation in
        "create")
            if check_analysis_exists "$analysis_id"; then
                print_red "Analysis already exists: $analysis_id"
                print_yellow "Use --operation update to update it"
                return 1
            fi
            create_analysis "$params_file" "$definition_file" "$dry_run"
            ;;
        "update")
            if ! check_analysis_exists "$analysis_id"; then
                print_red "Analysis does not exist: $analysis_id"
                print_yellow "Use --operation create to create it"
                return 1
            fi
            update_analysis "$params_file" "$definition_file" "$dry_run"
            ;;
        *)
            print_red "Unknown operation: $actual_operation"
            return 1
            ;;
    esac
    
    local main_result=$?
    
    # Update permissions (only on success)
    if [ $main_result -eq 0 ] && [ "$update_permissions" = "true" ]; then
        local permissions_file="$base_dir/../permissions/${base_name}-permissions.json"
        update_analysis_permissions "$analysis_id" "$permissions_file" "$dry_run"
    fi
    
    if [ $main_result -eq 0 ]; then
        print_green "=== Processing Complete: Success ==="
    else
        print_red "=== Processing Complete: Error ==="
    fi
    
    return $main_result
}

# Batch processing of multiple files
process_multiple_analyses() {
    local target_dir="$1"
    local operation="$2"
    local dry_run="$3"
    local update_permissions="$4"
    
    # Search for JSON files
    local json_files=()
    while IFS= read -r -d '' file; do
        # Exclude permissions and definition files
        if [[ "$file" != *"-permissions.json" ]] && [[ "$file" != *"-definition.json" ]]; then
            json_files+=("$file")
        fi
    done < <(find "$target_dir" -name "*.json" -print0 2>/dev/null)
    
    if [ ${#json_files[@]} -eq 0 ]; then
        print_red "No JSON files found"
        return 1
    fi
    
    # Display processing targets and confirmation
    show_multiple_analyses_info "$target_dir" "$operation" "${json_files[@]}"
    
    if [ "$dry_run" != "true" ]; then
        if ! confirm_execution "Will batch execute $operation operation on the above ${#json_files[@]} analyses."; then
            return 1
        fi
    fi
    
    print_bold "=== Batch Processing of Multiple Analyses Started ==="
    
    local success_count=0
    local error_count=0
    
    # Process each file (skip confirmation)
    for json_file in "${json_files[@]}"; do
        echo
        if process_analysis_json "$json_file" "$operation" "$dry_run" "$update_permissions" "true"; then
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
QuickSight Analysis Creation and Update Script

Usage:
    ./analysis_manager.sh [options]

Options:
    -f, --file FILE       Process a single JSON file
    -d, --dir DIR         Batch process JSON files in directory
    -o, --operation OP    Specify operation (create|update|upsert)
                         - create: Create new only
                         - update: Update existing only  
                         - upsert: Update if exists, create if not
    -p, --permissions     Also update permissions (if permissions file exists)
    -n, --dry-run         Show execution plan without actual execution
    -h, --help            Show this help

Safety Features:
    - Display detailed information of processing targets before execution
    - Show complete list of all targets before batch processing
    - Show confirmation prompt before actual operations (except in dry-run mode)

Examples:
    # Create new from single file
    ./analysis_manager.sh -f analysis.json -o create
    
    # Update single file (including permissions)
    ./analysis_manager.sh -f analysis.json -o update -p
    
    # Batch upsert directory contents
    ./analysis_manager.sh -d ./analyses/ -o upsert
    
    # Upsert (update if exists, create if not)
    ./analysis_manager.sh -f analysis.json -o upsert
    
    # Dry run execution
    ./analysis_manager.sh -f analysis.json -o upsert --dry-run

File Structure:
    analyses/
      ├── analysis1.json          # Analysis basic information
      └── analysis2.json
    definitions/
      ├── analysis1-definition.json  # Analysis definition (visuals, etc.)
      └── analysis2-definition.json
    permissions/
      ├── analysis1-permissions.json # Permission settings
      └── analysis2-permissions.json

Notes:
    - JSON files support QuickSight backup format (.Analysis)
    - Definition files are automatically searched (in definitions/ directory)
    - Permission files are automatically searched in permissions/ directory
    - Pre-validation with validate-changes is recommended before actual AWS operations
EOF
}

# Option parsing
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
    process_analysis_json "$TARGET_FILE" "$OPERATION" "$DRY_RUN" "$UPDATE_PERMISSIONS"
else
    process_multiple_analyses "$TARGET_DIR" "$OPERATION" "$DRY_RUN" "$UPDATE_PERMISSIONS"
fi
