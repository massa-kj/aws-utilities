#!/usr/bin/env bash

validate_config() {
}

show_effective_config() {
}

load_config() {
  local environment="$1"
  local service="${2:-}"
  local base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)"

  # Common settings
  [ -f "$base_dir/default/common.env" ] && source "$base_dir/default/common.env"
  [ -f "$base_dir/overwrite/common.env" ] && source "$base_dir/overwrite/common.env"

  # AWS-Tools profile settings
  if [ -n "$environment" ]; then
    [ -f "$base_dir/default/environments/${environment}.env" ] && source "$base_dir/default/environments/${environment}.env"
    [ -f "$base_dir/overwrite/environments/${environment}.env" ] && source "$base_dir/overwrite/environments/${environment}.env"
    export AWSTOOLS_PROFILE="$environment"
  else
    [ -f "$base_dir/default/environments/${AWSTOOLS_PROFILE}.env" ] && source "$base_dir/default/environments/${AWSTOOLS_PROFILE}.env"
    [ -f "$base_dir/overwrite/environments/${AWSTOOLS_PROFILE}.env" ] && source "$base_dir/overwrite/environments/${AWSTOOLS_PROFILE}.env"
  fi

  # Service settings
  if [ -n "$service" ]; then
    [ -f "$base_dir/default/services/${service}.env" ] && source "$base_dir/default/services/${service}.env"
    [ -f "$base_dir/overwrite/services/${service}.env" ] && source "$base_dir/overwrite/services/${service}.env"
  fi

  return 0
}
