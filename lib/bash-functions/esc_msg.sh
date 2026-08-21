#!/usr/bin/env bash
set -e
set -o pipefail

# Output a plain message, escaped so `echo -e` cannot reinterpret it.
#
# `log_msg` renders with `echo -e`, which interprets backslash escapes. AWS
# Organizations permits any printable ASCII in an account name, backslash
# included, and Identity Center is similarly permissive about group and
# permission set names. An unescaped name therefore mangles the line it appears
# in, and a name containing `\c` truncates the line outright — dropping, for
# example, the account ID an operator is meant to be checking before they
# approve a change. Doubling backslashes makes `echo -e` emit them literally.
#
# This also supplies `-q "$QUIET_MODE"`, which `log_msg` assigns to as a side
# effect: omitting it silently resets quiet mode to 0 for the rest of the run.
#
# @usage esc_msg "    ADD    grant 'admin' on some-account (123456789012)"
# @param $1 The line to output
function esc_msg {
  log_msg -l "${1//\\/\\\\}" -q "$QUIET_MODE"
}
