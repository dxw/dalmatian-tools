#!/usr/bin/env bash
set -e
set -o pipefail

# Send one request through the open tunnel
#
# The body is printed followed by the HTTP status code on its own last line,
# so callers can split the two. Credentials come from a curl config file
# (`user = "name:password"`) rather than the command line, which is what
# keeps them out of process listings.
#
# @usage marklogic_tunnel_request -X GET -u "/manage/v2/hosts?format=json" -K "$CURL_CONFIG" [-- <extra curl args>]
# @param -X <method>       HTTP method
# @param -u <path>         Path and query on the host
# @param -K <curl_config>  curl config file holding the credentials
# @return string           Response body, then the status code
function marklogic_tunnel_request {
  local METHOD=""
  local URL_PATH=""
  local CURL_CONFIG=""

  OPTIND=1
  while getopts "X:u:K:" opt; do
    case $opt in
      X)
        METHOD="$OPTARG"
        ;;
      u)
        URL_PATH="$OPTARG"
        ;;
      K)
        CURL_CONFIG="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_tunnel_request\` function usage" >&2
        return 1
        ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  if [[ -z "$METHOD" || -z "$URL_PATH" || -z "$CURL_CONFIG" ]]
  then
    echo "Invalid \`marklogic_tunnel_request\` function usage" >&2
    return 1
  fi

  if [ -z "${MARKLOGIC_TUNNEL_PID:-}" ]
  then
    err "No MarkLogic tunnel is open"
    return 1
  fi

  # Method and URL first: they are what tells one request from another
  curl \
    --request "$METHOD" \
    --url "http://localhost:$MARKLOGIC_TUNNEL_PORT$URL_PATH" \
    --silent \
    --show-error \
    --anyauth \
    --write-out $'\n%{http_code}' \
    --config "$CURL_CONFIG" \
    "$@"
}
