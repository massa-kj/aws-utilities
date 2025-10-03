#!/bin/bash

# QuickSight Configuration File
# Configure AWS account information and target resources in this file
#
# Usage:
# 1. Change ACCOUNT_ID to your AWS Account ID
# 2. Change REGION to the AWS region you want to use
# 3. Set TARGET_ANALYSES to the analysis names you want to backup
# 4. Set TARGET_DATASETS to the dataset names you want to backup

# =============================================================================
# AWS Configuration
# =============================================================================
# 12-digit AWS Account ID
ACCOUNT_ID="999999999999"

# AWS Region (e.g., us-east-1, eu-west-1, ap-northeast-1)
REGION="xx-yyyy-1"

# =============================================================================
# Target Analysis Configuration
# =============================================================================
# List of analysis names to backup and manage
TARGET_ANALYSES=(
)

# =============================================================================
# Target Dataset Configuration
# =============================================================================
# List of dataset names to backup and manage
TARGET_DATASETS=(
)

# =============================================================================
# Backup Configuration
# =============================================================================
# Base name for backup directories
BACKUP_DIR_PREFIX="quicksight-backup"

# =============================================================================
# Configuration Validation
# =============================================================================
validate_config() {
    local errors=0
    
    # Check required settings
    if [ -z "$ACCOUNT_ID" ]; then
        echo "Error: ACCOUNT_ID is not configured"
        ((errors++))
    fi
    
    if [ -z "$REGION" ]; then
        echo "Error: REGION is not configured"
        ((errors++))
    fi
    
    # AWS Account ID format check (12-digit number)
    if ! [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
        echo "Error: ACCOUNT_ID format is incorrect (must be a 12-digit number)"
        ((errors++))
    fi
    
    # Simple region format check
    if ! [[ "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        echo "Warning: REGION format may not be standard: $REGION"
    fi
    
    return $errors
}

# Display configuration information
show_config() {
    echo "=== QuickSight Configuration Information ==="
    echo "AWS Account ID: $ACCOUNT_ID"
    echo "AWS Region: $REGION"
    echo "Target analyses count: ${#TARGET_ANALYSES[@]}"
    echo "Target datasets count: ${#TARGET_DATASETS[@]}"
    echo "Verbose output: $VERBOSE_MODE"
    echo "Color output: $COLOR_OUTPUT"
}
