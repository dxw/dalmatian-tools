#!/usr/bin/env bats
# The password is deliberately full of shell metacharacters
# shellcheck disable=SC2016

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "rds_password generates 32 alphanumerics" {
  run rds_password
  assert_success
  [[ "$output" =~ ^[A-Za-z0-9]{32}$ ]] || fail "unexpected password: $output"
}

@test "rds_password -p reads stdin" {
  given="fake$BATS_TEST_NUMBER"'p@ss'"'"'"\$(id)'

  run rds_password -p <<< "$given"
  assert_success
  [ "$output" == "$given" ]
}

@test "rds_password -p refuses an empty password" {
  run --separate-stderr rds_password -p <<< ""
  assert_failure 1
  assert_stderr_contains "Password cannot be empty"
  [ -z "$output" ]
}
