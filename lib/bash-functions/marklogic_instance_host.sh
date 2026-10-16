#!/usr/bin/env bash
set -e
set -o pipefail

# The MarkLogic host name of one EC2 node, read through an open tunnel to any
# host's Manage API (marklogic_tunnel_open -P 8002)
#
# The MarkLogic template gives each node a second, managed network interface
# and MarkLogic names the host after that, so every interface's DNS name and
# address is matched, not just the instance's primary ones.
#
# @usage HOST="$(marklogic_instance_host -j "$NODES" -I "$INSTANCE_ID" -u "$ML_USER" -c "$CURL_CONFIG_LINE")"
# @param -j <json>         `ec2 describe-instances` JSON including the node
# @param -I <instance_id>  The node
# @param -u <user>         MarkLogic user, for error messages
# @param -c <config_line>  curl config line from marklogic_curl_config
# @return string           The host name
function marklogic_instance_host {
  local NODES_JSON=""
  local INSTANCE_ID=""
  local ML_USER=""
  local CONFIG_LINE=""
  local RESPONSE
  local HTTP_STATUS
  local BODY
  local HOST_NAME

  OPTIND=1
  while getopts "j:I:u:c:" opt; do
    case $opt in
      j)
        NODES_JSON="$OPTARG"
        ;;
      I)
        INSTANCE_ID="$OPTARG"
        ;;
      u)
        ML_USER="$OPTARG"
        ;;
      c)
        CONFIG_LINE="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_instance_host\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$NODES_JSON" || -z "$INSTANCE_ID" || -z "$ML_USER" || -z "$CONFIG_LINE" ]]
  then
    echo "Invalid \`marklogic_instance_host\` function usage" >&2
    return 1
  fi

  RESPONSE="$(marklogic_tunnel_request -X GET -u "/manage/v2/hosts?format=json" -K <(printf '%s\n' "$CONFIG_LINE"))" || return 1
  HTTP_STATUS="${RESPONSE##*$'\n'}"
  BODY="${RESPONSE%$'\n'*}"
  if [ "$HTTP_STATUS" != "200" ]
  then
    err "Manage API returned HTTP $HTTP_STATUS for user '$ML_USER' when listing hosts"
    return 1
  fi

  HOST_NAME="$(jq -rn \
    --argjson hosts "$BODY" \
    --argjson nodes "$NODES_JSON" \
    --arg i "$INSTANCE_ID" \
    '([$nodes.Reservations[].Instances[] | select(.InstanceId == $i)
       | .PrivateDnsName, .PrivateIpAddress, (.NetworkInterfaces[]? | .PrivateDnsName, .PrivateIpAddress)]
      | map(select(. != null and . != ""))) as $names
     | [$hosts["host-default-list"]["list-items"]["list-item"][]?.nameref
        | select(. as $h | $names | index($h))][0] // empty')"

  if [ -z "$HOST_NAME" ]
  then
    err "No MarkLogic host in the cluster matches $INSTANCE_ID"
    return 1
  fi

  echo "$HOST_NAME"
}
