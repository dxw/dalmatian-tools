#!/usr/bin/env bash
set -e
set -o pipefail

# Record a Dalmatian installation as the default in installations.json.
#
# @usage set_installation_default "example-project"
# @param $1 The installation name
function set_installation_default {
  local name=$1

  if ! installation_name_valid "$name"
  then
    die "'$name' is not a valid installation name: use lower-case letters, digits, '-' and '_', starting with a letter or digit"
  fi

  mkdir -p "$(dirname "$CONFIG_INSTALLATIONS_JSON_FILE")"
  jq -n --arg name "$name" '{default: $name}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
}
