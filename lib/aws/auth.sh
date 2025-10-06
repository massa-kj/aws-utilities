#!/bin/bash
#
# AWS Authentication Library
# Provides common authentication and AWS CLI validation functions
#

# Global variables for authentication state
AWS_AUTH_VALIDATED=false
AWS_ACCOUNT_ID=""
AWS_REGION=""

#
# Validate AWS CLI configuration and authentication
#
validate_aws_auth() {
    local quiet=${1:-false}
    
    # Check if AWS CLI is installed
    if ! command -v aws >/dev/null 2>&1; then
        if [[ "$quiet" != "true" ]]; then
            log_error "AWS CLI is not installed. Please install AWS CLI v2."
        fi
        return 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | head -n1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "$quiet" != "true" ]]; then
        log_info "AWS CLI version: $aws_version"
    fi
    
    # Test AWS credentials
    local caller_identity
    if ! caller_identity=$(aws sts get-caller-identity 2>/dev/null); then
        if [[ "$quiet" != "true" ]]; then
            log_error "AWS authentication failed. Please configure AWS credentials."
            log_info "Run: aws configure"
        fi
        return 1
    fi
    
    # Extract account ID and region
    AWS_ACCOUNT_ID=$(echo "$caller_identity" | jq -r '.Account')
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    if [[ "$quiet" != "true" ]]; then
        log_info "AWS Account ID: $AWS_ACCOUNT_ID"
        log_info "AWS Region: $AWS_REGION"
    fi
    
    AWS_AUTH_VALIDATED=true
    return 0
}

#
# Get AWS Account ID (validates auth if not already done)
#
get_aws_account_id() {
    if [[ "$AWS_AUTH_VALIDATED" != "true" ]]; then
        validate_aws_auth true || return 1
    fi
    echo "$AWS_ACCOUNT_ID"
}

#
# Get AWS Region (validates auth if not already done)
#
get_aws_region() {
    if [[ "$AWS_AUTH_VALIDATED" != "true" ]]; then
        validate_aws_auth true || return 1
    fi
    echo "$AWS_REGION"
}

#
# Set AWS Region override
#
set_aws_region() {
    local region="$1"
    if [[ -z "$region" ]]; then
        log_error "Region parameter is required"
        return 1
    fi
    
    AWS_REGION="$region"
    export AWS_DEFAULT_REGION="$region"
    log_info "AWS Region set to: $region"
}

#
# Execute AWS CLI command with error handling
#
aws_exec() {
    local cmd="$1"
    shift
    
    if [[ "$AWS_AUTH_VALIDATED" != "true" ]]; then
        validate_aws_auth true || return 1
    fi
    
    log_debug "Executing: aws $cmd $*"
    
    local output
    local exit_code
    
    output=$(aws "$cmd" "$@" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "$output"
        return 0
    else
        log_error "AWS command failed: aws $cmd $*"
        log_error "Error output: $output"
        return $exit_code
    fi
}

#
# Check if AWS service is available in current region
#
check_aws_service_availability() {
    local service="$1"
    local region="${2:-$AWS_REGION}"
    
    case "$service" in
        "quicksight")
            # QuickSight is available in specific regions
            case "$region" in
                "us-east-1"|"us-west-2"|"eu-west-1"|"ap-northeast-1"|"ap-southeast-1"|"ap-southeast-2")
                    return 0
                    ;;
                *)
                    log_warn "QuickSight may not be available in region: $region"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_warn "Service availability check not implemented for: $service"
            return 0
            ;;
    esac
}

# Export functions for use in other scripts
export -f validate_aws_auth
export -f get_aws_account_id
export -f get_aws_region
export -f set_aws_region
export -f aws_exec
export -f check_aws_service_availability
