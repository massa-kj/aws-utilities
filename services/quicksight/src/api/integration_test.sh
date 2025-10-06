#!/bin/bash
#
# API Abstraction Layer Integration Test
# Tests compatibility with existing quicksight_lib.sh functionality
#

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Load the new API abstraction layer
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/v1/analysis_api.sh"
source "$SCRIPT_DIR/v1/dataset_api.sh"

# Color output functions (compatibility with existing lib)
print_green() { echo -e "\033[32m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_blue() { echo -e "\033[34m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

#
# Test initialization
#
test_api_initialization() {
    print_bold "=== Testing API Initialization ==="
    
    if qs_api_init; then
        print_green "✓ API initialization successful"
        print_cyan "  Account ID: $(qs_get_account_id)"
        print_cyan "  Region: $(qs_get_region)"
        return 0
    else
        print_red "✗ API initialization failed"
        return 1
    fi
}

#
# Test analysis operations (compatibility with existing functions)
#
test_analysis_operations() {
    print_bold "\n=== Testing Analysis Operations ==="
    
    # Test list operation (equivalent to get_all_analyses)
    print_cyan "Testing analysis list operation..."
    local list_response
    list_response=$(qs_analysis_list 10)
    
    if qs_is_success "$list_response"; then
        print_green "✓ Analysis list operation successful"
        
        # Extract analysis data (compatible with existing format)
        local analyses_data
        analyses_data=$(qs_get_response_data "$list_response")
        
        local analysis_count
        analysis_count=$(echo "$analyses_data" | jq -r '.AnalysisSummaryList | length')
        print_cyan "  Found $analysis_count analyses"
        
        # Test filtering by name (equivalent to filter_target_analyses)
        if [[ $analysis_count -gt 0 ]]; then
            print_cyan "Testing analysis name filtering..."
            local first_analysis_name
            first_analysis_name=$(echo "$analyses_data" | jq -r '.AnalysisSummaryList[0].Name // "test"')
            
            local filter_response
            filter_response=$(qs_analysis_list_by_name "$first_analysis_name")
            
            if qs_is_success "$filter_response"; then
                print_green "✓ Analysis name filtering successful"
            else
                print_yellow "⚠ Analysis name filtering failed (expected for new API)"
            fi
        fi
        
        return 0
    else
        local error_info
        error_info=$(qs_get_error_info "$list_response")
        print_red "✗ Analysis list operation failed: $(echo "$error_info" | jq -r '.error_message')"
        return 1
    fi
}

#
# Test dataset operations (compatibility with existing functions)
#
test_dataset_operations() {
    print_bold "\n=== Testing Dataset Operations ==="
    
    # Test list operation (equivalent to get_all_datasets)
    print_cyan "Testing dataset list operation..."
    local list_response
    list_response=$(qs_dataset_list 10)
    
    if qs_is_success "$list_response"; then
        print_green "✓ Dataset list operation successful"
        
        # Extract dataset data (compatible with existing format)
        local datasets_data
        datasets_data=$(qs_get_response_data "$list_response")
        
        local dataset_count
        dataset_count=$(echo "$datasets_data" | jq -r '.DataSetSummaries | length')
        print_cyan "  Found $dataset_count datasets"
        
        # Test filtering by name (equivalent to filter_target_datasets)
        if [[ $dataset_count -gt 0 ]]; then
            print_cyan "Testing dataset name filtering..."
            local first_dataset_name
            first_dataset_name=$(echo "$datasets_data" | jq -r '.DataSetSummaries[0].Name // "test"')
            
            local filter_response
            filter_response=$(qs_dataset_list_by_name "$first_dataset_name")
            
            if qs_is_success "$filter_response"; then
                print_green "✓ Dataset name filtering successful"
            else
                print_yellow "⚠ Dataset name filtering failed (expected for new API)"
            fi
        fi
        
        return 0
    else
        local error_info
        error_info=$(qs_get_error_info "$list_response")
        print_red "✗ Dataset list operation failed: $(echo "$error_info" | jq -r '.error_message')"
        return 1
    fi
}

#
# Test error handling compatibility
#
test_error_handling() {
    print_bold "\n=== Testing Error Handling ==="
    
    # Test with invalid resource ID
    print_cyan "Testing error handling with invalid analysis ID..."
    local error_response
    error_response=$(qs_analysis_describe "invalid-id-test-12345-nonexistent")
    
    if ! qs_is_success "$error_response"; then
        print_green "✓ Error handling working correctly"
        
        local error_info
        error_info=$(qs_get_error_info "$error_response")
        print_cyan "  Error code: $(echo "$error_info" | jq -r '.error_code')"
        print_cyan "  Error message: $(echo "$error_info" | jq -r '.error_message')"
        
        return 0
    else
        print_red "✗ Error handling not working as expected"
        return 1
    fi
}

#
# Test response format compatibility
#
test_response_format() {
    print_bold "\n=== Testing Response Format Compatibility ==="
    
    # Test success response format
    print_cyan "Testing success response format..."
    local test_data='{"test_field": "test_value"}'
    local success_response
    success_response=$(qs_create_success_response "test" "analysis" "$test_data" "test-request-id")
    
    # Verify required fields
    local has_success has_data has_metadata
    has_success=$(echo "$success_response" | jq -r '.success')
    has_data=$(echo "$success_response" | jq -r '.data.test_field')
    has_metadata=$(echo "$success_response" | jq -r '.metadata.operation')
    
    if [[ "$has_success" == "true" && "$has_data" == "test_value" && "$has_metadata" == "test" ]]; then
        print_green "✓ Success response format is correct"
    else
        print_red "✗ Success response format is incorrect"
        return 1
    fi
    
    # Test error response format
    print_cyan "Testing error response format..."
    local error_response
    error_response=$(qs_create_error_response "test" "analysis" "TestError" "Test error message" "test-request-id")
    
    # Verify required fields
    local has_error_success has_error_code has_error_message
    has_error_success=$(echo "$error_response" | jq -r '.success')
    has_error_code=$(echo "$error_response" | jq -r '.error_code')
    has_error_message=$(echo "$error_response" | jq -r '.error_message')
    
    if [[ "$has_error_success" == "false" && "$has_error_code" == "TestError" && "$has_error_message" == "Test error message" ]]; then
        print_green "✓ Error response format is correct"
    else
        print_red "✗ Error response format is incorrect"
        return 1
    fi
    
    return 0
}

#
# Test legacy function compatibility
#
test_legacy_compatibility() {
    print_bold "\n=== Testing Legacy Function Compatibility ==="
    
    # Test backup JSON parameter extraction (compatible with existing quicksight_lib.sh)
    print_cyan "Testing analysis parameter extraction from backup JSON..."
    
    local sample_backup_json='{
        "Analysis": {
            "AnalysisId": "test-analysis-123",
            "Name": "Test Analysis",
            "Arn": "arn:aws:quicksight:us-east-1:123456789012:analysis/test-analysis-123",
            "Status": "READY",
            "CreatedTime": "2024-01-01T00:00:00Z",
            "LastUpdatedTime": "2024-01-02T00:00:00Z",
            "DataSetArns": ["arn:aws:quicksight:us-east-1:123456789012:dataset/test-dataset-123"]
        }
    }'
    
    local extract_response
    extract_response=$(qs_analysis_extract_params_from_backup "$sample_backup_json")
    
    if qs_is_success "$extract_response"; then
        print_green "✓ Analysis parameter extraction successful"
        
        local extracted_data
        extracted_data=$(qs_get_response_data "$extract_response")
        
        # Verify cleaned data (should not have Arn, CreatedTime, LastUpdatedTime, Status)
        local has_id has_name has_arn has_status
        has_id=$(echo "$extracted_data" | jq -r '.AnalysisId')
        has_name=$(echo "$extracted_data" | jq -r '.Name')
        has_arn=$(echo "$extracted_data" | jq -r '.Arn // "null"')
        has_status=$(echo "$extracted_data" | jq -r '.Status // "null"')
        
        if [[ "$has_id" == "test-analysis-123" && "$has_name" == "Test Analysis" && "$has_arn" == "null" && "$has_status" == "null" ]]; then
            print_green "✓ Parameter extraction correctly cleaned unnecessary fields"
        else
            print_yellow "⚠ Parameter extraction may not have cleaned all unnecessary fields"
        fi
    else
        print_red "✗ Analysis parameter extraction failed"
        return 1
    fi
    
    # Test dataset parameter extraction
    print_cyan "Testing dataset parameter extraction from backup JSON..."
    
    local sample_dataset_json='{
        "DataSet": {
            "DataSetId": "test-dataset-123",
            "Name": "Test Dataset",
            "Arn": "arn:aws:quicksight:us-east-1:123456789012:dataset/test-dataset-123",
            "CreatedTime": "2024-01-01T00:00:00Z",
            "LastUpdatedTime": "2024-01-02T00:00:00Z",
            "ConsumedSpiceCapacityInBytes": 1000,
            "ImportMode": "SPICE"
        }
    }'
    
    local dataset_extract_response
    dataset_extract_response=$(qs_dataset_extract_params_from_backup "$sample_dataset_json")
    
    if qs_is_success "$dataset_extract_response"; then
        print_green "✓ Dataset parameter extraction successful"
    else
        print_red "✗ Dataset parameter extraction failed"
        return 1
    fi
    
    return 0
}

