#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to compare the engine version in Dalmatian
# config with an upgrade target. Prints `ok` when the config version equals the
# target or is a prefix of it (the target starts with `<config>.`), `unknown`
# when no config version is given, and `update` otherwise.
#
# @param -c <config_version>  Engine version in config (may be empty)
# @param -t <target_version>  Upgrade target EngineVersion
function rds_config_version_status {
  local OPTIND opt OPTARG CONFIG_VERSION TARGET_VERSION
  OPTIND=1
  CONFIG_VERSION=""
  TARGET_VERSION=""
  while getopts "c:t:" opt; do
    case $opt in
      c)
        CONFIG_VERSION="$OPTARG"
        ;;
      t)
        TARGET_VERSION="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_config_version_status\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$TARGET_VERSION" ]]
  then
    echo "Invalid \`rds_config_version_status\` function usage" >&2
    exit 1
  fi

  if [[ -z "$CONFIG_VERSION" ]]
  then
    echo "unknown"
  elif [[ "$CONFIG_VERSION" == "$TARGET_VERSION" || "$TARGET_VERSION" == "$CONFIG_VERSION."* ]]
  then
    echo "ok"
  else
    echo "update"
  fi
}
