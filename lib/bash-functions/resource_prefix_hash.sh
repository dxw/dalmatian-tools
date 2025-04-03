#!/bin/bash
set -e
set -o pipefail

# Dalmatian specific function to get the resource prefix hash
# from a given infrastructure name and environment
#
# @param -i <infrastructure_name>  An infrastructure's friendly name
# @param -e <environment_name>     An infrastructure's environment name
function resource_prefix_hash {
  OPTIND=1
  while getopts "i:e:" opt; do
    case $opt in
      i)
        INFRASTRUCTURE_NAME="$OPTARG"
        ;;
      e)
        ENVIRONMENT_NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`resource_prefix_hash\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[
    -n "$INFRASTRUCTURE_NAME"
    && -n "$ENVIRONMENT_NAME"
  ]]
  then
    PROJECT_NAME="$(jq -r '.project_name' < "$CONFIG_SETUP_JSON_FILE")"
    RESOURCE_PREFIX_HASH="$(echo -n "$PROJECT_NAME-$INFRASTRUCTURE_NAME-$ENVIRONMENT_NAME" | sha512sum | head -c 8)"
    if [[ $RESOURCE_PREFIX_HASH =~ ^[0-9] ]]
    then
      RESOURCE_PREFIX_HASH="h$RESOURCE_PREFIX_HASH"
    fi
    echo "$RESOURCE_PREFIX_HASH"
  else
    echo "Invalid \`resource_prefix_hash\` function usage" >&2
    exit 1
  fi
}