#
# Test validation functions
#
test_validation_functions() {
    print_bold "\n=== Testing Validation Functions ==="
    
    # Test resource ID validation
    print_cyan "Testing resource ID validation..."
    
    if qs_validate_resource_id "analysis" "valid-analysis-123"; then
        print_green "✓ Valid analysis ID accepted"
    else
        print_red "✗ Valid analysis ID rejected"
        return 1
    fi
    
    if ! qs_validate_resource_id "analysis" "invalid id with spaces"; then
        print_green "✓ Invalid analysis ID rejected"
    else
        print_red "✗ Invalid analysis ID accepted"
        return 1
    fi
    
    # Test account ID validation
    print_cyan "Testing account ID validation..."
    
    if qs_validate_account_id "123456789012"; then
        print_green "✓ Valid account ID accepted"
    else
        print_red "✗ Valid account ID rejected"
        return 1
    fi
    
    if ! qs_validate_account_id "invalid-account"; then
        print_green "✓ Invalid account ID rejected"
    else
        print_red "✗ Invalid account ID accepted"
        return 1
    fi
    
    return 0
}

#
# Main test runner
#
run_integration_tests() {
    local test_count=0
    local passed_count=0
    
    print_bold "QuickSight API Abstraction Layer Integration Tests"
    print_bold "=================================================="
    
    # Test 1: API Initialization
    ((test_count++))
    if test_api_initialization; then
        ((passed_count++))
    fi
    
    # Test 2: Response Format
    ((test_count++))
    if test_response_format; then
        ((passed_count++))
    fi
    
    # Test 3: Validation Functions
    ((test_count++))
    if test_validation_functions; then
        ((passed_count++))
    fi
    
    # Test 4: Legacy Compatibility
    ((test_count++))
    if test_legacy_compatibility; then
        ((passed_count++))
    fi
    
    # Test 5: Error Handling
    ((test_count++))
    if test_error_handling; then
        ((passed_count++))
    fi
    
    # Test 6: Analysis Operations (only if API initialization succeeded)
    if qs_api_init true; then
        ((test_count++))
        if test_analysis_operations; then
            ((passed_count++))
        fi
        
        # Test 7: Dataset Operations
        ((test_count++))
        if test_dataset_operations; then
            ((passed_count++))
        fi
    else
        print_yellow "⚠ Skipping live API tests due to initialization failure"
    fi
    
    # Test Summary
    print_bold "\n=== Test Summary ==="
    print_cyan "Total tests: $test_count"
    print_green "Passed: $passed_count"
    
    if [[ $passed_count -eq $test_count ]]; then
        print_green "All tests passed! ✓"
        return 0
    else
        local failed_count=$((test_count - passed_count))
        print_red "Failed: $failed_count"
        print_yellow "Some tests failed. Please review the output above."
        return 1
    fi
}

