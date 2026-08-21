#!/usr/bin/env bash
set -e
set -o pipefail

# Refuse to run when the plan would be invisible but the confirmation prompt
# would still appear.
#
# Commands print their plan with esc_msg, which bin/dalmatian suppresses
# whenever stdout is not a terminal, or when -q was given. `yes_no`, by
# contrast, shows its prompt whenever *stdin* is a terminal. Those two
# conditions are independent, so redirecting stdout alone produces a "Proceed?"
# prompt with no visible plan anywhere — asking the operator to authorise
# changes they cannot see.
#
# The two flags are passed rather than read as globals because ASSUME_YES and
# DRY_RUN are command-local names, while QUIET_MODE belongs to the dispatcher.
#
# @usage require_visible_plan "$ASSUME_YES" "$DRY_RUN"
# @param $1 1 if -y was given (the operator has declined the prompt, so exempt)
# @param $2 1 if -n was given (a dry run changes nothing, so exempt)
function require_visible_plan {
  local assume_yes=${1:-0} dry_run=${2:-0}

  if ((QUIET_MODE && !assume_yes && !dry_run))
  then
    die "refusing to ask for confirmation when the plan cannot be shown.
       The plan is suppressed because output is not a terminal, or because -q
       was given, so you would be approving changes you cannot see. Re-run on a
       terminal, or pass -y to skip the confirmation, or -n for a dry run."
  fi
}
