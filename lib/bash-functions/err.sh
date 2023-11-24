#!/bin/bash
set -e
set -o pipefail

# Set up a handy repeatable error output function that uses `stderr`
#
# @usage err "A problem happened!"
# @param $* Any information to pass into stderr
function err {
  echo "[!] Error: $*" >&2
}

# Set up a handy log output function
#
# @usage log_info -l 'Something happened :)'"
# @param -l <log>  Any information to output
# @param -q <0/1>  Quiet mode
function log_info {
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
        echo "Invalid \`log_info\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [ "$QUIET_MODE" == "0" ]
  then
    echo "==> $LOG"
  fi
}
