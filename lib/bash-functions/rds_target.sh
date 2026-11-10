#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to find an RDS and the values an RDS user
# command substitutes into the script it runs in the utilities container, each
# checked against a pattern that cannot break out of it. Prints one JSON
# object:
#
#   {
#     "engine": "<RDS engine>",
#     "endpoint": "<writer address>",
#     "root_username": "<master user>",
#     "region": "<region of the profile>"
#   }
#
# The endpoint is the writer's, because the utilities task's own DB_HOST is a
# cluster's reader endpoint, which cannot take writes. Exits 1 with an error
# when a value is not what it should be.
#
# @param -p <aws_sso_profile>  AWS SSO profile
# @param -i <rds_identifier>   RDS identifier (<resource prefix hash>-<rds name>)
function rds_target {
  local OPTIND opt OPTARG PROFILE RDS_IDENTIFIER RDS_INFO RDS_ENGINE RDS_ENDPOINT RDS_ROOT_USERNAME REGION
  OPTIND=1
  while getopts "p:i:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      i)
        RDS_IDENTIFIER="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_target\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$PROFILE" || -z "$RDS_IDENTIFIER" ]]
  then
    echo "Invalid \`rds_target\` function usage" >&2
    exit 1
  fi

  RDS_INFO="$(rds_info -p "$PROFILE" -i "$RDS_IDENTIFIER")"
  RDS_ENGINE="$(echo "$RDS_INFO" | jq -r '.engine')"
  RDS_ROOT_USERNAME="$(echo "$RDS_INFO" | jq -r '.master_username')"
  RDS_ENDPOINT="$(echo "$RDS_INFO" | jq -r '.endpoint')"

  if [[ ! "$RDS_ENDPOINT" =~ ^[A-Za-z0-9.-]+$ ]]
  then
    err "Unexpected endpoint for $RDS_IDENTIFIER: $RDS_ENDPOINT"
    exit 1
  fi
  if [[ ! "$RDS_ROOT_USERNAME" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]
  then
    err "Unexpected root username for $RDS_IDENTIFIER: $RDS_ROOT_USERNAME"
    exit 1
  fi

  REGION="$("$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    configure get region)"
  if [[ ! "$REGION" =~ ^[a-z0-9-]+$ ]]
  then
    err "Unexpected region for profile $PROFILE: $REGION"
    exit 1
  fi

  jq -cn \
    --arg engine "$RDS_ENGINE" \
    --arg endpoint "$RDS_ENDPOINT" \
    --arg root_username "$RDS_ROOT_USERNAME" \
    --arg region "$REGION" \
    '{engine: $engine, endpoint: $endpoint, root_username: $root_username, region: $region}'
}
