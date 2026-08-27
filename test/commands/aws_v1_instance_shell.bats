#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
}

@test "instance-shell prints usage with no arguments" {
  run --separate-stderr run_command bin/aws/v1/instance-shell
  assert_failure 1
  assert_stderr_contains "Usage: instance-shell"
  assert_output_contains "-i <infrastructure>"
}

@test "instance-shell requires an infrastructure flag" {
  run --separate-stderr run_command bin/aws/v1/instance-shell -l
  assert_failure 1
  assert_stderr_contains "Usage: instance-shell"
}

@test "instance-shell -h shows usage" {
  run --separate-stderr run_command bin/aws/v1/instance-shell -h
  assert_failure 1
  assert_stderr_contains "Usage: instance-shell"
  assert_output_contains "Connect to any ec2 instance in an infrastructure"
}

@test "instance-shell checks for session-manager-plugin before parsing options" {
  # The plugin check runs before getopts, so even \`-h\` hits the plugin
  # error rather than usage() when the plugin is missing.
  local original_path="$PATH"
  mkdir -p "$SANDBOX/no-plugin-bin"
  ln -sfn "$(command -v bash)" "$SANDBOX/no-plugin-bin/bash"
  PATH="$SANDBOX/no-plugin-bin:/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/aws/v1/instance-shell -h

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}

@test "instance-shell -l lists available instances without connecting" {
  run run_command bin/aws/v1/instance-shell -i "example-infra" -l
  assert_success
  assert_output_contains "i-0123456789abcdef0"
  assert_output_contains "i-0fedcba987654321f"
  refute_stub_called_with "ssm start-session"
}

@test "instance-shell connects to an explicitly given instance" {
  run run_command bin/aws/v1/instance-shell -i "example-infra" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "instance-shell connects with an empty target when no instance is given or listed" {
  # Unlike ecs/v1/ec2-access, -I is documented as optional but there is no
  # fallback picker: omitting both -l and -I still reaches the ssm call, just
  # with an empty --target.
  run run_command bin/aws/v1/instance-shell -i "example-infra"
  assert_success
  assert_stub_called_with "ssm start-session --target"
  refute_stub_called_with "ssm start-session --target i-"
}
