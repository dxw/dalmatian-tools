#!/usr/bin/env bash
set -e
set -o pipefail

# The running EC2 instances of a MarkLogic CloudFormation cluster
#
# The MarkLogic template tags every instance it launches with the stack name
# under `marklogic:stack:name`, which is what the marklogic commands agree on
# as the definition of a node.
#
# @usage NODES="$(marklogic_stack_nodes -p "$PROFILE" -n "$STACK_NAME")"
# @param -p <profile>     AWS profile to query with
# @param -n <stack_name>  Full CloudFormation stack name
# @return string          `ec2 describe-instances` JSON
function marklogic_stack_nodes {
  local PROFILE=""
  local STACK_NAME=""

  OPTIND=1
  while getopts "p:n:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      n)
        STACK_NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_stack_nodes\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$PROFILE" || -z "$STACK_NAME" ]]
  then
    echo "Invalid \`marklogic_stack_nodes\` function usage" >&2
    return 1
  fi

  "$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    ec2 describe-instances \
    --filters "Name=tag:marklogic:stack:name,Values=$STACK_NAME" \
              "Name=instance-state-name,Values=running"
}