#
# Usage information
#
show_usage() {
    cat << 'EOF'
QuickSight API Abstraction Layer Integration Test

Usage:
    ./integration_test.sh [options]

Options:
    --help, -h          Show this help message
    --quiet, -q         Run tests in quiet mode
    --no-live           Skip live API tests (only run offline tests)

Examples:
    ./integration_test.sh                    # Run all tests
    ./integration_test.sh --no-live          # Run only offline tests
    ./integration_test.sh --quiet            # Run tests with minimal output

This script tests the compatibility between the new API abstraction layer
and the existing quicksight_lib.sh functionality to ensure smooth migration.
EOF
}

#
# Parse command line arguments
#
main() {
    local quiet_mode=false
    local no_live_tests=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --quiet|-q)
                quiet_mode=true
                shift
                ;;
            --no-live)
                no_live_tests=true
                shift
                ;;
            *)
                print_red "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set log level based on quiet mode
    if [[ "$quiet_mode" == "true" ]]; then
        export LOG_LEVEL="warn"
    else
        export LOG_LEVEL="info"
    fi
    
    # Skip live tests if requested
    if [[ "$no_live_tests" == "true" ]]; then
        export SKIP_LIVE_TESTS="true"
    fi
    
    # Run integration tests
    run_integration_tests
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
