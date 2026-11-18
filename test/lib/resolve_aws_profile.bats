#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles <<'PROFILES'
dalmatian-main
example-account
PROFILES
}

@test "resolve_aws_profile resolves from infrastructure and environment" {
  run resolve_aws_profile -i "example-infra" -e "staging"
  assert_success
  assert_output "example-account"
}

@test "resolve_aws_profile resolves from a dalmatian account name" {
  run resolve_aws_profile -a "dalmatian-aws-account-000-example-account"
  assert_success
  assert_output "example-account"
}

@test "resolve_aws_profile asks the CLI for the infrastructure list" {
  run resolve_aws_profile -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "dalmatian deploy list-infrastructures"
}

@test "resolve_aws_profile does not need the CLI when given an account name" {
  run resolve_aws_profile -a "dalmatian-aws-account-000-example-account"
  assert_success
  refute_stub_called_with "list-infrastructures"
}

@test "resolve_aws_profile fails when no profile exists for the account" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr resolve_aws_profile -i "example-infra" -e "staging"
  assert_failure
  assert_stderr_contains "Profile does not exist"
  assert_stderr_contains "dalmatian aws generate-config"
}

@test "resolve_aws_profile rejects an unknown flag" {
  run --separate-stderr resolve_aws_profile -z "nope"
  assert_failure
  assert_stderr_contains "Invalid \`resolve_aws_profile\` function usage"
}

@test "resolve_aws_profile names an infrastructure and environment it cannot find" {
  run --separate-stderr resolve_aws_profile -i "example-infra" -e "nonexistent"
  assert_failure
  assert_stderr_contains "No Dalmatian account has infrastructure 'example-infra' with environment 'nonexistent'"
  if [[ "$stderr" == *"generate-config"* ]]
  then
    fail "expected no generate-config hint, got: $stderr"
  fi
}

@test "resolve_aws_profile reports list-infrastructures output that is not JSON" {
  stub_response dalmatian-deploy-list_infrastructures <<'OUT'
Attempting to automatically open the SSO authorization page in your default browser.
{"accounts": {}}
OUT

  run --separate-stderr resolve_aws_profile -i "example-infra" -e "staging"
  assert_failure
  assert_stderr_contains "\`dalmatian deploy list-infrastructures\` did not return valid JSON"
  if [[ "$stderr" == *"generate-config"* ]]
  then
    fail "expected no generate-config hint, got: $stderr"
  fi
}
