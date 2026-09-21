#!/usr/bin/env bash
set -e
set -o pipefail

# Say which installation a command targets when DALMATIAN_INSTALLATION has
# overridden the recorded default.
#
# After resolve_installation, DALMATIAN_INSTALLATION equals the default
# whenever the default was the source, so a difference means the environment
# variable is in effect. That is the case worth announcing: a deploy against
# the wrong installation lands in the wrong AWS account. The line goes to
# stderr and is not subject to quiet mode, because it is a safeguard rather
# than progress output. Recursive bin/dalmatian children stay quiet through
# the exported DALMATIAN_INSTALLATION_ANNOUNCED marker, as before.
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
    warning "Using Dalmatian installation '$DALMATIAN_INSTALLATION' (DALMATIAN_INSTALLATION overrides the default '$default')"
  else
    warning "Using Dalmatian installation '$DALMATIAN_INSTALLATION' (set by DALMATIAN_INSTALLATION; no default is recorded)"
  fi

  export DALMATIAN_INSTALLATION_ANNOUNCED=1

  return 0
}
