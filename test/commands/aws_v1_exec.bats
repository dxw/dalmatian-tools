#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "exec prints usage with no arguments" {
  # usage() sends only its "Usage: ..." line to stderr; the two example lines
  # above it and the option list below it are plain \`echo\`, so they land on
  # stdout.
  run --separate-stderr run_command bin/aws/v1/exec
  assert_failure 1
  assert_stderr_contains "Usage: exec"
  assert_output_contains "-i <infrastructure>"
}

@test "exec requires an infrastructure flag even when an aws subcommand is given" {
  run --separate-stderr run_command bin/aws/v1/exec s3 ls
  assert_failure 1
  assert_stderr_contains "Usage: exec"
}

@test "exec -h shows usage" {
  run --separate-stderr run_command bin/aws/v1/exec -h
  assert_failure 1
  assert_stderr_contains "Usage: exec"
  assert_output_contains "Run any aws cli command in an infrastructure"
}

@test "exec runs the given aws subcommand once -i is satisfied" {
  run run_command bin/aws/v1/exec -i "example-infra" sts get-caller-identity
  assert_success
  assert_stub_called_with "sts get-caller-identity"
}

@test "exec passes arbitrary aws cli arguments straight through" {
  run run_command bin/aws/v1/exec -i "example-infra" s3 ls s3://example-bucket
  assert_success
  assert_stub_called_with "s3 ls s3://example-bucket"
}

@test "exec does not forward the infrastructure name to the aws call" {
  # -i only gates the usage check; it is never passed on to \`aws\`.
  run run_command bin/aws/v1/exec -i "example-infra" sts get-caller-identity
  assert_success
  refute_stub_called_with "example-infra"
}

@test "exec propagates a failing aws exit code" {
  stub_exit aws-sts-get_caller_identity 42

  run run_command bin/aws/v1/exec -i "example-infra" sts get-caller-identity
  assert_failure 42
}
