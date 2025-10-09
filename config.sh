#!/usr/bin/env bash
#=============================================================
# config.sh - AWS Common Configuration
#-------------------------------------------------------------
# • Safely load environment variables
# • Unify AWS_PROFILE / AWS_REGION priority order  
# • Allow per-user overrides (.env.local)
# • Auto-complete unset items
#=============================================================

set -euo pipefail

#--- Basic Configuration -------------------------------------
# Intended to be sourced during project tool execution
# ※Export global variables carefully (prevent impact on other tools)

# Default profile/region (applied only when unset)
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-}"

# Common locations (used as local variables)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$BASE_DIR/common"
SERVICES_DIR="$BASE_DIR/services"

#--- Local Override Configuration ----------------------------
# Load optional user/environment-specific config file (.env.local) if exists
if [ -f "$BASE_DIR/.env.local" ]; then
  source "$BASE_DIR/.env.local"
fi

#--- AWS Account Information Completion ---------------------
# Get ACCOUNT_ID if not set
if [ -z "${ACCOUNT_ID:-}" ]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  if [ -z "$ACCOUNT_ID" ]; then
    echo "[WARN] ACCOUNT_ID could not be determined. Check your AWS credentials." >&2
  fi
fi

#--- Basic Information Output (Debug mode only) -------------
if [ "${DEBUG_AWSTOOLS:-false}" = "true" ]; then
  echo "----------------------------------------"
  echo "AWS_PROFILE : $AWS_PROFILE"
  echo "AWS_REGION  : $AWS_REGION"
  echo "ACCOUNT_ID  : ${ACCOUNT_ID:-unknown}"
  echo "----------------------------------------"
fi

#--- Export Environment Variables ---------------------------
# (Intended to be used by source calls within this script)
export AWS_PROFILE AWS_REGION ACCOUNT_ID BASE_DIR COMMON_DIR SERVICES_DIR
