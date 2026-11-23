#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v1 specific function to read the engine_version of an RDS instance
# or Aurora cluster from the compiled dalmatian.yml. Prints nothing and
# succeeds when the file, infrastructure or entry is missing.
#
# @param -f <file>   Path to dalmatian.yml
# @param -i <infra>  Infrastructure name
# @param -b <block>  Config block: rds or aurora
# @param -r <name>   Entry identifier within the block
function rds_v1_config_engine_version {
  local OPTIND opt OPTARG FILE INFRA BLOCK NAME
  OPTIND=1
  FILE=""
  INFRA=""
  BLOCK=""
  NAME=""
  while getopts "f:i:b:r:" opt; do
    case $opt in
      f)
        FILE="$OPTARG"
        ;;
      i)
        INFRA="$OPTARG"
        ;;
      b)
        BLOCK="$OPTARG"
        ;;
      r)
        NAME="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_v1_config_engine_version\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$FILE" || -z "$INFRA" || -z "$NAME" ]] || [[ "$BLOCK" != "rds" && "$BLOCK" != "aurora" ]]
  then
    echo "Invalid \`rds_v1_config_engine_version\` function usage" >&2
    exit 1
  fi

  [[ -f "$FILE" ]] || return 0

  # BLOCK is restricted to rds|aurora above, so it is safe to splice into the
  # expression; INFRA and NAME must only travel via the environment. Dashes
  # are ignored on both sides because AWS identifiers drop them, so a name
  # recovered from an identifier has none while the config entry may.
  INFRA="$INFRA" NAME="$NAME" yq e ".infrastructures[strenv(INFRA)].${BLOCK}[]? | select((.identifier | sub(\"-\"; \"\")) == (strenv(NAME) | sub(\"-\"; \"\"))) | .engine_version // \"\"" "$FILE"
}
