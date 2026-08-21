#!/usr/bin/env bash
set -e
set -o pipefail

# Set IDENTITY_CENTER_PROFILE to a profile that can administer IAM Identity
# Center, and verify it actually authenticates.
#
# The Identity Center instance lives in the organisation's management account,
# which is not a Dalmatian-managed Terraform workspace and therefore gets no
# profile from `dalmatian aws generate-config`. When no usable profile exists,
# this discovers the management account and writes one.
#
# Reads PROFILE_OVERRIDE (from a command's -p flag, may be unset or empty) and
# IDENTITY_CENTER_PROFILE_NAME. Sets IDENTITY_CENTER_PROFILE, and via
# load_aws_sso_setup also AWS_SSO_START_URL, AWS_SSO_REGION,
# AWS_SSO_ADMIN_ROLE_NAME and CONSOLE_USERS_URL.
#
# @usage resolve_identity_center_profile
function resolve_identity_center_profile {
  load_aws_sso_setup

  if [[ -n "${PROFILE_OVERRIDE:-}" ]]
  then
    aws_profile_exists "$PROFILE_OVERRIDE" ||
      die "profile '$PROFILE_OVERRIDE' is not in $AWS_CONFIG_FILE.
       Try running \`dalmatian aws generate-config\` first."
    IDENTITY_CENTER_PROFILE=$PROFILE_OVERRIDE
  elif aws_profile_exists "$IDENTITY_CENTER_PROFILE_NAME"
  then
    IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
  else
    # A member account is permitted to call describe-organization, so this works
    # from dalmatian-main. stderr is folded into the variable so a failure can be
    # reported verbatim; the 12-digit check below is what catches a corrupted
    # value, an empty response, or the literal "None" that --output text prints
    # for a missing field.
    local management_account_id
    management_account_id=$(aws --profile dalmatian-main organizations describe-organization \
      --query 'Organization.MasterAccountId' --output text 2>&1) ||
      die "could not look up the organisation's management account: $management_account_id"
    [[ "$management_account_id" =~ ^[0-9]{12}$ ]] ||
      die "organizations describe-organization did not return a 12-digit management account ID (got '$management_account_id')"

    esc_info "$(printf "Adding the '%s' profile for management account %s" \
      "$IDENTITY_CENTER_PROFILE_NAME" "$management_account_id")"

    # The profile's region is the Identity Center region, not the project's
    # default region: sso-admin and identitystore calls have to be made in the
    # region the instance lives in. They are often the same value, which is
    # exactly why this is worth stating.
    #
    # append_sso_config_file appends blind with no existence check of its own, so
    # the aws_profile_exists call above is the whole of the idempotency. Note
    # that `dalmatian aws generate-config` rewrites this file wholesale and will
    # drop this profile; that costs nothing, because the next run re-adds it.
    append_sso_config_file \
      "$CONFIG_AWS_SSO_FILE" \
      "$IDENTITY_CENTER_PROFILE_NAME" \
      "$AWS_SSO_START_URL" \
      "$AWS_SSO_REGION" \
      "$management_account_id" \
      "$AWS_SSO_ADMIN_ROLE_NAME" \
      "$AWS_SSO_REGION"

    IDENTITY_CENTER_PROFILE=$IDENTITY_CENTER_PROFILE_NAME
  fi

  # Fail fast and usefully. Keep the underlying error rather than discarding it:
  # a profile that does not exist fails here too, and `aws sso login` cannot fix
  # that, so advice which assumes expiry would send the operator down a dead end.
  local auth_err
  if ! auth_err=$(aws --profile "$IDENTITY_CENTER_PROFILE" sts get-caller-identity 2>&1 >/dev/null)
  then
    die "cannot authenticate with profile '$IDENTITY_CENTER_PROFILE': ${auth_err:-unknown error}
       This usually means one of two things. Either the SSO session has expired,
       in which case run: dalmatian aws login
       Or you have no '$AWS_SSO_ADMIN_ROLE_NAME' permission set assigned on the
       organisation's management account, which no amount of logging in will fix."
  fi
}
