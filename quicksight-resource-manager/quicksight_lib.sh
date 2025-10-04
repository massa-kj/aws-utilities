#!/bin/bash

# QuickSight Common Library
# This file is sourced by main scripts

# =============================================================================
# Configuration File Loading
# =============================================================================

# Get current directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration file loading function
load_config() {
    local config_file="$LIB_DIR/config.sh"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        print_blue "Configuration file loaded: $config_file"
        
        # Validate configuration
        if ! validate_config; then
            print_red "Configuration file has errors"
            return 1
        fi
        
        return 0
    else
        print_red "Error: Configuration file not found: $config_file"
        print_yellow "Please create config.sh file"
        return 1
    fi
}

# =============================================================================
# Colored Message Functions
# =============================================================================
print_green() { echo -e "\033[32m$1\033[0m"; }
print_yellow() { echo -e "\033[33m$1\033[0m"; }
print_red() { echo -e "\033[31m$1\033[0m"; }
print_cyan() { echo -e "\033[36m$1\033[0m"; }
print_blue() { echo -e "\033[34m$1\033[0m"; }
print_bold() { echo -e "\033[1m$1\033[0m"; }

# =============================================================================
# Analysis Related Functions
# =============================================================================

# Get all analyses list
get_all_analyses() {
    local all_analyses
    all_analyses=$(aws quicksight list-analyses --aws-account-id "$ACCOUNT_ID" --region "$REGION" --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$all_analyses" = "null" ]; then
        print_red "Error: Failed to retrieve analyses."
        return 1
    fi
    
    echo "$all_analyses"
}

# Filter target analyses
filter_target_analyses() {
    local all_analyses="$1"
    local matched_analyses=()
    local analysis_ids=()
    
    for target_name in "${TARGET_ANALYSES[@]}"; do
        local matched_info
        matched_info=$(echo "$all_analyses" | jq -r --arg name "$target_name" \
            '.AnalysisSummaryList[] | select(.Name == $name) | "\(.Name)|\(.AnalysisId)|\(.CreatedTime // "N/A")|\(.LastUpdatedTime // "N/A")|\(.Status // "N/A")"')
        
        if [ -n "$matched_info" ]; then
            matched_analyses+=("$matched_info")
            local analysis_id
            analysis_id=$(echo "$matched_info" | cut -d'|' -f2)
            analysis_ids+=("$analysis_id")
        fi
    done
    
    if [ ${#matched_analyses[@]} -eq 0 ]; then
        print_red "Target analyses not found."
        print_yellow "Available analysis names:"
        echo "$all_analyses" | jq -r '.AnalysisSummaryList[].Name' | while read -r name; do
            echo "  - $name"
        done
        return 1
    fi
    
    # Set results to global variables
    MATCHED_ANALYSES=("${matched_analyses[@]}")
    ANALYSIS_IDS=("${analysis_ids[@]}")
}

# Backup analyses
backup_analyses() {
    local backup_dir="$1"
    local success_count=0
    local error_count=0
    local backup_summary=()
    
    print_yellow "Backing up analysis details..."
    
    # Create backup directories
    mkdir -p "$backup_dir/analyses"
    mkdir -p "$backup_dir/definitions"
    mkdir -p "$backup_dir/permissions"
    
    for analysis_info in "${MATCHED_ANALYSES[@]}"; do
        IFS='|' read -r analysis_name analysis_id created_time updated_time status <<< "$analysis_info"
        
        print_cyan "  Backing up: $analysis_name (ID: $analysis_id)"
        
        # Remove invalid characters from filename
        local safe_filename
        safe_filename=$(echo "$analysis_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get analysis basic information
        local analysis_detail
        if analysis_detail=$(aws quicksight describe-analysis \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$REGION" \
            --output json 2>/dev/null); then
            
            echo "$analysis_detail" > "$backup_dir/analyses/${safe_filename}-${analysis_id}.json"
            print_green "    ✓ Basic information saved"
            
        else
            print_red "    ✗ Basic information retrieval error: $analysis_name"
            ((error_count++))
            continue
        fi
        
        # Get analysis definition
        local analysis_definition sheet_count=0 visual_count=0
        if analysis_definition=$(aws quicksight describe-analysis-definition \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$REGION" \
            --output json 2>/dev/null); then
            
            echo "$analysis_definition" > "$backup_dir/definitions/${safe_filename}-${analysis_id}-definition.json"
            print_green "    ✓ Definition information saved"
            
            sheet_count=$(echo "$analysis_definition" | jq -r '.Definition.Sheets | length')
            visual_count=$(echo "$analysis_definition" | jq -r '.Definition.Sheets[].Visuals | length' | awk '{sum+=$1} END {print sum+0}')
            
        else
            print_red "    ✗ Definition information retrieval error: $analysis_name"
        fi
        
        # Get permission information
        if aws quicksight describe-analysis-permissions \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$REGION" \
            --output json > "$backup_dir/permissions/${safe_filename}-${analysis_id}-permissions.json" 2>/dev/null; then
            
            print_green "    ✓ Permission information saved"
        else
            print_red "    ✗ Permission information retrieval error: $analysis_name"
        fi
        
        # Extract dataset IDs
        local dataset_ids
        dataset_ids=$(echo "$analysis_detail" | jq -r '.Analysis.DataSetArns[]? // empty' | sed 's/.*dataset\///')
        
        backup_summary+=("$analysis_name|$analysis_id|$status|${sheet_count:-0}|${visual_count:-0}|$dataset_ids")
        ((success_count++))
    done
    
    # Save summary information
    save_analysis_summary "$backup_dir" "${backup_summary[@]}"
    
    print_green "Analysis backup completed: $success_count successful, $error_count errors"
    return $error_count
}

# =============================================================================
# Dataset Related Functions
# =============================================================================

# Get all datasets list
get_all_datasets() {
    local all_datasets
    all_datasets=$(aws quicksight list-data-sets --aws-account-id "$ACCOUNT_ID" --region "$REGION" --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$all_datasets" = "null" ]; then
        print_red "Error: Failed to retrieve datasets."
        return 1
    fi
    
    echo "$all_datasets"
}

# Filter target datasets
filter_target_datasets() {
    local all_datasets="$1"
    local matched_datasets=()
    local dataset_ids=()
    
    for target_name in "${TARGET_DATASETS[@]}"; do
        local matched_info
        matched_info=$(echo "$all_datasets" | jq -r --arg name "$target_name" \
            '.DataSetSummaries[] | select(.Name == $name) | "\(.Name)|\(.DataSetId)|\(.CreatedTime // "N/A")|\(.LastUpdatedTime // "N/A")|\(.ImportMode // "N/A")"')
        
        if [ -n "$matched_info" ]; then
            matched_datasets+=("$matched_info")
            local dataset_id
            dataset_id=$(echo "$matched_info" | cut -d'|' -f2)
            dataset_ids+=("$dataset_id")
        fi
    done
    
    if [ ${#matched_datasets[@]} -eq 0 ]; then
        print_red "Target datasets not found."
        print_yellow "Available dataset names:"
        echo "$all_datasets" | jq -r '.DataSetSummaries[].Name' | while read -r name; do
            echo "  - $name"
        done
        return 1
    fi
    
    # Set results to global variables
    MATCHED_DATASETS=("${matched_datasets[@]}")
    DATASET_IDS=("${dataset_ids[@]}")
}

# Backup datasets
backup_datasets() {
    local backup_dir="$1"
    local success_count=0
    local error_count=0
    local backup_summary=()
    
    print_yellow "Backing up dataset details..."
    
    # Create backup directories
    mkdir -p "$backup_dir/datasets"
    mkdir -p "$backup_dir/permissions"
    
    for dataset_info in "${MATCHED_DATASETS[@]}"; do
        IFS='|' read -r dataset_name dataset_id created_time updated_time import_mode <<< "$dataset_info"
        
        print_cyan "  Backing up: $dataset_name (ID: $dataset_id)"
        
        # Remove invalid characters from filename
        local safe_filename
        safe_filename=$(echo "$dataset_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get dataset detailed information
        local dataset_detail
        if dataset_detail=$(aws quicksight describe-data-set \
            --aws-account-id "$ACCOUNT_ID" \
            --data-set-id "$dataset_id" \
            --region "$REGION" \
            --output json 2>/dev/null); then
            
            echo "$dataset_detail" > "$backup_dir/datasets/${safe_filename}-${dataset_id}.json"
            print_green "    ✓ Detailed information saved"
            
        else
            print_red "    ✗ Detailed information retrieval error: $dataset_name"
            ((error_count++))
            continue
        fi
        
        # Get permission information
        if aws quicksight describe-data-set-permissions \
            --aws-account-id "$ACCOUNT_ID" \
            --data-set-id "$dataset_id" \
            --region "$REGION" \
            --output json > "$backup_dir/permissions/${safe_filename}-${dataset_id}-permissions.json" 2>/dev/null; then
            
            print_green "    ✓ Permission information saved"
        else
            print_red "    ✗ Permission information retrieval error: $dataset_name"
        fi
        
        backup_summary+=("$dataset_name|$dataset_id|$import_mode|$created_time|$updated_time")
        ((success_count++))
    done
    
    # Save summary information
    save_dataset_summary "$backup_dir" "${backup_summary[@]}"
    
    print_green "Dataset backup completed: $success_count successful, $error_count errors"
    return $error_count
}

# =============================================================================
# Summary Information Save Functions
# =============================================================================

# Save analysis summary information
save_analysis_summary() {
    local backup_dir="$1"
    shift
    local backup_summary=("$@")
    
    # Save analysis ID list in JSON format
    if [ ${#ANALYSIS_IDS[@]} -gt 0 ]; then
        printf '["%s"' "${ANALYSIS_IDS[0]}" > "$backup_dir/analysis-ids.json"
        for id in "${ANALYSIS_IDS[@]:1}"; do
            printf ',"%s"' "$id" >> "$backup_dir/analysis-ids.json"
        done
        echo ']' >> "$backup_dir/analysis-ids.json"
    fi
    
    # Create detailed analysis summary
    {
        echo "["
        for i in "${!backup_summary[@]}"; do
            IFS='|' read -r name id status sheets visuals datasets <<< "${backup_summary[i]}"
            
            if [ $i -eq $((${#backup_summary[@]} - 1)) ]; then
                COMMA=""
            else
                COMMA=","
            fi
            
            cat << EOF
  {
    "Name": "$name",
    "AnalysisId": "$id",
    "Status": "$status",
    "SheetCount": $sheets,
    "VisualCount": $visuals,
    "DataSetIds": [$(echo "$datasets" | sed 's/\([^ ]*\)/"\1"/g' | tr ' ' ',')]
  }$COMMA
EOF
        done
        echo "]"
    } > "$backup_dir/analysis-summary.json"
}

# Save dataset summary information
save_dataset_summary() {
    local backup_dir="$1"
    shift
    local backup_summary=("$@")
    
    # Save dataset ID list in JSON format
    if [ ${#DATASET_IDS[@]} -gt 0 ]; then
        printf '["%s"' "${DATASET_IDS[0]}" > "$backup_dir/dataset-ids.json"
        for id in "${DATASET_IDS[@]:1}"; do
            printf ',"%s"' "$id" >> "$backup_dir/dataset-ids.json"
        done
        echo ']' >> "$backup_dir/dataset-ids.json"
    fi
    
    # Create detailed dataset summary
    {
        echo "["
        for i in "${!backup_summary[@]}"; do
            IFS='|' read -r name id import_mode created_time updated_time <<< "${backup_summary[i]}"
            
            if [ $i -eq $((${#backup_summary[@]} - 1)) ]; then
                COMMA=""
            else
                COMMA=","
            fi
            
            cat << EOF
  {
    "Name": "$name",
    "DataSetId": "$id",
    "ImportMode": "$import_mode",
    "CreatedTime": "$created_time",
    "LastUpdatedTime": "$updated_time"
  }$COMMA
EOF
        done
        echo "]"
    } > "$backup_dir/dataset-summary.json"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Generate timestamped backup directory name
generate_backup_dir_name() {
    local type="$1"
    echo "quicksight-${type}-backup-$(date +%Y%m%d-%H%M%S)"
}

# Error handling
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_red "Error: AWS CLI is not installed."
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_red "Error: AWS credentials are not configured."
        return 1
    fi
    
    return 0
}

# Dependency check
check_dependencies() {
    local missing_deps=()
    
    command -v aws >/dev/null || missing_deps+=("aws")
    command -v jq >/dev/null || missing_deps+=("jq")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_red "Error: The following commands are not installed:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi
    
    return 0
}

# =============================================================================
# Detailed Diff Check Functions
# =============================================================================

# Get detailed information for a single resource
get_current_resource_detail() {
    local resource_type="$1"  # "analysis" or "dataset"
    local resource_id="$2"
    local resource_name="$3"
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    case $resource_type in
        "analysis")
            # Get analysis detailed information
            local detail_file="$temp_dir/detail.json"
            local definition_file="$temp_dir/definition.json"
            local permissions_file="$temp_dir/permissions.json"
            
            aws quicksight describe-analysis \
                --aws-account-id "$ACCOUNT_ID" \
                --analysis-id "$resource_id" \
                --region "$REGION" \
                --output json > "$detail_file" 2>/dev/null
            
            aws quicksight describe-analysis-definition \
                --aws-account-id "$ACCOUNT_ID" \
                --analysis-id "$resource_id" \
                --region "$REGION" \
                --output json > "$definition_file" 2>/dev/null
            
            aws quicksight describe-analysis-permissions \
                --aws-account-id "$ACCOUNT_ID" \
                --analysis-id "$resource_id" \
                --region "$REGION" \
                --output json > "$permissions_file" 2>/dev/null
            
            # Return structured results
            jq -s '{
                "detail": .[0],
                "definition": .[1],
                "permissions": .[2]
            }' "$detail_file" "$definition_file" "$permissions_file" 2>/dev/null
            ;;
            
        "dataset")
            # Get dataset detailed information
            local detail_file="$temp_dir/detail.json"
            local permissions_file="$temp_dir/permissions.json"
            
            aws quicksight describe-data-set \
                --aws-account-id "$ACCOUNT_ID" \
                --data-set-id "$resource_id" \
                --region "$REGION" \
                --output json > "$detail_file" 2>/dev/null
            
            aws quicksight describe-data-set-permissions \
                --aws-account-id "$ACCOUNT_ID" \
                --data-set-id "$resource_id" \
                --region "$REGION" \
                --output json > "$permissions_file" 2>/dev/null
            
            # Return structured results
            jq -s '{
                "detail": .[0],
                "permissions": .[1]
            }' "$detail_file" "$permissions_file" 2>/dev/null
            ;;
    esac
}

# Compare backup and current configuration content in detail
compare_resource_content() {
    local backup_dir="$1"
    local resource_type="$2"  # "analysis" or "dataset"
    
    case $resource_type in
        "analysis")
            if [ ! -f "$backup_dir/analysis-ids.json" ]; then
                print_yellow "Analysis backup files not found."
                return 1
            fi
            
            print_yellow "=== Detailed Analysis Configuration Diff Check ==="
            
            # Get backed up analysis IDs
            local backup_ids
            backup_ids=$(cat "$backup_dir/analysis-ids.json" | jq -r '.[]')
            
            # Get current analysis information
            local all_analyses
            if ! all_analyses=$(get_all_analyses) || ! filter_target_analyses "$all_analyses"; then
                return 1
            fi
            
            # Detailed comparison for each analysis
            while IFS= read -r analysis_id; do
                [ -z "$analysis_id" ] && continue
                
                print_cyan "\n--- Analysis ID: $analysis_id ---"
                
                # Get current analysis name
                local current_name
                current_name=$(echo "$all_analyses" | jq -r --arg id "$analysis_id" \
                    '.AnalysisSummaryList[] | select(.AnalysisId == $id) | .Name')
                
                if [ -z "$current_name" ] || [ "$current_name" = "null" ]; then
                    print_red "  ✗ Analysis not found (deleted?)"
                    continue
                fi
                
                print_blue "  Analysis name: $current_name"
                
                # Build backup file paths
                local safe_filename backup_basic backup_definition backup_permissions
                safe_filename=$(echo "$current_name" | sed 's/[\\/:*?"<>|]/_/g')
                backup_basic="$backup_dir/analyses/${safe_filename}-${analysis_id}.json"
                backup_definition="$backup_dir/definitions/${safe_filename}-${analysis_id}-definition.json"
                backup_permissions="$backup_dir/permissions/${safe_filename}-${analysis_id}-permissions.json"
                
                # Get current configuration
                local current_detail
                if current_detail=$(get_current_resource_detail "analysis" "$analysis_id" "$current_name"); then
                    
                    # Compare basic information
                    if [ -f "$backup_basic" ]; then
                        local backup_lastmodified current_lastmodified
                        backup_lastmodified=$(jq -r '.Analysis.LastUpdatedTime // "N/A"' "$backup_basic" 2>/dev/null)
                        current_lastmodified=$(echo "$current_detail" | jq -r '.detail.Analysis.LastUpdatedTime // "N/A"' 2>/dev/null)
                        
                        if [ "$backup_lastmodified" != "$current_lastmodified" ]; then
                            print_yellow "  ⚠ Update time changed:"
                            echo "    At backup: $backup_lastmodified"
                            echo "    Current: $current_lastmodified"
                        else
                            print_green "  ✓ No changes in basic information"
                        fi
                    fi
                    
                    # Compare definitions (sheet count, visual count, etc.)
                    if [ -f "$backup_definition" ]; then
                        local backup_sheets current_sheets backup_visuals current_visuals
                        backup_sheets=$(jq -r '.Definition.Sheets | length' "$backup_definition" 2>/dev/null)
                        current_sheets=$(echo "$current_detail" | jq -r '.definition.Definition.Sheets | length' 2>/dev/null)
                        backup_visuals=$(jq -r '[.Definition.Sheets[].Visuals | length] | add' "$backup_definition" 2>/dev/null)
                        current_visuals=$(echo "$current_detail" | jq -r '[.definition.Definition.Sheets[].Visuals | length] | add' 2>/dev/null)
                        
                        if [ "$backup_sheets" != "$current_sheets" ] || [ "$backup_visuals" != "$current_visuals" ]; then
                            print_yellow "  ⚠ Definition changed:"
                            echo "    Sheet count - At backup: ${backup_sheets:-0}, Current: ${current_sheets:-0}"
                            echo "    Visual count - At backup: ${backup_visuals:-0}, Current: ${current_visuals:-0}"
                        else
                            print_green "  ✓ No changes in definition"
                        fi
                    fi
                    
                else
                    print_red "  ✗ Current configuration retrieval error"
                fi
                
            done <<< "$backup_ids"
            ;;
            
        "dataset")
            if [ ! -f "$backup_dir/dataset-ids.json" ]; then
                print_yellow "Dataset backup files not found."
                return 1
            fi
            
            print_yellow "=== Detailed Dataset Configuration Diff Check ==="
            
            # Get backed up dataset IDs
            local backup_ids
            backup_ids=$(cat "$backup_dir/dataset-ids.json" | jq -r '.[]')
            
            # Get current dataset information
            local all_datasets
            if ! all_datasets=$(get_all_datasets) || ! filter_target_datasets "$all_datasets"; then
                return 1
            fi
            
            # Detailed comparison for each dataset
            while IFS= read -r dataset_id; do
                [ -z "$dataset_id" ] && continue
                
                print_cyan "\n--- Dataset ID: $dataset_id ---"
                
                # Get current dataset name
                local current_name
                current_name=$(echo "$all_datasets" | jq -r --arg id "$dataset_id" \
                    '.DataSetSummaries[] | select(.DataSetId == $id) | .Name')
                
                if [ -z "$current_name" ] || [ "$current_name" = "null" ]; then
                    print_red "  ✗ Dataset not found (deleted?)"
                    continue
                fi
                
                print_blue "  Dataset name: $current_name"
                
                # Build backup file paths
                local safe_filename backup_basic backup_permissions
                safe_filename=$(echo "$current_name" | sed 's/[\\/:*?"<>|]/_/g')
                backup_basic="$backup_dir/datasets/${safe_filename}-${dataset_id}.json"
                backup_permissions="$backup_dir/permissions/${safe_filename}-${dataset_id}-permissions.json"
                
                # Get current configuration
                local current_detail
                if current_detail=$(get_current_resource_detail "dataset" "$dataset_id" "$current_name"); then
                    
                    # Compare basic information
                    if [ -f "$backup_basic" ]; then
                        local backup_lastmodified current_lastmodified backup_import_mode current_import_mode
                        backup_lastmodified=$(jq -r '.DataSet.LastUpdatedTime // "N/A"' "$backup_basic" 2>/dev/null)
                        current_lastmodified=$(echo "$current_detail" | jq -r '.detail.DataSet.LastUpdatedTime // "N/A"' 2>/dev/null)
                        backup_import_mode=$(jq -r '.DataSet.ImportMode // "N/A"' "$backup_basic" 2>/dev/null)
                        current_import_mode=$(echo "$current_detail" | jq -r '.detail.DataSet.ImportMode // "N/A"' 2>/dev/null)
                        
                        local changes_detected=false
                        
                        if [ "$backup_lastmodified" != "$current_lastmodified" ]; then
                            print_yellow "  ⚠ Update time changed:"
                            echo "    At backup: $backup_lastmodified"
                            echo "    Current: $current_lastmodified"
                            changes_detected=true
                        fi
                        
                        if [ "$backup_import_mode" != "$current_import_mode" ]; then
                            print_yellow "  ⚠ Import mode changed:"
                            echo "    At backup: $backup_import_mode"
                            echo "    Current: $current_import_mode"
                            changes_detected=true
                        fi
                        
                        # Compare datasource configuration
                        local backup_datasource_count current_datasource_count
                        backup_datasource_count=$(jq -r '.DataSet.PhysicalTableMap | length' "$backup_basic" 2>/dev/null)
                        current_datasource_count=$(echo "$current_detail" | jq -r '.detail.DataSet.PhysicalTableMap | length' 2>/dev/null)
                        
                        if [ "$backup_datasource_count" != "$current_datasource_count" ]; then
                            print_yellow "  ⚠ Datasource count changed:"
                            echo "    At backup: ${backup_datasource_count:-0} sources"
                            echo "    Current: ${current_datasource_count:-0} sources"
                            changes_detected=true
                        fi
                        
                        if [ "$changes_detected" = false ]; then
                            print_green "  ✓ No changes in configuration"
                        fi
                    fi
                    
                else
                    print_red "  ✗ Current configuration retrieval error"
                fi
                
            done <<< "$backup_ids"
            ;;
    esac
}

# =============================================================================
# Future Integration Functions (callable from other scripts)
# =============================================================================

# Dataset management wrapper function
manage_dataset() {
    local operation="$1"     # create, update, upsert
    local json_file="$2" 
    local dry_run="${3:-false}"
    local update_permissions="${4:-false}"
    
    # Expected to call process_dataset_json function from dataset_manager.sh
    # Access via this function during future integration
    if [ -f "$SCRIPT_DIR/dataset_manager.sh" ]; then
        bash "$SCRIPT_DIR/dataset_manager.sh" \
            -f "$json_file" \
            -o "$operation" \
            $([ "$dry_run" = "true" ] && echo "-n") \
            $([ "$update_permissions" = "true" ] && echo "-p")
    else
        print_red "Error: dataset_manager.sh not found"
        return 1
    fi
}

# Analysis management wrapper function
manage_analysis() {
    local operation="$1"     # create, update, upsert
    local json_file="$2"
    local dry_run="${3:-false}"
    local update_permissions="${4:-false}"
    
    # Expected to call process_analysis_json function from analysis_manager.sh
    # Access via this function during future integration
    if [ -f "$SCRIPT_DIR/analysis_manager.sh" ]; then
        bash "$SCRIPT_DIR/analysis_manager.sh" \
            -f "$json_file" \
            -o "$operation" \
            $([ "$dry_run" = "true" ] && echo "-n") \
            $([ "$update_permissions" = "true" ] && echo "-p")
    else
        print_red "Error: analysis_manager.sh not found"
        return 1
    fi
}

# Batch apply from backup directory
apply_backup_directory() {
    local backup_dir="$1"
    local operation="${2:-upsert}"
    local dry_run="${3:-false}"
    local resource_types="${4:-all}"  # all, dataset, analysis
    
    print_bold "=== Batch Apply from Backup Directory ==="
    print_cyan "Target directory: $backup_dir"
    print_cyan "Operation: $operation"
    print_cyan "Target resources: $resource_types"
    
    local total_success=0
    local total_errors=0
    
    # Apply datasets
    if [[ "$resource_types" == "all" || "$resource_types" == "dataset" ]]; then
        if [ -d "$backup_dir/datasets" ]; then
            print_yellow "\n=== Applying Datasets ==="
            if bash "$SCRIPT_DIR/dataset_manager.sh" \
                -d "$backup_dir/datasets" \
                -o "$operation" \
                $([ "$dry_run" = "true" ] && echo "-n") \
                -p; then
                print_green "Dataset application completed"
            else
                print_red "Error occurred during dataset application"
                ((total_errors++))
            fi
        elif [ -d "$backup_dir" ] && ls "$backup_dir"/*.json >/dev/null 2>&1; then
            # When JSON files exist directly
            print_yellow "\n=== Applying Dataset Files ==="
            if bash "$SCRIPT_DIR/dataset_manager.sh" \
                -d "$backup_dir" \
                -o "$operation" \
                $([ "$dry_run" = "true" ] && echo "-n") \
                -p; then
                print_green "Dataset application completed"
            else
                print_red "Error occurred during dataset application"
                ((total_errors++))
            fi
        fi
    fi
    
    # Apply analyses
    if [[ "$resource_types" == "all" || "$resource_types" == "analysis" ]]; then
        if [ -d "$backup_dir/analyses" ]; then
            print_yellow "\n=== Applying Analyses ==="
            for analysis_file in "$backup_dir"/analyses/*.json; do
                [ -f "$analysis_file" ] || continue
                
                if bash "$SCRIPT_DIR/analysis_manager.sh" \
                    -f "$analysis_file" \
                    -o "$operation" \
                    $([ "$dry_run" = "true" ] && echo "-n") \
                    -p; then
                    ((total_success++))
                else
                    ((total_errors++))
                fi
            done
        fi
    fi
    
    print_bold "\n=== Batch Application Completed ==="
    print_green "Successful: $total_success items"
    [ $total_errors -gt 0 ] && print_red "Errors: $total_errors items"
    
    return $total_errors
}
