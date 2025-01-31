#!/bin/bash
set -e
set -o pipefail

function install_session_manager {
  BASE_URI="https://s3.amazonaws.com/session-manager-downloads/plugin/latest"

  ARCH="mac"
  if [[ $(uname -m) == 'arm64' ]]; then
    ARCH+="_$(uname -m)"
  fi

  SESSION_MANAGER_ZIP="$BASE_URI/$ARCH/sessionmanager-bundle.zip"
  SESSION_MANAGER_INSTALL_DIR="$HOME/Applications/session-manager-plugin"

  log_info -l "Installing AWS Session Manager Plugin into $SESSION_MANAGER_INSTALL_DIR" -q "$QUIET_MODE"

  # Grab the installer...
  mkdir -p "$SESSION_MANAGER_INSTALL_DIR"
  curl -fsSL "$SESSION_MANAGER_ZIP" -o "$HOME/Downloads/session-manager-plugin.zip"
  unzip -o "$HOME/Downloads/session-manager-plugin.zip" -d "$SESSION_MANAGER_INSTALL_DIR"

  # Run the installer...
  "$SESSION_MANAGER_INSTALL_DIR/sessionmanager-bundle/install" --install-dir "$SESSION_MANAGER_INSTALL_DIR" -b "$HOME/.bin/session-manager-plugin"

  # Try it for a nice confirmation message
  if ! is_installed "session-manager-plugin";
  then
    echo "Add 'session-manager-plugin' to your \$PATH by running:"
    echo
    echo "    export PATH=\"\$PATH:\$HOME/.bin/\""
    exit 1
  else
    session-manager-plugin
  fi

  # Cleanup..
  rm "$HOME/Downloads/session-manager-plugin.zip"
  rm -rf "$SESSION_MANAGER_INSTALL_DIR/sessionmanager-bundle"
}
