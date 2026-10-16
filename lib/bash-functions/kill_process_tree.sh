#!/usr/bin/env bash
set -e
set -o pipefail

# Terminate a process and everything it started
#
# `kill $!` on a background command only reaches the process bash forked.
# When that process is a chain (bin/dalmatian runs run-command, which runs
# aws, which runs session-manager-plugin, none via exec) the rest is
# reparented and carries on. Walking the tree first is what ends the chain.
#
# @usage kill_process_tree "$PID"
# @param $1 The pid at the root of the tree
function kill_process_tree {
  local PID="${1:-}"
  local CHILD

  if [ -z "$PID" ]
  then
    echo "Invalid \`kill_process_tree\` function usage" >&2
    return 1
  fi

  if command -v pgrep > /dev/null
  then
    for CHILD in $(pgrep -P "$PID" 2> /dev/null || true)
    do
      kill_process_tree "$CHILD"
    done
  fi
  kill "$PID" 2> /dev/null || true
}
