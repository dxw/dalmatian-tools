#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "rds_validate_names accepts plain names" {
  run rds_validate_names -i example-infra -e staging -r example-rds.1 -d app_db -u _app_user
  assert_success
}

@test "rds_validate_names makes the database and user optional" {
  run rds_validate_names -i example-infra -e staging -r example-rds
  assert_success
}

@test "rds_validate_names refuses a database name that is not a plain identifier" {
  for name in 'app"; DROP' 'app-db' '1app' '' ; do
    [ -z "$name" ] && continue
    run --separate-stderr rds_validate_names -i example-infra -e staging -r example-rds -d "$name"
    assert_failure 1
    assert_stderr_contains "Database name must be"
  done
}

@test "rds_validate_names refuses a user name that is not a plain identifier" {
  run --separate-stderr rds_validate_names -i example-infra -e staging -r example-rds -u "app-user"
  assert_failure 1
  assert_stderr_contains "User name must be"
}

@test "rds_validate_names refuses a name longer than 63 characters" {
  run --separate-stderr rds_validate_names -i example-infra -e staging -r example-rds -u "$(printf 'a%.0s' {1..64})"
  assert_failure 1
  assert_stderr_contains "User name must be"
}

@test "rds_validate_names refuses infrastructure, environment and RDS names that could break a path" {
  run --separate-stderr rds_validate_names -i example-infra -e staging -r 'rds;id'
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  run --separate-stderr rds_validate_names -i 'a/b' -e staging -r example-rds
  assert_failure 1
  run --separate-stderr rds_validate_names -i example-infra -e 'stag ing' -r example-rds
  assert_failure 1
}

@test "rds_validate_names requires infrastructure, environment and RDS name" {
  run --separate-stderr rds_validate_names -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Invalid \`rds_validate_names\` function usage"
}
