#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "list-environment-variables prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/list-environment-variables
  assert_failure 1
  assert_stderr_contains "Usage: list-environment-variables"
  assert_output_contains "-j"
}

@test "list-environment-variables requires a service" {
  run --separate-stderr run_command bin/service/v1/list-environment-variables \
    -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: list-environment-variables"
}

@test "list-environment-variables queries the path built from -i/-s/-e, recursively and decrypted" {
  stub_response_file aws-ssm-get_parameters_by_path service-v1-get-parameters-by-path.json

  run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "--path /example-infra/example-service/staging/"
  assert_stub_called_with "--recursive"
  assert_stub_called_with "--with-decryption"
}

@test "list-environment-variables prints KEY=VALUE sorted by name with the path prefix stripped" {
  stub_response_file aws-ssm-get_parameters_by_path service-v1-get-parameters-by-path.json

  run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging
  assert_success
  assert_line 0 "SMTP_HOST=smtp.example.org"
  assert_line 1 "SMTP_PORT=25"
}

# FINDING: -j output is emitted in the AWS response's original array order
# (jq -c ".Parameters[] | ...", no sort_by), while the default text output is
# explicitly `sort_by(.Name)`. The fixture lists SMTP_PORT before SMTP_HOST,
# so the two modes disagree on ordering for identical underlying data.
@test "list-environment-variables -j emits one JSON object per line, unsorted, with the prefix stripped" {
  stub_response_file aws-ssm-get_parameters_by_path service-v1-get-parameters-by-path.json

  run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging -j
  assert_success
  assert_line 0 '{"Name":"SMTP_PORT","Value":"25"}'
  assert_line 1 '{"Name":"SMTP_HOST","Value":"smtp.example.org"}'
}

@test "list-environment-variables prints nothing for an empty parameter path" {
  stub_response aws-ssm-get_parameters_by_path '{"Parameters": []}'

  run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging
  assert_success
  assert_output ""
}

@test "list-environment-variables logs what it is retrieving when not quiet" {
  stub_response aws-ssm-get_parameters_by_path '{"Parameters": []}'

  QUIET_MODE=0 run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging
  assert_success
  assert_output_contains "Retrieving env vars for example-infra/example-service/staging"
}

@test "list-environment-variables fails when the AWS call fails" {
  stub_exit aws-ssm-get_parameters_by_path 254

  run run_command bin/service/v1/list-environment-variables \
    -i example-infra -s example-service -e staging
  assert_failure
}
