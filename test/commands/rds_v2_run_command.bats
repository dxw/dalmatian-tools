#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

@test "run-command prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/run-command
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
  assert_output_contains "-r <rds_name>"
}

@test "run-command requires an infrastructure" {
  run --separate-stderr run_command bin/rds/v2/run-command -e "staging" -r "example-rds" -c "SELECT 1;"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command requires an environment" {
  run --separate-stderr run_command bin/rds/v2/run-command -i "example-infra" -r "example-rds" -c "SELECT 1;"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command requires an RDS name" {
  run --separate-stderr run_command bin/rds/v2/run-command -i "example-infra" -e "staging" -c "SELECT 1;"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command requires a command" {
  run --separate-stderr run_command bin/rds/v2/run-command -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command -h shows usage" {
  run --separate-stderr run_command bin/rds/v2/run-command -h
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command forwards to utilities run-command with -s for RDS execution" {
  run run_command bin/rds/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "SELECT 1;"
  assert_success
  assert_stub_called_with "utilities run-command -i example-infra -e staging -r example-rds -c SELECT 1; -s"
}

@test "run-command propagates a failing dalmatian call" {
  stub_exit dalmatian-utilities-run_command 9

  run run_command bin/rds/v2/run-command -i "example-infra" -e "staging" -r "example-rds" -c "SELECT 1;"
  assert_failure 9
}

@test "run-command does not call the CLI when validation fails" {
  run run_command bin/rds/v2/run-command -i "example-infra" -e "staging"
  refute_stub_called_with "utilities run-command"
}
