#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "delete-environment-variable prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/delete-environment-variable
  assert_failure 1
  assert_stderr_contains "Usage: delete-environment-variable"
  assert_output_contains "-k <key>"
}

@test "delete-environment-variable -h also exits 1 (usage() has no success path)" {
  run --separate-stderr run_command bin/service/v1/delete-environment-variable -h
  assert_failure 1
  assert_stderr_contains "Usage: delete-environment-variable"
}

@test "delete-environment-variable requires a key" {
  run --separate-stderr run_command bin/service/v1/delete-environment-variable \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Usage: delete-environment-variable"
  refute_stub_called_with "delete-parameter"
}

@test "delete-environment-variable deletes the parameter path built from -i/-s/-e/-k" {
  run run_command bin/service/v1/delete-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_success
  assert_stub_called_with "delete-parameter --name /example-infra/example-service/staging/SMTP_HOST"
}

@test "delete-environment-variable logs a confirmation on success when not quiet" {
  QUIET_MODE=0 run run_command bin/service/v1/delete-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_success
  assert_line 0 $'\033[0;36m==>\033[0m deleting environment variable SMTP_HOST for example-infra/example-service/staging ...'
  assert_line 1 $'\033[0;36m==>\033[0m deleted'
}

@test "delete-environment-variable fails, and never logs 'deleted', when the AWS call fails" {
  stub_exit aws-ssm-delete_parameter 254

  QUIET_MODE=0 run run_command bin/service/v1/delete-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_failure
  refute_output_line $'\033[0;36m==>\033[0m deleted'
}
