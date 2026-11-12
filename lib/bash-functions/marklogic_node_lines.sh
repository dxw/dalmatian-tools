#!/usr/bin/env bash
set -e
set -o pipefail

# Format MarkLogic node JSON as one line per node
#
# Like ec2_instance_lines, the first field is always the instance id so the
# same lines can be listed and picked from. Zone and AMI are added because
# which nodes are still on an old image is the usual question.
#
# @usage marklogic_node_lines -j "$NODES"
# @param -j <json>  `ec2 describe-instances` JSON
# @return string    Lines of "<instance id> | <name> | <zone> | <ami> | <launch time>"
function marklogic_node_lines {
  local NODES_JSON=""

  OPTIND=1
  while getopts "j:" opt; do
    case $opt in
      j)
        NODES_JSON="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_node_lines\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$NODES_JSON" ]
  then
    echo "Invalid \`marklogic_node_lines\` function usage" >&2
    return 1
  fi

  echo "$NODES_JSON" | jq -r '.Reservations[].Instances[] |
    .InstanceId + " | " +
    (((.Tags[]? | select(.Key == "Name") | .Value | select(. != "")) // "No Name")) + " | " +
    .Placement.AvailabilityZone + " | " +
    .ImageId + " | " +
    .LaunchTime'
}
