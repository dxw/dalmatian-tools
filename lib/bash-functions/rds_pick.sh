#!/usr/bin/env bash
set -e
set -o pipefail

# Choose one line from a list, returning its first space-delimited field
#
# A single line is returned without prompting. With more than one, fzf is used
# when it is installed and DALMATIAN_FZF_ENABLED is not 0, falling back to a
# numbered `select` menu. Everything the user sees is written to stderr so that
# the chosen field is the only thing on stdout
#
# @usage DB_NAME="$(rds_pick -l "$LINES" -n database -f -r)"
# @param -l <lines>  Candidate lines, one per line; the first field is returned
# @param -n <noun>   Singular noun for the candidates, used in messages
# @param -f <flag>   CLI flag that bypasses the picker, named in the failure hint
# @return string     First field of the chosen line
function rds_pick {
  local OPTIND opt OPTARG
  local LINES_INPUT
  local LINES_GIVEN=0
  local NOUN="item"
  local FLAG
  local COUNT
  local LINE_LIST
  local line
  local OPT
  local PS3

  OPTIND=1
  while getopts "l:n:f:" opt; do
    case $opt in
      l)
        LINES_INPUT="$OPTARG"
        LINES_GIVEN=1
        ;;
      n)
        NOUN="$OPTARG"
        ;;
      f)
        FLAG="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_pick\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ "$LINES_GIVEN" -eq 0 ] || [ -z "$FLAG" ]
  then
    echo "Invalid \`rds_pick\` function usage" >&2
    return 1
  fi

  if [ -z "$LINES_INPUT" ]
  then
    err "No ${NOUN}s to choose from"
    return 1
  fi

  COUNT="$(echo "$LINES_INPUT" | wc -l | tr -d '[:space:]')"
  if [ "$COUNT" -eq 1 ]
  then
    echo "$LINES_INPUT" | cut -d' ' -f1
    return 0
  fi

  # Both pickers need a terminal. Failing here rather than blocking on a read
  # keeps non-interactive callers (scripts, CI) diagnosable
  if [ ! -t 0 ]
  then
    err "$COUNT ${NOUN}s found, and there is no terminal to choose one with"
    log_msg -l "Pass one explicitly with \`$FLAG\`. Available:" -q "$QUIET_MODE" >&2
    echo "$LINES_INPUT" >&2
    return 1
  fi

  log_msg -l "Multiple ${NOUN}s found. Please choose one:" -q "$QUIET_MODE" >&2

  if [[ "${DALMATIAN_FZF_ENABLED:-1}" == "1" ]] && command -v fzf > /dev/null
  then
    # A cancelled fzf exits non-zero, which would otherwise abort the caller
    # before it can report that nothing was chosen
    OPT="$(echo "$LINES_INPUT" | fzf --height 40% --reverse --header "Select a ${NOUN} (esc to quit)")" || true
  else
    LINE_LIST=()
    while IFS='' read -r line
    do
      LINE_LIST+=("$line")
    done < <(echo "$LINES_INPUT")

    PS3="Select a ${NOUN} (1-${#LINE_LIST[@]}): "
    select OPT in "${LINE_LIST[@]}"
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
    err "No $NOUN selected"
    return 1
  fi

  echo "$OPT" | cut -d' ' -f1
}
