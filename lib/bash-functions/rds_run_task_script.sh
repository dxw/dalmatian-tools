#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to run a bash script in the utilities task
# for an RDS. The script is passed as base64 so that none of its quoting has
# to survive `utilities run-command` and the container's `bash -c`. It is run
# with `bash -c` rather than piped into bash, so a command in it that reads
# stdin cannot consume the rest of the script.
#
# The script lands in process arguments and the ECS RunTask request, so it
# must never contain a password.
#
# @param -i <infrastructure>   Infrastructure name
# @param -e <environment>      Environment name
# @param -r <rds_name>         RDS name
# @param -s <script>           Script to run
# @param -R <result_file>      Optional file for `utilities run-command` to write the task output to
function rds_run_task_script {
  local OPTIND opt OPTARG INFRASTRUCTURE ENVIRONMENT RDS_NAME TASK_SCRIPT RESULT_FILE TASK_SCRIPT_BASE64
  local -a RESULT_ARGS=()
  OPTIND=1
  while getopts "i:e:r:s:R:" opt; do
    case $opt in
      i)
        INFRASTRUCTURE="$OPTARG"
        ;;
      e)
        ENVIRONMENT="$OPTARG"
        ;;
      r)
        RDS_NAME="$OPTARG"
        ;;
      s)
        TASK_SCRIPT="$OPTARG"
        ;;
      R)
        RESULT_FILE="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_run_task_script\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$INFRASTRUCTURE" || -z "$ENVIRONMENT" || -z "$RDS_NAME" || -z "$TASK_SCRIPT" ]]
  then
    echo "Invalid \`rds_run_task_script\` function usage" >&2
    exit 1
  fi
  if [ -n "$RESULT_FILE" ]
  then
    RESULT_ARGS=(-R "$RESULT_FILE")
  fi

  TASK_SCRIPT_BASE64="$(printf '%s\n' "$TASK_SCRIPT" | base64 | tr -d '\n')"

  "$APP_ROOT/bin/dalmatian" utilities run-command \
    -i "$INFRASTRUCTURE" \
    -e "$ENVIRONMENT" \
    -r "$RDS_NAME" \
    -c "bash -c \"\$(echo $TASK_SCRIPT_BASE64 | base64 -d)\"" \
    "${RESULT_ARGS[@]}"
}
