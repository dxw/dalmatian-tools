#!/bin/bash
set -e
set -o pipefail

# Set up a handy repeatable error output function that uses `stderr`
#
# @usage err "A problem happened!"
# @param $* Any information to pass into stderr
function err {
  red='\033[0;31m'
  clear='\033[0m'

  echo -e "${red}[!] Error: ${clear}$*" >&2
}
