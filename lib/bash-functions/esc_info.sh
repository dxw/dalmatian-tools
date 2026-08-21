#!/usr/bin/env bash
set -e
set -o pipefail

# Output a `==>` progress message, escaped so `echo -e` cannot reinterpret it.
# See esc_msg.sh for why the escaping and the -q are both necessary.
#
# @usage esc_info "Creating user someone@example.com"
# @param $1 The line to output
function esc_info {
  log_info -l "${1//\\/\\\\}" -q "$QUIET_MODE"
}
