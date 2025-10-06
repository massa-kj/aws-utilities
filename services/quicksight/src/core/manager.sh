#!/bin/bash
#
# QuickSight Core Manager
# Modern implementation using the new API abstraction layer
# Compatible with existing quicksight_manager.sh functionality
#

# Get the directory of this script
CORE_MANAGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$CORE_MANAGER_DIR/../../../.." && pwd)"

# Load API abstraction layer and resource management modules
source "$CORE_MANAGER_DIR/../api/common.sh"
source "$CORE_MANAGER_DIR/../api/v1/analysis_api.sh"
source "$CORE_MANAGER_DIR/../api/v1/dataset_api.sh"
source "$CORE_MANAGER_DIR/../resources/analysis.sh"
source "$CORE_MANAGER_DIR/../resources/dataset.sh"

# Load configuration management
source "$PROJECT_ROOT/lib/utils/config_manager.sh"

# Color output functions (compatibility with existing lib)
print_green() { echo -e "\033[32m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_blue() { echo -e "\033[34m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

# =============================================================================
# Configuration and Initialization
# =============================================================================

#
# Load QuickSight service configuration
#
load_quicksight_config() {
    # Load service-specific configuration
    if ! load_service_config "quicksight"; then
        log_warn "Failed to load QuickSight service configuration, using defaults"
    fi
    
    # Set default values if not configured
    TARGET_ANALYSES=${TARGET_ANALYSES:-()}
    TARGET_DATASETS=${TARGET_DATASETS:-()}
    
    # Convert comma-separated strings to arrays if needed
    if [[ "${TARGET_ANALYSES}" =~ , ]]; then
        IFS=',' read -ra TARGET_ANALYSES <<< "${TARGET_ANALYSES}"
    fi
    
    if [[ "${TARGET_DATASETS}" =~ , ]]; then
        IFS=',' read -ra TARGET_DATASETS <<< "${TARGET_DATASETS}"
    fi
    
    return 0
}

#
# Validate dependencies and configuration
#
check_dependencies() {
    if ! qs_api_init true; then
        print_red "Error: Failed to initialize QuickSight API"
        print_yellow "Please ensure AWS CLI is configured and you have proper credentials"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_red "Error: jq is not installed"
        print_yellow "Please install jq: sudo apt-get install jq"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Backup Operations
# =============================================================================

#
# Backup analyses using new API abstraction layer
#
cmd_backup_analysis() {
    print_bold "=== QuickSight Analysis Backup ==="
    
    # Check dependencies and initialize
    if ! check_dependencies; then
        exit 1
    fi
    
    print_yellow "1. Retrieving all analyses list..."
    local list_response
    list_response=$(qs_analysis_list)
    
    if ! qs_is_success "$list_response"; then
        print_red "Failed to retrieve analyses list"
        local error_info
        error_info=$(qs_get_error_info "$list_response")
        print_red "Error: $(echo "$error_info" | jq -r '.error_message')"
        exit 1
    fi
    
    local all_analyses
    all_analyses=$(qs_get_response_data "$list_response")
    
    local analysis_count
    analysis_count=$(echo "$all_analyses" | jq -r '.AnalysisSummaryList | length')
    print_cyan "Retrieved analyses count: $analysis_count"
    
    # Filter target analyses
    print_yellow "2. Filtering target analyses..."
    local matched_analyses=()
    local analysis_ids=()
    
    if [[ ${#TARGET_ANALYSES[@]} -eq 0 ]]; then
        print_yellow "No target analyses configured, backing up all analyses"
        while IFS= read -r analysis; do
            matched_analyses+=("$analysis")
            local analysis_id
            analysis_id=$(echo "$analysis" | jq -r '.AnalysisId')
            analysis_ids+=("$analysis_id")
        done < <(echo "$all_analyses" | jq -c '.AnalysisSummaryList[]')
    else
        for target_name in "${TARGET_ANALYSES[@]}"; do
            local matched_analysis
            matched_analysis=$(echo "$all_analyses" | jq -c --arg name "$target_name" \
                '.AnalysisSummaryList[] | select(.Name == $name)')
            
            if [[ -n "$matched_analysis" ]]; then
                matched_analyses+=("$matched_analysis")
                local analysis_id
                analysis_id=$(echo "$matched_analysis" | jq -r '.AnalysisId')
                analysis_ids+=("$analysis_id")
            else
                print_yellow "Target analysis not found: $target_name"
            fi
        done
    fi
    
    if [[ ${#matched_analyses[@]} -eq 0 ]]; then
        print_red "No analyses to backup"
        exit 1
    fi
    
    print_cyan "Target analyses count: ${#matched_analyses[@]}"
    
    # Create backup directory
    local backup_dir
    backup_dir="quicksight-analysis-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir/analyses"
    mkdir -p "$backup_dir/definitions"
    mkdir -p "$backup_dir/permissions"
    print_yellow "3. Created backup directory: $backup_dir"
    
    # Backup each analysis
    print_yellow "4. Backing up analyses..."
    local success_count=0
    local error_count=0
    local backup_summary=()
    
    for i in "${!matched_analyses[@]}"; do
        local analysis
        analysis="${matched_analyses[i]}"
        
        local analysis_id analysis_name
        analysis_id=$(echo "$analysis" | jq -r '.AnalysisId')
        analysis_name=$(echo "$analysis" | jq -r '.Name')
        
        print_cyan "  Backing up: $analysis_name (ID: $analysis_id)"
        
        # Safe filename
        local safe_filename
        safe_filename=$(echo "$analysis_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get analysis basic information
        local basic_response
        basic_response=$(qs_analysis_describe "$analysis_id")
        
        if qs_is_success "$basic_response"; then
            local basic_data
            basic_data=$(qs_get_response_data "$basic_response")
            echo "$basic_data" > "$backup_dir/analyses/${safe_filename}-${analysis_id}.json"
            print_green "    ✓ Basic information saved"
        else
            print_red "    ✗ Basic information retrieval error"
            ((error_count++))
            continue
        fi
        
        # Get analysis definition
        local definition_response
        definition_response=$(qs_analysis_describe_definition "$analysis_id")
        
        if qs_is_success "$definition_response"; then
            local definition_data
            definition_data=$(qs_get_response_data "$definition_response")
            echo "$definition_data" > "$backup_dir/definitions/${safe_filename}-${analysis_id}-definition.json"
            print_green "    ✓ Definition information saved"
            
            # Extract sheet and visual counts
            local sheet_count visual_count
            sheet_count=$(echo "$definition_data" | jq -r '.Definition.Sheets | length // 0')
            visual_count=$(echo "$definition_data" | jq -r '[.Definition.Sheets[]?.Visuals | length] | add // 0')
            
            backup_summary+=("$analysis_name|$analysis_id|$sheet_count|$visual_count")
        else
            print_yellow "    ⚠ Definition information retrieval failed"
            backup_summary+=("$analysis_name|$analysis_id|0|0")
        fi
        
        # Get permissions
        local permissions_response
        permissions_response=$(qs_analysis_describe_permissions "$analysis_id")
        
        if qs_is_success "$permissions_response"; then
            local permissions_data
            permissions_data=$(qs_get_response_data "$permissions_response")
            echo "$permissions_data" > "$backup_dir/permissions/${safe_filename}-${analysis_id}-permissions.json"
            print_green "    ✓ Permission information saved"
        else
            print_yellow "    ⚠ Permission information retrieval failed"
        fi
        
        ((success_count++))
    done
    
    # Save summary information
    save_analysis_backup_summary "$backup_dir" "${analysis_ids[@]}" "${backup_summary[@]}"
    
    if [[ $error_count -eq 0 ]]; then
        print_green "\n=== Backup Completed ==="
        print_cyan "Backup location: $backup_dir"
        print_cyan "Successful: $success_count analyses"
    else
        print_yellow "\n=== Backup Completed with Warnings ==="
        print_cyan "Backup location: $backup_dir"
        print_cyan "Successful: $success_count analyses"
        print_yellow "Warnings: $error_count analyses"
    fi
}

#
# Backup datasets using new API abstraction layer
#
cmd_backup_dataset() {
    print_bold "=== QuickSight Dataset Backup ==="
    
    # Check dependencies and initialize
    if ! check_dependencies; then
        exit 1
    fi
    
    print_yellow "1. Retrieving all datasets list..."
    local list_response
    list_response=$(qs_dataset_list)
    
    if ! qs_is_success "$list_response"; then
        print_red "Failed to retrieve datasets list"
        local error_info
        error_info=$(qs_get_error_info "$list_response")
        print_red "Error: $(echo "$error_info" | jq -r '.error_message')"
        exit 1
    fi
    
    local all_datasets
    all_datasets=$(qs_get_response_data "$list_response")
    
    local dataset_count
    dataset_count=$(echo "$all_datasets" | jq -r '.DataSetSummaries | length')
    print_cyan "Retrieved datasets count: $dataset_count"
    
    # Filter target datasets
    print_yellow "2. Filtering target datasets..."
    local matched_datasets=()
    local dataset_ids=()
    
    if [[ ${#TARGET_DATASETS[@]} -eq 0 ]]; then
        print_yellow "No target datasets configured, backing up all datasets"
        while IFS= read -r dataset; do
            matched_datasets+=("$dataset")
            local dataset_id
            dataset_id=$(echo "$dataset" | jq -r '.DataSetId')
            dataset_ids+=("$dataset_id")
        done < <(echo "$all_datasets" | jq -c '.DataSetSummaries[]')
    else
        for target_name in "${TARGET_DATASETS[@]}"; do
            local matched_dataset
            matched_dataset=$(echo "$all_datasets" | jq -c --arg name "$target_name" \
                '.DataSetSummaries[] | select(.Name == $name)')
            
            if [[ -n "$matched_dataset" ]]; then
                matched_datasets+=("$matched_dataset")
                local dataset_id
                dataset_id=$(echo "$matched_dataset" | jq -r '.DataSetId')
                dataset_ids+=("$dataset_id")
            else
                print_yellow "Target dataset not found: $target_name"
            fi
        done
    fi
    
    if [[ ${#matched_datasets[@]} -eq 0 ]]; then
        print_red "No datasets to backup"
        exit 1
    fi
    
    print_cyan "Target datasets count: ${#matched_datasets[@]}"
    
    # Create backup directory
    local backup_dir
    backup_dir="quicksight-dataset-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir/datasets"
    mkdir -p "$backup_dir/permissions"
    print_yellow "3. Created backup directory: $backup_dir"
    
    # Backup each dataset
    print_yellow "4. Backing up datasets..."
    local success_count=0
    local error_count=0
    local backup_summary=()
    
    for i in "${!matched_datasets[@]}"; do
        local dataset
        dataset="${matched_datasets[i]}"
        
        local dataset_id dataset_name import_mode
        dataset_id=$(echo "$dataset" | jq -r '.DataSetId')
        dataset_name=$(echo "$dataset" | jq -r '.Name')
        import_mode=$(echo "$dataset" | jq -r '.ImportMode // "SPICE"')
        
        print_cyan "  Backing up: $dataset_name (ID: $dataset_id)"
        
        # Safe filename
        local safe_filename
        safe_filename=$(echo "$dataset_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get dataset detailed information
        local detail_response
        detail_response=$(qs_dataset_describe "$dataset_id")
        
        if qs_is_success "$detail_response"; then
            local detail_data
            detail_data=$(qs_get_response_data "$detail_response")
            echo "$detail_data" > "$backup_dir/datasets/${safe_filename}-${dataset_id}.json"
            print_green "    ✓ Detailed information saved"
            
            backup_summary+=("$dataset_name|$dataset_id|$import_mode")
        else
            print_red "    ✗ Detailed information retrieval error"
            ((error_count++))
            continue
        fi
        
        # Get permissions
        local permissions_response
        permissions_response=$(qs_dataset_describe_permissions "$dataset_id")
        
        if qs_is_success "$permissions_response"; then
            local permissions_data
            permissions_data=$(qs_get_response_data "$permissions_response")
            echo "$permissions_data" > "$backup_dir/permissions/${safe_filename}-${dataset_id}-permissions.json"
            print_green "    ✓ Permission information saved"
        else
            print_yellow "    ⚠ Permission information retrieval failed"
        fi
        
        ((success_count++))
    done
    
    # Save summary information
    save_dataset_backup_summary "$backup_dir" "${dataset_ids[@]}" "${backup_summary[@]}"
    
    if [[ $error_count -eq 0 ]]; then
        print_green "\n=== Backup Completed ==="
        print_cyan "Backup location: $backup_dir"
        print_cyan "Successful: $success_count datasets"
    else
        print_yellow "\n=== Backup Completed with Warnings ==="
        print_cyan "Backup location: $backup_dir"
        print_cyan "Successful: $success_count datasets"
        print_yellow "Warnings: $error_count datasets"
    fi
}

#
# Backup both analyses and datasets
#
cmd_backup_all() {
    local base_backup_dir
    base_backup_dir="quicksight-full-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$base_backup_dir"
    
    print_bold "=== QuickSight Full Backup ==="
    print_cyan "Backup directory: $base_backup_dir"
    
    if ! check_dependencies; then
        exit 1
    fi
    
    local error_count=0
    
    # Backup analyses
    print_yellow "\n=== Analyses Backup ==="
    (
        # Override backup directory name
        backup_dir="$base_backup_dir/analyses"
        cmd_backup_analysis_internal "$backup_dir"
    ) || ((error_count++))
    
    # Backup datasets  
    print_yellow "\n=== Datasets Backup ==="
    (
        # Override backup directory name
        backup_dir="$base_backup_dir/datasets"
        cmd_backup_dataset_internal "$backup_dir"
    ) || ((error_count++))
    
    if [[ $error_count -eq 0 ]]; then
        print_green "\n=== Full Backup Completed ==="
        print_cyan "Backup location: $base_backup_dir"
    else
        print_red "\n=== Full Backup Failed ==="
        exit 1
    fi
}

# =============================================================================
# List Operations
# =============================================================================

#
# List target analyses
#
cmd_list_analysis() {
    print_bold "=== Target Analyses List ==="
    
    if ! check_dependencies; then
        exit 1
    fi
    
    local list_response
    list_response=$(qs_analysis_list)
    
    if ! qs_is_success "$list_response"; then
        print_red "Failed to retrieve analyses list"
        exit 1
    fi
    
    local all_analyses
    all_analyses=$(qs_get_response_data "$list_response")
    
    if [[ ${#TARGET_ANALYSES[@]} -eq 0 ]]; then
        print_yellow "No target analyses configured, showing all analyses:"
        echo "$all_analyses" | jq -r '.AnalysisSummaryList[] | "\(.Name) (ID: \(.AnalysisId))"'
    else
        print_cyan "Configured target analyses:"
        for target_name in "${TARGET_ANALYSES[@]}"; do
            local matched_analysis
            matched_analysis=$(echo "$all_analyses" | jq -r --arg name "$target_name" \
                '.AnalysisSummaryList[] | select(.Name == $name) | "\(.Name) (ID: \(.AnalysisId)) - Status: \(.Status // "N/A")"')
            
            if [[ -n "$matched_analysis" ]]; then
                print_green "  ✓ $matched_analysis"
            else
                print_red "  ✗ $target_name (not found)"
            fi
        done
    fi
}

#
# List target datasets
#
cmd_list_dataset() {
    print_bold "=== Target Datasets List ==="
    
    if ! check_dependencies; then
        exit 1
    fi
    
    local list_response
    list_response=$(qs_dataset_list)
    
    if ! qs_is_success "$list_response"; then
        print_red "Failed to retrieve datasets list"
        exit 1
    fi
    
    local all_datasets
    all_datasets=$(qs_get_response_data "$list_response")
    
    if [[ ${#TARGET_DATASETS[@]} -eq 0 ]]; then
        print_yellow "No target datasets configured, showing all datasets:"
        echo "$all_datasets" | jq -r '.DataSetSummaries[] | "\(.Name) (ID: \(.DataSetId)) - Mode: \(.ImportMode // "N/A")"'
    else
        print_cyan "Configured target datasets:"
        for target_name in "${TARGET_DATASETS[@]}"; do
            local matched_dataset
            matched_dataset=$(echo "$all_datasets" | jq -r --arg name "$target_name" \
                '.DataSetSummaries[] | select(.Name == $name) | "\(.Name) (ID: \(.DataSetId)) - Mode: \(.ImportMode // "N/A")"')
            
            if [[ -n "$matched_dataset" ]]; then
                print_green "  ✓ $matched_dataset"
            else
                print_red "  ✗ $target_name (not found)"
            fi
        done
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

#
# Save analysis backup summary (compatible with existing format)
#
save_analysis_backup_summary() {
    local backup_dir="$1"
    shift
    local analysis_ids=("$@")
    
    # Extract summary info from the remaining args
    local summary_info=()
    local ids_part=true
    
    for arg in "$@"; do
        if [[ "$arg" =~ \| ]]; then
            ids_part=false
        fi
        
        if [[ "$ids_part" == false ]]; then
            summary_info+=("$arg")
        fi
    done
    
    # Save analysis ID list in JSON format
    if [[ ${#analysis_ids[@]} -gt 0 ]]; then
        printf '["%s"' "${analysis_ids[0]}" > "$backup_dir/analysis-ids.json"
        for id in "${analysis_ids[@]:1}"; do
            if [[ ! "$id" =~ \| ]]; then
                printf ',"%s"' "$id" >> "$backup_dir/analysis-ids.json"
            fi
        done
        echo ']' >> "$backup_dir/analysis-ids.json"
    fi
    
    # Create detailed analysis summary
    {
        echo "["
        local first=true
        for summary in "${summary_info[@]}"; do
            if [[ "$first" != "true" ]]; then
                echo ","
            fi
            first=false
            
            IFS='|' read -r name id sheets visuals <<< "$summary"
            cat << EOF
  {
    "Name": "$name",
    "AnalysisId": "$id",
    "SheetCount": ${sheets:-0},
    "VisualCount": ${visuals:-0}
  }
EOF
        done
        echo
        echo "]"
    } > "$backup_dir/analysis-summary.json"
}

#
# Save dataset backup summary (compatible with existing format)
#
save_dataset_backup_summary() {
    local backup_dir="$1"
    shift
    local dataset_ids=("$@")
    
    # Extract summary info from the remaining args
    local summary_info=()
    local ids_part=true
    
    for arg in "$@"; do
        if [[ "$arg" =~ \| ]]; then
            ids_part=false
        fi
        
        if [[ "$ids_part" == false ]]; then
            summary_info+=("$arg")
        fi
    done
    
    # Save dataset ID list in JSON format
    if [[ ${#dataset_ids[@]} -gt 0 ]]; then
        printf '["%s"' "${dataset_ids[0]}" > "$backup_dir/dataset-ids.json"
        for id in "${dataset_ids[@]:1}"; do
            if [[ ! "$id" =~ \| ]]; then
                printf ',"%s"' "$id" >> "$backup_dir/dataset-ids.json"
            fi
        done
        echo ']' >> "$backup_dir/dataset-ids.json"
    fi
    
    # Create detailed dataset summary
    {
        echo "["
        local first=true
        for summary in "${summary_info[@]}"; do
            if [[ "$first" != "true" ]]; then
                echo ","
            fi
            first=false
            
            IFS='|' read -r name id import_mode <<< "$summary"
            cat << EOF
  {
    "Name": "$name",
    "DataSetId": "$id",
    "ImportMode": "$import_mode"
  }
EOF
        done
        echo
        echo "]"
    } > "$backup_dir/dataset-summary.json"
}

# =============================================================================
# Configuration Display
# =============================================================================

#
# Show current configuration
#
cmd_show_config() {
    print_bold "=== QuickSight Configuration ==="
    
    print_cyan "AWS Configuration:"
    if qs_api_init true; then
        print_green "  Account ID: $(qs_get_account_id)"
        print_green "  Region: $(qs_get_region)"
    else
        print_red "  AWS authentication failed"
    fi
    
    print_cyan "\nTarget Analyses (${#TARGET_ANALYSES[@]}):"
    if [[ ${#TARGET_ANALYSES[@]} -eq 0 ]]; then
        print_yellow "  (All analyses will be processed)"
    else
        for analysis in "${TARGET_ANALYSES[@]}"; do
            print_blue "  - $analysis"
        done
    fi
    
    print_cyan "\nTarget Datasets (${#TARGET_DATASETS[@]}):"
    if [[ ${#TARGET_DATASETS[@]} -eq 0 ]]; then
        print_yellow "  (All datasets will be processed)"
    else
        for dataset in "${TARGET_DATASETS[@]}"; do
            print_blue "  - $dataset"
        done
    fi
}

# =============================================================================
# Main CLI Interface
# =============================================================================

#
# Show usage information
#
show_help() {
    cat << 'EOF'
QuickSight Core Manager

Usage:
    manager.sh [command] [options]

Commands:
    backup-analysis       Backup analyses
    backup-dataset        Backup datasets
    backup-all            Backup both analyses and datasets
    list-analysis         List target analyses
    list-dataset          List target datasets
    show-config           Show current configuration
    help                  Show this help

Options:
    -v, --verbose         Verbose output
    -n, --dry-run         Show execution content without running

Examples:
    ./manager.sh backup-all
    ./manager.sh list-analysis
    ./manager.sh show-config

Compatible with existing quicksight_manager.sh functionality.
EOF
}

#
# Parse command line arguments and execute
#
main() {
    # Load configuration first
    if ! load_quicksight_config; then
        print_yellow "Using default configuration"
    fi
    
    # Parse command line arguments
    local command=""
    local verbose="false"
    local dry_run="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            backup-analysis|backup-dataset|backup-all|list-analysis|list-dataset|show-config|help)
                command="$1"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                export LOG_LEVEL="debug"
                shift
                ;;
            -n|--dry-run)
                dry_run="true"
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
    
    # Execute command
    case "$command" in
        backup-analysis)
            cmd_backup_analysis
            ;;
        backup-dataset)
            cmd_backup_dataset
            ;;
        backup-all)
            cmd_backup_all
            ;;
        list-analysis)
            cmd_list_analysis
            ;;
        list-dataset)
            cmd_list_dataset
            ;;
        show-config)
            cmd_show_config
            ;;
        help|"")
            show_help
            ;;
        *)
            print_red "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# =============================================================================
# Export Functions
# =============================================================================

# Export functions for use by other scripts
export -f load_quicksight_config check_dependencies
export -f cmd_backup_analysis cmd_backup_dataset cmd_backup_all
export -f cmd_list_analysis cmd_list_dataset cmd_show_config
export -f save_analysis_backup_summary save_dataset_backup_summary

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
