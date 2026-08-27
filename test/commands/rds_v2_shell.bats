#!/usr/bin/env bats

load ../test_helper

# rds/v2/shell only ever forwards to `dalmatian utilities run-command`, which
# stub_cli intercepts -- so the whole script's behaviour is observable without
# reaching an actual interactive session. There is nothing further to stop
# at here.

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

@test "shell prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/shell
  assert_failure 1
  assert_stderr_contains "Usage: shell"
  assert_output_contains "-r <rds_name>"
}

@test "shell requires an infrastructure" {
  run --separate-stderr run_command bin/rds/v2/shell -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell requires an environment" {
  run --separate-stderr run_command bin/rds/v2/shell -i "example-infra" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell requires an RDS name" {
  run --separate-stderr run_command bin/rds/v2/shell -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell -h shows usage" {
  run --separate-stderr run_command bin/rds/v2/shell -h
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell forwards to utilities run-command with interactive and default keep-alive settings" {
  run run_command bin/rds/v2/shell -i "example-infra" -e "staging" -r "example-rds"
  assert_success
  assert_stub_called_with "utilities run-command -i example-infra -e staging -r example-rds -s -I -D 60 -M 600"
}

@test "shell forwards custom keep-alive delay and maximum lifetime" {
  run run_command bin/rds/v2/shell -i "example-infra" -e "staging" -r "example-rds" -D 30 -M 120
  assert_success
  assert_stub_called_with "-D 30 -M 120"
}

@test "shell propagates a failing dalmatian call" {
  stub_exit dalmatian-utilities-run_command 4

  run run_command bin/rds/v2/shell -i "example-infra" -e "staging" -r "example-rds"
  assert_failure 4
}

@test "shell does not call the CLI when validation fails" {
  run run_command bin/rds/v2/shell -i "example-infra" -e "staging"
  refute_stub_called_with "utilities run-command"
}
