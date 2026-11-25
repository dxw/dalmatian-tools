#!/usr/bin/env bash
set -e
set -o pipefail

# Start an AWS SSM session on an ECS instance, trying other running instances
# if starting the session fails (unless an explicit instance ID was given).
#
# @usage rds_ssm_start_session -i <infrastructure> -e <environment> -d <document> -p <parameters> [-v <vpc_id>] [-I <instance_id>] [-m <message>] [-x]
# @param -i <infrastructure>  Infrastructure name (e.g. my-infrastructure)
# @param -e <environment>     Environment name (e.g. staging/prod)
# @param -d <document>        SSM document name
# @param -p <parameters>      SSM session parameters
# @param -v <vpc_id>          Optional VPC ID filter when discovering ECS instances
# @param -I <instance_id>     Optional explicit ECS instance ID (disables fallback)
# @param -m <message>         Optional log_info message before starting each attempt
# @param -x                   Trace the `aws ssm start-session` command (xtrace)
function rds_ssm_start_session {
  local INFRASTRUCTURE_NAME=""
  local ENVIRONMENT=""
  local VPC_ID=""
  local EXPLICIT_INSTANCE_ID=""
  local DOCUMENT_NAME=""
  local PARAMETERS=""
  local MESSAGE=""
  local TRACE=0
  local ECS_INSTANCE_IDS
  local CANDIDATE_INSTANCES=()
  local candidate
  local instance_id
  local index=0
  local total
  local errexit_was=0
  local SESSION_EXIT=0

  OPTIND=1
  while getopts "i:e:v:I:d:p:m:x" opt; do
    case $opt in
      i)
        INFRASTRUCTURE_NAME="$OPTARG"
        ;;
      e)
        ENVIRONMENT="$OPTARG"
        ;;
      v)
        VPC_ID="$OPTARG"
        ;;
      I)
        EXPLICIT_INSTANCE_ID="$OPTARG"
        ;;
      d)
        DOCUMENT_NAME="$OPTARG"
        ;;
      p)
        PARAMETERS="$OPTARG"
        ;;
      m)
        MESSAGE="$OPTARG"
        ;;
      x)
        TRACE=1
        ;;
      *)
        echo "Invalid \`rds_ssm_start_session\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -z "$INFRASTRUCTURE_NAME" ] || [ -z "$ENVIRONMENT" ] || [ -z "$DOCUMENT_NAME" ]
  then
    echo "Invalid \`rds_ssm_start_session\` function usage" >&2
    return 1
  fi

  if [ -n "$EXPLICIT_INSTANCE_ID" ]
  then
    CANDIDATE_INSTANCES=("$EXPLICIT_INSTANCE_ID")
  else
    if [ -n "$VPC_ID" ]
    then
      ECS_INSTANCE_IDS="$(pick_ecs_instance -i "$INFRASTRUCTURE_NAME" -e "$ENVIRONMENT" -v "$VPC_ID" -a)" || return $?
    else
      ECS_INSTANCE_IDS="$(pick_ecs_instance -i "$INFRASTRUCTURE_NAME" -e "$ENVIRONMENT" -a)" || return $?
    fi

    while IFS= read -r candidate
    do
      if [ -n "$candidate" ]
      then
        CANDIDATE_INSTANCES+=("$candidate")
      fi
    done <<< "$ECS_INSTANCE_IDS"
  fi

  total="${#CANDIDATE_INSTANCES[@]}"
  if [ "$total" -eq 0 ]
  then
    err "No running ECS instances found for $INFRASTRUCTURE_NAME-$ENVIRONMENT"
    return 1
  fi

  case "$-" in
    *e*) errexit_was=1 ;;
  esac

  for instance_id in "${CANDIDATE_INSTANCES[@]}"
  do
    index=$((index + 1))
    log_info -l "ECS instance ID: $instance_id" -q "${QUIET_MODE:-0}"
    if [ -n "$MESSAGE" ]
    then
      log_info -l "$MESSAGE" -q "${QUIET_MODE:-0}"
    fi

    set +e
    if [ "$TRACE" -eq 1 ]
    then
      (
        set -x
        aws ssm start-session \
          --target "$instance_id" \
          --document-name "$DOCUMENT_NAME" \
          --parameters "$PARAMETERS"
      )
    else
      aws ssm start-session \
        --target "$instance_id" \
        --document-name "$DOCUMENT_NAME" \
        --parameters "$PARAMETERS"
    fi
    SESSION_EXIT=$?
    if [ "$errexit_was" -eq 1 ]
    then
      set -e
    fi

    if [ "$SESSION_EXIT" -eq 0 ]
    then
      return 0
    fi

    if [ "$SESSION_EXIT" -eq 130 ]
    then
      return 130
    fi

    if [ "$index" -lt "$total" ]
    then
      warning "Failed to start SSM session on $instance_id (exit $SESSION_EXIT); trying next instance..."
    fi
  done

  if [ -n "$EXPLICIT_INSTANCE_ID" ]
  then
    err "Failed to start SSM session on $EXPLICIT_INSTANCE_ID"
  else
    err "Failed to start SSM session on any available ECS instance"
  fi
  return "$SESSION_EXIT"
}
