#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "rds_pick returns the first field of the only line without prompting" {
  run rds_pick -l "examplerds mysql 8.4.3" -n database -f -r
  assert_success
  assert_output "examplerds"
}

@test "rds_pick fails when there is nothing to pick" {
  run --separate-stderr rds_pick -l "" -n database -f -r
  assert_failure
  assert_stderr_contains "No databases to choose from"
}

@test "rds_pick refuses to prompt with no terminal" {
  run --separate-stderr rds_pick -l $'examplerds mysql 8.4.3\nanotherrds postgres 16.4' -n database -f -r < /dev/null
  assert_failure
  assert_stderr_contains "2 databases found, and there is no terminal"
}

@test "rds_pick lists the candidates when it cannot prompt" {
  run --separate-stderr rds_pick -l $'examplerds mysql 8.4.3\nanotherrds postgres 16.4' -n database -f -r < /dev/null
  assert_failure
  assert_stderr_contains "examplerds mysql 8.4.3"
  assert_stderr_contains "anotherrds postgres 16.4"
  assert_stderr_contains "Pass one explicitly with \`-r\`"
}

@test "rds_pick rejects a missing -l" {
  run --separate-stderr rds_pick -n database -f -r
  assert_failure
  assert_stderr_contains "Invalid \`rds_pick\` function usage"
}
