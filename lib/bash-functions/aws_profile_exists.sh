#!/usr/bin/env bash
set -e
set -o pipefail

# Return 0 if the named profile is in the AWS config dalmatian is pointed at.
#
# `aws configure list-profiles` reads whatever AWS_CONFIG_FILE points at, which
# bin/dalmatian has already overridden to the Dalmatian SSO config, so this
# checks the right file without naming it. The match is exact, not a grep of the
# file, so a profile name that is a substring of another cannot satisfy it.
#
# The output is captured rather than read from a process substitution: a failure
# inside `< <(...)` is invisible, which would make an unreadable or unparseable
# config indistinguishable from "no such profile". That matters in both
# directions — a caller would append a duplicate profile, or would insist a
# profile is missing that the operator can plainly see in the file.
#
# @usage if aws_profile_exists "dalmatian-main"; then ...; fi
# @param $1 The profile name to look for
function aws_profile_exists {
  local wanted=$1 profile profiles

  profiles=$(aws configure list-profiles) ||
    die "could not read AWS profiles from $AWS_CONFIG_FILE"

  while IFS='' read -r profile
  do
    if [[ "$profile" == "$wanted" ]]
    then
      return 0
    fi
  done <<<"$profiles"
  return 1
}
