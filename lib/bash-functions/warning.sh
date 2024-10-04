#!/bin/bash
set -e
set -o pipefail

# Set up a handy repeatable warning output function that uses `stderr`
#
# @usage warning "Something may be wrong!"
# @param $* Any information to pass into stderr
function warning {
  yellow='\033[33m'
  clear='\033[0m'

  echo -e "${yellow}[!] Warning: ${clear}$*" >&2
}
