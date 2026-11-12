#!/usr/bin/env bash
set -e
set -o pipefail

# End the open tunnel, if any
#
# The session is a chain of processes (bin/dalmatian, run-command, aws, the
# session-manager-plugin), so the whole tree is ended, not just the first
function marklogic_tunnel_close {
  if [ -n "${MARKLOGIC_TUNNEL_PID:-}" ]
  then
    kill_process_tree "$MARKLOGIC_TUNNEL_PID"
    wait "$MARKLOGIC_TUNNEL_PID" 2> /dev/null || true
  fi
  MARKLOGIC_TUNNEL_PID=""
  # shellcheck disable=SC2034 # read by marklogic_tunnel_request
  MARKLOGIC_TUNNEL_PORT=""
}
