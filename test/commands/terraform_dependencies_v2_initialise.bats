#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli

  cat <<'JSON' > "$CONFIG_SETUP_JSON_FILE"
{
  "project_name": "example-project",
  "backend": {
    "s3": {
      "bucket_name": "example-tfstate",
      "bucket_region": "eu-west-2"
    }
  }
}
JSON
}

@test "initialise runs both terraform inits when the state bucket exists" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 0

  run run_command bin/terraform-dependencies/v2/initialise
  assert_success
  assert_stub_called_with "aws s3api head-bucket --bucket example-tfstate"
  assert_stub_called_with "dalmatian terraform-dependencies run-terraform-command -c init -a -q"
  assert_stub_called_with "dalmatian terraform-dependencies run-terraform-command -c init -i -q"
}

@test "initialise stops before init when the state bucket is missing and undeclined" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run run_command bin/terraform-dependencies/v2/initialise < /dev/null
  assert_failure
  refute_stub_called_with "dalmatian terraform-dependencies run-terraform-command"
}

@test "initialise -y creates the missing state bucket and continues to init" {
  stub_exit aws-s3api-head_bucket 254
  stub_response aws-s3api-head_bucket "An error occurred (404) when calling the HeadBucket operation: Not Found"

  run run_command bin/terraform-dependencies/v2/initialise -y
  assert_success
  assert_stub_called_with "aws s3api create-bucket --bucket example-tfstate"
  assert_stub_called_with "dalmatian terraform-dependencies run-terraform-command -c init -a -q"
  assert_stub_called_with "dalmatian terraform-dependencies run-terraform-command -c init -i -q"
}

# ACCOUNT_BOOTSTRAP_OPTIONS/INFRASTRUCTURE_OPTIONS in `initialise` are built up
# with -reconfigure/-upgrade from -r/-u, but nothing in the script ever reads
# those arrays back -- the two run-terraform-command calls always pass a bare
# "init". That is a pre-existing bug outside this change's scope, so this
# pins down what -r actually does today (nothing to the argv, no crash)
# instead of asserting the "-reconfigure" that a glance at the option-building
# code would suggest.
@test "-r does not change the run-terraform-command argv it actually sends" {
  stub_response aws-s3api-get_bucket_versioning "Enabled"
  stub_response aws-s3api-get_public_access_block "True	True	True	True"
  stub_exit aws-s3api-get_bucket_encryption 0

  run run_command bin/terraform-dependencies/v2/initialise -r
  assert_success
  assert_call_args dalmatian terraform-dependencies run-terraform-command -c init -a -q
  assert_call_args dalmatian terraform-dependencies run-terraform-command -c init -i -q
}
