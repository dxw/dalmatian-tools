#!/usr/bin/env bash
set -e
set -o pipefail

# Say which installation a command targets when DALMATIAN_INSTALLATION has
# overridden the recorded default.
#
# After resolve_installation, DALMATIAN_INSTALLATION equals the default
# whenever the default was the source, so a difference means the environment
# variable is in effect. That is the case worth announcing: a deploy against
# the wrong installation lands in the wrong AWS account. Recursive
# bin/dalmatian children are kept quiet by the exported DALMATIAN_INSTALLATION_ANNOUNCED
# marker, so only the user's own command prints.
#
# @usage announce_installation_override
function announce_installation_override {
  local default

  # Recursive bin/dalmatian children inherit this and stay silent
  if [[ "${DALMATIAN_INSTALLATION_ANNOUNCED:-0}" == "1" ]]
  then
    return 0
  fi

  if [[ -z "${DALMATIAN_INSTALLATION:-}" ]]
  then
    return 0
  fi

  default="$(installation_default)"

  if [[ "$DALMATIAN_INSTALLATION" == "$default" ]]
  then
    return 0
  fi

  if [[ -n "$default" ]]
  then
    log_info -l "Using Dalmatian installation '$DALMATIAN_INSTALLATION' (DALMATIAN_INSTALLATION overrides the default '$default')" -q "${QUIET_MODE:-0}"
  else
    log_info -l "Using Dalmatian installation '$DALMATIAN_INSTALLATION' (set by DALMATIAN_INSTALLATION; no default is recorded)" -q "${QUIET_MODE:-0}"
  fi

  export DALMATIAN_INSTALLATION_ANNOUNCED=1

  return 0
}
