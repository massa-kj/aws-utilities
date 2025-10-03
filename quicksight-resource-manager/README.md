# QuickSight Management Scripts

A collection of scripts for backing up and managing AWS QuickSight analyses and datasets.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Basic Usage](#basic-usage)
- [Backup Features](#backup-features)
- [Create/Update Features](#createupdate-features)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

## Prerequisites

The following tools must be installed:

- **AWS CLI** - Configured (testable with `aws sts get-caller-identity`)
- **jq** - For JSON processing

## Initial Setup

### 1. Edit Configuration File

Edit `config.sh` before first use:

```bash
# Edit configuration file
vi config.sh
```

Required configuration items:
- **ACCOUNT_ID**: Your AWS Account ID (12 digits)
- **REGION**: AWS region to use
- **TARGET_ANALYSES**: Analysis names to manage
- **TARGET_DATASETS**: Dataset names to manage

### 2. Verify Configuration

```bash
./quicksight_manager.sh show-config
```

## Basic Usage

### Show Help

```bash
./quicksight_manager.sh help
```

### Dry Run (Check Execution Content)

```bash
# Check execution content without actually running
./quicksight_manager.sh backup-all --dry-run
```

### List Target Resources

```bash
# List target analyses
./quicksight_manager.sh list-analysis

# List target datasets
./quicksight_manager.sh list-dataset
```

## Backup Features

### Resource Backup

```bash
# Backup analyses
./quicksight_manager.sh backup-analysis

# Backup datasets
./quicksight_manager.sh backup-dataset

# Backup all
./quicksight_manager.sh backup-all
```

### Backup File Structure

Backups are saved with the following structure:

```
quicksight-[type]-backup-YYYYMMDD-HHMMSS/
├── analyses/ or datasets/
│   ├── [resource-name]-[ID].json           # Basic information
│   └── ...
├── definitions/ (analyses only)
│   ├── [resource-name]-[ID]-definition.json # Definition information
│   └── ...
├── permissions/
│   ├── [resource-name]-[ID]-permissions.json # Permission information
│   └── ...
├── [analysis|dataset]-ids.json         # ID list
└── [analysis|dataset]-summary.json     # Summary information
```

## Create/Update Features

### Overview

You can create and update QuickSight datasets and analyses from backed up JSON files (editable).

- **`dataset_manager.sh`** - Dataset creation and updates
- **`analysis_manager.sh`** - Analysis creation and updates

### Basic Usage

#### Dataset Operations

```bash
# Create new from single file
./dataset_manager.sh -f backup_file.json -o create

# Update single file (including permissions)
./dataset_manager.sh -f backup_file.json -o update -p

# Update if exists, create if not (recommended)
./dataset_manager.sh -f backup_file.json -o upsert

# Batch process directory
./dataset_manager.sh -d ./dataset_backups/ -o upsert

# Dry run (check execution content)
./dataset_manager.sh -f backup_file.json -o upsert --dry-run
```

#### Analysis Operations

```bash
# Create new from single file
./analysis_manager.sh -f analysis_backup.json -o create

# Update single file (including permissions)
./analysis_manager.sh -f analysis_backup.json -o update -p

# Update if exists, create if not (recommended)
./analysis_manager.sh -f analysis_backup.json -o upsert

# Batch process directory
./analysis_manager.sh -d ./analyses/ -o upsert

# Dry run (check execution content)
./analysis_manager.sh -f analysis_backup.json -o upsert --dry-run
```

### Safety Features

#### Pre-execution Confirmation

For safety, confirmation is displayed before resource modification operations:

```bash
=== Processing Target Information ===
File: /path/to/dataset.json
Dataset ID: my-dataset-id
Dataset Name: My Dataset
Operation to execute: upsert
Will execute upsert operation on the above dataset.
Do you want to execute this operation? [y/N]:
```

#### Batch Processing Pre-confirmation

When batch processing multiple files, all targets are displayed before confirmation:

```bash
=== Batch Processing Target Information ===
Target Directory: ./datasets/
Operation to execute: upsert
Number of files to process: 2

Processing target list:
 1. dataset1.json
    ID: dataset-001
    Name: Example Dataset 1

 2. dataset2.json
    ID: dataset-002
    Name: Example Dataset 2
    
Will batch execute upsert operation on the above 2 datasets.
Do you want to execute this operation? [y/N]:
```

Notes:
- Confirmation is skipped during dry run (`--dry-run`)
- Execute with `y` or `yes`, cancel with anything else

### Operation Modes

- **`create`**: Create new only (error if already exists)
- **`update`**: Update only (error if doesn't exist)
- **`upsert`**: Update if exists, create if not (recommended)

## File Structure

| File | Description |
|------|-------------|
| `quicksight_manager.sh` | Main script (command line operations) |
| `quicksight_lib.sh` | Common library file (function collection) |
| `config.sh` | Configuration file (AWS account, target resources, etc.) |
| `dataset_manager.sh` | Dataset creation and update script |
| `analysis_manager.sh` | Analysis creation and update script |
