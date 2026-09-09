#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

@test "exec prints usage with no arguments" {
  run --separate-stderr run_command bin/aws/v2/exec
  assert_failure 1
  assert_stderr_contains "Usage: exec"
  assert_output_contains "-e <environment>"
}

@test "exec requires an environment as well as an infrastructure" {
  run --separate-stderr run_command bin/aws/v2/exec -i "example-infra" s3 ls
  assert_failure 1
  assert_stderr_contains "Usage: exec"
}

@test "exec requires an infrastructure as well as an environment" {
  run --separate-stderr run_command bin/aws/v2/exec -e "staging" s3 ls
  assert_failure 1
  assert_stderr_contains "Usage: exec"
}

@test "exec -h shows usage" {
  run --separate-stderr run_command bin/aws/v2/exec -h
  assert_failure 1
  assert_stderr_contains "Usage: exec"
  assert_output_contains "Run any aws cli command in an infrastructure environment"
}

@test "exec forwards to aws run-command with the resolved arguments" {
  run run_command bin/aws/v2/exec -i "example-infra" -e "staging" s3 ls s3://example-bucket
  assert_success
  assert_stub_called_with "aws run-command -i example-infra -e staging s3 ls s3://example-bucket"
}

@test "exec propagates the exit status of the dalmatian call" {
  stub_exit dalmatian-aws-run_command 7

  run run_command bin/aws/v2/exec -i "example-infra" -e "staging" sts get-caller-identity
  assert_failure 7
}
