#!/bin/bash
set -e
set -o pipefail

# Dalmatian specific function to resolve the aws-sso profile name
# from a given infrastructure name and environment, or a Dalmatian
# account name
#
# @param -i <infrastructure_name>  An infrastructure's friendly name
# @param -e <environment_name>     An infrastructure's environment name
# @param -a <dalmatian_account>    A Dalmatian Account name
function resolve_aws_profile {
  OPTIND=1
  while getopts "i:e:a:" opt; do
    case $opt in
      i)
        INFRASTRUCTURE_NAME="$OPTARG"
        ;;
      e)
        ENVIRONMENT_NAME="$OPTARG"
        ;;
      a)
        DALMATIAN_ACCOUNT="$OPTARG"
        ;;
      *)
        echo "Invalid \`resolve_aws_profile\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[
    -n "$INFRASTRUCTURE_NAME"
    && -n "$ENVIRONMENT_NAME"
  ]]
  then
    ACCOUNT_INFRASTRUCTURES="$("$APP_ROOT/bin/dalmatian" deploy list-infrastructures)"
    ACCOUNT_WORKSPACE="$(echo "$ACCOUNT_INFRASTRUCTURES" | jq -r \
    --arg infrastructure_name "$INFRASTRUCTURE_NAME" \
    --arg environment_name "$ENVIRONMENT_NAME" \
    '.accounts |
    to_entries |
    map(select(
      (.value.infrastructures | has($infrastructure_name) ) and
      ( .value.infrastructures[$infrastructure_name].environments | index($environment_name) )
    )) |
    from_entries |
    keys[0]')"
  elif [[
    -n "$DALMATIAN_ACCOUNT"
  ]]
  then
    ACCOUNT_WORKSPACE="$DALMATIAN_ACCOUNT"
  else
    echo "Invalid \`resolve_aws_profile\` function usage" >&2
  fi
  
  PROFILE_NAME="$(echo "$ACCOUNT_WORKSPACE" | cut -d'-' -f5-)"
  echo "$PROFILE_NAME"
}
