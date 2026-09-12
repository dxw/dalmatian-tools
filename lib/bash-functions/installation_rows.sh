#!/usr/bin/env bash
set -e
set -o pipefail

# Print one line per Dalmatian installation on this machine
#
# Shared by `installation list` and `pick_installation` so that what a user
# sees when listing installations is exactly what they choose from, and the
# two cannot drift apart
#
# Prints nothing, and always returns 0, when the installations directory is
# missing or empty
#
# @usage installation_rows
# @return string  "<marker> <name>                     <project>" per installation,
#                  `*` marking the default
function installation_rows {
  local default name project marker

  if [ ! -d "$CONFIG_INSTALLATIONS_DIR" ] || [ -z "$(ls -A "$CONFIG_INSTALLATIONS_DIR")" ]
  then
    return 0
  fi

  default="$(installation_default)"

  while IFS='' read -r name
  do
    if [ -f "$CONFIG_INSTALLATIONS_DIR/$name/setup.json" ]
    then
      project="$(
        jq -r 'select((.project_name | type) == "string") | .project_name' \
          < "$CONFIG_INSTALLATIONS_DIR/$name/setup.json" 2>/dev/null || true
      )"
    else
      project="(no setup.json)"
    fi

    marker=" "
    if [ "$name" == "$default" ]
    then
      marker="*"
    fi

    printf '%s %-24s %s\n' "$marker" "$name" "$project"
  done < <(find "$CONFIG_INSTALLATIONS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

  return 0
}
