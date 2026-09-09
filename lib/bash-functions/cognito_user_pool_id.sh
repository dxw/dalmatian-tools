#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian specific function to find a Cognito User Pool ID from its
# full name (<project>-<infrastructure>-<environment>-<pool>)
#
# @param -p <aws_sso_profile>  AWS SSO profile
# @param -n <pool_name>        Full pool name
function cognito_user_pool_id {
  local OPTIND opt OPTARG PROFILE POOL_NAME POOL_ID
  OPTIND=1
  while getopts "p:n:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      n)
        POOL_NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`cognito_user_pool_id\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$PROFILE" || -z "$POOL_NAME" ]]
  then
    echo "Invalid \`cognito_user_pool_id\` function usage" >&2
    exit 1
  fi
  POOL_ID="$(
    "$APP_ROOT/bin/dalmatian" aws run-command \
      -p "$PROFILE" \
      cognito-idp list-user-pools \
      --max-results 60 \
    | jq -r --arg name "$POOL_NAME" '.UserPools[] | select(.Name == $name) | .Id // empty'
  )"
  if [ -z "$POOL_ID" ]
  then
    err "Cognito User Pool '$POOL_NAME' not found"
    exit 1
  fi
  if [ "$(echo "$POOL_ID" | wc -l)" -gt 1 ]
  then
    err "More than one Cognito User Pool is named '$POOL_NAME'; resolve the duplicate before using dalmatian cognito"
    exit 1
  fi
  echo "$POOL_ID"
}
