#!/bin/bash

# QuickSight Management Script
# Performs backup, creation, update, and management of analyses and datasets

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
# Main Functions
# =============================================================================

# Help message
show_help() {
    cat << 'EOF'
QuickSight Management Script

Usage:
    ./quicksight_manager.sh [command] [options]

Commands:
    backup-analysis       Backup analyses
    backup-dataset        Backup datasets
    backup-all            Backup both analyses and datasets
    list-analysis         List target analyses
    list-dataset          List target datasets
    check-diff            Check differences between backup and current resource existence
    check-content-diff    Check detailed content differences between backup and current configuration
    show-config           Show current configuration
    help                  Show this help

Options:
    -d, --dir DIR         Specify backup directory
    -t, --type TYPE       Specify resource type (analysis|dataset|all)
    -v, --verbose         Verbose output
    -n, --dry-run         Show execution content without running

Examples:
    ./quicksight_manager.sh backup-all
    ./quicksight_manager.sh list-analysis
    ./quicksight_manager.sh check-diff -d quicksight-analysis-backup-20241002-140524
    ./quicksight_manager.sh check-content-diff -d quicksight-analysis-backup-20241002-140524 -t analysis
    ./quicksight_manager.sh check-content-diff -d quicksight-dataset-backup-20241002-140524 -t dataset
EOF
}

# Backup analyses
cmd_backup_analysis() {
    print_bold "=== QuickSight Analysis Backup ==="
    
    # Check dependencies
    check_dependencies || exit 1
    
    print_yellow "1. Retrieving all analyses list..."
    local all_analyses
    if ! all_analyses=$(get_all_analyses); then
        exit 1
    fi
    
    local analysis_count
    analysis_count=$(echo "$all_analyses" | jq -r '.AnalysisSummaryList | length')
    print_cyan "Retrieved analyses count: $analysis_count"
    
    print_yellow "2. Filtering target analyses..."
    if ! filter_target_analyses "$all_analyses"; then
        exit 1
    fi
    
    print_cyan "Target analyses count: ${#MATCHED_ANALYSES[@]}"
    
    # Create backup directory
    local backup_dir
    backup_dir=$(generate_backup_dir_name "analysis")
    mkdir -p "$backup_dir"
    print_yellow "3. Created backup directory: $backup_dir"
    
    # Backup analyses
    print_yellow "4. Backing up analyses..."
    if backup_analyses "$backup_dir"; then
        print_green "\n=== Backup Completed ==="
        print_cyan "Backup location: $backup_dir"
    else
        print_red "\n=== Backup Failed ==="
        exit 1
    fi
}

# Backup datasets
cmd_backup_dataset() {
    print_bold "=== QuickSight Dataset Backup ==="
    
    # Check dependencies
    check_dependencies || exit 1
    
    print_yellow "1. Retrieving all datasets list..."
    local all_datasets
    if ! all_datasets=$(get_all_datasets); then
        exit 1
    fi
    
    local dataset_count
    dataset_count=$(echo "$all_datasets" | jq -r '.DataSetSummaries | length')
    print_cyan "Retrieved datasets count: $dataset_count"
    
    print_yellow "2. Filtering target datasets..."
    if ! filter_target_datasets "$all_datasets"; then
        exit 1
    fi
    
    print_cyan "Target datasets count: ${#MATCHED_DATASETS[@]}"
    
    # Create backup directory
    local backup_dir
    backup_dir=$(generate_backup_dir_name "dataset")
    mkdir -p "$backup_dir"
    print_yellow "3. Created backup directory: $backup_dir"
    
    # Backup datasets
    print_yellow "4. Backing up datasets..."
    if backup_datasets "$backup_dir"; then
        print_green "\n=== Backup Completed ==="
        print_cyan "Backup location: $backup_dir"
    else
        print_red "\n=== Backup Failed ==="
        exit 1
    fi
}

