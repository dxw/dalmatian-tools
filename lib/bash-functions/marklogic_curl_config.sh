#!/usr/bin/env bash
set -e
set -o pipefail

# The `user = "name:password"` line for a curl --config file
#
# Passing credentials to curl through a config file keeps them off its
# command line. Inside the quotes curl's parser treats both `"` and `\` as
# escapes, so both are escaped here or a password with a backslash would
# reach the server altered. A line break would start a second directive, so
# it is refused.
#
# @usage marklogic_curl_config -u "$ADMIN_USER" -p "$PASSWORD"
# @param -u <user>      MarkLogic user
# @param -p <password>  Its password
# @return string        One curl config line
function marklogic_curl_config {
  local USER_NAME=""
  local PASSWORD=""

  OPTIND=1
  while getopts "u:p:" opt; do
    case $opt in
      u)
        USER_NAME="$OPTARG"
        ;;
      p)
        PASSWORD="$OPTARG"
        ;;
      *)
        echo "Invalid \`marklogic_curl_config\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$USER_NAME" || -z "$PASSWORD" ]]
  then
    echo "Invalid \`marklogic_curl_config\` function usage" >&2
    return 1
  fi

  if [[ "$USER_NAME$PASSWORD" == *$'\n'* || "$USER_NAME$PASSWORD" == *$'\r'* ]]
  then
    err "The MarkLogic user and password must not contain line breaks"
    return 1
  fi

  USER_NAME="${USER_NAME//\\/\\\\}"
  USER_NAME="${USER_NAME//\"/\\\"}"
  PASSWORD="${PASSWORD//\\/\\\\}"
  PASSWORD="${PASSWORD//\"/\\\"}"

  printf 'user = "%s:%s"\n' "$USER_NAME" "$PASSWORD"
}
