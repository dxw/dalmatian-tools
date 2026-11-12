#!/usr/bin/env bash
set -e
set -o pipefail

# Pause for a fraction of a second without `sleep`
#
# Reading with a timeout from a pipe that never delivers is a pause the
# test suite's sleep shim cannot shorten, which matters because this pause
# is what lets a failing session be seen as failed rather than probed. The
# holder is named in full for the same reason; it ends on its own
#
# @usage marklogic_tunnel_settle 0.3
# @param $1 Seconds, fractions allowed
function marklogic_tunnel_settle {
  read -r -t "$1" _ < <(exec /bin/sleep 5) || true
}
