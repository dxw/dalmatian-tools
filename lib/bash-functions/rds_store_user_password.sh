#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to get a password for an RDS user, either
# generated or read (see rds_password), and store it in SSM Parameter Store
# with `dalmatian aws put-secret`. The password goes in on stdin and is never
# printed.
#
# @param -i <infrastructure>  Infrastructure name
# @param -e <environment>     Environment name
# @param -u <user_name>       User name, for the log messages
# @param -n <secret_name>     Name for put-secret (rds/<rds_name>/<user_name>/password)
# @param -p                   Read the password instead of generating one
function rds_store_user_password {
  local OPTIND opt OPTARG INFRASTRUCTURE ENVIRONMENT USER_NAME SECRET_NAME READ_PASSWORD USER_PASSWORD
  READ_PASSWORD=0
  OPTIND=1
  while getopts "i:e:u:n:p" opt; do
    case $opt in
      i)
        INFRASTRUCTURE="$OPTARG"
        ;;
      e)
        ENVIRONMENT="$OPTARG"
        ;;
      u)
        USER_NAME="$OPTARG"
        ;;
      n)
        SECRET_NAME="$OPTARG"
        ;;
      p)
        READ_PASSWORD=1
        ;;
      *)
        echo "Invalid \`rds_store_user_password\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$INFRASTRUCTURE" || -z "$ENVIRONMENT" || -z "$USER_NAME" || -z "$SECRET_NAME" ]]
  then
    echo "Invalid \`rds_store_user_password\` function usage" >&2
    exit 1
  fi

  if [ "$READ_PASSWORD" -eq 1 ]
  then
    USER_PASSWORD="$(rds_password -p)" || return 1
  else
    log_info -l "Generating a password for $USER_NAME ..." -q "$QUIET_MODE"
    USER_PASSWORD="$(rds_password)" || return 1
  fi
  log_info -l "Storing the password in /$INFRASTRUCTURE/$ENVIRONMENT/$SECRET_NAME ..." -q "$QUIET_MODE"
  printf '%s' "$USER_PASSWORD" | "$APP_ROOT/bin/dalmatian" aws put-secret \
    -i "$INFRASTRUCTURE" \
    -e "$ENVIRONMENT" \
    -n "$SECRET_NAME" \
    > /dev/null
}
