#!/bin/bash
set -e
set -o pipefail

# Check to see if a binary is installed on the system
#
# @usage  is_installed "oathtool"
# @param  $1 binary name
# @export $IS_INSTALLED boolean Whether the binary was found
function is_installed {
  if ! which -s "$1" || ! type -p "$1" > /dev/null; then
    err "$1 was not detected in your \$PATH"
    return 1 # false
  fi

  return 0 # true
}
