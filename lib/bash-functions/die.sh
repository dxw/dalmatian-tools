#!/usr/bin/env bash
set -e
set -o pipefail

# Report a fatal error and exit.
#
# `err` prints in red to stderr but does not exit, so commands that want to
# abort need this wrapper rather than a bare `err` call.
#
# @usage die "could not find the thing"
# @param $1 The error message
function die {
  err "$1"
  exit 1
}