# Backup both analyses and datasets
cmd_backup_all() {
    local base_backup_dir
    base_backup_dir="quicksight-full-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$base_backup_dir"
    
    print_bold "=== QuickSight Full Backup ==="
    print_cyan "Backup directory: $base_backup_dir"
    
    # Check dependencies
    check_dependencies || exit 1
    
    local error_count=0
    
    # Backup analyses
    print_yellow "\n=== Analyses Backup ==="
    local all_analyses
    if all_analyses=$(get_all_analyses) && filter_target_analyses "$all_analyses"; then
        local analysis_backup_dir="$base_backup_dir/analyses"
        mkdir -p "$analysis_backup_dir"
        if ! backup_analyses "$analysis_backup_dir"; then
            ((error_count++))
        fi
    else
        ((error_count++))
    fi
    
    # Backup datasets
    print_yellow "\n=== Datasets Backup ==="
    local all_datasets
    if all_datasets=$(get_all_datasets) && filter_target_datasets "$all_datasets"; then
        local dataset_backup_dir="$base_backup_dir/datasets"
        mkdir -p "$dataset_backup_dir"
        if ! backup_datasets "$dataset_backup_dir"; then
            ((error_count++))
        fi
    else
        ((error_count++))
    fi
    
    if [ $error_count -eq 0 ]; then
        print_green "\n=== Full Backup Completed ==="
        print_cyan "Backup location: $base_backup_dir"
    else
        print_red "\n=== Backup Failed ==="
        exit 1
    fi
}

# List target analyses
cmd_list_analysis() {
    print_bold "=== Target Analyses List ==="
    
    check_dependencies || exit 1
    
    local all_analyses
    if ! all_analyses=$(get_all_analyses); then
        exit 1
    fi
    
    if ! filter_target_analyses "$all_analyses"; then
        exit 1
    fi
    
    print_cyan "Target analyses count: ${#MATCHED_ANALYSES[@]}"
    echo
    
    for analysis_info in "${MATCHED_ANALYSES[@]}"; do
        IFS='|' read -r analysis_name analysis_id created_time updated_time status <<< "$analysis_info"
        
        echo "Name: $analysis_name"
        echo "ID: $analysis_id"
        echo "Status: $status"
        echo "Created: $created_time"
        echo "Updated: $updated_time"
        echo "---"
    done
}

# List target datasets
cmd_list_dataset() {
    print_bold "=== Target Datasets List ==="
    
    check_dependencies || exit 1
    
    local all_datasets
    if ! all_datasets=$(get_all_datasets); then
        exit 1
    fi
    
    if ! filter_target_datasets "$all_datasets"; then
        exit 1
    fi
    
    print_cyan "Target datasets count: ${#MATCHED_DATASETS[@]}"
    echo
    
    for dataset_info in "${MATCHED_DATASETS[@]}"; do
        IFS='|' read -r dataset_name dataset_id created_time updated_time import_mode <<< "$dataset_info"
        
        echo "Name: $dataset_name"
        echo "ID: $dataset_id"
        echo "Import mode: $import_mode"
        echo "Created: $created_time"
        echo "Updated: $updated_time"
        echo "---"
    done
}

# Check differences between backup and current configuration
cmd_check_diff() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ]; then
        print_red "Error: Please specify backup directory."
        echo "Usage example: $0 check-diff -d quicksight-analysis-backup-20241002-140524"
        exit 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        print_red "Error: Backup directory not found: $backup_dir"
        exit 1
    fi
    
    print_bold "=== Backup Diff Check ==="
    print_cyan "Backup directory: $backup_dir"
    
    check_dependencies || exit 1
    
    # Check analysis differences
    if [ -f "$backup_dir/analysis-ids.json" ]; then
        print_yellow "\n=== Analysis Diff Check ==="
        
        local backup_ids current_ids
        backup_ids=$(cat "$backup_dir/analysis-ids.json" | jq -r '.[]')
        
        local all_analyses
        if all_analyses=$(get_all_analyses) && filter_target_analyses "$all_analyses"; then
            current_ids=$(printf '%s\n' "${ANALYSIS_IDS[@]}")
            
            echo "Analysis IDs at backup time:"
            echo "$backup_ids" | sed 's/^/  /'
            echo
            echo "Current analysis IDs:"
            echo "$current_ids" | sed 's/^/  /'
            echo
            
            # Show differences
            local added_ids removed_ids
            added_ids=$(comm -13 <(echo "$backup_ids" | sort) <(echo "$current_ids" | sort))
            removed_ids=$(comm -23 <(echo "$backup_ids" | sort) <(echo "$current_ids" | sort))
            
            if [ -n "$added_ids" ]; then
                print_green "Added analyses:"
                echo "$added_ids" | sed 's/^/  /'
            fi
            
            if [ -n "$removed_ids" ]; then
                print_red "Removed analyses:"
                echo "$removed_ids" | sed 's/^/  /'
            fi
            
            if [ -z "$added_ids" ] && [ -z "$removed_ids" ]; then
                print_cyan "No changes in analyses."
            fi
        fi
    fi
    
    # Check dataset differences
    if [ -f "$backup_dir/dataset-ids.json" ]; then
        print_yellow "\n=== Dataset Diff Check ==="
        
        local backup_ids current_ids
        backup_ids=$(cat "$backup_dir/dataset-ids.json" | jq -r '.[]')
        
        local all_datasets
        if all_datasets=$(get_all_datasets) && filter_target_datasets "$all_datasets"; then
            current_ids=$(printf '%s\n' "${DATASET_IDS[@]}")
            
            echo "Dataset IDs at backup time:"
            echo "$backup_ids" | sed 's/^/  /'
            echo
            echo "Current dataset IDs:"
            echo "$current_ids" | sed 's/^/  /'
            echo
            
            # Show differences
            local added_ids removed_ids
            added_ids=$(comm -13 <(echo "$backup_ids" | sort) <(echo "$current_ids" | sort))
            removed_ids=$(comm -23 <(echo "$backup_ids" | sort) <(echo "$current_ids" | sort))
            
            if [ -n "$added_ids" ]; then
                print_green "Added datasets:"
                echo "$added_ids" | sed 's/^/  /'
            fi
            
            if [ -n "$removed_ids" ]; then
                print_red "Removed datasets:"
                echo "$removed_ids" | sed 's/^/  /'
            fi
            
            if [ -z "$added_ids" ] && [ -z "$removed_ids" ]; then
                print_cyan "No changes in datasets."
            fi
        fi
    fi
}

