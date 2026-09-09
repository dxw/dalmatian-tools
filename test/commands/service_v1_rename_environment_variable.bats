#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'
}

@test "rename-environment-variable prints usage and fails with no arguments" {
  run --separate-stderr run_command bin/service/v1/rename-environment-variable
  assert_failure 1
  assert_stderr_contains "No arguments passed"
  assert_stderr_contains "Usage: rename-environment-variable"
  assert_output_contains "-n <new-key>"
}

# FINDING: unlike the other five commands, this usage() takes an explicit
# exit code (`exit $1`), and the `-h` case calls `usage 0` -- so `-h` here
# exits 0, whereas get/set/list/delete/copy-environment-variable(s) all
# hard-code `exit 1` for `-h`.
@test "rename-environment-variable -h exits 0, unlike the other environment-variable commands" {
  run --separate-stderr run_command bin/service/v1/rename-environment-variable -h
  assert_success
  assert_stderr_contains "Usage: rename-environment-variable"
}

@test "rename-environment-variable requires -i, -e and -s" {
  run --separate-stderr run_command bin/service/v1/rename-environment-variable \
    -k OLD_KEY -n NEW_KEY
  assert_failure 1
  assert_stderr_contains "Missing -i, -e or -s parameters"
  refute_stub_called_with "get-parameter"
}

@test "rename-environment-variable requires -k and -n" {
  run --separate-stderr run_command bin/service/v1/rename-environment-variable \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Missing -k or -n parameters"
  refute_stub_called_with "get-parameter"
}

@test "rename-environment-variable reads the old key, writes the new key with the same value, then deletes the old key" {
  run run_command bin/service/v1/rename-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST -n SMTP_HOSTNAME
  assert_success
  assert_stub_called_with "get-parameter --with-decryption --name /example-infra/example-service/staging/SMTP_HOST"
  assert_stub_called_with "put-parameter --name /example-infra/example-service/staging/SMTP_HOSTNAME --value smtp.example.org"
  assert_stub_called_with "delete-parameter --name /example-infra/example-service/staging/SMTP_HOST"
}

@test "rename-environment-variable never deletes the old key when the new key is rejected" {
  # set-environment-variable validates that -k (here, the new key) starts
  # with a letter; since rename shells out to it under `set -e`, a rejected
  # new key must abort before the delete step runs, leaving the old
  # parameter intact.
  run --separate-stderr run_command bin/service/v1/rename-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST -n 1BAD_KEY
  assert_failure
  assert_stub_called_with "get-parameter"
  refute_stub_called_with "delete-parameter"
}

@test "rename-environment-variable fails, and never writes or deletes, when the old key cannot be read" {
  stub_exit aws-ssm-get_parameter 254

  run run_command bin/service/v1/rename-environment-variable \
    -i example-infra -s example-service -e staging -k MISSING_KEY -n NEW_KEY
  assert_failure
  refute_stub_called_with "put-parameter"
  refute_stub_called_with "delete-parameter"
}
