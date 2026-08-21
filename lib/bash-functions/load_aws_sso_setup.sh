#!/usr/bin/env bash
set -e
set -o pipefail

# Read the AWS SSO values needed to talk to IAM Identity Center out of
# setup.json, and derive the console URL from the Identity Center region.
#
# Every value is checked. `jq -r` prints the literal string "null" for a missing
# field, which would otherwise be built into an SSO profile or a URL and only
# fail much later as an opaque AWS error.
#
# @usage load_aws_sso_setup
# Sets AWS_SSO_START_URL, AWS_SSO_REGION and AWS_SSO_ADMIN_ROLE_NAME in the
# calling shell.
# @export $CONSOLE_USERS_URL
function load_aws_sso_setup {
  [[ -f "$CONFIG_SETUP_JSON_FILE" ]] ||
    die "$CONFIG_SETUP_JSON_FILE does not exist. Run \`dalmatian setup\` first."

  AWS_SSO_START_URL=$(jq -r '.aws_sso.start_url // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"
  AWS_SSO_REGION=$(jq -r '.aws_sso.region // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"
  AWS_SSO_ADMIN_ROLE_NAME=$(jq -r '.aws_sso.default_admin_role_name // empty' < "$CONFIG_SETUP_JSON_FILE" 2>/dev/null) ||
    die "could not parse $CONFIG_SETUP_JSON_FILE"

  [[ -n "$AWS_SSO_START_URL" ]] ||
    die "aws_sso.start_url is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."
  [[ -n "$AWS_SSO_REGION" ]] ||
    die "aws_sso.region is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."
  [[ -n "$AWS_SSO_ADMIN_ROLE_NAME" ]] ||
    die "aws_sso.default_admin_role_name is not set in $CONFIG_SETUP_JSON_FILE. Run \`dalmatian setup\`."

  # Exported rather than merely assigned, matching
  # export_aws_caller_identity_username.sh: this one is consumed by the calling
  # command rather than by anything in this file, and exporting says so (as well
  # as keeping shellcheck's SC2034 quiet without a suppression comment).
  CONSOLE_USERS_URL="https://$AWS_SSO_REGION.console.aws.amazon.com/singlesignon/identity/home?region=$AWS_SSO_REGION#!/users"
  export CONSOLE_USERS_URL
}
