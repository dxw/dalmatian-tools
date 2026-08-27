#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  # Output here comes entirely from log_msg/log_info, both of which are
  # no-ops when QUIET_MODE=1, so QUIET_MODE stays at its default (0) in this
  # file specifically to make that output observable.
  export QUIET_MODE=0
  stub_cli
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
}

@test "list-bucket-properties prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-12 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/s3/v2/list-bucket-properties
  assert_failure 1
  assert_stderr_contains "Usage: list-bucket-properties"
  assert_output_contains "-b <bucket_name>"
}

@test "list-bucket-properties requires an infrastructure" {
  run --separate-stderr run_command bin/s3/v2/list-bucket-properties -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: list-bucket-properties"
}

@test "list-bucket-properties requires an environment" {
  run --separate-stderr run_command bin/s3/v2/list-bucket-properties -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: list-bucket-properties"
}

@test "list-bucket-properties -h shows usage" {
  run --separate-stderr run_command bin/s3/v2/list-bucket-properties -h
  assert_failure 1
  assert_stderr_contains "Usage: list-bucket-properties"
}

@test "list-bucket-properties lists all buckets in the account when -b is omitted" {
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-list_buckets v2-s3-list-buckets.json
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_bucket_acl v2-s3-bucket-acl-owner-only.json

  run run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "s3api list-buckets"
  assert_output_contains "example-bucket-one"
  assert_output_contains "example-bucket-two"
}

@test "list-bucket-properties inspects only the named bucket when -b is given" {
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_bucket_acl v2-s3-bucket-acl-owner-only.json

  run run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging" -b "example-bucket"
  assert_success
  refute_stub_called_with "s3api list-buckets"
  assert_stub_called_with "s3api get-bucket-acl --bucket example-bucket"
  assert_output_contains "example-bucket"
  refute_output_line "example-bucket-one"
}

@test "list-bucket-properties reports full owner control as satisfied" {
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_bucket_acl v2-s3-bucket-acl-owner-only.json
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_public_access_block v2-s3-public-access-block-blocked.json

  run run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging" -b "example-bucket"
  assert_success
  assert_output_contains "Bucket owner Full Control: ✅"
  assert_output_contains "Other ACLs: 0 ✅"
  assert_output_contains "Blocks public access: ✅"
}

@test "list-bucket-properties flags an extra ACL grant to a different account" {
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_bucket_acl v2-s3-bucket-acl-other-grant.json

  run run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging" -b "example-bucket"
  assert_success
  assert_output_contains "Other ACLs: 1 ❌"
}

@test "list-bucket-properties reports blocked public access as not enabled when the call errors" {
  # get-public-access-block is never stubbed, so the call's stderr-suppressed
  # jq failure falls through the script's own \`|| echo "false"\`.
  stub_response_file dalmatian-aws-run_command-p-example_account-s3api-get_bucket_acl v2-s3-bucket-acl-owner-only.json

  run run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging" -b "example-bucket"
  assert_success
  assert_output_contains "Blocks public access: ❌"
}

@test "list-bucket-properties fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/s3/v2/list-bucket-properties -i "example-infra" -e "staging" -b "example-bucket"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "get-bucket-acl"
}
