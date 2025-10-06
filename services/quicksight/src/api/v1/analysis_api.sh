#!/bin/bash
#
# QuickSight Analysis API Abstraction Layer
# Provides high-level functions for QuickSight Analysis operations with
# standardized error handling, response processing, and retry logic
#

# Get the directory of this script
ANALYSIS_API_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common API functionality
source "$ANALYSIS_API_DIR/../common.sh"

# =============================================================================
# Analysis List Operations
# =============================================================================

#
# List all analyses in the account
# Returns: standardized response with analyses list
#
qs_analysis_list() {
    local max_results="${1:-100}"
    local next_token="$2"
    
    qs_log_operation_start "list" "analysis"
    
    local aws_args=("list-analyses" "--aws-account-id" "$(qs_get_account_id)")
    
    if [[ -n "$max_results" && "$max_results" -gt 0 ]]; then
        aws_args+=("--max-results" "$max_results")
    fi
    
    if [[ -n "$next_token" ]]; then
        aws_args+=("--next-token" "$next_token")
    fi
    
    local response
    response=$(qs_execute_aws_command "list" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "list" "analysis" "" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "list" "analysis" "$error_code" "$error_message" "" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# List analyses by name pattern
# Returns: standardized response with filtered analyses
#
qs_analysis_list_by_name() {
    local name_pattern="$1"
    
    if [[ -z "$name_pattern" ]]; then
        qs_create_error_response "list_by_name" "analysis" "InvalidParameter" "Name pattern is required"
        return 1
    fi
    
    qs_log_operation_start "list_by_name" "analysis"
    
    local list_response
    list_response=$(qs_analysis_list)
    
    if ! qs_is_success "$list_response"; then
        echo "$list_response"
        return 1
    fi
    
    # Filter analyses by name pattern
    local analyses_data filtered_analyses
    analyses_data=$(qs_get_response_data "$list_response")
    
    filtered_analyses=$(echo "$analyses_data" | jq \
        --arg pattern "$name_pattern" \
        '.AnalysisSummaryList | map(select(.Name | test($pattern; "i")))')
    
    local filtered_data
    filtered_data=$(echo "$analyses_data" | jq \
        --argjson filtered "$filtered_analyses" \
        '. + {AnalysisSummaryList: $filtered}')
    
    qs_create_success_response "list_by_name" "analysis" "$filtered_data"
}

# =============================================================================
# Analysis Detail Operations
# =============================================================================

#
# Describe analysis basic information
# Returns: standardized response with analysis details
#
qs_analysis_describe() {
    local analysis_id="$1"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "describe" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "describe" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "describe" "analysis" "$analysis_id"
    
    local aws_args=("describe-analysis" 
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id")
    
    local response
    response=$(qs_execute_aws_command "describe" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "describe" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "describe" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# Describe analysis definition (structure, sheets, visuals)
# Returns: standardized response with analysis definition
#
qs_analysis_describe_definition() {
    local analysis_id="$1"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "describe_definition" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "describe_definition" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "describe_definition" "analysis" "$analysis_id"
    
    local aws_args=("describe-analysis-definition"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id")
    
    local response
    response=$(qs_execute_aws_command "describe_definition" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "describe_definition" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "describe_definition" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# Describe analysis permissions
# Returns: standardized response with permissions
#
qs_analysis_describe_permissions() {
    local analysis_id="$1"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "describe_permissions" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "describe_permissions" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "describe_permissions" "analysis" "$analysis_id"
    
    local aws_args=("describe-analysis-permissions"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id")
    
    local response
    response=$(qs_execute_aws_command "describe_permissions" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "describe_permissions" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "describe_permissions" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

#
# Get comprehensive analysis information (basic + definition + permissions)
# Returns: standardized response with all analysis information
#
qs_analysis_get_full() {
    local analysis_id="$1"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "get_full" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    qs_log_operation_start "get_full" "analysis" "$analysis_id"
    
    # Get basic information
    local basic_response
    basic_response=$(qs_analysis_describe "$analysis_id")
    if ! qs_is_success "$basic_response"; then
        echo "$basic_response"
        return 1
    fi
    
    # Get definition
    local definition_response
    definition_response=$(qs_analysis_describe_definition "$analysis_id")
    local definition_data="null"
    if qs_is_success "$definition_response"; then
        definition_data=$(qs_get_response_data "$definition_response")
    fi
    
    # Get permissions
    local permissions_response
    permissions_response=$(qs_analysis_describe_permissions "$analysis_id")
    local permissions_data="null"
    if qs_is_success "$permissions_response"; then
        permissions_data=$(qs_get_response_data "$permissions_response")
    fi
    
    # Combine all information
    local basic_data combined_data
    basic_data=$(qs_get_response_data "$basic_response")
    
    combined_data=$(jq -n \
        --argjson basic "$basic_data" \
        --argjson definition "$definition_data" \
        --argjson permissions "$permissions_data" \
        '{
            basic: $basic,
            definition: $definition,
            permissions: $permissions
        }')
    
    qs_create_success_response "get_full" "analysis" "$combined_data"
}

# =============================================================================
# Analysis Creation Operations
# =============================================================================

#
# Create analysis from definition
# Returns: standardized response with creation result
#
qs_analysis_create() {
    local analysis_id="$1"
    local analysis_name="$2"
    local definition_json="$3"
    local theme_arn="$4"
    local source_entity="$5"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "create" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if [[ -z "$analysis_name" ]]; then
        qs_create_error_response "create" "analysis" "InvalidParameter" "Analysis name is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "create" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "create" "analysis" "$analysis_id"
    
    local aws_args=("create-analysis"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id"
                    "--name" "$analysis_name")
    
    # Add definition if provided
    if [[ -n "$definition_json" && "$definition_json" != "null" ]]; then
        local temp_definition_file="$QS_TEMP_DIR/definition_${analysis_id}.json"
        echo "$definition_json" > "$temp_definition_file"
        aws_args+=("--definition" "file://$temp_definition_file")
    fi
    
    # Add theme ARN if provided
    if [[ -n "$theme_arn" && "$theme_arn" != "null" ]]; then
        aws_args+=("--theme-arn" "$theme_arn")
    fi
    
    # Add source entity if provided
    if [[ -n "$source_entity" && "$source_entity" != "null" ]]; then
        local temp_source_file="$QS_TEMP_DIR/source_${analysis_id}.json"
        echo "$source_entity" > "$temp_source_file"
        aws_args+=("--source-entity" "file://$temp_source_file")
    fi
    
    local response
    response=$(qs_execute_aws_command "create" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "create" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "create" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Analysis Update Operations
# =============================================================================

#
# Update analysis definition
# Returns: standardized response with update result
#
qs_analysis_update() {
    local analysis_id="$1"
    local analysis_name="$2"
    local definition_json="$3"
    local theme_arn="$4"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "update" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if [[ -z "$analysis_name" ]]; then
        qs_create_error_response "update" "analysis" "InvalidParameter" "Analysis name is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "update" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "update" "analysis" "$analysis_id"
    
    local aws_args=("update-analysis"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id"
                    "--name" "$analysis_name")
    
    # Add definition if provided
    if [[ -n "$definition_json" && "$definition_json" != "null" ]]; then
        local temp_definition_file="$QS_TEMP_DIR/definition_${analysis_id}.json"
        echo "$definition_json" > "$temp_definition_file"
        aws_args+=("--definition" "file://$temp_definition_file")
    fi
    
    # Add theme ARN if provided
    if [[ -n "$theme_arn" && "$theme_arn" != "null" ]]; then
        aws_args+=("--theme-arn" "$theme_arn")
    fi
    
    local response
    response=$(qs_execute_aws_command "update" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "update" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "update" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Analysis Permission Operations
# =============================================================================

#
# Update analysis permissions
# Returns: standardized response with permission update result
#
qs_analysis_update_permissions() {
    local analysis_id="$1"
    local grant_permissions="$2"  # JSON array of permissions to grant
    local revoke_permissions="$3" # JSON array of permissions to revoke
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "update_permissions" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "update_permissions" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    if [[ -z "$grant_permissions" && -z "$revoke_permissions" ]]; then
        qs_create_error_response "update_permissions" "analysis" "InvalidParameter" "Either grant or revoke permissions must be specified"
        return 1
    fi
    
    qs_log_operation_start "update_permissions" "analysis" "$analysis_id"
    
    local aws_args=("update-analysis-permissions"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id")
    
    if [[ -n "$grant_permissions" && "$grant_permissions" != "null" ]]; then
        local temp_grant_file="$QS_TEMP_DIR/grant_${analysis_id}.json"
        echo "$grant_permissions" > "$temp_grant_file"
        aws_args+=("--grant-permissions" "file://$temp_grant_file")
    fi
    
    if [[ -n "$revoke_permissions" && "$revoke_permissions" != "null" ]]; then
        local temp_revoke_file="$QS_TEMP_DIR/revoke_${analysis_id}.json"
        echo "$revoke_permissions" > "$temp_revoke_file"
        aws_args+=("--revoke-permissions" "file://$temp_revoke_file")
    fi
    
    local response
    response=$(qs_execute_aws_command "update_permissions" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "update_permissions" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "update_permissions" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# Analysis Deletion Operations
# =============================================================================

#
# Delete analysis
# Returns: standardized response with deletion result
#
qs_analysis_delete() {
    local analysis_id="$1"
    local recovery_window_days="$2"  # Optional: 1-30 days
    local force_delete="${3:-false}"
    
    if [[ -z "$analysis_id" ]]; then
        qs_create_error_response "delete" "analysis" "InvalidParameter" "Analysis ID is required"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "$analysis_id"; then
        qs_create_error_response "delete" "analysis" "InvalidParameter" "Invalid analysis ID format: $analysis_id"
        return 1
    fi
    
    qs_log_operation_start "delete" "analysis" "$analysis_id"
    
    local aws_args=("delete-analysis"
                    "--aws-account-id" "$(qs_get_account_id)"
                    "--analysis-id" "$analysis_id")
    
    if [[ -n "$recovery_window_days" && "$recovery_window_days" -ge 1 && "$recovery_window_days" -le 30 ]]; then
        aws_args+=("--recovery-window-in-days" "$recovery_window_days")
    fi
    
    if [[ "$force_delete" == "true" ]]; then
        aws_args+=("--force-delete-without-recovery")
    fi
    
    local response
    response=$(qs_execute_aws_command "delete" "analysis" "${aws_args[@]}")
    local result=$?
    
    if [[ $result -eq 0 ]] && qs_is_success "$response"; then
        local request_id
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_success "delete" "analysis" "$analysis_id" "$request_id"
    else
        local error_info error_code error_message request_id
        error_info=$(qs_get_error_info "$response")
        error_code=$(echo "$error_info" | jq -r '.error_code')
        error_message=$(echo "$error_info" | jq -r '.error_message')
        request_id=$(qs_get_request_id "$response")
        qs_log_operation_failure "delete" "analysis" "$error_code" "$error_message" "$analysis_id" "$request_id"
    fi
    
    echo "$response"
    return $result
}

# =============================================================================
# High-Level Analysis Operations
# =============================================================================

#
# Check if analysis exists
# Returns: true/false
#
qs_analysis_exists() {
    local analysis_id="$1"
    
    if [[ -z "$analysis_id" ]]; then
        return 1
    fi
    
    local response
    response=$(qs_analysis_describe "$analysis_id")
    qs_is_success "$response"
}

#
# Create or update analysis (upsert operation)
# Returns: standardized response with upsert result
#
qs_analysis_upsert() {
    local analysis_id="$1"
    local analysis_name="$2"
    local definition_json="$3"
    local theme_arn="$4"
    local source_entity="$5"
    
    qs_log_operation_start "upsert" "analysis" "$analysis_id"
    
    if qs_analysis_exists "$analysis_id"; then
        log_debug "Analysis exists, performing update operation"
        qs_analysis_update "$analysis_id" "$analysis_name" "$definition_json" "$theme_arn"
    else
        log_debug "Analysis does not exist, performing create operation"
        qs_analysis_create "$analysis_id" "$analysis_name" "$definition_json" "$theme_arn" "$source_entity"
    fi
}

# =============================================================================
# Utility Functions for Legacy Compatibility
# =============================================================================

#
# Extract analysis parameters from existing JSON structure (for migration)
# Compatible with existing quicksight_lib.sh format
#
qs_analysis_extract_params_from_backup() {
    local backup_json="$1"
    
    if [[ -z "$backup_json" ]]; then
        qs_create_error_response "extract_params" "analysis" "InvalidParameter" "Backup JSON is required"
        return 1
    fi
    
    # Extract and clean analysis data
    local cleaned_data
    cleaned_data=$(echo "$backup_json" | jq '.Analysis | del(.Arn, .CreatedTime, .LastUpdatedTime, .Status)')
    
    if [[ $? -ne 0 ]]; then
        qs_create_error_response "extract_params" "analysis" "JSONParseError" "Failed to parse backup JSON"
        return 1
    fi
    
    qs_create_success_response "extract_params" "analysis" "$cleaned_data"
}

# =============================================================================
# Export Functions
# =============================================================================

# Export all analysis API functions
export -f qs_analysis_list qs_analysis_list_by_name
export -f qs_analysis_describe qs_analysis_describe_definition qs_analysis_describe_permissions
export -f qs_analysis_get_full
export -f qs_analysis_create qs_analysis_update
export -f qs_analysis_update_permissions
export -f qs_analysis_delete
export -f qs_analysis_exists qs_analysis_upsert
export -f qs_analysis_extract_params_from_backup
