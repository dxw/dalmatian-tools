#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response dalmatian-aws-run_command-p-example_account-ssm-get_parameter \
    "arn:aws:ssm:eu-west-2:123456789012:parameter/example-infra/staging/mysecret"
}

@test "put-secret prints usage with no arguments" {
  run --separate-stderr run_command bin/aws/v2/put-secret
  assert_failure 1
  assert_stderr_contains "Usage: put-secret"
  assert_output_contains "-n <secret-name>"
  refute_stub_called_with "ssm put-parameter"
}

@test "put-secret requires infrastructure, environment and a secret name" {
  run --separate-stderr run_command bin/aws/v2/put-secret -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: put-secret"
  refute_stub_called_with "ssm put-parameter"
}

@test "put-secret -h shows usage" {
  run --separate-stderr run_command bin/aws/v2/put-secret -h
  assert_failure 1
  assert_stderr_contains "Usage: put-secret"
  assert_output_contains "puts an arbitrary secret into SSM Parameter Store"
}

@test "put-secret resolves the profile, stores the value and prints the ARN" {
  run run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "mysecret" -v "example-secret-value"
  assert_success
  assert_stub_called_with "deploy list-infrastructures"
  assert_stub_called_with "aws run-command -p example-account ssm put-parameter --name /example-infra/staging/mysecret --value example-secret-value --type SecureString --key-id alias/aws/ssm --overwrite"
  assert_output_contains "arn:aws:ssm:eu-west-2:123456789012:parameter/example-infra/staging/mysecret"
}

@test "put-secret strips a leading slash from the secret name" {
  run run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "/mysecret" -v "example-secret-value"
  assert_success
  assert_stub_called_with "--name /example-infra/staging/mysecret"
  refute_stub_called_with "--name //example-infra"
}

@test "put-secret reads the value from stdin when -v is not given" {
  run run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "mysecret" <<< "piped-secret-value"
  assert_success
  assert_stub_called_with "--value piped-secret-value"
}

@test "put-secret fails and writes nothing when the secret value is empty" {
  run --separate-stderr run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "mysecret" < /dev/null
  assert_failure 1
  assert_stderr_contains "Secret value cannot be empty"
  refute_stub_called_with "ssm put-parameter"
}

@test "put-secret respects a custom KMS key id" {
  run run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "mysecret" -v "example-secret-value" -k "alias/example-custom-key"
  assert_success
  assert_stub_called_with "--key-id alias/example-custom-key"
}

@test "put-secret fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/aws/v2/put-secret -i "example-infra" -e "staging" -n "mysecret" -v "example-secret-value"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "ssm put-parameter"
}
