#!/bin/bash
set -e
set -o pipefail

# Get an ECS Host ID from a list of available instances
#
# @usage pick_ecs_instance -i <infrastructure> -e <environment>
# @param -i <infrastructure>  Infrastructure name (e.g. dxw-govpress)
# @param -e <environment>     Environment name (e.g. staging/prod)
# @return string              ID of an EC2 Instance
function pick_ecs_instance {
  while getopts "i:e" opt; do
    case $opt in
      i)
        local INFRASTRUCTURE_NAME="$OPTARG"
        ;;
      e)
        local ENVIRONMENT="$OPTARG"
        ;;
      *)
        ;;
    esac
  done

  ECS_INSTANCES=$(
    aws ec2 describe-instances \
      --filters "Name=instance-state-code,Values=16" Name=tag:Name,Values="$INFRASTRUCTURE_NAME-$ENVIRONMENT*"
  )

  ECS_INSTANCE_ID=$(
    echo "$ECS_INSTANCES" \
      | jq -r .Reservations[0].Instances[0].InstanceId
  )

  echo "$ECS_INSTANCE_ID"
}
