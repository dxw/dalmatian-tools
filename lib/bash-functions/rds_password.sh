#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to print a password for an RDS user. By
# default it is 32 random alphanumerics. With -p it is read the way
# `dalmatian aws put-secret` reads a secret: a hidden prompt on a TTY,
# otherwise all of stdin. An empty password is refused.
#
# @param -p  Read the password instead of generating one
function rds_password {
  local OPTIND opt OPTARG READ_PASSWORD PASSWORD RANDOM_CHARACTERS
  READ_PASSWORD=0
  OPTIND=1
  while getopts "p" opt; do
    case $opt in
      p)
        READ_PASSWORD=1
        ;;
      *)
        echo "Invalid \`rds_password\` function usage" >&2
        exit 1
        ;;
    esac
  done

  if [ "$READ_PASSWORD" -eq 0 ]
  then
    RANDOM_CHARACTERS="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
    echo "${RANDOM_CHARACTERS:0:32}"
    return 0
  fi

  if [ -t 0 ]
  then
    echo -n "Enter password: " >&2
    read -rs PASSWORD || true
    echo >&2
  else
    PASSWORD="$(cat)"
  fi

  if [ -z "$PASSWORD" ]
  then
    err "Password cannot be empty"
    return 1
  fi
  printf '%s\n' "$PASSWORD"
}
