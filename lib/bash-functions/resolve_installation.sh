#!/usr/bin/env bash
# shellcheck disable=SC2153
set -e
set -o pipefail

# Work out which Dalmatian installation this invocation runs against.
#
# Precedence is the DALMATIAN_INSTALLATION environment variable, then the
# default recorded in installations.json. Exports DALMATIAN_INSTALLATION so
# the recursive bin/dalmatian calls the dispatcher makes (the update check,
# the login) agree with their parent, and CONFIG_INSTALLATION_DIR, from which
# bin/dalmatian derives every per-installation CONFIG_* path. Both are empty
# when nothing is configured; the v2 block of bin/dalmatian decides whether
# that is an error, because v1 must still fall through to its IAM-user path.
#
# `version` is invoked recursively on every run to read the active command
# tree and reads nothing per-installation, so it skips resolution and the
# legacy migration; otherwise its `-q` invocation would swallow the
# migration message before the user's real command ran.
#
# @usage resolve_installation "$SUBCOMMAND"
# @param $1 The subcommand being dispatched
function resolve_installation {
  local subcommand=$1 name source

  export DALMATIAN_INSTALLATION="${DALMATIAN_INSTALLATION:-}"
  export CONFIG_INSTALLATION_DIR=""

  if [[ "$subcommand" == "version" ]]
  then
    return 0
  fi

  migrate_legacy_installation

  if [[ -n "$DALMATIAN_INSTALLATION" ]]
  then
    name="$DALMATIAN_INSTALLATION"
    source="the DALMATIAN_INSTALLATION environment variable"
  else
    name="$(installation_default)"
    source="the default in $CONFIG_INSTALLATIONS_JSON_FILE"
  fi

  if [[ -z "$name" ]]
  then
    return 0
  fi

  if ! installation_name_valid "$name"
  then
    die "'$name' is not a valid installation name (from $source): use lower-case letters, digits, '-' and '_', starting with a letter or digit"
  fi

  export DALMATIAN_INSTALLATION="$name"
  export CONFIG_INSTALLATION_DIR="$CONFIG_INSTALLATIONS_DIR/$name"

  # These must run before any installation exists
  case "$subcommand" in
    setup|installation|update)
      return 0
      ;;
  esac

  if [[ ! -d "$CONFIG_INSTALLATION_DIR" ]]
  then
    err "Dalmatian installation '$name' does not exist (selected by $source)"
    err "Run \`dalmatian installation list\` to see the installations on this machine"
    exit 1
  fi
}
