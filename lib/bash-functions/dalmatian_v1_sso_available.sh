#!/usr/bin/env bash
set -e
set -o pipefail

# Check whether the AWS SSO configuration that Dalmatian v1 needs is usable.
#
# v1 only ever reads this configuration; `dalmatian setup` (v2) writes it.
# Returns non-zero, so only ever call this in a conditional.
#
# @usage if dalmatian_v1_sso_available; then ... fi
# @return 0 when the AWS SSO configuration is usable, 1 otherwise
function dalmatian_v1_sso_available {
  local setup_json_file aws_sso_file start_url

  setup_json_file="${CONFIG_SETUP_JSON_FILE:-$HOME/.config/dalmatian/setup.json}"
  aws_sso_file="${CONFIG_AWS_SSO_FILE:-$HOME/.config/dalmatian/dalmatian-sso.config}"

  if [[ ! -f "$setup_json_file" || ! -f "$aws_sso_file" ]]
  then
    return 1
  fi

  start_url="$(
    jq -r 'select((.aws_sso.start_url | type) == "string") | .aws_sso.start_url' \
      < "$setup_json_file" 2>/dev/null || true
  )"

  if [[ -z "$start_url" ]]
  then
    return 1
  fi

  if ! grep -q '^\[profile dalmatian-main\]' "$aws_sso_file"
  then
    return 1
  fi

  return 0
}
