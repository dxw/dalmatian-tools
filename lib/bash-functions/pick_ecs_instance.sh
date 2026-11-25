#!/usr/bin/env bash
set -e
set -o pipefail

# Get an ECS Host ID (or all running IDs with -a) from available instances
#
# @usage pick_ecs_instance -i <infrastructure> -e <environment> [-v <vpc_id>] [-a]
# @param -i <infrastructure>  Infrastructure name (e.g. my-infrastructure)
# @param -e <environment>     Environment name (e.g. staging/prod)
# @param -v <vpc_id>          Optional VPC ID to filter by
# @param -a                   Return all running instance IDs, one per line
# @return string              ID(s) of running EC2 instance(s)
function pick_ecs_instance {
  local INFRASTRUCTURE_NAME=""
  local ENVIRONMENT=""
  local VPC_ID=""
  local ALL=0
  local ECS_INSTANCES
  local FILTERS

  OPTIND=1
  while getopts "i:e:v:a" opt; do
    case $opt in
      i)
        INFRASTRUCTURE_NAME="$OPTARG"
        ;;
      e)
        ENVIRONMENT="$OPTARG"
        ;;
      v)
        VPC_ID="$OPTARG"
        ;;
      a)
        ALL=1
        ;;
      *)
        echo "Invalid \`pick_ecs_instance\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$INFRASTRUCTURE_NAME" ] || [ -z "$ENVIRONMENT" ]
  then
    echo "Invalid \`pick_ecs_instance\` function usage" >&2
    return 1
  fi

  FILTERS=("Name=instance-state-code,Values=16" "Name=tag:Name,Values=$INFRASTRUCTURE_NAME-$ENVIRONMENT*")
  if [ -n "$VPC_ID" ]
  then
    FILTERS=("Name=vpc-id,Values=$VPC_ID" "${FILTERS[@]}")
  fi

  ECS_INSTANCES=$(
    aws ec2 describe-instances \
      --filters "${FILTERS[@]}"
  ) || return $?

  if [ "$ALL" -eq 1 ]
  then
    echo "$ECS_INSTANCES" \
      | jq -r '.Reservations[].Instances[]?.InstanceId // empty'
  else
    echo "$ECS_INSTANCES" \
      | jq -r '[.Reservations[].Instances[]?.InstanceId // empty][0] // empty'
  fi
}
