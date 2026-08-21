#!/usr/bin/env bash
set -e
set -o pipefail

# Discover the single IAM Identity Center instance.
#
# Requires IDENTITY_CENTER_PROFILE to be set, so call
# resolve_identity_center_profile first. Sets INSTANCE_ARN and
# IDENTITY_STORE_ID in the calling shell.
#
# @usage identity_center_instance
function identity_center_instance {
  # Deliberately not redirecting aws's stderr into the variable: if
  # list-instances ever writes diagnostics to stderr they should reach the
  # terminal untouched, rather than get folded into $instances and corrupt the
  # JSON.
  local instances count
  instances=$(aws --profile "$IDENTITY_CENTER_PROFILE" sso-admin list-instances --output json) ||
    die "failed to list Identity Center instances"

  # jq exits non-zero on unparseable input. Without this check `set -e` kills the
  # caller on jq's own status and the operator gets a raw parse error instead of
  # a diagnosis. The numeric test also stops an empty response producing the
  # nonsense message "found " with a blank count.
  count=$(jq '.Instances | length' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"
  [[ "$count" =~ ^[0-9]+$ ]] ||
    die "could not parse the response from sso-admin list-instances"
  [[ "$count" == 1 ]] ||
    die "expected exactly 1 Identity Center instance, found $count"

  # `// empty` makes jq print nothing for a missing or null field. Without it
  # `jq -r` prints the literal string "null", this succeeds, and the failure
  # resurfaces as an opaque ValidationException much later.
  INSTANCE_ARN=$(jq -r '.Instances[0].InstanceArn // empty' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"
  IDENTITY_STORE_ID=$(jq -r '.Instances[0].IdentityStoreId // empty' <<<"$instances" 2>/dev/null) ||
    die "could not parse the response from sso-admin list-instances"

  [[ -n "$INSTANCE_ARN" && -n "$IDENTITY_STORE_ID" ]] ||
    die "sso-admin list-instances returned an instance with no ARN or identity store ID"
}
