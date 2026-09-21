#!/usr/bin/env bash
set -e
set -o pipefail

# Check whether a string is usable as a Dalmatian installation name.
#
# Names become directory names under ~/.config/dalmatian/installations/ and
# tmp/, so they are restricted to lower-case letters, digits, '-' and '_',
# starting with a letter or digit. Returns non-zero, so only ever call it in a
# conditional.
#
# @usage if installation_name_valid "$NAME"; then ... fi
# @param $1 The candidate name
# @return 0 when the name is valid, 1 otherwise
function installation_name_valid {
  [[ "${1-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}
