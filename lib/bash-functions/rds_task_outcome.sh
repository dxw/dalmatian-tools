#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to interpret the result file that
# `utilities run-command -R` writes for a task run by rds_run_task_script.
# Prints `exited <status>`, `never-ran` or `unknown`. A container killed by
# SIGKILL or SIGTERM (137, 143) is `unknown`, as it may have been stopped
# after the work it was running committed. A missing, empty or malformed file
# is `unknown` too.
#
# @param $1  Result file
function rds_task_outcome {
  local RESULT_FILE OUTCOME
  RESULT_FILE="$1"
  if [ -z "$RESULT_FILE" ]
  then
    echo "Invalid \`rds_task_outcome\` function usage" >&2
    exit 1
  fi
  OUTCOME="$(cat "$RESULT_FILE" 2>/dev/null)" || OUTCOME=""

  if [[ "$OUTCOME" =~ ^exited\ ([0-9]+)$ ]]
  then
    case "${BASH_REMATCH[1]}" in
      137|143)
        echo "unknown"
        ;;
      *)
        echo "$OUTCOME"
        ;;
    esac
  elif [ "$OUTCOME" == "never-ran" ]
  then
    echo "never-ran"
  else
    echo "unknown"
  fi
}
