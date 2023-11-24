#!/bin/bash
set -e
set -o pipefail

# Prompt the user with a binary question
#
# @usage yes_no "Continue with setup? (Y/n)" "Y"
# @param $1 Message to prompt the user with
# @param $2 The default value if the user does not specify
function yes_no {
  local MESSAGE
  local DEFAULT

  MESSAGE="${1-"Continue? (Y/n)"}"
  DEFAULT="${2-"Y"}"

  while true; do
    read -rep "${MESSAGE} [$DEFAULT]: " CHOICE
    CHOICE=${CHOICE:-$DEFAULT}
    echo
    case "${CHOICE:0:1}" in
      [yY] )
        return 0 # true
        ;;
      [nN] )
        return 1 # false
        ;;
      * )
        echo "Please answer Y or N"
        ;;
    esac
  done
}
