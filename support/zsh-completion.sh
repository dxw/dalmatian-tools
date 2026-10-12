#!/usr/bin/env bash
# Needs `bashcompinit` loaded first (see the README). zsh runs the completion
# function in sh emulation, so the bash one works unchanged; zsh sets $0 to
# this file's path when sourcing it.
# shellcheck source=support/bash-completion.sh
source "$(dirname "$0")/bash-completion.sh"
