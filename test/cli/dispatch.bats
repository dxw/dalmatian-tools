#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  use_test_app_root
  login_sandbox
}

@test "dalmatian runs the command for the current version" {
  run "$TEST_DALMATIAN" probe echo-args alpha beta
  assert_success
  assert_output_contains "alpha"
  assert_output_contains "beta"
}

@test "dalmatian strips -q from the command arguments" {
  run "$TEST_DALMATIAN" probe echo-args -q alpha
  assert_success
  assert_output "alpha"
}

@test "dalmatian reports an unknown subcommand" {
  run --separate-stderr "$TEST_DALMATIAN" nonsense echo-args
  assert_failure 1
  assert_stderr_contains "\`nonsense\` is not a dalmatian subcommand"
}

@test "dalmatian points at the version switch for a v2-only subcommand" {
  run --separate-stderr "$TEST_DALMATIAN" only-v2 echo-args
  assert_failure 1
  assert_stderr_contains "\`only-v2\` is not available in v1"
  assert_stderr_contains "dalmatian version -v 2"
}

@test "dalmatian lists the available commands when the command is unknown" {
  run "$TEST_DALMATIAN" probe nonsense
  assert_failure 1
  assert_output_contains "dalmatian probe echo-args"
}

@test "dalmatian refuses to run with no configuration at all" {
  rm -f "$CONFIG_SETUP_JSON_FILE" "$CONFIG_AWS_SSO_FILE"

  run --separate-stderr "$TEST_DALMATIAN" probe echo-args
  assert_failure 1
  assert_stderr_contains "No AWS SSO configuration was found"
  assert_stderr_contains "dalmatian version -v 2 && dalmatian setup"
}

@test "dalmatian aws mfa is refused on the AWS SSO path" {
  run --separate-stderr "$TEST_DALMATIAN" aws mfa
  assert_failure 1
  assert_stderr_contains "does not apply when Dalmatian is signing in with AWS SSO"
  assert_stderr_contains "dalmatian aws login"
}
