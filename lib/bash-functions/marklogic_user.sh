#!/usr/bin/env bash
set -e
set -o pipefail

# The MarkLogic user a command authenticates as
#
# Operators have their own MarkLogic users. The stack's AdminUser is the
# emergency account, for when no operator user exists or has the
# permission, so it is never a default: it is used only with -A, and says
# so. Otherwise the user comes from -u, then MARKLOGIC_USER, then a prompt.
#
# @usage ML_USER="$(marklogic_user -u "$USER_OPTION" -a "$STACK_ADMIN_USER" [-A])"
# @param -u <user>        User given on the command line (optional)
# @param -a <stack_admin> The stack's AdminUser parameter (only read with -A)
# @param -A               Use the stack's admin user
# @return string          The user name
function marklogic_user {
  local USER_OPTION=""
  local STACK_ADMIN_USER=""
  local USE_STACK_ADMIN=""
  local TYPED_USER=""

  OPTIND=1
  while getopts "u:a:A" opt; do
    case $opt in
      u)
        USER_OPTION="$OPTARG"
        ;;
      a)
        STACK_ADMIN_USER="$OPTARG"
        ;;
      A)
        USE_STACK_ADMIN=1
        ;;
      *)
        echo "Invalid \`marklogic_user\` function usage" >&2
        return 1
        ;;
    esac
  done

  if [ -n "$USE_STACK_ADMIN" ]
  then
    if [ -n "$USER_OPTION" ]
    then
      err "-A and -u cannot be used together"
      return 1
    fi
    if [ -z "$STACK_ADMIN_USER" ]
    then
      err "-A was given but the stack has no AdminUser parameter"
      return 1
    fi
    warning "Using the stack's admin user '$STACK_ADMIN_USER'. That is the emergency account; use your own MarkLogic user where it has the permission"
    echo "$STACK_ADMIN_USER"
    return 0
  fi

  if [ -n "$USER_OPTION" ]
  then
    echo "$USER_OPTION"
    return 0
  fi

  if [ -n "${MARKLOGIC_USER:-}" ]
  then
    echo "$MARKLOGIC_USER"
    return 0
  fi

  read -r -p "MarkLogic username: " TYPED_USER || true
  if [ -z "$TYPED_USER" ]
  then
    err "No MarkLogic username given. Pass -u, set MARKLOGIC_USER, or use -A for the stack's admin user in an emergency"
    return 1
  fi
  echo "$TYPED_USER"
}
