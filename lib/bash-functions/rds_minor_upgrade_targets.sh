#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to list the minor engine versions an RDS
# instance can be upgraded to in place, from `aws rds describe-db-engine-versions`
# output. Major version targets are dropped. Prints one EngineVersion per line,
# in ascending version order, and nothing when there are none.
#
# @param -j <json>  Output of `aws rds describe-db-engine-versions`
function rds_minor_upgrade_targets {
  local OPTIND opt OPTARG JSON
  OPTIND=1
  while getopts "j:" opt; do
    case $opt in
      j)
        JSON="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_minor_upgrade_targets\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$JSON" ]]
  then
    echo "Invalid \`rds_minor_upgrade_targets\` function usage" >&2
    exit 1
  fi

  jq -r '.DBEngineVersions[]?.ValidUpgradeTarget[]? | select(.IsMajorVersionUpgrade == false) | .EngineVersion' <<< "$JSON" | sort -V
}
