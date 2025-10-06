#!/bin/bash
#
# QuickSight API Common Library
# Provides common functionality for QuickSight API calls including
# authentication, error handling, response standardization, and retry logic
#

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

# Load common libraries
if [[ -f "$PROJECT_ROOT/lib/loader.sh" ]]; then
    source "$PROJECT_ROOT/lib/loader.sh"
else
    echo "Error: Cannot load common libraries from $PROJECT_ROOT/lib/loader.sh" >&2
    exit 1
fi

# Load AWS utilities
source "$PROJECT_ROOT/lib/aws/auth.sh"
source "$PROJECT_ROOT/lib/aws/error_handler.sh"

# =============================================================================
# API Configuration and State Management
# =============================================================================

# QuickSight API configuration
declare -r QS_API_VERSION="2018-04-01" 2>/dev/null || QS_API_VERSION="2018-04-01"
declare -r QS_SERVICE="quicksight" 2>/dev/null || QS_SERVICE="quicksight"

# Response processing configuration
declare -r QS_TEMP_DIR="/tmp/quicksight-api-$$" 2>/dev/null || QS_TEMP_DIR="/tmp/quicksight-api-$$"
declare -r QS_MAX_RETRIES="${QS_MAX_RETRIES:-3}" 2>/dev/null || QS_MAX_RETRIES=${QS_MAX_RETRIES:-3}
declare -r QS_RETRY_DELAY="${QS_RETRY_DELAY:-2}" 2>/dev/null || QS_RETRY_DELAY=${QS_RETRY_DELAY:-2}
declare -r QS_TIMEOUT="${QS_TIMEOUT:-300}" 2>/dev/null || QS_TIMEOUT=${QS_TIMEOUT:-300}

# API state variables
QS_API_INITIALIZED=false
QS_AWS_ACCOUNT_ID=""
QS_AWS_REGION=""

# =============================================================================
# API Initialization and Authentication
# =============================================================================

#
# Initialize QuickSight API environment
# Sets up authentication, creates temp directories, validates access
#
qs_api_init() {
    local quiet=${1:-false}
    
    if [[ "$QS_API_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    if [[ "$quiet" != "true" ]]; then
        log_info "Initializing QuickSight API environment..."
    fi
    
    # Validate AWS authentication
    if ! validate_aws_auth "$quiet"; then
        log_error "AWS authentication validation failed"
        return 1
    fi
    
    # Set account ID and region
    QS_AWS_ACCOUNT_ID=$(get_aws_account_id)
    QS_AWS_REGION=$(get_aws_region)
    
    if [[ -z "$QS_AWS_ACCOUNT_ID" ]]; then
        log_error "Unable to determine AWS Account ID"
        return 1
    fi
    
    if [[ -z "$QS_AWS_REGION" ]]; then
        log_error "Unable to determine AWS Region"
        return 1
    fi
    
    # Create temporary directory for API operations
    mkdir -p "$QS_TEMP_DIR"
    trap 'rm -rf "$QS_TEMP_DIR"' EXIT
    
    if [[ "$quiet" != "true" ]]; then
        log_info "QuickSight API initialized successfully"
        log_debug "Account ID: $QS_AWS_ACCOUNT_ID"
        log_debug "Region: $QS_AWS_REGION"
        log_debug "Temp directory: $QS_TEMP_DIR"
    fi
    
    QS_API_INITIALIZED=true
    return 0
}

#
# Get current AWS account ID (ensures API is initialized)
#
qs_get_account_id() {
    if ! qs_api_init true; then
        return 1
    fi
    echo "$QS_AWS_ACCOUNT_ID"
}

#
# Get current AWS region (ensures API is initialized)
#
qs_get_region() {
    if ! qs_api_init true; then
        return 1
    fi
    echo "$QS_AWS_REGION"
}

# =============================================================================
# Standardized API Response Processing
# =============================================================================

#
# Standard API response structure
# {
#   "success": true/false,
#   "error_code": "ErrorCode" or null,
#   "error_message": "Error message" or null,
#   "data": {...} or null,
#   "metadata": {
#     "request_id": "...",
#     "timestamp": "...",
#     "operation": "...",
#     "resource_type": "...",
#     "api_version": "..."
#   }
# }
#

#
# Create standardized success response
#
qs_create_success_response() {
    local operation="$1"
    local resource_type="$2"
    local data="$3"
    local request_id="$4"
    
    jq -n \
        --arg success "true" \
        --arg operation "$operation" \
        --arg resource_type "$resource_type" \
        --arg api_version "$QS_API_VERSION" \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg request_id "${request_id:-$(uuidgen 2>/dev/null || echo "unknown")}" \
        --argjson data "${data:-null}" \
        '{
            success: ($success == "true"),
            error_code: null,
            error_message: null,
            data: $data,
            metadata: {
                request_id: $request_id,
                timestamp: $timestamp,
                operation: $operation,
                resource_type: $resource_type,
                api_version: $api_version
            }
        }'
}

#
# Create standardized error response
#
qs_create_error_response() {
    local operation="$1"
    local resource_type="$2"
    local error_code="$3"
    local error_message="$4"
    local request_id="$5"
    
    jq -n \
        --arg success "false" \
        --arg operation "$operation" \
        --arg resource_type "$resource_type" \
        --arg api_version "$QS_API_VERSION" \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg request_id "${request_id:-$(uuidgen 2>/dev/null || echo "unknown")}" \
        --arg error_code "$error_code" \
        --arg error_message "$error_message" \
        '{
            success: ($success == "true"),
            error_code: $error_code,
            error_message: $error_message,
            data: null,
            metadata: {
                request_id: $request_id,
                timestamp: $timestamp,
                operation: $operation,
                resource_type: $resource_type,
                api_version: $api_version
            }
        }'
}

