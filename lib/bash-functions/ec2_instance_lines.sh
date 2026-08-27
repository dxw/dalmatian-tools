#!/usr/bin/env bash
set -e
set -o pipefail

# Format `ec2 describe-instances` JSON as one human readable line per instance
#
# The format is shared by the `-l` listing and the instance picker so that what
# a user sees when listing is what they pick from, and so that the first
# space-delimited field is always the instance id
#
# @usage ec2_instance_lines -j "$INSTANCES"
# @param -j <json>  `ec2 describe-instances` JSON
# @return string    Lines of "<instance id> | <name> | <launch time>"
function ec2_instance_lines {
  local INSTANCES_JSON

  OPTIND=1
  while getopts "j:" opt; do
    case $opt in
      j)
        INSTANCES_JSON="$OPTARG"
        ;;
      *)
        echo "Invalid \`ec2_instance_lines\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$INSTANCES_JSON" ]
  then
    echo "Invalid \`ec2_instance_lines\` function usage" >&2
    return 1
  fi

  # `.Tags[]?` and the `//` default keep untagged instances in the list rather
  # than dropping them or failing the whole expression. The `select(. != "")`
  # is needed because an empty string is truthy to jq's `//`, so a Name tag
  # present but set to "" would otherwise render as a blank name
  echo "$INSTANCES_JSON" | jq -r '.Reservations[].Instances[] |
    (.InstanceId) + " | " +
      (((.Tags[]? | select(.Key == "Name") | .Value | select(. != "")) // "No Name")) + " | " +
    (.LaunchTime)'
}
