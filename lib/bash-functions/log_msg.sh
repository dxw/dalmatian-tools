#!/bin/bash
set -e
set -o pipefail

# Set up a handy log output function for plain messages
#
# @usage log_msg -l 'Something happened :)'"
# @param -l <log>  Any information to output
# @param -q <0/1>  Quiet mode
function log_msg {
  OPTIND=1
  QUIET_MODE=0
  while getopts "l:q:" opt; do
    case $opt in
      l)
        LOG="$OPTARG"
        ;;
      q)
        QUIET_MODE="$OPTARG"
        ;;
      *)
        echo "Invalid \`log_msg\` function usage" >&2
        exit 1
        ;;
    esac
  done

  QUIET_MODE="${QUIET_MODE:-0}"

  if [ "$QUIET_MODE" == "0" ]
  then
    echo -e "$LOG"
  fi

  return 0
}
