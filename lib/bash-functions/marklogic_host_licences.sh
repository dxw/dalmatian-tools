#!/usr/bin/env bash
set -e
set -o pipefail

# The licence of every host in a MarkLogic cluster, read through an open
# tunnel to any host's Manage API (marklogic_tunnel_open -P 8002)
#
# The Manage API reports a host's licence under
# host-status.status-properties.status-detail: license-key and licensee as
# plain strings, license-key-expires as {"units": "datetime", "value": ...}.
# Values are read whether or not they are wrapped, since the API wraps some
# properties and not others.
#
# Hosts are tied back to instances by MarkLogic's host name. The template
# gives each node a second, managed network interface and MarkLogic names
# the host after that, so every interface's DNS name and address is checked,
# not just the instance's primary ones.
#
# Values are trimmed: the documented curl for setting a licence closes its
# quote on the line after the key, and hosts licensed that way store the key
# with a trailing newline.
#
# @usage marklogic_host_licences -j "$NODES" -u "$ADMIN_USER" -c "$CURL_CONFIG_LINE"
# @param -j <json>         `ec2 describe-instances` JSON for the cluster's nodes
# @param -u <admin_user>   MarkLogic user, for error messages
# @param -c <config_line>  curl config line from marklogic_curl_config
# @return string           One JSON object per host:
#                          {"host", "instance", "licensee", "key", "expires"}
function marklogic_host_licences {
  local NODES_JSON=""
  local ADMIN_USER=""
  local CONFIG_LINE=""
  local RESPONSE
  local HTTP_STATUS
  local BODY
  local HOST_NAME
  local HOST_PATH
  local -a HOST_NAMES=()

  OPTIND=1
  while getopts "j:u:c:" opt; do
    case $opt in
      j)
        NODES_JSON="$OPTARG"
        ;;
      u)
        ADMIN_USER="$OPTARG"
        ;;
      c)
        CONFIG_LINE="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_host_licences\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$NODES_JSON" || -z "$ADMIN_USER" || -z "$CONFIG_LINE" ]]
  then
    echo "Invalid \`marklogic_host_licences\` function usage" >&2
    return 1
  fi

  RESPONSE="$(marklogic_tunnel_request -X GET -u "/manage/v2/hosts?format=json" -K <(printf '%s\n' "$CONFIG_LINE"))"
  HTTP_STATUS="${RESPONSE##*$'\n'}"
  BODY="${RESPONSE%$'\n'*}"
  if [ "$HTTP_STATUS" != "200" ]
  then
    err "Manage API returned HTTP $HTTP_STATUS for user '$ADMIN_USER' when listing hosts"
    return 1
  fi

  while IFS='' read -r HOST_NAME
  do
    [ -n "$HOST_NAME" ] && HOST_NAMES+=("$HOST_NAME")
  done < <(echo "$BODY" | jq -r '.["host-default-list"]["list-items"]["list-item"][]?.nameref')

  if [ "${#HOST_NAMES[@]}" -eq 0 ]
  then
    err "The Manage API listed no hosts"
    return 1
  fi

  for HOST_NAME in "${HOST_NAMES[@]}"
  do
    # The name comes from the server; encoded so it can only ever be a path
    # segment
    HOST_PATH="$(jq -rn --arg h "$HOST_NAME" '$h | @uri')"
    RESPONSE="$(marklogic_tunnel_request -X GET -u "/manage/v2/hosts/$HOST_PATH?view=status&format=json" -K <(printf '%s\n' "$CONFIG_LINE"))"
    HTTP_STATUS="${RESPONSE##*$'\n'}"
    BODY="${RESPONSE%$'\n'*}"
    if [ "$HTTP_STATUS" != "200" ]
    then
      err "Manage API returned HTTP $HTTP_STATUS for the status of host '$HOST_NAME'"
      return 1
    fi

    jq -nc \
      --arg host "$HOST_NAME" \
      --argjson status "$BODY" \
      --argjson nodes "$NODES_JSON" \
      'def unwrap: if type == "object" and has("value") then .value else . end
                   | if . == null then "" else tostring end
                   | gsub("^\\s+|\\s+$"; "");
       ($status["host-status"]["status-properties"]["status-detail"] // {}) as $d
       | {
           host: $host,
           instance: ([$nodes.Reservations[].Instances[]
                       | select(
                           ([.PrivateDnsName, .PrivateIpAddress]
                            + [.NetworkInterfaces[]? | .PrivateDnsName, .PrivateIpAddress])
                           | index($host))
                       | .InstanceId + " ("
                         + (((.Tags[]? | select(.Key == "Name") | .Value | select(. != "")) // "No Name"))
                         + ")"][0] // "-"),
           licensee: ($d.licensee | unwrap),
           key: ($d["license-key"] | unwrap),
           expires: ($d["license-key-expires"] | unwrap)
         }'
  done
}
