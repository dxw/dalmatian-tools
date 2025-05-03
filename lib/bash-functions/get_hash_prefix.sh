#!/bin/bash
set -e
set -o pipefail

# Get the first 8 chars of a sha512 hash for a given string.
# Useful when trying to locate resources deployed by Dalmatian v2
# @see https://github.com/dxw/terraform-dxw-dalmatian-infrastructure/blob/main/locals.tf#L8
# @usage get_hash_prefix "${PROJECT_NAME}-${INFRASTRUCTURE}-${ENVIRONMENT}"
# @param string that you want to hash
function get_hash_prefix {
  hash=$(echo -n "$1" | sha512sum)
  echo "${hash:0:8}"
}
