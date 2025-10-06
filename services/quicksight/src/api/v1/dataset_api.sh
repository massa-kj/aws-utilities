#!/bin/bash
#
# QuickSight Dataset API Abstraction Layer
# Provides high-level functions for QuickSight Dataset operations with
# standardized error handling, response processing, and retry logic
#

# Get the directory of this script
DATASET_API_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common API functionality
source "$DATASET_API_DIR/../common.sh"

# =============================================================================
# Dataset List Operations
# =============================================================================

#
# List all datasets in the account
# Returns: standardized response with datasets list
#
qs_dataset_list() {
    local max_results="${1:-100}"
    local next_token="$2"
    
    qs_log_operation_start "list" "dataset"
    
    local aws_args=("list-data-sets" "--aws-account-id" "$(qs_get_account_id)")
    
    if [[ -n "$max_results" && "$max_results" -gt 0 ]]; then
        aws_args+=("--max-results" "$max_results")
    fi
    
    if [[ -n "$next_token" ]]; then
        aws_args+=("--next-token" "$next_token")
    fi
    
    local response
    response=$(qs_execute_aws_command "list" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "list" "dataset" "" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "list" "dataset" "$error_code" "$error_message" "" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# List datasets by name pattern
# Returns: standardized response with filtered datasets
#
qs_dataset_list_by_name() {
    local name_pattern="$1"
    
    if [[ -z "$name_pattern" ]]; then
        qs_create_error_response "list_by_name" "dataset" "InvalidParameter" "Name pattern is required"
        return 1
    fi
    
    qs_log_operation_start "list_by_name" "dataset"
    
    local list_response
    list_response=$(qs_dataset_list)
    
    if ! qs_is_success "$list_response"; then
        echo "$list_response"
        return 1
    fi
    
    # Filter datasets by name pattern
    local datasets_data filtered_datasets
    datasets_data=$(qs_get_response_data "$list_response")
    
    filtered_datasets=$(echo "$datasets_data" | jq \
        --arg pattern "$name_pattern" \
        '.DataSetSummaries | map(select(.Name | test($pattern; "i")))')
    
    local filtered_data
    filtered_data=$(echo "$datasets_data" | jq \
        --argjson filtered "$filtered_datasets" \
        '. + {DataSetSummaries: $filtered}')
    
    qs_create_success_response "list_by_name" "dataset" "$filtered_data"
}

# =============================================================================
# Dataset Detail Operations
# =============================================================================

#
# Describe dataset basic information
# Returns: standardized response with dataset details
#
qs_dataset_describe() {
    local dataset_id="$1"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "describe" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "describe" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "describe" "dataset" "$dataset_id"
    
    local aws_args=("describe-data-set" 
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id")
    
    local response
    response=$(qs_execute_aws_command "describe" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "describe" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "describe" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# Describe dataset permissions
# Returns: standardized response with permissions
#
qs_dataset_describe_permissions() {
    local dataset_id="$1"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "describe_permissions" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "describe_permissions" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "describe_permissions" "dataset" "$dataset_id"
    
    local aws_args=("describe-data-set-permissions"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id")
    
    local response
    response=$(qs_execute_aws_command "describe_permissions" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "describe_permissions" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "describe_permissions" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# Get comprehensive dataset information (basic + permissions)
# Returns: standardized response with all dataset information
#
qs_dataset_get_full() {
    local dataset_id="$1"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "get_full" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    qs_log_operation_start "get_full" "dataset" "$dataset_id"
    
    # Get basic information
    local basic_response
    basic_response=$(qs_dataset_describe "$dataset_id")
    if ! qs_is_success "$basic_response"; then
        echo "$basic_response"
        return 1
    fi
    
    # Get permissions
    local permissions_response
    permissions_response=$(qs_dataset_describe_permissions "$dataset_id")
    local permissions_data="null"
    if qs_is_success "$permissions_response"; then
        permissions_data=$(qs_get_response_data "$permissions_response")
    fi
    
    # Combine all information
    local basic_data combined_data
    basic_data=$(qs_get_response_data "$basic_response")
    
    combined_data=$(jq -n \
        --argjson basic "$basic_data" \
        --argjson permissions "$permissions_data" \
        '{
            basic: $basic,
            permissions: $permissions
        }')
    
    qs_create_success_response "get_full" "dataset" "$combined_data"
}

# =============================================================================
# Dataset Creation Operations
# =============================================================================

#
# Create dataset
# Returns: standardized response with creation result
#
qs_dataset_create() {
    local dataset_id="$1"
    local dataset_name="$2"
    local physical_table_map="$3"
    local logical_table_map="$4"
    local import_mode="$5"
    local column_groups="$6"
    local field_folders="$7"
    local data_set_usage_configuration="$8"
    local column_level_permission_rules="$9"
    local row_level_permission_data_set="${10}"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "create" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if [[ -z "$dataset_name" ]]; then
        qs_create_error_response "create" "dataset" "InvalidParameter" "Dataset name is required"
        return 1
    fi
    
    if [[ -z "$physical_table_map" ]]; then
        qs_create_error_response "create" "dataset" "InvalidParameter" "Physical table map is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "create" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "create" "dataset" "$dataset_id"
    
    local aws_args=("create-data-set"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id"
                    "--name" "$dataset_name")
    
    # Add physical table map
    local temp_physical_file="$QS_TEMP_DIR/physical_${dataset_id}.json"
    echo "$physical_table_map" > "$temp_physical_file"
    aws_args+=("--physical-table-map" "file://$temp_physical_file")
    
    # Add logical table map if provided
    if [[ -n "$logical_table_map" && "$logical_table_map" != "null" ]]; then
        local temp_logical_file="$QS_TEMP_DIR/logical_${dataset_id}.json"
        echo "$logical_table_map" > "$temp_logical_file"
        aws_args+=("--logical-table-map" "file://$temp_logical_file")
    fi
    
    # Add import mode if provided
    if [[ -n "$import_mode" && "$import_mode" != "null" ]]; then
        aws_args+=("--import-mode" "$import_mode")
    fi
    
    # Add column groups if provided
    if [[ -n "$column_groups" && "$column_groups" != "null" ]]; then
        local temp_columns_file="$QS_TEMP_DIR/columns_${dataset_id}.json"
        echo "$column_groups" > "$temp_columns_file"
        aws_args+=("--column-groups" "file://$temp_columns_file")
    fi
    
    # Add field folders if provided
    if [[ -n "$field_folders" && "$field_folders" != "null" ]]; then
        local temp_fields_file="$QS_TEMP_DIR/fields_${dataset_id}.json"
        echo "$field_folders" > "$temp_fields_file"
        aws_args+=("--field-folders" "file://$temp_fields_file")
    fi
    
    # Add data set usage configuration if provided
    if [[ -n "$data_set_usage_configuration" && "$data_set_usage_configuration" != "null" ]]; then
        local temp_usage_file="$QS_TEMP_DIR/usage_${dataset_id}.json"
        echo "$data_set_usage_configuration" > "$temp_usage_file"
        aws_args+=("--data-set-usage-configuration" "file://$temp_usage_file")
    fi
    
    # Add column level permission rules if provided
    if [[ -n "$column_level_permission_rules" && "$column_level_permission_rules" != "null" ]]; then
        local temp_column_perms_file="$QS_TEMP_DIR/column_perms_${dataset_id}.json"
        echo "$column_level_permission_rules" > "$temp_column_perms_file"
        aws_args+=("--column-level-permission-rules" "file://$temp_column_perms_file")
    fi
    
    # Add row level permission data set if provided
    if [[ -n "$row_level_permission_data_set" && "$row_level_permission_data_set" != "null" ]]; then
        local temp_row_perms_file="$QS_TEMP_DIR/row_perms_${dataset_id}.json"
        echo "$row_level_permission_data_set" > "$temp_row_perms_file"
        aws_args+=("--row-level-permission-data-set" "file://$temp_row_perms_file")
    fi
    
    local response
    response=$(qs_execute_aws_command "create" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "create" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "create" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Dataset Update Operations
# =============================================================================

#
# Update dataset
# Returns: standardized response with update result
#
qs_dataset_update() {
    local dataset_id="$1"
    local dataset_name="$2"
    local physical_table_map="$3"
    local logical_table_map="$4"
    local import_mode="$5"
    local column_groups="$6"
    local field_folders="$7"
    local row_level_permission_data_set="$8"
    local column_level_permission_rules="$9"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "update" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if [[ -z "$dataset_name" ]]; then
        qs_create_error_response "update" "dataset" "InvalidParameter" "Dataset name is required"
        return 1
    fi
    
    if [[ -z "$physical_table_map" ]]; then
        qs_create_error_response "update" "dataset" "InvalidParameter" "Physical table map is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "update" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "update" "dataset" "$dataset_id"
    
    local aws_args=("update-data-set"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id"
                    "--name" "$dataset_name")
    
    # Add physical table map
    local temp_physical_file="$QS_TEMP_DIR/physical_${dataset_id}.json"
    echo "$physical_table_map" > "$temp_physical_file"
    aws_args+=("--physical-table-map" "file://$temp_physical_file")
    
    # Add logical table map if provided
    if [[ -n "$logical_table_map" && "$logical_table_map" != "null" ]]; then
        local temp_logical_file="$QS_TEMP_DIR/logical_${dataset_id}.json"
        echo "$logical_table_map" > "$temp_logical_file"
        aws_args+=("--logical-table-map" "file://$temp_logical_file")
    fi
    
    # Add import mode if provided
    if [[ -n "$import_mode" && "$import_mode" != "null" ]]; then
        aws_args+=("--import-mode" "$import_mode")
    fi
    
    # Add column groups if provided
    if [[ -n "$column_groups" && "$column_groups" != "null" ]]; then
        local temp_columns_file="$QS_TEMP_DIR/columns_${dataset_id}.json"
        echo "$column_groups" > "$temp_columns_file"
        aws_args+=("--column-groups" "file://$temp_columns_file")
    fi
    
    # Add field folders if provided
    if [[ -n "$field_folders" && "$field_folders" != "null" ]]; then
        local temp_fields_file="$QS_TEMP_DIR/fields_${dataset_id}.json"
        echo "$field_folders" > "$temp_fields_file"
        aws_args+=("--field-folders" "file://$temp_fields_file")
    fi
    
    # Add row level permission data set if provided
    if [[ -n "$row_level_permission_data_set" && "$row_level_permission_data_set" != "null" ]]; then
        local temp_row_perms_file="$QS_TEMP_DIR/row_perms_${dataset_id}.json"
        echo "$row_level_permission_data_set" > "$temp_row_perms_file"
        aws_args+=("--row-level-permission-data-set" "file://$temp_row_perms_file")
    fi
    
    # Add column level permission rules if provided
    if [[ -n "$column_level_permission_rules" && "$column_level_permission_rules" != "null" ]]; then
        local temp_column_perms_file="$QS_TEMP_DIR/column_perms_${dataset_id}.json"
        echo "$column_level_permission_rules" > "$temp_column_perms_file"
        aws_args+=("--column-level-permission-rules" "file://$temp_column_perms_file")
    fi
    
    local response
    response=$(qs_execute_aws_command "update" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "update" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "update" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Dataset Permission Operations
# =============================================================================

#
# Update dataset permissions
# Returns: standardized response with permission update result
#
qs_dataset_update_permissions() {
    local dataset_id="$1"
    local grant_permissions="$2"  # JSON array of permissions to grant
    local revoke_permissions="$3" # JSON array of permissions to revoke
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "update_permissions" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "update_permissions" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    if [[ -z "$grant_permissions" && -z "$revoke_permissions" ]]; then
        qs_create_error_response "update_permissions" "dataset" "InvalidParameter" "Either grant or revoke permissions must be specified"
        return 1
    fi
    
    qs_log_operation_start "update_permissions" "dataset" "$dataset_id"
    
    local aws_args=("update-data-set-permissions"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id")
    
    if [[ -n "$grant_permissions" && "$grant_permissions" != "null" ]]; then
        local temp_grant_file="$QS_TEMP_DIR/grant_${dataset_id}.json"
        echo "$grant_permissions" > "$temp_grant_file"
        aws_args+=("--grant-permissions" "file://$temp_grant_file")
    fi
    
    if [[ -n "$revoke_permissions" && "$revoke_permissions" != "null" ]]; then
        local temp_revoke_file="$QS_TEMP_DIR/revoke_${dataset_id}.json"
        echo "$revoke_permissions" > "$temp_revoke_file"
        aws_args+=("--revoke-permissions" "file://$temp_revoke_file")
    fi
    
    local response
    response=$(qs_execute_aws_command "update_permissions" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "update_permissions" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "update_permissions" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Dataset Deletion Operations
# =============================================================================

#
# Delete dataset
# Returns: standardized response with deletion result
#
qs_dataset_delete() {
    local dataset_id="$1"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "delete" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "delete" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "delete" "dataset" "$dataset_id"
    
    local aws_args=("delete-data-set"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id")
    
    local response
    response=$(qs_execute_aws_command "delete" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "delete" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "delete" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Dataset Refresh Operations
# =============================================================================

#
# Create dataset ingestion/refresh
# Returns: standardized response with ingestion result
#
qs_dataset_create_ingestion() {
    local dataset_id="$1"
    local ingestion_id="$2"
    local ingestion_type="${3:-INCREMENTAL_REFRESH}"
    local request_source="${4:-MANUAL}"
    
    if [[ -z "$dataset_id" ]]; then
        qs_create_error_response "create_ingestion" "dataset" "InvalidParameter" "Dataset ID is required"
        return 1
    fi
    
    if [[ -z "$ingestion_id" ]]; then
        qs_create_error_response "create_ingestion" "dataset" "InvalidParameter" "Ingestion ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "dataset" "$dataset_id"; then
        qs_create_error_response "create_ingestion" "dataset" "InvalidParameter" "Invalid dataset ID format: $dataset_id"
        return 1
    fi
    
    qs_log_operation_start "create_ingestion" "dataset" "$dataset_id"
    
    local aws_args=("create-ingestion"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--data-set-id" "$dataset_id"
                    "--ingestion-id" "$ingestion_id"
                    "--ingestion-type" "$ingestion_type"
                    "--request-source" "$request_source")
    
    local response
    response=$(qs_execute_aws_command "create_ingestion" "dataset" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "create_ingestion" "dataset" "$dataset_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "create_ingestion" "dataset" "$error_code" "$error_message" "$dataset_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# High-Level Dataset Operations
# =============================================================================

#
# Check if dataset exists
# Returns: true/false
#
qs_dataset_exists() {
    local dataset_id="$1"
    
    if [[ -z "$dataset_id" ]]; then
        return 1
    fi
    
    local response
    response=$(qs_dataset_describe "$dataset_id")
    qs_is_success "$response"
}

#
# Create or update dataset (upsert operation)
# Returns: standardized response with upsert result
#
qs_dataset_upsert() {
    local dataset_id="$1"
    local dataset_name="$2"
    local physical_table_map="$3"
    local logical_table_map="$4"
    local import_mode="$5"
    local column_groups="$6"
    local field_folders="$7"
    shift 7
    local additional_args=("$@")
    
    qs_log_operation_start "upsert" "dataset" "$dataset_id"
    
    if qs_dataset_exists "$dataset_id"; then
        log_debug "Dataset exists, performing update operation"
        qs_dataset_update "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode" "$column_groups" "$field_folders" "${additional_args[@]}"
    else
        log_debug "Dataset does not exist, performing create operation"
        qs_dataset_create "$dataset_id" "$dataset_name" "$physical_table_map" "$logical_table_map" "$import_mode" "$column_groups" "$field_folders" "${additional_args[@]}"
    fi
}

# =============================================================================
# Utility Functions for Legacy Compatibility
# =============================================================================

#
# Extract dataset parameters from existing JSON structure (for migration)
# Compatible with existing quicksight_lib.sh format
#
qs_dataset_extract_params_from_backup() {
    local backup_json="$1"
    
    if [[ -z "$backup_json" ]]; then
        qs_create_error_response "extract_params" "dataset" "InvalidParameter" "Backup JSON is required"
        return 1
    fi
    
    # Extract and clean dataset data
    local cleaned_data
    cleaned_data=$(echo "$backup_json" | jq '.DataSet | del(.Arn, .CreatedTime, .LastUpdatedTime, .ConsumedSpiceCapacityInBytes)')
    
    if [[ $? -ne 0 ]]; then
        qs_create_error_response "extract_params" "dataset" "JSONParseError" "Failed to parse backup JSON"
        return 1
    fi
    
    qs_create_success_response "extract_params" "dataset" "$cleaned_data"
}

# =============================================================================
# Export Functions
# =============================================================================

# Export all dataset API functions
export -f qs_dataset_list qs_dataset_list_by_name
export -f qs_dataset_describe qs_dataset_describe_permissions
export -f qs_dataset_get_full
export -f qs_dataset_create qs_dataset_update
export -f qs_dataset_update_permissions
export -f qs_dataset_delete
export -f qs_dataset_create_ingestion
export -f qs_dataset_exists qs_dataset_upsert
export -f qs_dataset_extract_params_from_backup
