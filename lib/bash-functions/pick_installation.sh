#!/usr/bin/env bash
set -e
set -o pipefail

# Choose a Dalmatian installation from the ones configured on this machine
#
# Candidate rows come from `installation_rows`, the same lines `installation
# list` prints, so the picker and the listing cannot drift apart
#
# A single installation is returned without prompting. With more than one,
# fzf is used when it is installed and DALMATIAN_FZF_ENABLED is not 0, falling
# back to a numbered `select` menu. Everything the user sees is written to
# stderr so that the installation name is the only thing on stdout
#
# @usage NAME="$(pick_installation)"
# @return string  the chosen installation name
function pick_installation {
  local AVAILABLE_INSTALLATIONS
  local INSTALLATION_COUNT
  local INSTALLATION_LIST
  local line
  local OPT
  local PS3

  AVAILABLE_INSTALLATIONS="$(installation_rows)"
  if [ -z "$AVAILABLE_INSTALLATIONS" ]
  then
    err "No installations to choose from"
    log_msg -l "Run \`dalmatian setup\` to create one" -q "$QUIET_MODE" >&2
    return 1
  fi

  INSTALLATION_COUNT="$(echo "$AVAILABLE_INSTALLATIONS" | wc -l | tr -d '[:space:]')"
  if [ "$INSTALLATION_COUNT" -eq 1 ]
  then
    echo "$AVAILABLE_INSTALLATIONS" | sed -E 's/^\*? *//' | cut -d' ' -f1
    return 0
  fi

  # Both pickers need a terminal. Failing here rather than blocking on a read
  # keeps non-interactive callers (scripts, CI) diagnosable
  if [ ! -t 0 ]
  then
    err "$INSTALLATION_COUNT installations found, and there is no terminal to choose one with"
    log_msg -l "Pass the installation name as an argument. Available installations:" -q "$QUIET_MODE" >&2
    echo "$AVAILABLE_INSTALLATIONS" >&2
    return 1
  fi

  log_msg -l "Choose an installation:" -q "$QUIET_MODE" >&2

  if [[ "${DALMATIAN_FZF_ENABLED:-1}" == "1" ]] && command -v fzf > /dev/null
  then
    # A cancelled fzf exits non-zero, which would otherwise abort the caller
    # before it can report that nothing was chosen
    OPT="$(echo "$AVAILABLE_INSTALLATIONS" | fzf --height 40% --reverse --header "Select an installation (esc to quit)")" || true
  else
    INSTALLATION_LIST=()
    while IFS='' read -r line
    do
      INSTALLATION_LIST+=("$line")
    done < <(echo "$AVAILABLE_INSTALLATIONS")

    PS3="Select an installation (1-${#INSTALLATION_LIST[@]}): "
    select OPT in "${INSTALLATION_LIST[@]}"
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
    err "No installation selected"
    return 1
  fi

  echo "$OPT" | sed -E 's/^\*? *//' | cut -d' ' -f1
}
