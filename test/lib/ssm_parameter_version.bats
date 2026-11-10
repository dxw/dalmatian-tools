#!/usr/bin/env bats

load ../test_helper

GET_PARAMETER=dalmatian-aws-run_command-p-example_account-ssm-get_parameter
PARAMETER_NAME=/example-infra/staging/rds/example-rds/app_user/password

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
}

@test "ssm_parameter_version prints the version of a stored parameter" {
  stub_response "$GET_PARAMETER" "7"

  run --separate-stderr ssm_parameter_version -p "example-account" -n "$PARAMETER_NAME"
  assert_success
  assert_output "7"
  assert_call_args dalmatian aws run-command -p example-account ssm get-parameter --name "$PARAMETER_NAME" --query Parameter.Version --output text
}

@test "ssm_parameter_version prints nothing for ParameterNotFound" {
  stub_exit "$GET_PARAMETER" 254
  stub_stderr "$GET_PARAMETER" "An error occurred (ParameterNotFound) when calling the GetParameter operation: "

  run --separate-stderr ssm_parameter_version -p "example-account" -n "$PARAMETER_NAME"
  assert_success
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "ssm_parameter_version fails with the AWS error otherwise" {
  stub_exit "$GET_PARAMETER" 254
  stub_stderr "$GET_PARAMETER" "An error occurred (AccessDeniedException) when calling the GetParameter operation: denied"

  run --separate-stderr ssm_parameter_version -p "example-account" -n "$PARAMETER_NAME"
  assert_failure 254
  assert_stderr_contains "AccessDeniedException"
  [ -z "$output" ]
}

@test "ssm_parameter_version never asks for decryption" {
  stub_response "$GET_PARAMETER" "7"

  run ssm_parameter_version -p "example-account" -n "$PARAMETER_NAME"
  assert_success
  refute_stub_called_with "--with-decryption"
}
