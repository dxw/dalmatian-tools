#!/usr/bin/env bash
# shellcheck disable=SC2153
set -e
set -o pipefail

# Resolve the Dalmatian installation and export the per-installation
# configuration paths that every command script reads.
#
# bin/dalmatian calls this before dispatching. A command run by path rather
# than through the dispatcher -- bin/aws/v1/export-credentials is called that
# way by the Dalmatian repository's scripts, because v1 commands are
# unreachable through `dalmatian` while v2 is the active version -- calls it
# itself when CONFIG_INSTALLATION_DIR is unset, so both routes agree on the
# installation and on where its configuration lives.
#
# Machine-wide files live at CONFIG_DIR. With no installation selected the
# per-installation paths stay empty rather than resolving to files at the
# filesystem root; the commands allowed to run in that state (setup, update,
# installation, and v1's IAM-user path) treat empty as absent.
#
# @usage export_installation_config "$SUBCOMMAND"
# @param $1 The subcommand being dispatched
function export_installation_config {
  local subcommand=$1

  export CONFIG_DIR="$HOME/.config/dalmatian"
  export CONFIG_INSTALLATIONS_DIR="$CONFIG_DIR/installations"
  export CONFIG_INSTALLATIONS_JSON_FILE="$CONFIG_DIR/installations.json"

  resolve_installation "$subcommand"

  if [ -n "$CONFIG_INSTALLATION_DIR" ]
  then
    export CONFIG_SETUP_JSON_FILE="$CONFIG_INSTALLATION_DIR/setup.json"
    export CONFIG_AWS_SSO_FILE="$CONFIG_INSTALLATION_DIR/dalmatian-sso.config"
  else
    export CONFIG_SETUP_JSON_FILE=""
    export CONFIG_AWS_SSO_FILE=""
  fi
}
