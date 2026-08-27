#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  export PAGER=true
  export TMP_SERVICE_ENV_DIR="$SANDBOX/service-environment-files"
  stub_cli
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file dalmatian-service-list_services v2-service-details.json
}

@test "get-environment-variables prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list (lines
  # 9-12 of the script) is plain \`echo\`, so it lands on stdout.
  run --separate-stderr run_command bin/service/v2/get-environment-variables
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variables"
  assert_output_contains "-s <service>"
}

@test "get-environment-variables requires an infrastructure" {
  run --separate-stderr run_command bin/service/v2/get-environment-variables -e "staging" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variables"
}

@test "get-environment-variables requires an environment" {
  run --separate-stderr run_command bin/service/v2/get-environment-variables -i "example-infra" -s "example-service"
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variables"
}

@test "get-environment-variables requires a service" {
  run --separate-stderr run_command bin/service/v2/get-environment-variables -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variables"
}

@test "get-environment-variables -h shows usage" {
  run --separate-stderr run_command bin/service/v2/get-environment-variables -h
  assert_failure 1
  assert_stderr_contains "Usage: get-environment-variables"
}

@test "get-environment-variables asks the CLI for the service's environment file location" {
  stub_response dalmatian-aws-run_command-p-example_account-s3api-head_object '{"ContentLength": 42}'

  run run_command bin/service/v2/get-environment-variables -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "service list-services -i example-infra -e staging -s example-service"
}

@test "get-environment-variables downloads the file from the exact bucket and key named by the service" {
  stub_response dalmatian-aws-run_command-p-example_account-s3api-head_object '{"ContentLength": 42}'

  run run_command bin/service/v2/get-environment-variables -i "example-infra" -e "staging" -s "example-service"
  assert_success
  assert_stub_called_with "s3api head-object --bucket example-bucket --key example-service.env"
  assert_stub_called_with "s3 cp s3://example-bucket/example-service.env $TMP_SERVICE_ENV_DIR/example-infra-staging-example-service.env"
}

@test "get-environment-variables reports a missing file and exits 1 without downloading" {
  # No head-object stub is registered, so the call resolves to an unstubbed
  # response: empty output, exit 0. ENVIRONMENT_FILE_META_JSON is then empty,
  # taking the "does not exist" branch.
  run --separate-stderr run_command bin/service/v2/get-environment-variables -i "example-infra" -e "staging" -s "example-service"
  assert_failure 1
  refute_stub_called_with "s3 cp"
}

@test "get-environment-variables fails when no AWS profile matches the infrastructure/environment" {
  stub_response aws-configure-list_profiles "dalmatian-main"

  run --separate-stderr run_command bin/service/v2/get-environment-variables -i "example-infra" -e "staging" -s "example-service"
  assert_failure
  assert_stderr_contains "Profile does not exist for example-infra staging"
  refute_stub_called_with "service list-services"
}
