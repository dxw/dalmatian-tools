#!/usr/bin/env bats
# The password is deliberately full of shell metacharacters
# shellcheck disable=SC2016

load ../test_helper
load ../rds_v2_task_helper

PUT_SECRET=dalmatian-aws-put_secret

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
  export QUIET_MODE=1
  stub_capture_stdin "$PUT_SECRET"
}

@test "rds_store_user_password stores a generated password with put-secret" {
  run rds_store_user_password -i example-infra -e staging -u app_user -n rds/example-rds/app_user/password
  assert_success
  assert_call_args dalmatian aws put-secret -i example-infra -e staging -n rds/example-rds/app_user/password
  [[ "$(stub_stdin "$PUT_SECRET")" =~ ^[A-Za-z0-9]{32}$ ]] || fail "unexpected generated password: $(stub_stdin "$PUT_SECRET")"
}

@test "rds_store_user_password -p stores the password read from stdin, intact" {
  given="$(fake_password given)"'a'"'"'b"c\d$(id)'

  run rds_store_user_password -i example-infra -e staging -u app_user -n rds/example-rds/app_user/password -p <<< "$given"
  assert_success
  [ "$(stub_stdin "$PUT_SECRET")" == "$given" ]
  [[ "$output" != *"$given"* ]]
}

@test "rds_store_user_password -p refuses an empty password and stores nothing" {
  run --separate-stderr rds_store_user_password -i example-infra -e staging -u app_user -n rds/example-rds/app_user/password -p <<< ""
  assert_failure 1
  assert_stderr_contains "Password cannot be empty"
  refute_stub_called_with "put-secret"
}

@test "rds_store_user_password requires its names" {
  run --separate-stderr rds_store_user_password -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_store_user_password\` function usage"
}
