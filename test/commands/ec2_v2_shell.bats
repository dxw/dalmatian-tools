#!/usr/bin/env bats

load ../test_helper

# ec2/v2/shell ends with `"$APP_ROOT/bin/dalmatian" aws run-command -p "$PROFILE"
# ssm start-session --target "$INSTANCE_ID"`, an interactive session.
# stub_cli intercepts that call, so the picking/validation logic up to and
# including the exact ssm start-session invocation is fully covered here;
# this file stops at the point the real script would hand off to an
# interactive terminal.

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
}

@test "shell prints usage with no arguments" {
  run --separate-stderr run_command bin/ec2/v2/shell
  assert_failure 1
  assert_stderr_contains "Usage: shell"
  assert_output_contains "-I <instance_id>"
}

@test "shell shows usage when no profile can be resolved" {
  run --separate-stderr run_command bin/ec2/v2/shell -l
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell -h shows usage" {
  run --separate-stderr run_command bin/ec2/v2/shell -h
  assert_failure 1
  assert_stderr_contains "Usage: shell"
}

@test "shell resolves the profile from infrastructure and environment, then lists instances" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-one.json

  run run_command bin/ec2/v2/shell -i "example-infra" -e "staging" -l
  assert_success
  assert_stub_called_with "aws run-command -p example-account ec2 describe-instances --filters Name=instance-state-code,Values=16"
  assert_output_contains "i-0123456789abcdef0"
}

@test "shell uses an explicit -p profile without resolving one" {
  stub_response_file dalmatian-aws-run_command-p-example_profile-ec2-describe_instances ec2-describe-instances-one.json

  run run_command bin/ec2/v2/shell -p "example-profile" -l
  assert_success
  assert_stub_called_with "aws run-command -p example-profile ec2 describe-instances"
  refute_stub_called_with "deploy list-infrastructures"
}

@test "shell connects to the sole running instance without prompting" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-one.json

  run run_command bin/ec2/v2/shell -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "aws run-command -p example-account ssm start-session --target i-0123456789abcdef0"
}

@test "shell connects to an explicitly given instance id" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-two.json

  run run_command bin/ec2/v2/shell -i "example-infra" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "shell rejects an instance id that is not running" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-two.json

  run --separate-stderr run_command bin/ec2/v2/shell -i "example-infra" -e "staging" -I "i-00000000000000000"
  assert_failure 1
  assert_stderr_contains "was not found or is not running"
  refute_stub_called_with "ssm start-session"
}

@test "shell reports no running instances found" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/ec2/v2/shell -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "No running instances found in profile 'example-account'"
}

@test "shell cannot prompt with no terminal when multiple instances are found" {
  stub_response_file dalmatian-aws-run_command-p-example_account-ec2-describe_instances ec2-describe-instances-two.json

  run --separate-stderr run_command bin/ec2/v2/shell -i "example-infra" -e "staging" < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

@test "shell fails without the session-manager-plugin" {
  # session-manager-plugin is checked via `command -v`, a PATH lookup rather
  # than a stub hash, so it is exercised with a restricted PATH the way
  # ecs_ec2_access.bats does for the v1 equivalent.
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ec2/v2/shell -i "example-infra" -e "staging"

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}
