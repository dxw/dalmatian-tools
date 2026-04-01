#!/usr/bin/env bash
set -e
set -o pipefail

# This script is sourced by dalmatian and subcommands.
# It ensures that a modern version of Bash is used.

function check_bash_version() {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: Bash 4.0 or newer is required." >&2
    echo "You appear to be running Bash ${BASH_VERSION}." >&2
    echo "On macOS, you can install a modern version with: brew install bash" >&2
    exit 1
  fi
}