#
# Parse AWS CLI error response and extract relevant information
#
qs_parse_aws_error() {
    local aws_output="$1"
    local default_error_code="${2:-UnknownError}"
    
    local error_code error_message
    
    # Try to extract error from AWS CLI JSON output
    if error_code=$(echo "$aws_output" | jq -r '.Error.Code // empty' 2>/dev/null) && [[ -n "$error_code" ]]; then
        error_message=$(echo "$aws_output" | jq -r '.Error.Message // "Unknown error"' 2>/dev/null)
    elif error_code=$(echo "$aws_output" | jq -r '.__type // empty' 2>/dev/null) && [[ -n "$error_code" ]]; then
        error_message=$(echo "$aws_output" | jq -r '.message // .Message // "Unknown error"' 2>/dev/null)
    else
        # Fallback: try to extract from plain text
        error_code="$default_error_code"
        error_message="$aws_output"
    fi
    
    jq -n \
        --arg error_code "$error_code" \
        --arg error_message "$error_message" \
        '{error_code: $error_code, error_message: $error_message}'
}

# =============================================================================
# Core API Call Functions
# =============================================================================

#
# Execute AWS CLI command with retry logic and standardized error handling
#
qs_execute_aws_command() {
    local operation="$1"
    local resource_type="$2"
    shift 2
    local aws_args=("$@")
    
    if ! qs_api_init true; then
        qs_create_error_response "$operation" "$resource_type" "InitializationError" "Failed to initialize QuickSight API"
        return 1
    fi
    
    local attempt=1
    local temp_output="$QS_TEMP_DIR/aws_output_$$"
    local temp_error="$QS_TEMP_DIR/aws_error_$$"
    
    log_debug "Executing AWS CLI command: aws quicksight ${aws_args[*]}"
    
    while [[ $attempt -le $QS_MAX_RETRIES ]]; do
        log_debug "Attempt $attempt of $QS_MAX_RETRIES"
        
        # Execute AWS CLI command
        if timeout "$QS_TIMEOUT" aws quicksight "${aws_args[@]}" \
            --output json \
            --region "$QS_AWS_REGION" \
            > "$temp_output" 2> "$temp_error"; then
            
            # Success - parse and return standardized response
            local aws_output request_id
            aws_output=$(cat "$temp_output")
            
            # Extract RequestId if available
            request_id=$(echo "$aws_output" | jq -r '.ResponseMetadata.RequestId // empty' 2>/dev/null)
            
            log_debug "AWS CLI command succeeded on attempt $attempt"
            qs_create_success_response "$operation" "$resource_type" "$aws_output" "$request_id"
            return 0
            
        else
            local exit_code=$?
            local aws_error_output
            aws_error_output=$(cat "$temp_error" 2>/dev/null)
            
            log_debug "AWS CLI command failed on attempt $attempt (exit code: $exit_code)"
            log_debug "Error output: $aws_error_output"
            
            # Check if this is a retryable error
            if qs_is_retryable_error "$aws_error_output" "$exit_code"; then
                if [[ $attempt -lt $QS_MAX_RETRIES ]]; then
                    log_debug "Retryable error detected, waiting ${QS_RETRY_DELAY}s before retry"
                    sleep "$QS_RETRY_DELAY"
                    ((attempt++))
                    continue
                else
                    log_debug "Max retries reached for retryable error"
                fi
            else
                log_debug "Non-retryable error detected"
            fi
            
            # Parse error and return standardized error response
            local error_info error_code error_message
            error_info=$(qs_parse_aws_error "$aws_error_output" "AWS_CLI_Error")
            error_code=$(echo "$error_info" | jq -r '.error_code')
            error_message=$(echo "$error_info" | jq -r '.error_message')
            
            qs_create_error_response "$operation" "$resource_type" "$error_code" "$error_message"
            return 1
        fi
    done
    
    # This shouldn't be reached, but just in case
    qs_create_error_response "$operation" "$resource_type" "MaxRetriesExceeded" "Maximum retry attempts exceeded"
    return 1
}

