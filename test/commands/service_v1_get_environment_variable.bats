#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=0
}

@test "get-environment-variable prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list itself is
  # plain `echo`, so it lands on stdout. Existing behaviour of the script.
  run --separate-stderr run_command bin/service/v1/get-environment-variable
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variable"
  assert_output_contains "-k <key>"
}

@test "get-environment-variable -h also exits 1 (usage() has no success path)" {
  run --separate-stderr run_command bin/service/v1/get-environment-variable -h
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variable"
}

@test "get-environment-variable requires a key" {
  run --separate-stderr run_command bin/service/v1/get-environment-variable \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variable"
}

@test "get-environment-variable requires an infrastructure" {
  run --separate-stderr run_command bin/service/v1/get-environment-variable \
    -s example-service -e staging -k SMTP_HOST
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variable"
}

@test "get-environment-variable builds the parameter path from -i/-s/-e/-k" {
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'

  run run_command bin/service/v1/get-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_success
  assert_stub_called_with "--name /example-infra/example-service/staging/SMTP_HOST"
  assert_stub_called_with "--with-decryption"
}

@test "get-environment-variable prints the decrypted value on stdout" {
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'

  run run_command bin/service/v1/get-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_success
  assert_line 1 "smtp.example.org"
}

@test "get-environment-variable logs what it is fetching when not quiet" {
  stub_response aws-ssm-get_parameter '{"Parameter": {"Value": "smtp.example.org"}}'

  run run_command bin/service/v1/get-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST
  assert_success
  assert_output_contains "getting environment variable SMTP_HOST for example-infra/example-service/staging"
}

@test "get-environment-variable fails when the AWS call fails" {
  # pipefail means the pipeline's exit status is aws's non-zero status even
  # though `jq -r` on the resulting empty stdin exits 0 by itself.
  stub_exit aws-ssm-get_parameter 254

  run run_command bin/service/v1/get-environment-variable \
    -i example-infra -s example-service -e staging -k MISSING_KEY
  assert_failure
}
