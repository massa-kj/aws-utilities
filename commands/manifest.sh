#!/usr/bin/env bash
# commands/manifest.sh - Global commands manifest

# Define available global commands
declare -A GLOBAL_COMMANDS=(
  ["detect-auth"]="Detect authentication source (profile, env-vars, iam-role)"
)

# Function to list all available global commands
list_global_commands() {
  for cmd in "${!GLOBAL_COMMANDS[@]}"; do
    printf "  - %-20s %s\n" "$cmd" "${GLOBAL_COMMANDS[$cmd]}"
  done
}

# Function to check if a command is a global command
is_global_command() {
  local cmd="$1"
  [[ -n "${GLOBAL_COMMANDS[$cmd]:-}" ]]
}

# Function to get command description
get_command_description() {
  local cmd="$1"
  echo "${GLOBAL_COMMANDS[$cmd]:-}"
}
