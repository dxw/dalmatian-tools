#!/usr/bin/env bash
set -e
set -o pipefail

# The forests on one MarkLogic host, each with its state and the states of
# its replicas, read through an open tunnel to any host's Manage API
# (marklogic_tunnel_open -P 8002)
#
# The state is read from forest-status.status-properties.state, wrapped as
# {"value": ...} or not. Replicas are listed by id somewhere under the
# forest's replica-forests property; the ids are collected wherever they sit
# rather than from one assumed path, and each replica's own status is read
# for its state. A state that cannot be read is given as "", so callers
# treat it as unknown rather than as any particular state.
#
# @usage marklogic_host_forests -H "$HOST" -u "$ML_USER" -c "$CURL_CONFIG_LINE"
# @param -H <host>         MarkLogic host name
# @param -u <user>         MarkLogic user, for error messages
# @param -c <config_line>  curl config line from marklogic_curl_config
# @return string           One JSON object per forest:
#                          {"name", "state", "replicas": [{"id", "state"}]}
function marklogic_host_forests {
  local HOST_NAME=""
  local ML_USER=""
  local CONFIG_LINE=""
  local RESPONSE
  local BODY
  local FOREST
  local FOREST_STATE
  local FOREST_PATH
  local FOREST_STATUS
  local REPLICA_ID
  local REPLICA_STATES
  local -a FORESTS=()

  OPTIND=1
  while getopts "H:u:c:" opt; do
    case $opt in
      H)
        HOST_NAME="$OPTARG"
        ;;
      u)
        ML_USER="$OPTARG"
        ;;
      c)
        CONFIG_LINE="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_host_forests\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$HOST_NAME" || -z "$ML_USER" || -z "$CONFIG_LINE" ]]
  then
    echo "Invalid \`marklogic_host_forests\` function usage" >&2
    return 1
  fi

  # Fetch, check the status and return the body of one Manage API GET
  _marklogic_manage_get() {
    local WHAT=$1 URL_PATH=$2 GOT
    GOT="$(marklogic_tunnel_request -X GET -u "$URL_PATH" -K <(printf '%s\n' "$CONFIG_LINE"))"
    if [ "${GOT##*$'\n'}" != "200" ]
    then
      err "Manage API returned HTTP ${GOT##*$'\n'} for $WHAT"
      return 1
    fi
    printf '%s\n' "${GOT%$'\n'*}"
  }

  _marklogic_forest_state() {
    echo "$1" | jq -r '(.["forest-status"]["status-properties"].state // "")
      | if type == "object" then (.value // "") else . end | tostring'
  }

  # Each failure returns explicitly: callers test this function's result,
  # which switches errexit off inside it
  BODY="$(_marklogic_manage_get "the forests on host '$HOST_NAME' (user '$ML_USER')" \
    "/manage/v2/forests?host-id=$(jq -rn --arg h "$HOST_NAME" '$h | @uri')&format=json")" || return 1

  while IFS='' read -r FOREST
  do
    [ -n "$FOREST" ] && FORESTS+=("$FOREST")
  done < <(echo "$BODY" | jq -r '.["forest-default-list"]["list-items"]["list-item"][]?.nameref')

  for FOREST in "${FORESTS[@]}"
  do
    FOREST_PATH="$(jq -rn --arg f "$FOREST" '$f | @uri')"
    FOREST_STATUS="$(_marklogic_manage_get "the status of forest '$FOREST'" "/manage/v2/forests/$FOREST_PATH?view=status&format=json")" || return 1

    REPLICA_STATES="[]"
    while IFS='' read -r REPLICA_ID
    do
      [ -n "$REPLICA_ID" ] || continue
      RESPONSE="$(_marklogic_manage_get "the status of replica forest '$REPLICA_ID' of '$FOREST'" "/manage/v2/forests/$REPLICA_ID?view=status&format=json")" || return 1
      REPLICA_STATES="$(jq -c --arg id "$REPLICA_ID" --arg state "$(_marklogic_forest_state "$RESPONSE")" \
        '. + [{id: $id, state: $state}]' <<< "$REPLICA_STATES")"
    done < <(echo "$FOREST_STATUS" | jq -r \
      '[.. | objects | .["replica-forests"]? // empty | .. | scalars | tostring | select(test("^[0-9]+$"))] | unique | .[]')

    FOREST_STATE="$(_marklogic_forest_state "$FOREST_STATUS")"
    jq -nc --arg name "$FOREST" --arg state "$FOREST_STATE" --argjson replicas "$REPLICA_STATES" \
      '{name: $name, state: $state, replicas: $replicas}'
  done
}