# Check detailed content differences
cmd_check_content_diff() {
    local backup_dir="$1"
    local resource_type="$2"
    
    if [ -z "$backup_dir" ]; then
        print_red "Error: Please specify backup directory."
        echo "Usage example: $0 check-content-diff -d quicksight-analysis-backup-20241002-140524 -t analysis"
        exit 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        print_red "Error: Backup directory not found: $backup_dir"
        exit 1
    fi
    
    if [ -z "$resource_type" ]; then
        # Auto-detect resource type if not specified
        if [ -f "$backup_dir/analysis-ids.json" ] && [ -f "$backup_dir/dataset-ids.json" ]; then
            resource_type="all"
        elif [ -f "$backup_dir/analysis-ids.json" ]; then
            resource_type="analysis"
        elif [ -f "$backup_dir/dataset-ids.json" ]; then
            resource_type="dataset"
        else
            print_red "Error: No valid ID files found in backup directory."
            exit 1
        fi
        print_yellow "Auto-detected resource type: $resource_type"
    fi
    
    print_bold "=== Detailed Content Diff Check ==="
    print_cyan "Backup directory: $backup_dir"
    print_cyan "Target resource: $resource_type"
    
    check_dependencies || exit 1
    
    case $resource_type in
        "analysis")
            compare_resource_content "$backup_dir" "analysis"
            ;;
        "dataset")
            compare_resource_content "$backup_dir" "dataset"
            ;;
        "all")
            compare_resource_content "$backup_dir" "analysis"
            echo
            compare_resource_content "$backup_dir" "dataset"
            ;;
        *)
            print_red "Error: Invalid resource type: $resource_type"
            echo "Valid types: analysis, dataset, all"
            exit 1
            ;;
    esac
    
    print_green "\n=== Detailed Diff Check Completed ==="
}

# =============================================================================
# Main Logic
# =============================================================================

# Option parsing
VERBOSE=false
DRY_RUN=false
BACKUP_DIR=""
RESOURCE_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -t|--type)
            RESOURCE_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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
        backup-analysis)
            COMMAND="backup-analysis"
            shift
            ;;
        backup-dataset)
            COMMAND="backup-dataset"
            shift
            ;;
        backup-all)
            COMMAND="backup-all"
            shift
            ;;
        list-analysis)
            COMMAND="list-analysis"
            shift
            ;;
        list-dataset)
            COMMAND="list-dataset"
            shift
            ;;
        check-diff)
            COMMAND="check-diff"
            shift
            ;;
        check-content-diff)
            COMMAND="check-content-diff"
            shift
            ;;
        show-config)
            show_config
            exit 0
            ;;
        help)
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

# Show help if no command is specified
if [ -z "${COMMAND:-}" ]; then
    show_help
    exit 1
fi

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    print_yellow "Dry run mode: No actual operations will be performed."
    echo "Command to be executed: $COMMAND"
    [ -n "$BACKUP_DIR" ] && echo "Specified directory: $BACKUP_DIR"
    exit 0
fi

# Execute command
case $COMMAND in
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
    check-diff)
        cmd_check_diff "$BACKUP_DIR"
        ;;
    check-content-diff)
        cmd_check_content_diff "$BACKUP_DIR" "$RESOURCE_TYPE"
        ;;
    *)
        print_red "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
