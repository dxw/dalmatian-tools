#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to print the current version of an SSM
# parameter, without decrypting it. Prints nothing and succeeds when the
# parameter does not exist; any other failure is passed through with its
# message and status, so that an expired session or AccessDenied is not
# mistaken for a missing parameter.
#
# @param -p <aws_sso_profile>  AWS SSO profile
# @param -n <parameter_name>   SSM parameter name
function ssm_parameter_version {
  local OPTIND opt OPTARG PROFILE PARAMETER_NAME ERROR_FILE STATUS VERSION
  OPTIND=1
  while getopts "p:n:" opt; do
    case $opt in
      p)
        PROFILE="$OPTARG"
        ;;
      n)
        PARAMETER_NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`ssm_parameter_version\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$PROFILE" || -z "$PARAMETER_NAME" ]]
  then
    echo "Invalid \`ssm_parameter_version\` function usage" >&2
    exit 1
  fi

  ERROR_FILE="$(mktemp)"
  STATUS=0
  VERSION="$("$APP_ROOT/bin/dalmatian" aws run-command \
    -p "$PROFILE" \
    ssm get-parameter \
    --name "$PARAMETER_NAME" \
    --query Parameter.Version \
    --output text \
    2>"$ERROR_FILE")" || STATUS=$?

  if [ "$STATUS" -eq 0 ]
  then
    rm -f "$ERROR_FILE"
    echo "$VERSION"
    return 0
  fi
  if grep -q "ParameterNotFound" "$ERROR_FILE"
  then
    rm -f "$ERROR_FILE"
    return 0
  fi
  cat "$ERROR_FILE" >&2
  rm -f "$ERROR_FILE"
  return "$STATUS"
}
