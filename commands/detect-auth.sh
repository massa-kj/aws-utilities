#!/usr/bin/env bash
#=============================================================
# detect-auth.sh - Detect authentication source
#=============================================================

set -euo pipefail

# Load common utilities
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/common/logger.sh"

detect_auth_source() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    echo "profile:${AWS_PROFILE}"
  elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "env-vars"
  else
    echo "iam-role"
  fi
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
detect-auth - Detect authentication source

Usage:
  awstools detect-auth

Description:
  Detects the current AWS authentication source:
  - profile:<name>   AWS CLI profile is being used
  - env-vars         Environment variables (AWS_ACCESS_KEY_ID, etc.)
  - iam-role         IAM role (EC2 instance profile, etc.)

Examples:
  awstools detect-auth
EOF
  exit 0
fi

detect_auth_source
