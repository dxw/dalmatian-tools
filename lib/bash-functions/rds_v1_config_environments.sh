#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v1 specific function to list the environment names of an
# infrastructure in the compiled dalmatian.yml, sorted, one per line. Prints
# nothing and succeeds when the file or infrastructure is missing.
#
# @param -f <file>   Path to dalmatian.yml
# @param -i <infra>  Infrastructure name
function rds_v1_config_environments {
  local OPTIND opt OPTARG FILE INFRA
  OPTIND=1
  FILE=""
  INFRA=""
  while getopts "f:i:" opt; do
    case $opt in
      f)
        FILE="$OPTARG"
        ;;
      i)
        INFRA="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_v1_config_environments\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$FILE" || -z "$INFRA" ]]
  then
    echo "Invalid \`rds_v1_config_environments\` function usage" >&2
    exit 1
  fi

  [[ -f "$FILE" ]] || return 0

  INFRA="$INFRA" yq e '.infrastructures[strenv(INFRA)].environments // {} | keys | .[]' "$FILE" | sort
}
