#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to hold the names an RDS user command was
# given to patterns that cannot break out of the task script they are
# substituted into, or out of an SSM parameter path. Database and user names
# are limited to what both engines accept as identifiers rather than escaped.
# Exits 1 with an error naming the offending value's kind.
#
# @param -i <infrastructure>  Infrastructure name
# @param -e <environment>     Environment name
# @param -r <rds_name>        RDS name
# @param -d <db_name>         Database name (optional)
# @param -u <user_name>       User name (optional)
function rds_validate_names {
  local OPTIND opt OPTARG INFRASTRUCTURE ENVIRONMENT RDS_NAME DB_NAME USER_NAME IDENTIFIER_PATTERN
  OPTIND=1
  while getopts "i:e:r:d:u:" opt; do
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
      d)
        DB_NAME="$OPTARG"
        ;;
      u)
        USER_NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_validate_names\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$INFRASTRUCTURE" || -z "$ENVIRONMENT" || -z "$RDS_NAME" ]]
  then
    echo "Invalid \`rds_validate_names\` function usage" >&2
    exit 1
  fi

  IDENTIFIER_PATTERN='^[A-Za-z_][A-Za-z0-9_]{0,62}$'
  if [[ -n "$DB_NAME" && ! "$DB_NAME" =~ $IDENTIFIER_PATTERN ]]
  then
    err "Database name must be letters, digits and underscores, not starting with a digit"
    exit 1
  fi
  if [[ -n "$USER_NAME" && ! "$USER_NAME" =~ $IDENTIFIER_PATTERN ]]
  then
    err "User name must be letters, digits and underscores, not starting with a digit"
    exit 1
  fi
  if [[ ! "$INFRASTRUCTURE/$ENVIRONMENT/$RDS_NAME" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
  then
    err "Infrastructure, environment and RDS names must be letters, digits, '.', '_' and '-'"
    exit 1
  fi
}
