#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

@test "run-command shows usage when neither a profile, an infra/env pair, nor an account is given" {
  # There is no leading \`$# -eq 0\` guard here: the usage() call comes purely
  # from the validation of -p/-i+-e/-a, so a bare invocation reaches it too.
  run --separate-stderr run_command bin/aws/v2/run-command
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
  assert_output_contains "-a <account_name>"
}

@test "run-command shows usage when only an infrastructure is given" {
  run --separate-stderr run_command bin/aws/v2/run-command -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command -h shows usage" {
  run --separate-stderr run_command bin/aws/v2/run-command -h
  assert_failure 1
  assert_stderr_contains "Usage: run-command"
}

@test "run-command uses an explicit -p profile without resolving one" {
  run run_command bin/aws/v2/run-command -p "example-profile" sts get-caller-identity
  assert_success
  assert_stub_called_with "sts get-caller-identity"
  refute_stub_called_with "deploy list-infrastructures"
  refute_stub_called_with "configure list-profiles"
}

@test "run-command resolves a profile from infrastructure and environment" {
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"

  run run_command bin/aws/v2/run-command -i "example-infra" -e "staging" sts get-caller-identity
  assert_success
  assert_stub_called_with "sts get-caller-identity"
  assert_stub_called_with "deploy list-infrastructures"
  assert_stub_called_with "configure list-profiles"
}

@test "run-command resolves a profile from a dalmatian account name without listing infrastructures" {
  stub_response aws-configure-list_profiles "example-account"

  run run_command bin/aws/v2/run-command -a "dalmatian-aws-account-000-example-account" sts get-caller-identity
  assert_success
  assert_stub_called_with "sts get-caller-identity"
  refute_stub_called_with "deploy list-infrastructures"
}

@test "run-command propagates a failing aws exit code" {
  stub_exit aws-sts-get_caller_identity 5

  run run_command bin/aws/v2/run-command -p "example-profile" sts get-caller-identity
  assert_failure 5
}
