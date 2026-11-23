#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to tell whether a piece of text, such as a
# pending maintenance action description, names an engine version. The
# version must not be part of a longer one, so it counts only where no digit
# or `.` sits immediately before or after it: 14.1 is not named by 14.10, nor
# 3.10.3 by 13.10.3 or 3.10.3.1. Returns 0 when named and 1 otherwise.
#
# @param -t <text>     The text to search
# @param -v <version>  The engine version to look for
function rds_text_names_version {
  local OPTIND opt OPTARG TEXT VERSION INDEX VERSION_LENGTH BEFORE AFTER
  OPTIND=1
  TEXT=""
  VERSION=""
  while getopts "t:v:" opt; do
    case $opt in
      t)
        TEXT="$OPTARG"
        ;;
      v)
        VERSION="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_text_names_version\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$VERSION" ]]
  then
    echo "Invalid \`rds_text_names_version\` function usage" >&2
    exit 1
  fi

  VERSION_LENGTH="${#VERSION}"
  for (( INDEX = 0; INDEX + VERSION_LENGTH <= ${#TEXT}; INDEX++ ))
  do
    if [[ "${TEXT:INDEX:VERSION_LENGTH}" != "$VERSION" ]]
    then
      continue
    fi
    BEFORE=""
    if (( INDEX > 0 ))
    then
      BEFORE="${TEXT:INDEX-1:1}"
    fi
    AFTER="${TEXT:INDEX+VERSION_LENGTH:1}"
    if [[ ! "$BEFORE" =~ [0-9.] && ! "$AFTER" =~ [0-9.] ]]
    then
      return 0
    fi
  done
  return 1
}
