#!/usr/bin/env bash
set -e
set -o pipefail

# Choose a running EC2 instance from `ec2 describe-instances` JSON
#
# The caller passes the JSON it has already fetched rather than this querying
# again, because the filters differ per command (ECS hosts are tag filtered,
# plain shells are not) and the caller needs the same JSON afterwards to
# resolve the instance's name
#
# A single instance is returned without prompting. With more than one, fzf is
# used when it is installed and DALMATIAN_FZF_ENABLED is not 0, falling back to
# a numbered `select` menu. Everything the user sees is written to stderr so
# that the instance id is the only thing on stdout
#
# @usage INSTANCE_ID="$(pick_ec2_instance -j "$INSTANCES")"
# @param -j <json>  `ec2 describe-instances` JSON
# @return string    ID of the chosen EC2 instance
function pick_ec2_instance {
  local INSTANCES_JSON
  local AVAILABLE_INSTANCES
  local INSTANCE_COUNT
  local INSTANCE_LIST
  local line
  local OPT
  local PS3

  OPTIND=1
  while getopts "j:" opt; do
    case $opt in
      j)
        INSTANCES_JSON="$OPTARG"
        ;;
      *)
        echo "Invalid \`pick_ec2_instance\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$INSTANCES_JSON" ]
  then
    echo "Invalid \`pick_ec2_instance\` function usage" >&2
    return 1
  fi

  AVAILABLE_INSTANCES="$(ec2_instance_lines -j "$INSTANCES_JSON")"
  if [ -z "$AVAILABLE_INSTANCES" ]
  then
    err "No running instances to choose from"
    return 1
  fi

  INSTANCE_COUNT="$(echo "$AVAILABLE_INSTANCES" | wc -l | tr -d '[:space:]')"
  if [ "$INSTANCE_COUNT" -eq 1 ]
  then
    echo "$AVAILABLE_INSTANCES" | cut -d' ' -f1
    return 0
  fi

  # Both pickers need a terminal. Failing here rather than blocking on a read
  # keeps non-interactive callers (scripts, CI) diagnosable
  if [ ! -t 0 ]
  then
    err "$INSTANCE_COUNT running instances found, and there is no terminal to choose one with"
    log_msg -l "Pass an instance id explicitly with \`-I\`. Available instances:" -q "$QUIET_MODE" >&2
    echo "$AVAILABLE_INSTANCES" >&2
    return 1
  fi

  log_msg -l "Multiple instances found. Please choose one:" -q "$QUIET_MODE" >&2

  if [[ "${DALMATIAN_FZF_ENABLED:-1}" == "1" ]] && command -v fzf > /dev/null
  then
    # A cancelled fzf exits non-zero, which would otherwise abort the caller
    # before it can report that nothing was chosen
    OPT="$(echo "$AVAILABLE_INSTANCES" | fzf --height 40% --reverse --header "Select an instance (esc to quit)")" || true
  else
    INSTANCE_LIST=()
    while IFS='' read -r line
    do
      INSTANCE_LIST+=("$line")
    done < <(echo "$AVAILABLE_INSTANCES")

    PS3="Select an instance (1-${#INSTANCE_LIST[@]}): "
    select OPT in "${INSTANCE_LIST[@]}"
    do
      if [ -n "$OPT" ]
      then
        break
      fi
      echo "Invalid selection" >&2
    done
  fi

  if [ -z "$OPT" ]
  then
    err "No instance selected"
    return 1
  fi

  echo "$OPT" | cut -d' ' -f1
}