#
# Check if an error is retryable (rate limiting, temporary failures, etc.)
#
qs_is_retryable_error() {
    local error_output="$1"
    local exit_code="$2"
    
    # Check for rate limiting
    if echo "$error_output" | grep -qi "throttling\|rate.limit\|too.many.requests"; then
        return 0
    fi
    
    # Check for temporary service errors
    if echo "$error_output" | grep -qi "internal.error\|service.unavailable\|timeout"; then
        return 0
    fi
    
    # Check for specific HTTP status codes that are retryable
    if echo "$error_output" | grep -E "(429|502|503|504)" >/dev/null; then
        return 0
    fi
    
    # Non-retryable by default
    return 1
}

# =============================================================================
# Resource Validation Functions
# =============================================================================

#
# Validate QuickSight resource ID format
#
qs_validate_resource_id() {
    local resource_type="$1"
    local resource_id="$2"
    
    if [[ -z "$resource_id" ]]; then
        return 1
    fi
    
    case "$resource_type" in
        "analysis"|"dataset"|"dashboard"|"template")
            # QuickSight resource IDs: alphanumeric, hyphens, underscores, 1-512 chars
            if [[ "$resource_id" =~ ^[a-zA-Z0-9_-]{1,512}$ ]]; then
                return 0
            fi
            ;;
        *)
            log_warn "Unknown resource type for validation: $resource_type"
            return 1
            ;;
    esac
    
    return 1
}

#
# Validate AWS account ID format
#
qs_validate_account_id() {
    local account_id="$1"
    
    if [[ "$account_id" =~ ^[0-9]{12}$ ]]; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# Utility Functions
# =============================================================================

#
# Check if response indicates success
#
qs_is_success() {
    local response="$1"
    echo "$response" | jq -r '.success' 2>/dev/null | grep -q "true"
}

#
# Extract data from successful response
#
qs_get_response_data() {
    local response="$1"
    echo "$response" | jq -r '.data'
}

#
# Extract error information from failed response
#
qs_get_error_info() {
    local response="$1"
    echo "$response" | jq -r '{error_code: .error_code, error_message: .error_message}'
}

#
# Extract request ID from response
#
qs_get_request_id() {
    local response="$1"
    echo "$response" | jq -r '.metadata.request_id // "unknown"'
}

#
# Clean up temporary files
#
qs_cleanup() {
    if [[ -d "$QS_TEMP_DIR" ]]; then
        rm -rf "$QS_TEMP_DIR"
    fi
}

# =============================================================================
# Logging Integration
# =============================================================================

#
# Log API operation start
#
qs_log_operation_start() {
    local operation="$1"
    local resource_type="$2"
    local resource_id="${3:-}"
    
    if [[ -n "$resource_id" ]]; then
        log_info "Starting QuickSight $operation operation for $resource_type: $resource_id"
    else
        log_info "Starting QuickSight $operation operation for $resource_type"
    fi
}

#
# Log API operation success
#
qs_log_operation_success() {
    local operation="$1"
    local resource_type="$2"
    local resource_id="${3:-}"
    local request_id="${4:-}"
    
    local message="QuickSight $operation operation successful for $resource_type"
    if [[ -n "$resource_id" ]]; then
        message="$message: $resource_id"
    fi
    if [[ -n "$request_id" && "$request_id" != "unknown" ]]; then
        message="$message (Request ID: $request_id)"
    fi
    
    log_info "$message"
}

#
# Log API operation failure
#
qs_log_operation_failure() {
    local operation="$1"
    local resource_type="$2"
    local error_code="$3"
    local error_message="$4"
    local resource_id="${5:-}"
    local request_id="${6:-}"
    
    local message="QuickSight $operation operation failed for $resource_type"
    if [[ -n "$resource_id" ]]; then
        message="$message: $resource_id"
    fi
    message="$message - $error_code: $error_message"
    if [[ -n "$request_id" && "$request_id" != "unknown" ]]; then
        message="$message (Request ID: $request_id)"
    fi
    
    log_error "$message"
}

# =============================================================================
# Export Functions
# =============================================================================

# Make functions available to other scripts
export -f qs_api_init qs_get_account_id qs_get_region
export -f qs_create_success_response qs_create_error_response qs_parse_aws_error
export -f qs_execute_aws_command qs_is_retryable_error
export -f qs_validate_resource_id qs_validate_account_id
export -f qs_is_success qs_get_response_data qs_get_error_info qs_get_request_id
export -f qs_cleanup
export -f qs_log_operation_start qs_log_operation_success qs_log_operation_failure

# Make constants available
export QS_API_VERSION QS_SERVICE QS_TEMP_DIR QS_MAX_RETRIES QS_RETRY_DELAY QS_TIMEOUT
