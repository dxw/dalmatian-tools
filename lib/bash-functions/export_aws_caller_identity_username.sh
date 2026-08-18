#!/usr/bin/env bash
set -e
set -o pipefail

# Export the username portion of the current AWS caller identity ARN.
#
# Handles both an IAM user ARN
# (arn:aws:iam::<account>:user/dalmatian_admins/<username>) and an assumed role
# ARN (arn:aws:sts::<account>:assumed-role/<role>/<username>).
#
# @usage export_aws_caller_identity_username
# @export $AWS_CALLER_IDENTITY_USERNAME
function export_aws_caller_identity_username {
  local caller_identity_arn

  # `--query`/`--output text` rather than `jq`, so the parsing does not break if
  # the configured or inherited AWS CLI output format is not JSON
  caller_identity_arn="$(aws sts get-caller-identity --query Arn --output text)"
  AWS_CALLER_IDENTITY_USERNAME="${caller_identity_arn##*/}"
  export AWS_CALLER_IDENTITY_USERNAME
}
