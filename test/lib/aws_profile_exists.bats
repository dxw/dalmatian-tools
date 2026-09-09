#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  export AWS_CONFIG_FILE="$CONFIG_AWS_SSO_FILE"
}

@test "aws_profile_exists finds a profile that is present" {
  stub_response aws-configure-list_profiles <<'PROFILES'
dalmatian-main
example-account
PROFILES

  run aws_profile_exists "example-account"
  assert_success
}

@test "aws_profile_exists does not match on a substring" {
  stub_response aws-configure-list_profiles <<'PROFILES'
dalmatian-main
example-account-staging
PROFILES

  run aws_profile_exists "example-account"
  assert_failure
}

@test "aws_profile_exists fails loudly when the config cannot be read" {
  stub_exit aws-configure-list_profiles 1

  run --separate-stderr aws_profile_exists "example-account"
  assert_failure
  assert_stderr_contains "could not read AWS profiles"
}

@test "aws_profile_exists reads whatever AWS_CONFIG_FILE points at" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run aws_profile_exists "dalmatian-main"
  assert_success
  assert_stub_called_with "aws configure list-profiles"
}
