#!/usr/bin/env bash
set -e
set -o pipefail

# Print the default Dalmatian installation name recorded in installations.json.
#
# Prints nothing when the file is missing, unparseable, or has no string
# `default`, and always returns 0, so it is safe in an assignment under
# `set -e`: NAME="$(installation_default)".
#
# @usage NAME="$(installation_default)"
function installation_default {
  local name

  if [[ ! -r "$CONFIG_INSTALLATIONS_JSON_FILE" ]]
  then
    return 0
  fi

  name="$(
    jq -r 'select((.default | type) == "string") | .default' \
      < "$CONFIG_INSTALLATIONS_JSON_FILE" 2>/dev/null || true
  )"

  if [[ -n "$name" ]]
  then
    echo "$name"
  fi

  return 0
}
