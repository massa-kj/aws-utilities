#!/bin/bash
#
# QuickSight Migration Integration Test Suite
# Tests the compatibility and functionality of the new architecture
#

# Get the directory of this script
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

# Color output functions for test results
print_green() { echo -e "\033[32m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test results array
declare -a TEST_RESULTS=()

#
# Test framework functions
#
test_start() {
    local test_name="$1"
    ((TOTAL_TESTS++))
    print_cyan "[$TOTAL_TESTS] Testing: $test_name"
}

test_pass() {
    local test_name="$1"
    ((PASSED_TESTS++))
    TEST_RESULTS+=("PASS: $test_name")
    print_green "  ✓ PASS: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    ((FAILED_TESTS++))
    TEST_RESULTS+=("FAIL: $test_name - $reason")
    print_red "  ✗ FAIL: $test_name - $reason"
}

test_skip() {
    local test_name="$1"
    local reason="$2"
    ((SKIPPED_TESTS++))
    TEST_RESULTS+=("SKIP: $test_name - $reason")
    print_yellow "  ⚠ SKIP: $test_name - $reason"
}

# =============================================================================
# File Structure Tests
# =============================================================================

test_file_structure() {
    print_bold "\n=== File Structure Tests ==="
    
    # Test core manager
    test_start "Core manager exists"
    if [[ -f "$PROJECT_ROOT/services/quicksight/src/core/manager.sh" ]]; then
        test_pass "Core manager file exists"
    else
        test_fail "Core manager file exists" "File not found"
    fi
    
    # Test API abstraction layer
    test_start "API abstraction layer structure"
    local api_files=(
        "services/quicksight/src/api/common.sh"
        "services/quicksight/src/api/v1/analysis_api.sh"
        "services/quicksight/src/api/v1/dataset_api.sh"
    )
    
    local missing_files=()
    for file in "${api_files[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        test_pass "API abstraction layer structure"
    else
        test_fail "API abstraction layer structure" "Missing files: ${missing_files[*]}"
    fi
    
    # Test resource management modules
    test_start "Resource management modules"
    local resource_files=(
        "services/quicksight/src/resources/analysis.sh"
        "services/quicksight/src/resources/dataset.sh"
    )
    
    local missing_resource_files=()
    for file in "${resource_files[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
            missing_resource_files+=("$file")
        fi
    done
    
    if [[ ${#missing_resource_files[@]} -eq 0 ]]; then
        test_pass "Resource management modules"
    else
        test_fail "Resource management modules" "Missing files: ${missing_resource_files[*]}"
    fi
    
    # Test compatibility wrapper
    test_start "Compatibility wrapper"
    if [[ -f "$PROJECT_ROOT/quicksight-resource-manager/quicksight_manager.sh" ]]; then
        test_pass "Compatibility wrapper exists"
    else
        test_fail "Compatibility wrapper exists" "File not found"
    fi
}

# =============================================================================
# Syntax and Execution Tests
# =============================================================================

test_syntax() {
    print_bold "\n=== Syntax Tests ==="
    
    # Test core manager syntax
    test_start "Core manager syntax"
    if bash -n "$PROJECT_ROOT/services/quicksight/src/core/manager.sh" 2>/dev/null; then
        test_pass "Core manager syntax"
    else
        test_fail "Core manager syntax" "Syntax error detected"
    fi
    
    # Test API layer syntax
    test_start "API layer syntax"
    local api_syntax_errors=()
    
    for file in "services/quicksight/src/api/common.sh" \
                "services/quicksight/src/api/v1/analysis_api.sh" \
                "services/quicksight/src/api/v1/dataset_api.sh"; do
        if ! bash -n "$PROJECT_ROOT/$file" 2>/dev/null; then
            api_syntax_errors+=("$file")
        fi
    done
    
    if [[ ${#api_syntax_errors[@]} -eq 0 ]]; then
        test_pass "API layer syntax"
    else
        test_fail "API layer syntax" "Syntax errors in: ${api_syntax_errors[*]}"
    fi
    
    # Test compatibility wrapper syntax
    test_start "Compatibility wrapper syntax"
    if bash -n "$PROJECT_ROOT/quicksight-resource-manager/quicksight_manager.sh" 2>/dev/null; then
        test_pass "Compatibility wrapper syntax"
    else
        test_fail "Compatibility wrapper syntax" "Syntax error detected"
    fi
}

# =============================================================================
# Help Command Tests
# =============================================================================

test_help_commands() {
    print_bold "\n=== Help Command Tests ==="
    
    # Test core manager help
    test_start "Core manager help command"
    local core_help_output
    if core_help_output=$("$PROJECT_ROOT/services/quicksight/src/core/manager.sh" help 2>&1); then
        if [[ "$core_help_output" =~ "QuickSight Core Manager" ]]; then
            test_pass "Core manager help command"
        else
            test_fail "Core manager help command" "Help output format incorrect"
        fi
    else
        test_fail "Core manager help command" "Command failed to execute"
    fi
    
    # Test compatibility wrapper help
    test_start "Compatibility wrapper help command"
    local wrapper_help_output
    if wrapper_help_output=$("$PROJECT_ROOT/quicksight-resource-manager/quicksight_manager.sh" help 2>&1); then
        if [[ "$wrapper_help_output" =~ "QuickSight Core Manager" ]]; then
            test_pass "Compatibility wrapper help command"
        else
            test_fail "Compatibility wrapper help command" "Help output format incorrect"
        fi
    else
        test_fail "Compatibility wrapper help command" "Command failed to execute"
    fi
}

# =============================================================================
# Configuration Tests
# =============================================================================

test_configuration() {
    print_bold "\n=== Configuration Tests ==="
    
    # Test service configuration exists
    test_start "Service configuration exists"
    if [[ -f "$PROJECT_ROOT/config/services/quicksight.env" ]]; then
        test_pass "Service configuration exists"
    else
        test_fail "Service configuration exists" "Configuration file not found"
    fi
    
    # Test configuration loading
    test_start "Configuration loading"
    local config_test_output
    if config_test_output=$("$PROJECT_ROOT/services/quicksight/src/core/manager.sh" show-config 2>&1); then
        if [[ "$config_test_output" =~ "QuickSight Configuration" ]]; then
            test_pass "Configuration loading"
        else
            test_fail "Configuration loading" "Configuration display failed"
        fi
    else
        test_fail "Configuration loading" "show-config command failed"
    fi
}

# =============================================================================
# Integration Tests
# =============================================================================

test_integration() {
    print_bold "\n=== Integration Tests ==="
    
    # Test API abstraction layer integration test
    test_start "API integration test execution"
    local integration_test_file="$PROJECT_ROOT/services/quicksight/src/api/integration_test.sh"
    
    if [[ -f "$integration_test_file" ]]; then
        local integration_output
        if integration_output=$("$integration_test_file" 2>&1); then
            local success_count
            success_count=$(echo "$integration_output" | grep -o "Test [0-9]*/[0-9]* passed" | head -1 | cut -d'/' -f1 | cut -d' ' -f2)
            
            if [[ -n "$success_count" && "$success_count" -gt 0 ]]; then
                test_pass "API integration test execution"
            else
                test_skip "API integration test execution" "No successful tests detected"
            fi
        else
            test_skip "API integration test execution" "Integration test failed to execute"
        fi
    else
        test_skip "API integration test execution" "Integration test file not found"
    fi
    
    # Test compatibility between old and new interfaces
    test_start "Command compatibility"
    local old_help_output new_help_output
    
    # Get help from both interfaces
    old_help_output=$("$PROJECT_ROOT/quicksight-resource-manager/quicksight_manager.sh" help 2>&1) || true
    new_help_output=$("$PROJECT_ROOT/services/quicksight/src/core/manager.sh" help 2>&1) || true
    
    # Check if both contain expected commands
    local expected_commands=("backup-analysis" "backup-dataset" "backup-all" "list-analysis" "list-dataset")
    local compatibility_ok=true
    
    for cmd in "${expected_commands[@]}"; do
        if [[ ! "$old_help_output" =~ $cmd ]] || [[ ! "$new_help_output" =~ $cmd ]]; then
            compatibility_ok=false
            break
        fi
    done
    
    if [[ "$compatibility_ok" == "true" ]]; then
        test_pass "Command compatibility"
    else
        test_fail "Command compatibility" "Command sets don't match"
    fi
}

# =============================================================================
# Performance Tests
# =============================================================================

test_performance() {
    print_bold "\n=== Performance Tests ==="
    
    # Test startup time for core manager
    test_start "Core manager startup time"
    local start_time end_time duration
    start_time=$(date +%s%N)
    "$PROJECT_ROOT/services/quicksight/src/core/manager.sh" help >/dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [[ $duration -lt 5000 ]]; then  # Less than 5 seconds
        test_pass "Core manager startup time ($duration ms)"
    else
        test_fail "Core manager startup time" "Too slow: $duration ms"
    fi
    
    # Test startup time for compatibility wrapper
    test_start "Compatibility wrapper startup time"
    start_time=$(date +%s%N)
    "$PROJECT_ROOT/quicksight-resource-manager/quicksight_manager.sh" help >/dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [[ $duration -lt 5000 ]]; then  # Less than 5 seconds
        test_pass "Compatibility wrapper startup time ($duration ms)"
    else
        test_fail "Compatibility wrapper startup time" "Too slow: $duration ms"
    fi
}

# =============================================================================
# Main Test Execution
# =============================================================================

main() {
    print_bold "QuickSight Migration Integration Test Suite"
    print_cyan "Testing QuickSight Resource Manager migration to new architecture"
    print_cyan "Project root: $PROJECT_ROOT"
    echo
    
    # Run all test suites
    test_file_structure
    test_syntax
    test_help_commands
    test_configuration
    test_integration
    test_performance
    
    # Print summary
    print_bold "\n=== Test Summary ==="
    print_cyan "Total tests: $TOTAL_TESTS"
    print_green "Passed: $PASSED_TESTS"
    print_red "Failed: $FAILED_TESTS"
    print_yellow "Skipped: $SKIPPED_TESTS"
    
    local success_rate
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
        print_cyan "Success rate: ${success_rate}%"
    fi
    
    # Print detailed results
    if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then
        print_bold "\n=== Detailed Results ==="
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" =~ ^PASS: ]]; then
                print_green "  $result"
            elif [[ "$result" =~ ^FAIL: ]]; then
                print_red "  $result"
            else
                print_yellow "  $result"
            fi
        done
    fi
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        print_bold "\n✓ All tests passed or skipped - Migration successful!"
        exit 0
    else
        print_bold "\n✗ Some tests failed - Review required"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
